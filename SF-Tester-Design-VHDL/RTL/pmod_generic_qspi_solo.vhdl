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
-- \file pmod_generic_qspi_solo.vhdl
--
-- \brief Custom SPI driver for generic usage, able to operate Enhanced SPI on a
-- Quad I/O SPI bus. Quad I/O is stubbed, but incomplete.
--
-- \description A new SPI transaction can be issued when \ref o_spi_idle
-- indicates a '1'.
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
entity pmod_generic_qspi_solo is
	generic(
		-- Ratio of i_ext_spi_clk_x to SPI sck bus output.
		parm_ext_spi_clk_ratio : natural := 32;
		-- LOG2 of the TX FIFO max count
		parm_tx_len_bits : natural := 9;
		-- LOG2 of max Wait Cycles count between end of TX and start of RX
		parm_wait_cyc_bits : natural := 9;
		-- LOG2 of the RX FIFO max count
		parm_rx_len_bits : natural := 9
	);
	port(
		-- system clock and reset, with clock being MMCM generated as 4x the
		-- SPI bus speed
		i_ext_spi_clk_x : in std_logic;
		i_srst          : in std_logic;
		i_spi_ce_4x     : in std_logic;
		-- SPI machine system interfaces
		i_go_enhan  : in  std_logic;
		i_go_quadio : in  std_logic;
		o_spi_idle  : out std_logic;
		i_tx_len    : in  std_logic_vector((parm_tx_len_bits - 1) downto 0);
		i_wait_cyc  : in  std_logic_vector((parm_wait_cyc_bits - 1) downto 0);
		i_rx_len    : in  std_logic_vector((parm_rx_len_bits - 1) downto 0);
		-- SPI machine FIFO interfaces for TX
		i_tx_data    : in  std_logic_vector(7 downto 0);
		i_tx_enqueue : in  std_logic;
		o_tx_ready   : out std_logic;
		-- SPI machine FIFO interfaces for RX
		o_rx_data    : out std_logic_vector(7 downto 0);
		i_rx_dequeue : in  std_logic;
		o_rx_valid   : out std_logic;
		o_rx_avail   : out std_logic;
		-- SPI machine external interface to top-level
		eio_sck_o      : out std_logic;
		eio_sck_t      : out std_logic;
		eio_csn_o      : out std_logic;
		eio_csn_t      : out std_logic;
		eio_copi_dq0_o : out std_logic;
		eio_copi_dq0_i : in  std_logic;
		eio_copi_dq0_t : out std_logic;
		eio_cipo_dq1_o : out std_logic;
		eio_cipo_dq1_i : in  std_logic;
		eio_cipo_dq1_t : out std_logic;
		eio_wrpn_dq2_o : out std_logic;
		eio_wrpn_dq2_i : in  std_logic;
		eio_wrpn_dq2_t : out std_logic;
		eio_hldn_dq3_o : out std_logic;
		eio_hldn_dq3_i : in  std_logic;
		eio_hldn_dq3_t : out std_logic
	);
