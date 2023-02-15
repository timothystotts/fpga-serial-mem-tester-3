--------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2020,2022 Timothy Stotts
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
-- \file pmod_generic_spi_solo.vhdl
--
-- \brief A custom SPI driver for generic usage, implementing only Standard
-- SPI operating in Mode 0, without Extended data transfer of more than the
-- standard COPI and CIPO data signals. Note that the bus is only controlled to
-- TX data, optional waiting time, and optional RX data, for a Standard SPI Bus
-- with only one peripheral. This suits the Digilent Inc. SPI-based PMOD
-- peripherals well, but is too simplistic for a board design of one SPI bus
-- with multiple peripherals.
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
entity pmod_generic_spi_solo is
    generic(
        -- Ratio of i_ext_spi_clk_x to SPI sck bus output.
        parm_ext_spi_clk_ratio : natural := 32;
        -- LOG2 of the TX FIFO max count
        parm_tx_len_bits : natural := 11;
        -- LOG2 of max Wait Cycles count between end of TX and start of RX
        parm_wait_cyc_bits : natural := 2;
        -- LOG2 of the RX FIFO max count
        parm_rx_len_bits : natural := 11
    );
    port(
        -- SPI bus outputs and input to top-level
        eo_sck_o  : out std_logic;
        eo_sck_t  : out std_logic;
        eo_csn_o  : out std_logic;
        eo_csn_t  : out std_logic;
        eo_copi_o : out std_logic;
        eo_copi_t : out std_logic;
        ei_cipo_i : in  std_logic;
        -- SPI state machine clock at \ref parm_ext_spi_clk_ratio the SPI bus
        -- clock speed, with clock enable at 4x the SPI bus clock speed, and a
        -- synchronous reset
        i_ext_spi_clk_x : in std_logic;
        i_srst          : in std_logic;
        i_spi_ce_4x     : in std_logic;
        -- inputs and output for triggering a new SPI bus cycle
        i_go_stand : in  std_logic;
        o_spi_idle : out std_logic;
        i_tx_len   : in  std_logic_vector((parm_tx_len_bits - 1) downto 0);
        i_wait_cyc : in  std_logic_vector((parm_wait_cyc_bits - 1) downto 0);
        i_rx_len   : in  std_logic_vector((parm_rx_len_bits - 1) downto 0);
        -- system interface to TX FIFO
        i_tx_data    : in  std_logic_vector(7 downto 0);
        i_tx_enqueue : in  std_logic;
        o_tx_ready   : out std_logic;
        -- system interface to RX FIFO
        o_rx_data    : out std_logic_vector(7 downto 0);
        i_rx_dequeue : in  std_logic;
        o_rx_valid   : out std_logic;
        o_rx_avail   : out std_logic
    );
