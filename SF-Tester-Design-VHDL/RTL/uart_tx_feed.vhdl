--------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2020 Timothy Stotts
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
-- \file uart_tx_feed.vhdl
--
-- \brief A simple text byte feeder to the UART TX module.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--------------------------------------------------------------------------------
entity uart_tx_feed is
	generic(
		-- the ASCII line length
		parm_ascii_line_length : natural := 35
	);
	port(
		-- system clock and reset
		i_clk_40mhz      : in  std_logic;
		i_rst_40mhz      : in  std_logic;
		-- data and valid pulse output to the UART TX
		o_tx_data        : out std_logic_vector(7 downto 0);
		o_tx_valid       : out std_logic;
		-- the TX Ready input from the UART TX
		i_tx_ready       : in  std_logic;
		-- system pulse to start transmit of a new line
		i_tx_go          : in  std_logic;
		-- data captured as next 35 character line to transmit
		i_dat_ascii_line : in  std_logic_vector((parm_ascii_line_length*8-1) downto 0)
	);
end entity uart_tx_feed;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
architecture rtl of uart_tx_feed is
	-- UART TX update FSM state declarations
	type t_uarttx_feed_state is (ST_UARTFEED_IDLE, ST_UARTFEED_CAPT,
			ST_UARTFEED_DATA, ST_UARTFEED_WAIT);

	-- UART feed FSM state register
	signal s_uartfeed_pr_state : t_uarttx_feed_state;
	signal s_uartfeed_nx_state : t_uarttx_feed_state;

	-- UART feed FSM auxliary registers
	signal s_uart_k_val    : natural range 0 to 63;
	signal s_uart_k_aux    : natural range 0 to 63;
	signal s_uart_line_val : std_logic_vector((parm_ascii_line_length*8-1) downto 0);
	signal s_uart_line_aux : std_logic_vector((parm_ascii_line_length*8-1) downto 0);

	-- preset values on START
	constant c_uart_k_preset : natural := parm_ascii_line_length;

	-- preset values on reset
	constant c_line_of_spaces : std_logic_vector((parm_ascii_line_length*8-1) downto 0) :=
		x"2020202020202020202020202020202020202020202020202020202020202020200D0A";

begin
	-- UART TX machine, the \ref parm_ascii_line_length bytes
	-- of \ref i_dat_ascii_line
	-- are feed into out the \ref o_tx_data and \ref o_tx_valid signals.
	-- Another module receives the bytes, indicates readiness on signal
	-- \ref i_tx_ready .

	-- UART TX machine, synchronous state, auxiliary counting register K,
	-- and auxiliary line data register LINE.
	p_uartfeed_fsm_state_aux : process(i_clk_40mhz)
	begin
		if rising_edge(i_clk_40mhz) then
			if (i_rst_40mhz = '1') then
				s_uartfeed_pr_state <= ST_UARTFEED_IDLE;
				s_uart_k_aux        <= 0;
				s_uart_line_aux     <= c_line_of_spaces;
			else
				s_uartfeed_pr_state <= s_uartfeed_nx_state;
				s_uart_k_aux        <= s_uart_k_val;
				s_uart_line_aux     <= s_uart_line_val;
			end if;
		end if;
	end process p_uartfeed_fsm_state_aux;

	-- UART TX machine, combinatorial next state, with usage of auxiliary
	-- counting register and auxiliary text line register.
	p_uartfeed_fsm_nx_out : process(s_uartfeed_pr_state, s_uart_k_aux, s_uart_line_aux,
			i_tx_go, i_dat_ascii_line, i_tx_ready)
	begin
		case (s_uartfeed_pr_state) is
			when ST_UARTFEED_CAPT =>
				-- Capture the input ASCII line and the index K.
				-- The value of \ref i_tx_ready is also checked as to
				-- not overflow the UART TX buffer. Once TX is ready,
				-- begin the enqueue of outgoing data. TX Ready is presumed to
				-- indicate that the TX FIFO is below the threshold of almost
				-- full and that enqueueing the full line will not overflow
				-- the TX FIFO.
				o_tx_data       <= x"00";
				o_tx_valid      <= '0';
				s_uart_k_val    <= c_uart_k_preset;
				s_uart_line_val <= i_dat_ascii_line;

				if (i_tx_ready = '1') then
					s_uartfeed_nx_state <= ST_UARTFEED_DATA;
				else
					s_uartfeed_nx_state <= ST_UARTFEED_CAPT;
				end if;

			when ST_UARTFEED_DATA =>
				-- Enqueue the \ref c_uart_k_preset count of bytes from register
				-- \ref s_uart_line_aux. Then transition to the WAIT state.
				-- To accomplish this, s_uart_line_aux is shifted left, one byte
				-- at-a-time.
				o_tx_data       <= s_uart_line_aux(((8 * c_uart_k_preset) - 1) downto (8 * (c_uart_k_preset - 1)));
				o_tx_valid      <= '1';
				s_uart_k_val    <= s_uart_k_aux - 1;
				s_uart_line_val <= s_uart_line_aux((8 * (c_uart_k_preset - 1) - 1) downto 0) & x"00";

				if (s_uart_k_aux = 1) then
					s_uartfeed_nx_state <= ST_UARTFEED_WAIT;
				else
					s_uartfeed_nx_state <= ST_UARTFEED_DATA;
				end if;

			when ST_UARTFEED_WAIT =>
				-- Wait for the \ref i_tx_go pulse to be low, and then
				-- transition to the IDLE state.
				o_tx_data       <= x"00";
				o_tx_valid      <= '0';
				s_uart_k_val    <= s_uart_k_aux;
				s_uart_line_val <= s_uart_line_aux;

				if (i_tx_go = '0') then
					s_uartfeed_nx_state <= ST_UARTFEED_IDLE;
				else
					s_uartfeed_nx_state <= ST_UARTFEED_WAIT;
				end if;

			when others => -- ST_UARTFEED_IDLE
				           -- IDLE the FSM while waiting for a pulse on \ref i_tx_go 
				o_tx_data       <= x"00";
				o_tx_valid      <= '0';
				s_uart_k_val    <= s_uart_k_aux;
				s_uart_line_val <= s_uart_line_aux;

				if (i_tx_go = '1') then
					s_uartfeed_nx_state <= ST_UARTFEED_CAPT;
				else
					s_uartfeed_nx_state <= ST_UARTFEED_IDLE;
				end if;
		end case;
	end process p_uartfeed_fsm_nx_out;

end architecture rtl;
--------------------------------------------------------------------------------