end entity pmod_generic_qspi_solo;
--------------------------------------------------------------------------------
architecture spi_hybrid_fsm of pmod_generic_qspi_solo is
	-- SPI FSM state declarations
	type t_spi_state is (
			-- Enhanced SPI with single MOSI, MISO states
			ST_IDLE_ENHAN, ST_START_D_ENHAN, ST_START_S_ENHAN,
			ST_TX_ENHAN, ST_WAIT_ENHAN, ST_RX_ENHAN, ST_STOP_S_ENHAN,
			ST_STOP_D_ENHAN);

	signal s_spi_pr_state                      : t_spi_state := ST_IDLE_ENHAN;
	signal s_spi_nx_state                      : t_spi_state := ST_IDLE_ENHAN;
	signal s_spi_pr_state_delayed1             : t_spi_state := ST_IDLE_ENHAN;
	signal s_spi_pr_state_delayed2             : t_spi_state := ST_IDLE_ENHAN;
	signal s_spi_pr_state_delayed3             : t_spi_state := ST_IDLE_ENHAN;
	attribute fsm_encoding                     : string;
	attribute fsm_encoding of s_spi_pr_state   : signal is "gray";
	attribute fsm_safe_state                   : string;
	attribute fsm_safe_state of s_spi_pr_state : signal is "default_state";

	-- Data start FSM state declarations
	type t_dat_state is (
			ST_WAIT_PULSE, ST_HOLD_PULSE_0, ST_HOLD_PULSE_1, ST_HOLD_PULSE_2,
			ST_HOLD_PULSE_3);
	signal s_dat_pr_state                      : t_dat_state := ST_WAIT_PULSE;
	signal s_dat_nx_state                      : t_dat_state := ST_WAIT_PULSE;
	attribute fsm_encoding of s_dat_pr_state   : signal is "gray";
	attribute fsm_safe_state of s_dat_pr_state : signal is "default_state";

	-- Timer signals and constants
	constant c_t_enhan_wait_ss  : natural := 4;
	constant c_t_enhan_max_tx   : natural := 2096;
	constant c_t_enhan_max_wait : natural := 512;
	constant c_t_enhan_max_rx   : natural := 2088;

	constant c_tmax : natural := c_t_enhan_max_tx - 1;

	signal s_t          : natural range 0 to c_tmax;
	signal s_t_delayed1 : natural range 0 to c_tmax;
	signal s_t_delayed2 : natural range 0 to c_tmax;
	signal s_t_delayed3 : natural range 0 to c_tmax;

	signal s_t_inc : natural range 1 to 4;

	-- SPI 4x and 1x clocking signals and enables
	signal s_spi_ce_4x   : std_logic;
	signal s_spi_clk_1x  : std_logic;
	signal s_spi_rst_1x  : std_logic;
	signal s_spi_clk_ce0 : std_logic;
	signal s_spi_clk_ce1 : std_logic;
	signal s_spi_clk_ce2 : std_logic;
	signal s_spi_clk_ce3 : std_logic;

	-- FSM pulse stretched
	signal s_go_enhan  : std_logic;

	-- FSM auxiliary registers
	signal s_tx_len_val    : unsigned((parm_tx_len_bits - 1) downto 0);
	signal s_tx_len_aux    : unsigned((parm_tx_len_bits - 1) downto 0);
	signal s_rx_len_val    : unsigned((parm_rx_len_bits - 1) downto 0);
	signal s_rx_len_aux    : unsigned((parm_rx_len_bits - 1) downto 0);
	signal s_wait_cyc_val  : unsigned((parm_wait_cyc_bits - 1) downto 0);
	signal s_wait_cyc_aux  : unsigned((parm_wait_cyc_bits - 1) downto 0);
	signal s_go_enhan_val  : std_logic;
	signal s_go_enhan_aux  : std_logic;

	-- FSM output status
	signal s_spi_idle : std_logic;

	-- Mapping for FIFO RX
	signal s_data_fifo_rx_in            : std_logic_vector(7 downto 0);
	signal s_data_fifo_rx_out           : std_logic_vector(7 downto 0);
	signal s_data_fifo_rx_re            : std_logic;
	signal s_data_fifo_rx_we            : std_logic;
	signal s_data_fifo_rx_full          : std_logic;
	signal s_data_fifo_rx_empty         : std_logic;
	signal s_data_fifo_rx_valid         : std_logic;
	signal s_data_fifo_rx_valid_stretch : std_logic;
	signal s_data_fifo_rx_rdcount       : std_logic_vector(10 downto 0);
	signal s_data_fifo_rx_wrcount       : std_logic_vector(10 downto 0);
	signal s_data_fifo_rx_almostfull    : std_logic;
	signal s_data_fifo_rx_almostempty   : std_logic;
	signal s_data_fifo_rx_wrerr         : std_logic;
	signal s_data_fifo_rx_rderr         : std_logic;

	-- Mapping for FIFO TX
	signal s_data_fifo_tx_in          : std_logic_vector(7 downto 0);
	signal s_data_fifo_tx_out         : std_logic_vector(7 downto 0);
	signal s_data_fifo_tx_re          : std_logic;
	signal s_data_fifo_tx_we          : std_logic;
	signal s_data_fifo_tx_full        : std_logic;
	signal s_data_fifo_tx_empty       : std_logic;
	--signal s_data_fifo_tx_valid       : std_logic;
	signal s_data_fifo_tx_rdcount     : std_logic_vector(10 downto 0);
	signal s_data_fifo_tx_wrcount     : std_logic_vector(10 downto 0);
	signal s_data_fifo_tx_almostfull  : std_logic;
	signal s_data_fifo_tx_almostempty : std_logic;
	signal s_data_fifo_tx_wrerr       : std_logic;
	signal s_data_fifo_tx_rderr       : std_logic;

	signal v_phase_counter : natural range 0 to (parm_ext_spi_clk_ratio - 1);