end entity pmod_generic_spi_solo;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
architecture moore_fsm_recursive of pmod_generic_spi_solo is
    -- SPI FSM state declarations
    type t_spi_state is (ST_STAND_IDLE, ST_STAND_START_D, ST_STAND_START_S,
            ST_STAND_TX, ST_STAND_WAIT, ST_STAND_RX, ST_STAND_STOP_S,
            ST_STAND_STOP_D);

    signal s_spi_pr_state          : t_spi_state := ST_STAND_IDLE;
    signal s_spi_nx_state          : t_spi_state := ST_STAND_IDLE;
    signal s_spi_pr_state_delayed1 : t_spi_state := ST_STAND_IDLE;
    signal s_spi_pr_state_delayed2 : t_spi_state := ST_STAND_IDLE;
    signal s_spi_pr_state_delayed3 : t_spi_state := ST_STAND_IDLE;
    -- Xilinx attributes for Gray encoding of the FSM and safe state is
    -- Default State.
    attribute fsm_encoding                     : string;
    attribute fsm_safe_state                   : string;
    attribute fsm_encoding of s_spi_pr_state   : signal is "gray";
    attribute fsm_safe_state of s_spi_pr_state : signal is "default_state";

    -- Data start FSM state declarations
    type t_dat_state is (ST_PULSE_WAIT, ST_PULSE_HOLD_0, ST_PULSE_HOLD_1,
            ST_PULSE_HOLD_2, ST_PULSE_HOLD_3);

    signal s_dat_pr_state : t_dat_state := ST_PULSE_WAIT;
    signal s_dat_nx_state : t_dat_state := ST_PULSE_WAIT;
    -- Xilinx attributes for Gray encoding of the FSM and safe state isDefault
    -- State.
    attribute fsm_encoding of s_dat_pr_state   : signal is "gray";
    attribute fsm_safe_state of s_dat_pr_state : signal is "default_state";

    -- Timer signals and constants
    constant c_t_stand_wait_ss  : natural := 4;
    constant c_t_stand_max_tx   : natural := 4144;
    constant c_t_stand_max_wait : natural := 31;
    constant c_t_stand_max_rx   : natural := 4136;
    constant c_tmax             : natural := c_t_stand_max_tx;
    constant c_t_inc            : natural := 1;

    signal s_t          : natural range 0 to c_tmax;
    signal s_t_delayed1 : natural range 0 to c_tmax;
    signal s_t_delayed2 : natural range 0 to c_tmax;
    signal s_t_delayed3 : natural range 0 to c_tmax;

    -- SPI 4x and 1x clocking signals and enables
    signal s_spi_ce_4x   : std_logic;
    signal s_spi_clk_1x  : std_logic;

    signal s_spi_clk_ce0 : std_logic;
    signal s_spi_clk_ce1 : std_logic;
    signal s_spi_clk_ce2 : std_logic;
    signal s_spi_clk_ce3 : std_logic;

    -- FSM pulse stretched signal
    signal s_go_stand : std_logic;

    -- FSM auxiliary registers
    signal s_tx_len_val   : unsigned((parm_tx_len_bits - 1) downto 0);
    signal s_tx_len_aux   : unsigned((parm_tx_len_bits - 1) downto 0);
    signal s_rx_len_val   : unsigned((parm_rx_len_bits - 1) downto 0);
    signal s_rx_len_aux   : unsigned((parm_rx_len_bits - 1) downto 0);
    signal s_wait_cyc_val : unsigned((parm_wait_cyc_bits - 1) downto 0);
    signal s_wait_cyc_aux : unsigned((parm_wait_cyc_bits - 1) downto 0);
    signal s_go_stand_val : std_logic;
    signal s_go_stand_aux : std_logic;

    -- FSM output status
    signal s_spi_idle : std_logic;

    -- Mapping for FIFO RX
    signal s_data_fifo_rx_in          : std_logic_vector(7 downto 0);
    signal s_data_fifo_rx_out         : std_logic_vector(7 downto 0);
    signal s_data_fifo_rx_re          : std_logic;
    signal s_data_fifo_rx_we          : std_logic;
    signal s_data_fifo_rx_full        : std_logic;
    signal s_data_fifo_rx_empty       : std_logic;
    signal s_data_fifo_rx_valid       : std_logic;
    signal s_data_fifo_rx_rdcount     : std_logic_vector(10 downto 0);
    signal s_data_fifo_rx_wrcount     : std_logic_vector(10 downto 0);
    signal s_data_fifo_rx_almostfull  : std_logic;
    signal s_data_fifo_rx_almostempty : std_logic;
    signal s_data_fifo_rx_wrerr       : std_logic;
    signal s_data_fifo_rx_rderr       : std_logic;

    -- Mapping for FIFO TX
    signal s_data_fifo_tx_in          : std_logic_vector(7 downto 0);
    signal s_data_fifo_tx_out         : std_logic_vector(7 downto 0);
    signal s_data_fifo_tx_re          : std_logic;
    signal s_data_fifo_tx_we          : std_logic;
    signal s_data_fifo_tx_full        : std_logic;
    signal s_data_fifo_tx_empty       : std_logic;
    -- signal s_data_fifo_tx_valid       : std_logic;
    signal s_data_fifo_tx_rdcount     : std_logic_vector(10 downto 0);
    signal s_data_fifo_tx_wrcount     : std_logic_vector(10 downto 0);
    signal s_data_fifo_tx_almostfull  : std_logic;
    signal s_data_fifo_tx_almostempty : std_logic;
    signal s_data_fifo_tx_wrerr       : std_logic;
    signal s_data_fifo_tx_rderr       : std_logic;

    -- A counter for tracking 4 phases of the clock enable against the bus
    -- output clock
    signal v_phase_counter : natural range 0 to (parm_ext_spi_clk_ratio - 1);

