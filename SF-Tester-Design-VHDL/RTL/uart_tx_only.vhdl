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
-- \file uart_tx_only.vhdl
--
-- \brief A simplified UART function to drive TX characters on a UART board
--        connection, independent of any RX function (presumed to be ingored).
--        Maximum baudrate is 115200; input clock is 7.37 MHz to support division
--        to modem clock rates.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library UNIMACRO;
use UNIMACRO.vcomponents.all;

library work;
--------------------------------------------------------------------------------
entity uart_tx_only is
	generic(
		-- the Modem Baud Rate of the UART TX machine, max 115200
		parm_BAUD : natural := 115200;
		-- the ASCII line length
		parm_ascii_line_length : natural := 35;
		-- the almost full threshold for FIFO byte count range 0 to 2047
		parm_almost_full_thresh : bit_vector(10 downto 0) := "111" & x"dc"
	);
	port(
		-- system clock
		i_clk_40mhz : in std_logic;
		i_rst_40mhz : in std_logic;
		-- modem clock from MMCM divided down
		i_clk_7_37mhz : in std_logic;
		i_rst_7_37mhz : in std_logic;
		-- the output to connect to USB-UART RXD pin
		eo_uart_tx : out std_logic;
		-- data to transmit out the UART
		i_tx_data  : in std_logic_vector(7 downto 0);
		i_tx_valid : in std_logic;
		-- indication that the FIFO is not almost full and can receive a line of data
		o_tx_ready : out std_logic
	);
end entity uart_tx_only;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
architecture moore_fsm_recursive of uart_tx_only is
	-- State machine states.
	type t_uarttxonly_fsm_state is (ST_IDLE, ST_START, ST_DATA, ST_STOP);

	-- State machine state register.
	signal s_uarttxonly_pr_state : t_uarttxonly_fsm_state;
	signal s_uarttxonly_nx_state : t_uarttxonly_fsm_state;
	-- Xilinx state machine register attributes.
	attribute fsm_encoding                            : string;
	attribute fsm_safe_state                          : string;
	attribute fsm_encoding of s_uarttxonly_pr_state   : signal is "gray";
	attribute fsm_safe_state of s_uarttxonly_pr_state : signal is "default_state";

	-- State machine output and auxiliary registers
	signal so_uart_tx : std_logic;
	signal s_i_val    : natural range 0 to 15;
	signal s_i_aux    : natural range 0 to 15;
	signal s_data_val : std_logic_vector(7 downto 0);
	signal s_data_aux : std_logic_vector(7 downto 0);

	-- Internal clock for 1x the baud rate.
	signal s_ce_baud_1x : std_logic;

	-- Mapping for FIFO TX.
	signal s_data_fifo_tx_in          : std_logic_vector(7 downto 0);
	signal s_data_fifo_tx_out         : std_logic_vector(7 downto 0);
	signal s_data_fifo_tx_re          : std_logic;
	signal s_data_fifo_tx_we          : std_logic;
	signal s_data_fifo_tx_full        : std_logic;
	signal s_data_fifo_tx_empty       : std_logic;
	signal s_data_fifo_tx_valid       : std_logic;
	signal s_data_fifo_tx_wr_count    : std_logic_vector(10 downto 0);
	signal s_data_fifo_tx_rd_count    : std_logic_vector(10 downto 0);
	signal s_data_fifo_tx_almostempty : std_logic;
	signal s_data_fifo_tx_almostfull  : std_logic;
	signal s_data_fifo_tx_rd_err      : std_logic;
	signal s_data_fifo_tx_wr_err      : std_logic;