begin
	o_spi_idle <= '1' when ((s_spi_idle = '1') and (s_dat_pr_state = ST_WAIT_PULSE)) else '0';

	-- In this implementation, the 4x SPI clock is operated by a clock enable against
	-- the system clock \ref i_ext_spi_clk_x .
	s_spi_ce_4x <= i_spi_ce_4x;

	-- Mapping of the RX FIFO to external control and reception of datafor
	-- readingoperations
	o_rx_avail        <= (not s_data_fifo_rx_empty) and s_spi_ce_4x;
	o_rx_valid        <= s_data_fifo_rx_valid_stretch and s_spi_ce_4x;
	s_data_fifo_rx_re <= i_rx_dequeue and s_spi_ce_4x;
	o_rx_data         <= s_data_fifo_rx_out;

	u_pulse_stretch_fifo_rx_0 : entity work.pulse_stretcher_synch(moore_fsm_timed)
		generic map(
			par_T_stretch_count => (parm_ext_spi_clk_ratio / 4 - 1)
		)
		port map(
			o_y   => s_data_fifo_rx_valid_stretch,
			i_clk => i_ext_spi_clk_x,
			i_rst => i_srst,
			i_x   => s_data_fifo_rx_valid
		);

	p_gen_fifo_rx_valid : process(i_ext_spi_clk_x)
	begin
		if rising_edge(i_ext_spi_clk_x) then
			s_data_fifo_rx_valid <= s_data_fifo_rx_re;
		end if;
	end process p_gen_fifo_rx_valid;

	-- FIFO_SYNC_MACRO: Synchronous First-In, First-Out (FIFO) RAM Buffer
	--                  Artix-7
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

	u_fifo_rx_0 : FIFO_SYNC_MACRO
		generic map (
			DEVICE              => "7SERIES",      -- Target Device: "VIRTEX5, "VIRTEX6", "7SERIES" 
			ALMOST_FULL_OFFSET  => "0000" & x"80", -- Sets almost full threshold
			ALMOST_EMPTY_OFFSET => "0000" & x"80", -- Sets the almost empty threshold
			DATA_WIDTH          => 8,              -- Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
			FIFO_SIZE           => "18Kb")         -- Target BRAM, "18Kb" or "36Kb" 
		port map (
			ALMOSTEMPTY => s_data_fifo_rx_almostempty, -- 1-bit output almost empty
			ALMOSTFULL  => s_data_fifo_rx_almostfull,  -- 1-bit output almost full
			DO          => s_data_fifo_rx_out,         -- Output data, width defined by DATA_WIDTH parameter
			EMPTY       => s_data_fifo_rx_empty,       -- 1-bit output empty
			FULL        => s_data_fifo_rx_full,        -- 1-bit output full
			RDCOUNT     => s_data_fifo_rx_rdcount,     -- Output read count, width determined by FIFO depth
			RDERR       => s_data_fifo_rx_rderr,       -- 1-bit output read error
			WRCOUNT     => s_data_fifo_rx_wrcount,     -- Output write count, width determined by FIFO depth
			WRERR       => s_data_fifo_rx_wrerr,       -- 1-bit output write error
			CLK         => i_ext_spi_clk_x,            -- 1-bit input clock
			DI          => s_data_fifo_rx_in,          -- Input data, width defined by DATA_WIDTH parameter
			RDEN        => s_data_fifo_rx_re,          -- 1-bit input read enable
			RST         => i_srst,                     -- 1-bit input reset
			WREN        => s_data_fifo_rx_we           -- 1-bit input write enable
		);
	-- End of u_fifo_rx_0 instantiation

	-- Mapping of the TX FIFO to external control and transmission of data for
	-- PAGE PROGRAM operations
	s_data_fifo_tx_in <= i_tx_data;
	s_data_fifo_tx_we <= i_tx_enqueue and s_spi_ce_4x;
	o_tx_ready        <= (not s_data_fifo_tx_full) and s_spi_ce_4x;

	--p_gen_fifo_tx_valid : process(i_ext_spi_clk_x)
	--begin
	--	if rising_edge(i_ext_spi_clk_x) then
	--		s_data_fifo_tx_valid <= s_data_fifo_tx_re;
	--	end if;
	--end process p_gen_fifo_tx_valid;

	-- FIFO_SYNC_MACRO: Synchronous First-In, First-Out (FIFO) RAM Buffer
	--                  Artix-7
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

	u_fifo_tx_0 : FIFO_SYNC_MACRO
		generic map (
			DEVICE              => "7SERIES",     -- Target Device: "VIRTEX5, "VIRTEX6", "7SERIES" 
			ALMOST_FULL_OFFSET  => "000" & x"80", -- Sets almost full threshold
			ALMOST_EMPTY_OFFSET => "000" & x"80", -- Sets the almost empty threshold
			DATA_WIDTH          => 8,             -- Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
			FIFO_SIZE           => "18Kb")        -- Target BRAM, "18Kb" or "36Kb" 
		port map (
			ALMOSTEMPTY => s_data_fifo_tx_almostempty, -- 1-bit output almost empty
			ALMOSTFULL  => s_data_fifo_tx_almostfull,  -- 1-bit output almost full
			DO          => s_data_fifo_tx_out,         -- Output data, width defined by DATA_WIDTH parameter
			EMPTY       => s_data_fifo_tx_empty,       -- 1-bit output empty
			FULL        => s_data_fifo_tx_full,        -- 1-bit output full
			RDCOUNT     => s_data_fifo_tx_rdcount,     -- Output read count, width determined by FIFO depth
			RDERR       => s_data_fifo_tx_rderr,       -- 1-bit output read error
			WRCOUNT     => s_data_fifo_tx_wrcount,     -- Output write count, width determined by FIFO depth
			WRERR       => s_data_fifo_tx_wrerr,       -- 1-bit output write error
			CLK         => i_ext_spi_clk_x,            -- 1-bit input clock
			DI          => s_data_fifo_tx_in,          -- Input data, width defined by DATA_WIDTH parameter
			RDEN        => s_data_fifo_tx_re,          -- 1-bit input read enable
			RST         => i_srst,                     -- 1-bit input reset
			WREN        => s_data_fifo_tx_we           -- 1-bit input write enable
		);
	-- End of FIFO_SYNC_MACRO_inst instantiation

	-- spi clock for SCK output, generated clock
	-- requires create_generated_clock constraint in XDC
	u_spi_1x_clock_divider : entity work.clock_divider(rtl)
		generic map(
			par_clk_divisor => parm_ext_spi_clk_ratio
		)
		port map(
			o_clk_div => s_spi_clk_1x,
			o_rst_div => open,
			i_clk_mhz => i_ext_spi_clk_x,
			i_rst_mhz => i_srst
		);

	-- 25% point clock enables for period of 4 times SPI CLK output based on s_spi_ce_4x
	p_phase_4x_ce : process(i_ext_spi_clk_x)
	begin
		if rising_edge(i_ext_spi_clk_x) then
			if (i_srst = '1') then
				v_phase_counter <= 0;
			else
				if (v_phase_counter < parm_ext_spi_clk_ratio - 1) then
					v_phase_counter <= v_phase_counter + 1;
				else
					v_phase_counter <= 0;
				end if;
			end if;
		end if;
	end process p_phase_4x_ce;

	s_spi_clk_ce0 <= '1' when (v_phase_counter = parm_ext_spi_clk_ratio / 4 * 0) and (s_spi_ce_4x = '1') else '0';
	s_spi_clk_ce1 <= '1' when (v_phase_counter = parm_ext_spi_clk_ratio / 4 * 1) and (s_spi_ce_4x = '1') else '0';
	s_spi_clk_ce2 <= '1' when (v_phase_counter = parm_ext_spi_clk_ratio / 4 * 2) and (s_spi_ce_4x = '1') else '0';
	s_spi_clk_ce3 <= '1' when (v_phase_counter = parm_ext_spi_clk_ratio / 4 * 3) and (s_spi_ce_4x = '1') else '0';

	-- Timer 1 (Strategy #1) with modifiable timer increment
	p_timer_1 : process(i_ext_spi_clk_x)
	begin
		if rising_edge(i_ext_spi_clk_x) then
			if (i_srst = '1') then
				s_t          <= 0;
				s_t_delayed1 <= 0;
				s_t_delayed2 <= 0;
				s_t_delayed3 <= 0;
				s_t_inc      <= 1;
			else
				if (i_spi_ce_4x = '1') then
					s_t_delayed3 <= s_t_delayed2;
					s_t_delayed2 <= s_t_delayed1;
					s_t_delayed1 <= s_t;
				end if;

				-- clock enable on falling SPIedge
				-- for timerchange
				if (s_spi_clk_ce2 = '1') then
					if (s_spi_pr_state /= s_spi_nx_state) then
						s_t <= 0;
					elsif (s_t < c_tmax) then
						s_t <= s_t + s_t_inc;
					end if;
				end if;

				if (s_go_enhan = '1') then
					s_t_inc <= 1;
				end if;
			end if;
		end if;
	end process p_timer_1;

	-- FSM for holding control inputs upon system 4x clock cycle pulse on
	-- i_go_enhan.
	p_dat_fsm_state_aux : process(i_ext_spi_clk_x)
	begin
		if rising_edge(i_ext_spi_clk_x) then
			if (i_srst = '1') then
				s_dat_pr_state <= ST_WAIT_PULSE;

				s_tx_len_aux    <= (others => '0');
				s_rx_len_aux    <= (others => '0');
				s_wait_cyc_aux  <= (others => '0');
				s_go_enhan_aux  <= '0';

			elsif (s_spi_ce_4x = '1') then
				-- no phase counter clock enable as this is a system-side interface
				s_dat_pr_state <= s_dat_nx_state;

				-- auxiliary assignments
				s_tx_len_aux    <= s_tx_len_val;
				s_rx_len_aux    <= s_rx_len_val;
				s_wait_cyc_aux  <= s_wait_cyc_val;
				s_go_enhan_aux  <= s_go_enhan_val;
			end if;
		end if;
	end process p_dat_fsm_state_aux;

	-- Pass the auxiliary signals that last for a single iteration of all four
	-- i_spi_ce_4x clock enables on to the \ref p_spi_fsm_comb
	s_go_enhan  <= s_go_enhan_aux;

	-- System Data GO data value holder and i_go_enhan pulse stretcher for all
	-- four clock enables duration of the 4x clock, starting at an clock enable
	-- position. Combinatorial logic paired with the \ref p_dat_fsm_state
	-- assignments.
	p_dat_fsm_comb : process(s_dat_pr_state, i_go_enhan,
			i_tx_len, i_rx_len, i_wait_cyc, s_tx_len_aux, s_rx_len_aux,
			s_wait_cyc_aux, s_go_enhan_aux)
	begin
		s_tx_len_val    <= s_tx_len_aux;
		s_rx_len_val    <= s_rx_len_aux;
		s_wait_cyc_val  <= s_wait_cyc_aux;
		s_go_enhan_val  <= s_go_enhan_aux;

		case (s_dat_pr_state) is
			when ST_HOLD_PULSE_0 =>
				-- Hold the GO signal and auxiliary for this cycle.
				s_dat_nx_state <= ST_HOLD_PULSE_1;

			when ST_HOLD_PULSE_1 =>
				-- Hold the GO signal and auxiliary for this cycle.
				s_dat_nx_state <= ST_HOLD_PULSE_2;

			when ST_HOLD_PULSE_2 =>
				-- Hold the GO signal and auxiliary for this cycle.
				s_dat_nx_state <= ST_HOLD_PULSE_3;

			when ST_HOLD_PULSE_3 =>
				-- Reset the GO signal and and hold the auxiliary for this cycle.
				s_go_enhan_val  <= '0';
				s_dat_nx_state  <= ST_WAIT_PULSE;

			when others => -- ST_WAIT_PULSE
				           -- If GO signal is 1, assign it and the auxiliary on the
				           -- transition to the first HOLD state. Otherwise, hold
				           -- the values already assigned.
				if (i_go_enhan = '1') then
					s_go_enhan_val  <= i_go_enhan;
					s_tx_len_val    <= unsigned(i_tx_len);
					s_rx_len_val    <= unsigned(i_rx_len);
					s_wait_cyc_val  <= unsigned(i_wait_cyc);
					s_dat_nx_state  <= ST_HOLD_PULSE_0;
				else
					s_dat_nx_state <= ST_WAIT_PULSE;
				end if;
		end case;
	end process p_dat_fsm_comb;

	-- SPI bus control state machine assignments for falling edge of 1x clock
	-- assignment of state value, plus delayed state value for the RX capture
	-- on the SPI rising edge of 1x clock in a different process.
	p_spi_fsm_state : process(i_ext_spi_clk_x)
	begin
		if rising_edge(i_ext_spi_clk_x) then
			if (i_srst = '1') then
				s_spi_pr_state_delayed3 <= ST_IDLE_ENHAN;
				s_spi_pr_state_delayed2 <= ST_IDLE_ENHAN;
				s_spi_pr_state_delayed1 <= ST_IDLE_ENHAN;
				s_spi_pr_state          <= ST_IDLE_ENHAN;

			else
				if (s_spi_ce_4x = '1') then
					-- the delayed state value allows for registration of TX clock
					-- and double registration of RX value to capture after the
					-- registration of outputs and synchronization of inputs
					s_spi_pr_state_delayed3 <= s_spi_pr_state_delayed2;
					s_spi_pr_state_delayed2 <= s_spi_pr_state_delayed1;
					s_spi_pr_state_delayed1 <= s_spi_pr_state;
				end if;

				if (s_spi_clk_ce2 = '1') then -- clock enable on falling SPI edge
					                          -- for state change
					s_spi_pr_state <= s_spi_nx_state;
				end if;
			end if;
		end if;
	end process p_spi_fsm_state;

	-- SPI bus control state machine assignments for combinatorial assignmentto
	-- SPI bus outputs, timing of slave select, transmission of TXdata,
	-- holding for wait cycles, and timing for RX data where RX data iscaptured
	-- in a different synchronous state machine delayed from the state ofthis
	-- machine.
	p_spi_fsm_comb : process(s_spi_pr_state, s_spi_clk_1x, s_go_enhan,
			s_tx_len_aux, s_rx_len_aux,
			s_wait_cyc_aux, s_t, s_t_inc,
			s_data_fifo_tx_empty, s_spi_clk_ce2, s_spi_clk_ce3,
			s_data_fifo_rx_full,
			s_data_fifo_tx_out,
			eio_copi_dq0_i, eio_cipo_dq1_i, eio_wrpn_dq2_i, eio_hldn_dq3_i,
			i_tx_len, i_rx_len, i_wait_cyc)
	begin
		-- default to not idle indication
		s_spi_idle <= '0';
		-- default to running the SPI clock
		-- the 5 other pins are controlled explicitly within each state
		eio_sck_o <= s_spi_clk_1x;
		eio_sck_t <= '0';
		-- default to not reading from the TX FIFO
		s_data_fifo_tx_re <= '0';

		case (s_spi_pr_state) is
			when ST_START_D_ENHAN =>
				-- halt clock
				eio_sck_o <= '0';
				eio_sck_t <= '0';
				-- no chip select
				eio_csn_o <= '1';
				eio_csn_t <= '0';
				-- zero MOSI
				eio_copi_dq0_o <= '0';
				eio_copi_dq0_t <= '0';
				-- High-Z MISO
				eio_cipo_dq1_o <= '0';
				eio_cipo_dq1_t <= '1';
				-- Write Protect not asserted
				eio_wrpn_dq2_o <= '1';
				eio_wrpn_dq2_t <= '0';
				-- Hold not asserted
				eio_hldn_dq3_o <= '1';
				eio_hldn_dq3_t <= '0';

				-- wait for time to hold chip select value
				if (s_t = c_t_enhan_wait_ss - s_t_inc) then
					s_spi_nx_state <= ST_START_S_ENHAN;
				else
					s_spi_nx_state <= ST_START_D_ENHAN;
				end if;

			when ST_START_S_ENHAN =>
				-- halt clock
				eio_sck_o <= '0';
				eio_sck_t <= '0';
				-- assert chip select
				eio_csn_o <= '0';
				eio_csn_t <= '0';
				-- zero MOSI
				eio_copi_dq0_o <= '0';
				eio_copi_dq0_t <= '0';
				-- High-Z MISO
				eio_cipo_dq1_o <= '0';
				eio_cipo_dq1_t <= '1';
				-- Write Protect not asserted
				eio_wrpn_dq2_o <= '1';
				eio_wrpn_dq2_t <= '0';
				-- Hold not asserted
				eio_hldn_dq3_o <= '1';
				eio_hldn_dq3_t <= '0';

				-- hold not reading the TX FIFO
				s_data_fifo_tx_re <= s_spi_clk_ce3 when ((s_t = c_t_enhan_wait_ss - s_t_inc) and 
					(s_data_fifo_tx_empty = '0')) else '0';

				-- wait for time to hold chip select value
				if (s_t = c_t_enhan_wait_ss - s_t_inc) then
					s_spi_nx_state <= ST_TX_ENHAN;
				else
					s_spi_nx_state <= ST_START_S_ENHAN;
				end if;

			when ST_TX_ENHAN =>
				-- assert chip select
				eio_csn_o <= '0';
				eio_csn_t <= '0';

				-- output currently dequeued byte
				eio_copi_dq0_o <= s_data_fifo_tx_out(7 - (s_t mod 8)) when (s_t < 8 * s_tx_len_aux) else '0';
				eio_copi_dq0_t <= '0';

				-- High-Z CIPO
				eio_cipo_dq1_o <= '0';
				eio_cipo_dq1_t <= '1';
				-- Write Protect not asserted
				eio_wrpn_dq2_o <= '1';
				eio_wrpn_dq2_t <= '0';
				-- Hold not asserted
				eio_hldn_dq3_o <= '1';
				eio_hldn_dq3_t <= '0';

				-- read byte by byte from the TX FIFO
				-- only if on last bit, dequeue another byte
				s_data_fifo_tx_re <= s_spi_clk_ce2 when ((s_t /= (8 * s_tx_len_aux) - s_t_inc) and
					(s_t mod 8 = 7) and (s_data_fifo_tx_empty = '0')) else '0';

				-- If every bit from the FIFO according to i_tx_len value captured
				-- in s_tx_len_aux, then move to either WAIT for RX or STOP.
				if (s_t = (8 * s_tx_len_aux) - s_t_inc) then
					if (s_rx_len_aux > 0) then
						if (s_wait_cyc_aux > 0) then
							s_spi_nx_state <= ST_WAIT_ENHAN;
						else
							s_spi_nx_state <= ST_RX_ENHAN;
						end if;
					else
						s_spi_nx_state <= ST_STOP_S_ENHAN;
					end if;
				else
					s_spi_nx_state <= ST_TX_ENHAN;
				end if;

			when ST_WAIT_ENHAN =>
				-- assert chip select
				eio_csn_o <= '0';
				eio_csn_t <= '0';
				-- zero COPI
				eio_copi_dq0_o <= '0';
				eio_copi_dq0_t <= '0';
				-- High-Z CIPO
				eio_cipo_dq1_o <= '0';
				eio_cipo_dq1_t <= '1';
				-- Write Protect not asserted
				eio_wrpn_dq2_o <= '1';
				eio_wrpn_dq2_t <= '0';
				-- Hold not asserted
				eio_hldn_dq3_o <= '1';
				eio_hldn_dq3_t <= '0';

				if (s_t = s_wait_cyc_aux - s_t_inc) then
					s_spi_nx_state <= ST_RX_ENHAN;
				else
					s_spi_nx_state <= ST_WAIT_ENHAN;
				end if;

			when ST_RX_ENHAN =>
				-- assert chip select
				eio_csn_o <= '0';
				eio_csn_t <= '0';
				-- zero MOSI
				eio_copi_dq0_o <= '0';
				eio_copi_dq0_t <= '0';
				-- High-Z MISO
				eio_cipo_dq1_o <= '0';
				eio_cipo_dq1_t <= '1';
				-- Write Protect not asserted
				eio_wrpn_dq2_o <= '1';
				eio_wrpn_dq2_t <= '0';
				-- Hold not asserted
				eio_hldn_dq3_o <= '1';
				eio_hldn_dq3_t <= '0';

				-- If every bit from the FIFO according to i_rx_len value captured
				-- in s_rx_len_aux, then move to STOP.
				if (s_t = (8 * s_rx_len_aux) - s_t_inc) then
					s_spi_nx_state <= ST_STOP_S_ENHAN;
				else
					s_spi_nx_state <= ST_RX_ENHAN;
				end if;

			when ST_STOP_S_ENHAN =>
				-- halt clock
				eio_sck_o <= '0';
				eio_sck_t <= '0';
				-- assert chip select
				eio_csn_o <= '0';
				eio_csn_t <= '0';
				-- zero COPI
				eio_copi_dq0_o <= '0';
				eio_copi_dq0_t <= '0';
				-- High-Z CIPO
				eio_cipo_dq1_o <= '0';
				eio_cipo_dq1_t <= '1';
				-- Write Protect not asserted
				eio_wrpn_dq2_o <= '1';
				eio_wrpn_dq2_t <= '0';
				-- Hold not asserted
				eio_hldn_dq3_o <= '1';
				eio_hldn_dq3_t <= '0';

				-- wait for time to hold chip select value
				if (s_t = c_t_enhan_wait_ss - s_t_inc) then
					s_spi_nx_state <= ST_STOP_D_ENHAN;
				else
					s_spi_nx_state <= ST_STOP_S_ENHAN;
				end if;

			when ST_STOP_D_ENHAN =>
				-- halt clock
				eio_sck_o <= '0';
				eio_sck_t <= '0';
				-- deassert chip select
				eio_csn_o <= '1';
				eio_csn_t <= '0';
				-- zero COPI
				eio_copi_dq0_o <= '0';
				eio_copi_dq0_t <= '0';
				-- High-Z CIPO
				eio_cipo_dq1_o <= '0';
				eio_cipo_dq1_t <= '1';
				-- Write Protect not asserted
				eio_wrpn_dq2_o <= '1';
				eio_wrpn_dq2_t <= '0';
				-- Hold not asserted
				eio_hldn_dq3_o <= '1';
				eio_hldn_dq3_t <= '0';

				-- wait for time to hold chip select value deasserted
				if (s_t = c_t_enhan_wait_ss - s_t_inc) then
					s_spi_nx_state <= ST_IDLE_ENHAN;
				else
					s_spi_nx_state <= ST_STOP_D_ENHAN;
				end if;

			when others => -- ST_IDLE_ENHAN
				-- hald clock at Mode 0
				eio_sck_o      <= '0';
				eio_sck_t      <= '0';
				-- deasserted chip select
				eio_csn_o      <= '1';
				eio_csn_t      <= '0';
				-- zero value for COPI
				eio_copi_dq0_o <= '0';
				eio_copi_dq0_t <= '0';
				-- High-Z CIPO
				eio_cipo_dq1_o <= '0';
				eio_cipo_dq1_t <= '1';
				-- Write Protect not asserted
				eio_wrpn_dq2_o <= '1';
				eio_wrpn_dq2_t <= '0';
				-- Hold not asserted
				eio_hldn_dq3_o <= '1';
				eio_hldn_dq3_t <= '0';

				-- machine is idle
				s_spi_idle     <= '1';

				if (s_go_enhan = '1') then
					s_spi_nx_state <= ST_START_D_ENHAN;
				else
					s_spi_nx_state <= ST_IDLE_ENHAN;
				end if;
		end case;

	end process p_spi_fsm_comb;

	-- Captures the RX inputs into the RX fifo.
	-- Note that the RX inputs are delayed by 3 clk_4x clock cycles.
	-- Before the delay, the falling edge would occur at the capture of
	-- clock enable 0; but with the delay of registering output and double
	-- registering input, the FSM state is delayed by 3 clock cycles for
	-- RX only and the clock enable to process on the effective falling edge of
	-- the bus SCK as perceived from propagation out and back in, is 3 clock
	-- cycles, thus CE 3 instead of CE 0.
	p_spi_fsm_inputs : process(i_ext_spi_clk_x)
	begin
		if rising_edge(i_ext_spi_clk_x) then
			if (i_srst = '1') then
				s_data_fifo_rx_we             <= '0';
				s_data_fifo_rx_in(7 downto 0) <= x"00";
			else
				if (s_spi_clk_ce3 = '1') then
					if (s_spi_pr_state_delayed3 = ST_RX_ENHAN) then
						-- input current byte to enqueue, one bit at a time, shifting
						s_data_fifo_rx_in <= s_data_fifo_rx_in(6 downto 0) & eio_cipo_dq1_i when
							(s_t_delayed3 < (8 * s_rx_len_aux)) else x"00";

						-- only if on last bit, enqueue another byte
						-- only if RX FIFO is not full, enqueue another byte
						s_data_fifo_rx_we <= '1' when ((s_t_delayed3 mod 8 = 7) and
							(s_data_fifo_rx_full = '0')) else '0';
					else
						s_data_fifo_rx_we <= '0';
						s_data_fifo_rx_in <= x"00";
					end if;
				else
					s_data_fifo_rx_we <= '0';
					s_data_fifo_rx_in <= s_data_fifo_rx_in;
				end if;
			end if;
		end if;
	end process p_spi_fsm_inputs;

end architecture spi_hybrid_fsm;
--------------------------------------------------------------------------------