begin
    -- The SPI driver is IDLE only if the state signals as IDLE and more than four
    -- clock cycles have elapsed since a system clock pulse on input
    -- \ref i_go_stand.
    o_spi_idle <= '1' when ((s_spi_idle = '1') and (s_dat_pr_state = ST_PULSE_WAIT)) else '0';

    -- In this implementation, the 4x SPI clock is operated by a clock enable against
    -- the system clock \ref i_ext_spi_clk_x .
    s_spi_ce_4x <= i_spi_ce_4x;

    -- Mapping of the RX FIFO to external control and external reception of data for
    -- reading operations
    o_rx_avail        <= (not s_data_fifo_rx_empty) and s_spi_ce_4x;
    o_rx_valid        <= s_data_fifo_rx_valid and s_spi_ce_4x;
    s_data_fifo_rx_re <= i_rx_dequeue and s_spi_ce_4x;
    o_rx_data         <= s_data_fifo_rx_out;

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
    -- writing operations
    s_data_fifo_tx_in <= i_tx_data;
    s_data_fifo_tx_we <= i_tx_enqueue and s_spi_ce_4x;
    o_tx_ready        <= not s_data_fifo_tx_full and s_spi_ce_4x;

    --p_gen_fifo_tx_valid : process(i_ext_spi_clk_x)
    --begin
    --  if rising_edge(i_ext_spi_clk_x) then
    --      s_data_fifo_tx_valid <= s_data_fifo_tx_re;
    --  end if;
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

    -- Timer 1 (Strategy #1) with constant timer increment
    p_timer_1 : process(i_ext_spi_clk_x)
    begin
        if rising_edge(i_ext_spi_clk_x) then
            if (i_srst = '1') then
                s_t          <= 0;
                s_t_delayed1 <= 0;
                s_t_delayed2 <= 0;
                s_t_delayed3 <= 0;
            else
                if (i_spi_ce_4x = '1') then
                    s_t_delayed3 <= s_t_delayed2;
                    s_t_delayed2 <= s_t_delayed1;
                    s_t_delayed1 <= s_t;
                end if;

                -- clock enable on falling SPI edge for timer change
                if (s_spi_clk_ce2 = '1') then
                    if (s_spi_pr_state /= s_spi_nx_state) then
                        s_t <= 0;
                    elsif (s_t < c_tmax) then
                        s_t <= s_t + c_t_inc;
                    end if;
                end if;
            end if;
        end if;
    end process p_timer_1;

    -- System Data GO data value holder and i_go_stand pulse stretcher for duration
    -- of all four clock enables duration of the 4x clock, starting at a clock
    -- enable position. State assignment and Auxiliary register assignment.
    p_dat_fsm_state_aux : process(i_ext_spi_clk_x)
    begin
        if rising_edge(i_ext_spi_clk_x) then
            if (i_srst = '1') then
                s_dat_pr_state <= ST_PULSE_WAIT;

                s_tx_len_aux   <= to_unsigned(0, s_tx_len_aux'length);
                s_rx_len_aux   <= to_unsigned(0, s_rx_len_aux'length);
                s_wait_cyc_aux <= to_unsigned(0, s_wait_cyc_aux'length);
                s_go_stand_aux <= '0';

            elsif (s_spi_ce_4x = '1') then
                -- no clock enable as this is a system-side interface
                s_dat_pr_state <= s_dat_nx_state;

                -- auxiliary assignments
                s_tx_len_aux   <= s_tx_len_val;
                s_rx_len_aux   <= s_rx_len_val;
                s_wait_cyc_aux <= s_wait_cyc_val;
                s_go_stand_aux <= s_go_stand_val;
            end if;
        end if;
    end process p_dat_fsm_state_aux;

    -- Pass the auxiliary signal that lasts for a single iteration of all four
    -- s_spi_clk_4x clock enables on to the \ref p_spi_fsm_combmachine.
    s_go_stand <= s_go_stand_aux;

    -- System Data GO data value holder and i_go_stand pulse stretcher for all
    -- four clock enables duration of the 4x clock, starting at a clock enable
    -- position. Combinatorial logic paired with the \ref p_dat_fsm_state
    -- assignments.
    p_dat_fsm_comb : process(s_dat_pr_state, i_go_stand,
            i_tx_len, i_rx_len, i_wait_cyc,
            s_tx_len_aux, s_rx_len_aux, s_wait_cyc_aux,
            s_go_stand_aux)
    begin
        case (s_dat_pr_state) is
            when ST_PULSE_HOLD_0 =>
                -- Hold the GO signal and auxiliary for this cycle.
                s_go_stand_val <= s_go_stand_aux;
                s_tx_len_val   <= s_tx_len_aux;
                s_rx_len_val   <= s_rx_len_aux;
                s_wait_cyc_val <= s_wait_cyc_aux;
                s_dat_nx_state <= ST_PULSE_HOLD_1;

            when ST_PULSE_HOLD_1 =>
                -- Hold the GO signal and auxiliary for this cycle.
                s_go_stand_val <= s_go_stand_aux;
                s_tx_len_val   <= s_tx_len_aux;
                s_rx_len_val   <= s_rx_len_aux;
                s_wait_cyc_val <= s_wait_cyc_aux;
                s_dat_nx_state <= ST_PULSE_HOLD_2;

            when ST_PULSE_HOLD_2 =>
                -- Hold the GO signal and auxiliary for this cycle.
                s_go_stand_val <= s_go_stand_aux;
                s_tx_len_val   <= s_tx_len_aux;
                s_rx_len_val   <= s_rx_len_aux;
                s_wait_cyc_val <= s_wait_cyc_aux;
                s_dat_nx_state <= ST_PULSE_HOLD_3;

            when ST_PULSE_HOLD_3 =>
                -- Reset the GO signal and and hold the auxiliary for this cycle.
                s_go_stand_val <= '0';
                s_tx_len_val   <= s_tx_len_aux;
                s_rx_len_val   <= s_rx_len_aux;
                s_wait_cyc_val <= s_wait_cyc_aux;
                s_dat_nx_state <= ST_PULSE_WAIT;

            when others => -- ST_PULSE_WAIT
                -- If GO signal is 1, assign it and the auxiliary on the
                -- transition to the first HOLD state. Otherwise, hold
                -- the values already assigned.
                if (i_go_stand = '1') then
                    s_go_stand_val <= i_go_stand;
                    s_tx_len_val   <= unsigned(i_tx_len);
                    s_rx_len_val   <= unsigned(i_rx_len);
                    s_wait_cyc_val <= unsigned(i_wait_cyc);
                    s_dat_nx_state <= ST_PULSE_HOLD_0;
                else
                    s_go_stand_val <= s_go_stand_aux;
                    s_tx_len_val   <= s_tx_len_aux;
                    s_rx_len_val   <= s_rx_len_aux;
                    s_wait_cyc_val <= s_wait_cyc_aux;
                    s_dat_nx_state <= ST_PULSE_WAIT;
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
                s_spi_pr_state_delayed3 <= ST_STAND_IDLE;
                s_spi_pr_state_delayed2 <= ST_STAND_IDLE;
                s_spi_pr_state_delayed1 <= ST_STAND_IDLE;
                s_spi_pr_state          <= ST_STAND_IDLE;

            else
                if (s_spi_ce_4x = '1') then
                    -- The delayed state value allows for registration of TX clock
                    -- and double registration of RX value to capture after the
                    -- registration of outputs and synchronization of inputs.
                    s_spi_pr_state_delayed3 <= s_spi_pr_state_delayed2;
                    s_spi_pr_state_delayed2 <= s_spi_pr_state_delayed1;
                    s_spi_pr_state_delayed1 <= s_spi_pr_state;
                end if;

                -- clock enable on falling SPI edge for state change
                if (s_spi_clk_ce2 = '1') then
                    s_spi_pr_state <= s_spi_nx_state;
                end if;
            end if;
        end if;
    end process p_spi_fsm_state;

    -- SPI bus control state machine assignments for combinatorial assignment to
    -- SPI bus outputs, timing of chip select, transmission of TXdata,
    -- holding for wait cycles, and timing for RX data where RX data is captured
    -- in a different synchronous state machine delayed from the state of this
    -- machine.
    p_spi_fsm_comb : process(s_spi_pr_state, s_spi_clk_1x, s_go_stand,
            s_tx_len_aux, s_rx_len_aux, s_wait_cyc_aux,
            s_t,
            s_data_fifo_tx_empty, s_data_fifo_tx_out,
            s_spi_clk_ce2, s_spi_clk_ce3)
    begin
        case (s_spi_pr_state) is
            when ST_STAND_START_D =>
                -- halt clock at Mode 0
                eo_sck_o <= '0';
                eo_sck_t <= '0';
                -- no chips elect
                eo_csn_o <= '1';
                eo_csn_t <= '0';
                -- zero value for COPI
                eo_copi_o <= '0';
                eo_copi_t <= '0';
                -- hold not reading the TX FIFO
                s_data_fifo_tx_re <= '0';
                -- machine is not idle
                s_spi_idle <= '0';

                -- time the chip not selected start time
                if (s_t = c_t_stand_wait_ss - c_t_inc) then
                    s_spi_nx_state <= ST_STAND_START_S;
                else
                    s_spi_nx_state <= ST_STAND_START_D;
                end if;

            when ST_STAND_START_S =>
                -- halt clock at Mode 0
                eo_sck_o <= '0';
                eo_sck_t <= '0';
                -- assert chip select
                eo_csn_o <= '0';
                eo_csn_t <= '0';
                -- zero value for COPI
                eo_copi_o <= '0';
                eo_copi_t <= '0';
                -- machine is not idle
                s_spi_idle <= '0';

                -- start reading the TX FIFO only on transition to next state
                s_data_fifo_tx_re <= s_spi_clk_ce3 when
                        ((s_t = c_t_stand_wait_ss - c_t_inc) and
                        (s_data_fifo_tx_empty = '0')) else '0';

                -- time the chip selected start time
                if (s_t = c_t_stand_wait_ss - c_t_inc) then
                    s_spi_nx_state <= ST_STAND_TX;
                else
                    s_spi_nx_state <= ST_STAND_START_S;
                end if;

            when ST_STAND_TX =>
                -- run clock at Mode 0
                eo_sck_o <= s_spi_clk_1x;
                eo_sck_t <= '0';
                -- assert chip select
                eo_csn_o <= '0';
                eo_csn_t <= '0';
                -- data value for COPI, muxing the TX FIFO 8-bits ready to TX
                eo_copi_o <= s_data_fifo_tx_out(7 - (s_t mod 8)) when (s_t < 8 * s_tx_len_aux) else '0';
                eo_copi_t <= '0';

                -- machine is not idle
                s_spi_idle <= '0';

                -- read-enable byte by byte from the TX FIFO
                -- only if on last bit, dequeue another byte
                s_data_fifo_tx_re <= s_spi_clk_ce2 when ((s_t /= (8 * s_tx_len_aux) - c_t_inc) and
                        (s_t mod 8 = 7) and (s_data_fifo_tx_empty = '0')) else '0';

                -- If every bit from the FIFO according to i_tx_len value captured
                -- in s_tx_len_aux, then move to either WAIT, RX, or STOP.
                if (s_t = (8 * s_tx_len_aux) - c_t_inc) then
                    if (s_rx_len_aux > 0) then
                        if (s_wait_cyc_aux > 0) then
                            s_spi_nx_state <= ST_STAND_WAIT;
                        else
                            s_spi_nx_state <= ST_STAND_RX;
                        end if;
                    else
                        s_spi_nx_state <= ST_STAND_STOP_S;
                    end if;
                else
                    s_spi_nx_state <= ST_STAND_TX;
                end if;

            when ST_STAND_WAIT =>
                -- run clock at Mode 0
                eo_sck_o <= s_spi_clk_1x;
                eo_sck_t <= '0';
                -- assert chip select
                eo_csn_o <= '0';
                eo_csn_t <= '0';
                -- zero value for COPI
                eo_copi_o <= '0';
                eo_copi_t <= '0';
                -- hold not reading the TX FIFO
                s_data_fifo_tx_re <= '0';
                -- machine is not idle
                s_spi_idle <= '0';

                -- time the wait duration and then move to RX
                if (s_t = s_wait_cyc_aux - c_t_inc) then
                    s_spi_nx_state <= ST_STAND_RX;
                else
                    s_spi_nx_state <= ST_STAND_WAIT;
                end if;

            when ST_STAND_RX =>
                -- run clock at Mode 0
                eo_sck_o <= s_spi_clk_1x;
                eo_sck_t <= '0';
                -- assert chip select
                eo_csn_o <= '0';
                eo_csn_t <= '0';
                -- zero value for COPI
                eo_copi_o <= '0';
                eo_copi_t <= '0';
                -- hold not reading the TX FIFO
                s_data_fifo_tx_re <= '0';
                -- machine is not idle
                s_spi_idle <= '0';

                -- time the RX bit count and then begin deselect SPI chip
                if (s_t = (8 * s_rx_len_aux) - c_t_inc) then
                    s_spi_nx_state <= ST_STAND_STOP_S;
                else
                    s_spi_nx_state <= ST_STAND_RX;
                end if;

            when ST_STAND_STOP_S =>
                -- halt clock at Mode 0
                eo_sck_o <= '0';
                eo_sck_t <= '0';
                -- assert chip select
                eo_csn_o <= '0';
                eo_csn_t <= '0';
                -- zero value for COPI
                eo_copi_o <= '0';
                eo_copi_t <= '0';
                -- hold not reading the TX FIFO
                s_data_fifo_tx_re <= '0';
                -- machine is not idle
                s_spi_idle <= '0';

                -- wait the chip selected delay time
                if (s_t = c_t_stand_wait_ss - c_t_inc) then
                    s_spi_nx_state <= ST_STAND_STOP_D;
                else
                    s_spi_nx_state <= ST_STAND_STOP_S;
                end if;

            when ST_STAND_STOP_D =>
                -- halt clock at Mode 0
                eo_sck_o <= '0';
                eo_sck_t <= '0';
                -- no chip select
                eo_csn_o <= '1';
                eo_csn_t <= '0';
                -- zero value for COPI
                eo_copi_o <= '0';
                eo_copi_t <= '0';
                -- hold not reading the TX FIFO
                s_data_fifo_tx_re <= '0';
                -- machine is not idle
                s_spi_idle <= '0';

                -- the chip not selected stop time
                if (s_t = c_t_stand_wait_ss - c_t_inc) then
                    s_spi_nx_state <= ST_STAND_IDLE;
                else
                    s_spi_nx_state <= ST_STAND_STOP_D;
                end if;

            when others => -- ST_STAND_IDLE
                -- halt clock at Mode 0
                eo_sck_o <= '0';
                eo_sck_t <= '0';
                -- no chip select
                eo_csn_o <= '1';
                eo_csn_t <= '0';
                -- zero value for COPI
                eo_copi_o <= '0';
                eo_copi_t <= '0';
                -- hold not reading the TX FIFO
                s_data_fifo_tx_re <= '0';
                -- machine is idle
                s_spi_idle <= '1';

                -- run the SPI cycle only if \ref s_go_stand is pulsed while idle
                if (s_go_stand = '1') then
                    s_spi_nx_state <= ST_STAND_START_D;
                else
                    s_spi_nx_state <= ST_STAND_IDLE;
                end if;
        end case;
    end process p_spi_fsm_comb;

    -- Captures the RX inputs into the RX fifo.
    -- Note that the RX inputs are delayed by 3 clk_4x clock cycles
    -- before the delay, the falling edge would occur at the capture of
    -- clock enable 0; but with the delay of registering output and double
    -- registering input, the FSM state is delayed by 3 clock cycles for
    -- RX only and the clock enable to process on the effective falling edge of
    -- the bus SCK as perceived from propagation out and back in, is 3 clock
    -- cycles, thus CE 3 instead of CE 0.
    p_spi_fsm_inputs : process(i_ext_spi_clk_x)
    begin
        if rising_edge(i_ext_spi_clk_x) then
            if (i_srst = '1') then
                s_data_fifo_rx_we <= '0';
                s_data_fifo_rx_in <= x"00";
            else
                if (s_spi_clk_ce3 = '1') then
                    if (s_spi_pr_state_delayed3 = ST_STAND_RX) then
                        -- input current byte to enqueue, one bit at a time, shifting
                        s_data_fifo_rx_in <= s_data_fifo_rx_in(6 downto 0) & ei_cipo_i when
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

end architecture moore_fsm_recursive;
--------------------------------------------------------------------------------