begin
	-- clock enable for 1x times the baud rate: no oversampling for TX ONLY
	u_baud_1x_ce_divider : entity work.clock_enable_divider(rtl)
		generic map(
			par_ce_divisor => (4 * 16 * 115200 / parm_BAUD)
		)
		port map(
			o_ce_div  => s_ce_baud_1x,
			i_clk_mhz => i_clk_7_37mhz,
			i_rst_mhz => i_rst_7_37mhz,
			i_ce_mhz  => '1'
		);

	-- FIFO to receive from system and gradually transmit to UART. 
	-- The FIFO must implement read-ahead output on rd_en.
	s_data_fifo_tx_in <= i_tx_data;
	s_data_fifo_tx_we <= i_tx_valid;
	o_tx_ready        <= '1' when ((s_data_fifo_tx_full = '0') and (s_data_fifo_tx_almostfull = '0')) else '0';

	-- Generate a Valid pulse on TX read
	--p_gen_fifo_tx_valid : process(i_clk_7_37mhz)
	--begin
	--	if rising_edge(i_clk_7_37mhz) then
	--		s_data_fifo_tx_valid <= s_data_fifo_tx_re;
	--	end if;
	--end process p_gen_fifo_tx_valid;

	-- FIFO_DUALCLOCK_MACRO: Dual-Clock First-In, First-Out (FIFO) RAM Buffer
	--                       Artix-7
	-- Xilinx HDL Language Template, version 2019.1

	-- Note -  This Unimacro model assumes the port directions to be "downto". 
	--         Simulation of this model with "to" in the port directions could lead to erroneous results.

	-----------------------------------------------------------------
	-- DATA_WIDTH | FIFO_SIZE | FIFO Depth | RDCOUNT/WRCOUNT Width --
	-- ===========|===========|============|=======================--
	--   37-72    |  "36Kb"   |     512    |         9-bit         --
	--   19-36    |  "36Kb"   |    1024    |        10-bit         --
	--   19-36    |  "18Kb"   |     512    |         9-bit         --
	--   10-18    |  "36Kb"   |    2048    |        11-bit         --
	--   10-18    |  "18Kb"   |    1024    |        10-bit         --
	--    5-9     |  "36Kb"   |    4096    |        12-bit         --
	--    5-9     |  "18Kb"   |    2048    |        11-bit         --
	--    1-4     |  "36Kb"   |    8192    |        13-bit         --
	--    1-4     |  "18Kb"   |    4096    |        12-bit         --
	-----------------------------------------------------------------

	u_fifo_uart_tx_0 : FIFO_DUALCLOCK_MACRO
		generic map (
			DEVICE                  => "7SERIES",               -- Target Device: "VIRTEX5", "VIRTEX6", "7SERIES" 
			ALMOST_FULL_OFFSET      => parm_almost_full_thresh, -- Sets almost full threshold
			ALMOST_EMPTY_OFFSET     => "000" & x"23",           -- Sets the almost empty threshold
			DATA_WIDTH              => 8,                       -- Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
			FIFO_SIZE               => "18Kb",                  -- Target BRAM, "18Kb" or "36Kb" 
			FIRST_WORD_FALL_THROUGH => TRUE)                    -- Sets the FIFO FWFT to TRUE or FALSE
		port map (
			ALMOSTEMPTY => s_data_fifo_tx_almostempty, -- 1-bit output almost empty
			ALMOSTFULL  => s_data_fifo_tx_almostfull,  -- 1-bit output almost full
			DO          => s_data_fifo_tx_out,         -- Output data, width defined by DATA_WIDTH parameter
			EMPTY       => s_data_fifo_tx_empty,       -- 1-bit output empty
			FULL        => s_data_fifo_tx_full,        -- 1-bit output full
			RDCOUNT     => s_data_fifo_tx_rd_count,    -- Output read count, width determined by FIFO depth
			RDERR       => s_data_fifo_tx_rd_err,      -- 1-bit output read error
			WRCOUNT     => s_data_fifo_tx_wr_count,    -- Output write count, width determined by FIFO depth
			WRERR       => s_data_fifo_tx_wr_err,      -- 1-bit output write error
			DI          => s_data_fifo_tx_in,          -- Input data, width defined by DATA_WIDTH parameter
			RDCLK       => i_clk_7_37mhz,              -- 1-bit input read clock
			RDEN        => s_data_fifo_tx_re,          -- 1-bit input read enable
			RST         => i_rst_7_37mhz,              -- 1-bit input reset
			WRCLK       => i_clk_40mhz,                -- 1-bit input write clock
			WREN        => s_data_fifo_tx_we           -- 1-bit input write enable
		);
	-- End of u_fifo_uart_tx_0 instantiation

	-- FSM register and auxiliary registers
	p_uarttxonly_fsm_state_aux : process(i_clk_7_37mhz)
	begin
		if rising_edge(i_clk_7_37mhz) then
			if (i_rst_7_37mhz = '1') then
				s_uarttxonly_pr_state <= ST_IDLE;

				s_i_aux    <= 0;
				s_data_aux <= x"00";
			elsif (s_ce_baud_1x = '1') then
				s_uarttxonly_pr_state <= s_uarttxonly_nx_state;

				s_i_aux    <= s_i_val;
				s_data_aux <= s_data_val;
			end if;
		end if;
	end process p_uarttxonly_fsm_state_aux;

	-- FSM combinatorial logic with output and auxiliary registers
	p_uarttxonly_fsm_nx_out : process(s_uarttxonly_pr_state,
			s_data_fifo_tx_empty, s_i_aux, s_data_aux,
			s_data_fifo_tx_out, s_ce_baud_1x)
	begin
		case (s_uarttxonly_pr_state) is
			when ST_START =>
				-- Transmit the UART serial START bit '0' and load the 
				-- next TX FIFO byte on transition.
				s_data_fifo_tx_re <= s_ce_baud_1x;
				s_data_val        <= s_data_fifo_tx_out;
				s_i_val           <= 0;

				so_uart_tx <= '0';

				s_uarttxonly_nx_state <= ST_DATA;
			when ST_DATA =>
				-- Transmit the byte data to UART serial, least significant
				-- bit first, index 0 to 7.
				s_data_fifo_tx_re <= '0';
				s_data_val        <= s_data_aux;
				s_i_val           <= s_i_aux + 1;

				so_uart_tx <= s_data_aux(s_i_aux);

				if (s_i_aux = 7) then
					s_uarttxonly_nx_state <= ST_STOP;
				else
					s_uarttxonly_nx_state <= ST_DATA;
				end if;
			when ST_STOP =>
				-- Transmit the UART serial STOP bit '1'. Check the FIFO
				-- status. If FIFO contains more data, then transition
				-- directly back to the START bit. Otherwise, transition
				-- to the IDLE state.
				s_data_fifo_tx_re <= '0';
				s_data_val        <= s_data_aux;
				s_i_val           <= s_i_aux;

				so_uart_tx <= '1';

				if (s_data_fifo_tx_empty = '0') then
					s_uarttxonly_nx_state <= ST_START;
				else
					s_uarttxonly_nx_state <= ST_IDLE;
				end if;
			when others => -- ST_IDLE
				           -- The IDLE state holds a continuous high value on the
				           -- serial line to indicate UART signal is IDLE.
				s_data_fifo_tx_re <= '0';
				s_data_val        <= s_data_aux;
				s_i_val           <= s_i_aux;

				so_uart_tx <= '1';

				if (s_data_fifo_tx_empty = '0') then
					s_uarttxonly_nx_state <= ST_START;
				else
					s_uarttxonly_nx_state <= ST_IDLE;
				end if;
		end case;
	end process p_uarttxonly_fsm_nx_out;

	-- Registered output for timing closure and glitch removal on the output pin
	p_fsm_out_reg : process(i_clk_7_37mhz)
	begin
		if rising_edge(i_clk_7_37mhz) then
			if (s_ce_baud_1x = '1') then
				eo_uart_tx <= so_uart_tx;
			end if;
		end if;
	end process p_fsm_out_reg;

end architecture moore_fsm_recursive;
--------------------------------------------------------------------------------
