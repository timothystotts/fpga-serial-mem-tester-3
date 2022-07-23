--------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2021 Timothy Stotts
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--------------------------------------------------------------------------------
-- \file board_uart.vhdl
--
-- \brief OSVVM testbench component: Simulation Model of board UART.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

library osvvm_uart;
context osvvm_uart.UartContext;

library work;
use work.sf3_testbench_types_pkg.all;
use work.sf3_testbench_pkg.all;
--------------------------------------------------------------------------------
entity tbc_board_uart is
	port(
		TBID             : in    AlertLogIDType;
		BarrierTestStart : inout std_logic;
		BarrierLogStart  : inout std_logic;
		TransRec         : inout UartRecType;
		ci_rxd           : in    std_logic;
		co_txd           : out   std_logic
	);
end entity tbc_board_uart;
--------------------------------------------------------------------------------
architecture simulation_default of tbc_board_uart is
    -- Simulation logging ID for this architecture.
	signal ModelID : AlertLogIDType;
begin
	-- Simulation initialization for the tbc_board_uart component.
	p_sim_init : process
		variable ID : AlertLogIDType;
	begin
		wait for 0 ns;
		WaitForBarrier(BarrierTestStart);
		ID      := GetAlertLogID(PathTail(tbc_board_uart'path_name), TBID);
		ModelID <= ID;

		wait on ModelID;
		SB_CLS.SetAlertLogID("MeasModeBoardUart", ModelID);

		Log(ModelID, "Starting Board UART emulation at baud 115200.", ALWAYS);
		wait;
	end process p_sim_init;

	UartTbRxProc : process
		-- A variable to assign ModelID and use with procedures that can only
		-- accept a variable instead of a signal for the Alert/Log ID.
		variable ID           : AlertLogIDType;
		-- Record to track UART RX communication.
		variable RxStim       : UartStimType;
		-- The ASCII line buffer.
		variable rx_ascii_buf : string(1 to 64) := (others => NUL);
		-- The ASCII line buffer position/length count.
		variable rx_ascii_cnt : natural         := 0;
		-- The current ASCII character after ASCII table conversion.
		variable rx_ascii_chr : character;
		-- The flag to track if the ASCII buffer overflowed during this
		-- iteration of capturing RX data.
		variable rx_ascii_ovr : boolean := false;
		-- The byte line buffer.
		variable v_hex_expect : std_logic_vector(255 downto 0);
		-- The byte line buffer position/length count.
		variable v_hex_cnt    : natural := 0;
		-- The ScoreBoard binary value for finding in the history.
		variable v_slv_expect : t_reg_sb;
		-- A constant that is all Undefind, same type as the \ref v_slv_expect .
		constant c_all_undef : t_reg_sb := (others => 'U');
		-- Variable for querying the ScoreBoard FIFO position of the matching
		-- data \ref v_slv_expect .
		variable v_expect_idx : integer;
	begin
		wait for 0 ns;
		WaitForBarrier(BarrierLogStart);
		ID := ModelID;
		GetAlertLogID(TransRec, ID);
		WaitForClock(TransRec, 2);

		-- Loop receiving one byte at a time via RX UART in the test-bench.
		-- Upon receiving '\n' Line Feed character, analyze the received
		-- vector of bytes, pressuming that they are ASCII bytes, and that
		-- the vector contains a representation of the ScoreBoard type with
		-- 16 hexadecimal nibbles.
		l_recv_uart : loop
			-- Receive the next RX byte
			Get(TransRec, RxStim.Data);
			-- Prepare to track any errors
			RxStim.Error := std_logic_vector(TransRec.ParamFromModel);

			if (RxStim.Data = x"0A") then
				-- If the received byte is '\n' Line Feed, attempt to convert
				-- and find in the ScoreBoard.

				-- If the ASCII line buffer overflowed, alert an error.
				AlertIf(ModelID, rx_ascii_ovr, "The test model overflowed " &
					"receiving UART ASCII text line. Not all characters are " &
					"displayed.",
					ERROR);
				-- Log the ASCII line received
				Log(ModelID, "UART Received from FPGA the ASCII line: " &
					rx_ascii_buf(1 to rx_ascii_cnt),
					INFO);

				-- Convert the ASCII line to 64-bits of hexadecimal data
				v_slv_expect(63 downto 32) := fn_convert_hex_to_slv32(v_hex_expect(255 downto 128), 8);
				v_slv_expect(31 downto 0) := fn_convert_hex_to_slv32(v_hex_expect(127 downto 0), 8);

				Log(ModelID, "BOARD UART text line not configured to search ScoreBoard history", INFO);

				if (v_slv_expect /= c_all_undef) then
					-- If the expected data is not all "U" bits, then attempt to
					-- find the expected vector in the ScoreBoard. It will
					-- likely not be the first in the FIFO as the UART runs
					-- at a less frequent interval that the Pmod ACL2 filter
					-- rate. Thus, find the match and drop all preceding values.
					--v_expect_idx := SB_UART.Find(v_slv_expect);
					--Log(ModelID, "BOARD UART text line not configured to search ScoreBoard history", INFO);
					--SB_UART.Flush(v_expect_idx);
				else
					-- If \ref v_slv_expect is all "U" bits, then this ASCII
					-- line was something other than raw register values. Thus,
					-- do not test it with the ScoreBoard, but alert with a
					-- warning.
					--Alert(ModelID, "BOARD UART text line not tested with " &
					--	"ScoreBoard history.",
					--	WARNING);
				end if;

				-- Reset data tracking in preparation of receiving next text
				-- line.
				rx_ascii_buf := (others => NUL);
				rx_ascii_cnt := 0;
				rx_ascii_ovr := false;
				v_hex_expect := (others => 'U');
				v_hex_cnt := 0;
				v_slv_expect := (others => 'U');
			else
				-- Use a 8-bit at a time shift register to capture the current
				-- raw ASCII value from the RX UART. Only capture if the number 
				-- of bytes received this far is less than the length of the
				-- buffer, which is 32 ASCII bytes, same as the Pmod CLS
				-- display.
				if (v_hex_cnt < v_hex_expect'length / 8) then
					v_hex_expect := v_hex_expect((v_hex_expect'length - 1 - 8) downto 0) & RxStim.Data;
					v_hex_cnt := v_hex_cnt + 1;
				end if;

				-- Log the captured byte, both in raw vector value as well as
				-- the ASCII character conversion.
				rx_ascii_chr := fn_convert_slv_to_ascii(RxStim.Data);
				Log(ModelID, "UART Received ASCII byte: x" &
					to_hstring(RxStim.Data) &
					" '" & rx_ascii_chr & "'",
					DEBUG);

				-- Store the current ASCII character conversion, but only if
				-- the ASCII line buffer is not overflowed, and only if the
				-- the ASCII conversion is not carriage return '\r' or line
				-- feed '\n'.
				if (rx_ascii_cnt <= rx_ascii_buf'right) then
					if ((RxStim.Data /= x"0A") and (RxStim.Data /= x"0D")) then
						rx_ascii_cnt := rx_ascii_cnt + 1;
						rx_ascii_buf(rx_ascii_cnt) := rx_ascii_chr;
					end if;
				else
					-- If the ASCII buffer overlowed, flag for the Alert error
					-- when the ASCII line ends.
					rx_ascii_ovr := true;
				end if;
			end if;
		end loop l_recv_uart;
		wait ;
	end process UartTbRxProc ;

	-- The FPGA operates as UART TX only
	co_txd <= '0'; -- TX from PC is held stopped
end architecture simulation_default;
--------------------------------------------------------------------------------
