--------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2020,2023 Timothy Stotts
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
-- \file sf_tester_fsm.vhdl
--
-- \brief A package to contain constants, types and functions for the
-- SF Tester FSM module.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--------------------------------------------------------------------------------
package sf_tester_fsm_pkg is
    -- Function to determine the maximum value of timer T based upon whether
    -- the module is operating with fast simulation, or is synthesized to target.
    -- If simulating, the return is 3 milliseconds. If synthesized, the return is
    -- 3 seconds.
    function fn_set_t_max(fclk : natural; div_ratio : natural; fast_sim : integer)
        return natural;

    -- The Tester FSM states definition
    type t_tester_state is (ST_WAIT_BUTTON_DEP, ST_WAIT_BUTTON0_REL,
            ST_WAIT_BUTTON1_REL, ST_WAIT_BUTTON2_REL, ST_WAIT_BUTTON3_REL,
            ST_SET_PATTERN_A, ST_SET_PATTERN_B, ST_SET_PATTERN_C, ST_SET_PATTERN_D,
            ST_SET_START_ADDR_A, ST_SET_START_ADDR_B, ST_SET_START_ADDR_C,
            ST_SET_START_ADDR_D, ST_SET_START_WAIT_A, ST_SET_START_WAIT_B,
            ST_SET_START_WAIT_C, ST_SET_START_WAIT_D,
            ST_CMD_ERASE_START, ST_CMD_ERASE_WAIT, ST_CMD_ERASE_NEXT,
            ST_CMD_ERASE_DONE, ST_CMD_PAGE_START, ST_CMD_PAGE_BYTE, ST_CMD_PAGE_WAIT,
            ST_CMD_PAGE_NEXT, ST_CMD_PAGE_DONE, ST_CMD_READ_START, ST_CMD_READ_BYTE,
            ST_CMD_READ_WAIT, ST_CMD_READ_NEXT, ST_CMD_READ_DONE, ST_DISPLAY_FINAL
        );

    -- system control of N25Q state machine
    --constant c_max_possible_byte_count  : natural := 67_108_864; -- 512 Mbit
    constant c_max_possible_byte_count  : natural := 33_554_432; -- 256 Mbit
    constant c_total_iteration_count    : natural := 32;
    constant c_per_iteration_byte_count : natural :=
        c_max_possible_byte_count / c_total_iteration_count;
    constant c_last_starting_byte_addr : natural :=
        c_per_iteration_byte_count * (c_total_iteration_count - 1);

    constant c_sf3_subsector_addr_incr : natural := 4096;
    constant c_sf3_page_addr_incr      : natural := 256;

    constant c_tester_subsector_cnt_per_iter : natural := 8192 / c_total_iteration_count;
    constant c_tester_page_cnt_per_iter      : natural := 131072 / c_total_iteration_count;

    -- Testing patterns, the starting byte value and the byte increment value, causing
    -- either a sequential counting pattern or a pseudo-random counting pattern. All
    -- 8-bit values will occur in the sequence if the increment is a prime number.
    constant c_tester_pattern_startval_a : unsigned(7 downto 0) := x"00";
    constant c_tester_pattern_incrval_a  : unsigned(7 downto 0) := x"01";

    constant c_tester_pattern_startval_b : unsigned(7 downto 0) := x"08";
    constant c_tester_pattern_incrval_b  : unsigned(7 downto 0) := x"07";

    constant c_tester_pattern_startval_c : unsigned(7 downto 0) := x"10";
    constant c_tester_pattern_incrval_c  : unsigned(7 downto 0) := x"0F";

    constant c_tester_pattern_startval_d : unsigned(7 downto 0) := x"18";
    constant c_tester_pattern_incrval_d  : unsigned(7 downto 0) := x"17";

end package sf_tester_fsm_pkg;
--------------------------------------------------------------------------------
package body sf_tester_fsm_pkg is
    function fn_set_t_max(fclk : natural; div_ratio : natural; fast_sim : integer)
        return natural is
    begin
        if (fast_sim = 0) then
            return fclk / div_ratio * 3 - 1; -- three second delay count
        else
            return fclk / div_ratio * 3 / 1000 - 1; -- three millisecond delay count
        end if;
    end function fn_set_t_max;
end package body;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.sf_tester_fsm_pkg.all;
--------------------------------------------------------------------------------
entity sf_tester_fsm is
    generic(
        -- define as non-zero for a fast simulation that is faster than
        -- synthesis timing for the purpose of displaying SPI bus with a visual
        -- testbench.
        parm_fast_simulation         : natural := 0;
        -- Frequency of the clock
        parm_FCLK                    : natural := 40_000_000;
        -- Ratio of the clock enable to the clock
        parm_sf3_tester_ce_div_ratio : natural := 2;
        -- Patterns A, B, C, D
        parm_pattern_startval_a      : unsigned(7 downto 0);
        parm_pattern_incrval_a       : unsigned(7 downto 0);
        parm_pattern_startval_b      : unsigned(7 downto 0);
        parm_pattern_incrval_b       : unsigned(7 downto 0);
        parm_pattern_startval_c      : unsigned(7 downto 0);
        parm_pattern_incrval_c       : unsigned(7 downto 0);
        parm_pattern_startval_d      : unsigned(7 downto 0);
        parm_pattern_incrval_d       : unsigned(7 downto 0);
        -- Maximum byte count of the memory being operated
        parm_max_possible_byte_count : natural
    );
    port(
        -- clock and reset
        i_clk_40mhz : in std_logic;
        i_rst_40mhz : in std_logic;
        i_ce_div    : in std_logic;
        -- interface to Pmod SF3 Custom Driver
        i_sf3_command_ready       : in  std_logic;
        i_sf3_rd_data_valid       : in  std_logic;
        i_sf3_rd_data_stream      : in  std_logic_vector(7 downto 0);
        i_sf3_wr_data_ready       : in  std_logic;
        o_sf3_wr_data_stream      : out std_logic_vector(7 downto 0);
        o_sf3_wr_data_valid       : out std_logic;
        o_sf3_len_random_read     : out std_logic_vector(8 downto 0);
        o_sf3_cmd_random_read     : out std_logic;
        o_sf3_cmd_page_program    : out std_logic;
        o_sf3_cmd_erase_subsector : out std_logic;
        o_sf3_address_of_cmd      : out std_logic_vector(31 downto 0);
        -- interface to user I/O
        i_buttons_debounced  : in std_logic_vector(3 downto 0);
        i_switches_debounced : in std_logic_vector(3 downto 0);
        -- state and status outputs
        o_tester_pr_state : out t_tester_state;
        o_addr_start      : out std_logic_vector(31 downto 0);
        o_pattern_start   : out std_logic_vector(7 downto 0);
        o_pattern_incr    : out std_logic_vector(7 downto 0);
        o_error_count     : out natural range 0 to parm_max_possible_byte_count;
        o_test_pass       : out std_logic;
        o_test_done       : out std_logic
    );
end entity sf_tester_fsm;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
architecture rtl of sf_tester_fsm is
    -- Maximum count is three seconds parm_FCLK / parm_sf3_tester_ce_div_ratio * 3 - 1
    -- for hardware execution.
    constant c_t_max : natural := fn_set_t_max(parm_FCLK, parm_sf3_tester_ce_div_ratio, parm_fast_simulation);

    -- Timer variable
    signal s_t : natural range 0 to c_t_max;

    -- Tester state value
    signal s_tester_pr_state   : t_tester_state;
    signal s_tester_nx_state   : t_tester_state;

    -- Tester auxiliary registers
    signal s_dat_wr_cntidx_val : natural range 0 to 255;
    signal s_dat_wr_cntidx_aux : natural range 0 to 255;
    signal s_dat_rd_cntidx_val : natural range 0 to 255;
    signal s_dat_rd_cntidx_aux : natural range 0 to 255;
    signal s_test_pass_val     : std_logic;
    signal s_test_pass_aux     : std_logic;
    signal s_test_done_val     : std_logic;
    signal s_test_done_aux     : std_logic;
    signal s_err_count_val     : natural range 0 to parm_max_possible_byte_count;
    signal s_err_count_aux     : natural range 0 to parm_max_possible_byte_count;
    signal s_pattern_start_val   : std_logic_vector(7 downto 0);
    signal s_pattern_start_aux   : std_logic_vector(7 downto 0);
    signal s_pattern_incr_val    : std_logic_vector(7 downto 0);
    signal s_pattern_incrval_aux : std_logic_vector(7 downto 0);
    signal s_pattern_track_val   : std_logic_vector(7 downto 0);
    signal s_pattern_track_aux   : std_logic_vector(7 downto 0);
    signal s_addr_start_val      : std_logic_vector(31 downto 0);
    signal s_addr_start_aux      : std_logic_vector(31 downto 0);
    signal s_start_at_zero_val   : std_logic;
    signal s_start_at_zero_aux   : std_logic;
    signal s_i_val               : natural range 0 to c_tester_page_cnt_per_iter;
    signal s_i_aux               : natural range 0 to c_tester_page_cnt_per_iter;
begin
    -- Outputs for other modules to read
    o_tester_pr_state <= s_tester_pr_state;
    o_addr_start      <= s_addr_start_aux;
    o_pattern_start   <= s_pattern_start_aux;
    o_pattern_incr    <= s_pattern_incrval_aux;
    o_error_count     <= s_err_count_aux;
    o_test_pass       <= s_test_pass_aux;
    o_test_done       <= s_test_done_aux;

    -- Timer strategy #1 for the serial flash tester FSM
    p_tester_timer : process(i_clk_40mhz)
    begin
        if rising_edge(i_clk_40mhz) then
            if (i_rst_40mhz = '1') then
                s_t <= 0;
            elsif (i_ce_div = '1') then
                if (s_tester_pr_state /= s_tester_nx_state) then
                    s_t <= 0;
                elsif (s_t < c_t_max) then
                    s_t <= s_t + 1;
                end if;
            end if;
        end if;
    end process p_tester_timer;

    -- State and auxiliary registers for the serial flash tester FSM
    p_tester_fsm_state : process(i_clk_40mhz)
    begin
        if rising_edge(i_clk_40mhz) then
            if (i_rst_40mhz = '1') then
                s_tester_pr_state <= ST_WAIT_BUTTON_DEP;

                s_dat_wr_cntidx_aux   <= 0;
                s_dat_rd_cntidx_aux   <= 0;
                s_test_pass_aux       <= '0';
                s_test_done_aux       <= '0';
                s_err_count_aux       <= 0;
                s_pattern_start_aux   <= std_logic_vector(parm_pattern_startval_a);
                s_pattern_incrval_aux <= std_logic_vector(parm_pattern_incrval_a);
                s_pattern_track_aux   <= x"00";
                s_addr_start_aux      <= x"00000000";
                s_start_at_zero_aux   <= '1';
                s_i_aux               <= 0;

            elsif (i_ce_div = '1') then
                s_tester_pr_state <= s_tester_nx_state;

                s_dat_wr_cntidx_aux   <= s_dat_wr_cntidx_val;
                s_dat_rd_cntidx_aux   <= s_dat_rd_cntidx_val;
                s_test_pass_aux       <= s_test_pass_val;
                s_test_done_aux       <= s_test_done_val;
                s_err_count_aux       <= s_err_count_val;
                s_pattern_start_aux   <= s_pattern_start_val;
                s_pattern_incrval_aux <= s_pattern_incr_val;
                s_pattern_track_aux   <= s_pattern_track_val;
                s_addr_start_aux      <= s_addr_start_val;
                s_start_at_zero_aux   <= s_start_at_zero_val;
                s_i_aux               <= s_i_val;
            end if;
        end if;
    end process p_tester_fsm_state;

    -- Combinatorial logic for the serial flash tester FSM
    p_tester_fsm_comb : process(
            s_tester_pr_state,
            i_buttons_debounced, i_switches_debounced,
            i_sf3_wr_data_ready,
            i_sf3_command_ready,
            i_sf3_rd_data_valid,
            i_sf3_rd_data_stream,
            s_dat_wr_cntidx_aux,
            s_dat_rd_cntidx_aux,
            s_test_pass_aux,
            s_test_done_aux,
            s_err_count_aux,
            s_pattern_start_aux,
            s_pattern_incrval_aux,
            s_pattern_track_aux,
            s_addr_start_aux,
            s_start_at_zero_aux,
            s_i_aux,
            s_t)
    begin
        -- Default auxiliary register no-change values for briefer code
        s_dat_wr_cntidx_val <= s_dat_wr_cntidx_aux;
        s_dat_rd_cntidx_val <= s_dat_rd_cntidx_aux;
        s_test_pass_val     <= s_test_pass_aux;
        s_test_done_val     <= s_test_done_aux;
        s_err_count_val     <= s_err_count_aux;
        s_pattern_start_val <= s_pattern_start_aux;
        s_pattern_incr_val  <= s_pattern_incrval_aux;
        s_pattern_track_val <= s_pattern_track_aux;
        s_addr_start_val    <= s_addr_start_aux;
        s_start_at_zero_val <= s_start_at_zero_aux;
        s_i_val             <= s_i_aux;

        -- Default data writing values as zero and not writing
        o_sf3_wr_data_stream <= x"00";
        o_sf3_wr_data_valid  <= '0';

        case (s_tester_pr_state) is

            when ST_WAIT_BUTTON_DEP =>
                -- Wait for a button depress or a switch position before
                -- performing the next test iteration
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');

                s_test_done_val <= '0' when (to_integer(unsigned(s_addr_start_aux)) < c_last_starting_byte_addr) else '1';

                if (to_integer(unsigned(s_addr_start_aux)) < c_last_starting_byte_addr) then
                    if ((i_buttons_debounced = "0001") or (i_switches_debounced = "0001")) then
                        s_tester_nx_state <= ST_WAIT_BUTTON0_REL;
                    elsif ((i_buttons_debounced = "0010") or (i_switches_debounced = "0010")) then
                        s_tester_nx_state <= ST_WAIT_BUTTON1_REL;
                    elsif ((i_buttons_debounced = "0100") or (i_switches_debounced = "0100")) then
                        s_tester_nx_state <= ST_WAIT_BUTTON2_REL;
                    elsif ((i_buttons_debounced = "1000") or (i_switches_debounced = "1000")) then
                        s_tester_nx_state <= ST_WAIT_BUTTON3_REL;
                    else
                        s_tester_nx_state <= ST_WAIT_BUTTON_DEP;
                    end if;
                else
                    s_tester_nx_state <= ST_WAIT_BUTTON_DEP;
                end if;

            when ST_WAIT_BUTTON0_REL =>
                -- Button 0 or Switch 0 was selected.
                -- Choose the pattern as A and transition when no buttons are
                -- depressed.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');

                if (i_buttons_debounced = "0000") then
                    s_tester_nx_state <= ST_SET_PATTERN_A;
                else
                    s_tester_nx_state <= ST_WAIT_BUTTON0_REL;
                end if;

            when ST_WAIT_BUTTON1_REL =>
                -- Button 1 or Switch 1 was selected.
                -- Choose the pattern as B and transition when no buttons are
                -- depressed.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');

                if (i_buttons_debounced = "0000") then
                    s_tester_nx_state <= ST_SET_PATTERN_B;
                else
                    s_tester_nx_state <= ST_WAIT_BUTTON1_REL;
                end if;

            when ST_WAIT_BUTTON2_REL =>
                -- Button 2 or Switch 2 was selected.
                -- Choose the pattern as C and transition when no buttons are
                -- depressed.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');

                if (i_buttons_debounced = "0000") then
                    s_tester_nx_state <= ST_SET_PATTERN_C;
                else
                    s_tester_nx_state <= ST_WAIT_BUTTON2_REL;
                end if;

            when ST_WAIT_BUTTON3_REL =>
                -- Button 3 or Switch 3 was selected.
                -- Choose the pattern as D and transition when no buttons are
                -- depressed.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');

                if (i_buttons_debounced = "0000") then
                    s_tester_nx_state <= ST_SET_PATTERN_D;
                else
                    s_tester_nx_state <= ST_WAIT_BUTTON3_REL;
                end if;

            when ST_SET_PATTERN_A =>
                -- Set the Pattern as A and transition when the SF3 driver is
                -- ready for a command.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');

                s_pattern_start_val <= std_logic_vector(parm_pattern_startval_a);
                s_pattern_incr_val  <= std_logic_vector(parm_pattern_incrval_a);

                if (i_sf3_command_ready = '1') then
                    s_tester_nx_state <= ST_SET_START_ADDR_A;
                else
                    s_tester_nx_state <= ST_SET_PATTERN_A;
                end if;

            when ST_SET_PATTERN_B =>
                -- Set the Pattern as B and transition when the SF3 driver is
                -- ready for a command.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');

                s_pattern_start_val <= std_logic_vector(parm_pattern_startval_b);
                s_pattern_incr_val  <= std_logic_vector(parm_pattern_incrval_b);

                if (i_sf3_command_ready = '1') then
                    s_tester_nx_state <= ST_SET_START_ADDR_B;
                else
                    s_tester_nx_state <= ST_SET_PATTERN_B;
                end if;


            when ST_SET_PATTERN_C =>
                -- Set the Pattern as C and transition when the SF3 driver is
                -- ready for a command.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');

                s_pattern_start_val <= std_logic_vector(parm_pattern_startval_c);
                s_pattern_incr_val  <= std_logic_vector(parm_pattern_incrval_c);

                if (i_sf3_command_ready = '1') then
                    s_tester_nx_state <= ST_SET_START_ADDR_C;
                else
                    s_tester_nx_state <= ST_SET_PATTERN_C;
                end if;

            when ST_SET_PATTERN_D =>
                -- Set the Pattern as D and transition when the SF3 driver is
                -- ready for a command.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');

                s_pattern_start_val <= std_logic_vector(parm_pattern_startval_d);
                s_pattern_incr_val  <= std_logic_vector(parm_pattern_incrval_d);

                if (i_sf3_command_ready = '1') then
                    s_tester_nx_state <= ST_SET_START_ADDR_D;
                else
                    s_tester_nx_state <= ST_SET_PATTERN_D;
                end if;

            when ST_SET_START_ADDR_A =>
                -- If not first iteration of erase/program/test-read cycle,
                -- increment the starting address and then transition to a
                -- wait state.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');
                s_start_at_zero_val       <= '0';
                s_i_val                   <= 0;

                -- Increment the address for the next iteration
                if (s_start_at_zero_aux = '1') then
                    s_addr_start_val  <= x"00000000";
                    s_test_done_val   <= '0';
                    s_tester_nx_state <= ST_SET_START_WAIT_A;
                elsif (to_integer(unsigned(s_addr_start_aux)) < c_last_starting_byte_addr) then
                    s_addr_start_val <= std_logic_vector(
                        unsigned(s_addr_start_aux) + c_per_iteration_byte_count);
                    s_test_done_val   <= '0';
                    s_tester_nx_state <= ST_SET_START_WAIT_A;
                else
                    s_test_done_val   <= '1';
                    s_tester_nx_state <= ST_WAIT_BUTTON_DEP;
                end if;

            when ST_SET_START_ADDR_B =>
                -- If not first iteration of erase/program/test-read cycle,
                -- increment the starting address and then transition to a
                -- wait state.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');
                s_start_at_zero_val       <= '0';
                s_i_val                   <= 0;

                -- Increment the address for the next iteration
                if (s_start_at_zero_aux = '1') then
                    s_addr_start_val  <= x"00000000";
                    s_test_done_val   <= '0';
                    s_tester_nx_state <= ST_SET_START_WAIT_B;
                elsif (to_integer(unsigned(s_addr_start_aux)) < c_last_starting_byte_addr) then
                    s_addr_start_val <= std_logic_vector(
                            unsigned(s_addr_start_aux) + c_per_iteration_byte_count);
                    s_test_done_val   <= '0';
                    s_tester_nx_state <= ST_SET_START_WAIT_B;
                else
                    s_test_done_val   <= '1';
                    s_tester_nx_state <= ST_WAIT_BUTTON_DEP;
                end if;

            when ST_SET_START_ADDR_C =>
                -- If not first iteration of erase/program/test-read cycle,
                -- increment the starting address and then transition to a
                -- wait state.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');
                s_start_at_zero_val       <= '0';
                s_i_val                   <= 0;

                -- Increment the address for the next iteration
                if (s_start_at_zero_aux = '1') then
                    s_addr_start_val  <= x"00000000";
                    s_test_done_val   <= '0';
                    s_tester_nx_state <= ST_SET_START_WAIT_C;
                elsif (to_integer(unsigned(s_addr_start_aux)) < c_last_starting_byte_addr) then
                    s_addr_start_val <= std_logic_vector(
                            unsigned(s_addr_start_aux) + c_per_iteration_byte_count);
                    s_test_done_val   <= '0';
                    s_tester_nx_state <= ST_SET_START_WAIT_C;
                else
                    s_test_done_val   <= '1';
                    s_tester_nx_state <= ST_WAIT_BUTTON_DEP;
                end if;

            when ST_SET_START_ADDR_D =>
                -- If not first iteration of erase/program/test-read cycle,
                -- increment the starting address and then transition to a
                -- wait state.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');
                s_start_at_zero_val       <= '0';
                s_i_val                   <= 0;

                -- Increment the address for the next iteration
                if (s_start_at_zero_aux = '1') then
                    s_addr_start_val  <= x"00000000";
                    s_test_done_val   <= '0';
                    s_tester_nx_state <= ST_SET_START_WAIT_D;
                elsif (to_integer(unsigned(s_addr_start_aux)) < c_last_starting_byte_addr) then
                    s_addr_start_val <= std_logic_vector(
                            unsigned(s_addr_start_aux) + c_per_iteration_byte_count);
                    s_test_done_val   <= '0';
                    s_tester_nx_state <= ST_SET_START_WAIT_D;
                else
                    s_test_done_val   <= '1';
                    s_tester_nx_state <= ST_WAIT_BUTTON_DEP;
                end if;

            when ST_SET_START_WAIT_A =>
                -- Wait for half of the 3 second timer and transition to the
                -- Erase command. Pause in this state for purpose of lighting
                -- LED to indicate pattern A is starting.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');

                if (s_t = c_t_max / 2) then
                    s_tester_nx_state <= ST_CMD_ERASE_START;
                else
                    s_tester_nx_state <= ST_SET_START_WAIT_A;
                end if;

            when ST_SET_START_WAIT_B =>
                -- Wait for half of the 3 second timer and transition to the
                -- Erase command. Pause in this state for purpose of lighting
                -- LED to indicate pattern B is starting.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');

                if (s_t = c_t_max / 2) then
                    s_tester_nx_state <= ST_CMD_ERASE_START;
                else
                    s_tester_nx_state <= ST_SET_START_WAIT_B;
                end if;

            when ST_SET_START_WAIT_C =>
                -- Wait for half of the 3 second timer and transition to the
                -- Erase command. Pause in this state for purpose of lighting
                -- LED to indicate pattern C is starting.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');

                if (s_t = c_t_max / 2) then
                    s_tester_nx_state <= ST_CMD_ERASE_START;
                else
                    s_tester_nx_state <= ST_SET_START_WAIT_C;
                end if;

            when ST_SET_START_WAIT_D =>
                -- Wait for half of the 3 second timer and transition to the
                -- Erase command. Pause in this state for purpose of lighting
                -- LED to indicate pattern D is starting.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= (others => '0');

                if (s_t = c_t_max / 2) then
                    s_tester_nx_state <= ST_CMD_ERASE_START;
                else
                    s_tester_nx_state <= ST_SET_START_WAIT_D;
                end if;

            when ST_CMD_ERASE_START =>
                -- Issue an Erase Subsector Command at the starting address
                -- of this iteration. Wait to transition when the SF3 driver
                -- indicates command not ready.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '1';
                o_sf3_address_of_cmd      <= std_logic_vector(
                        unsigned(s_addr_start_aux) +
                        (s_i_aux * c_sf3_subsector_addr_incr));

                if (i_sf3_command_ready = '0') then
                    s_tester_nx_state <= ST_CMD_ERASE_WAIT;
                else
                    s_tester_nx_state <= ST_CMD_ERASE_START;
                end if;

            when ST_CMD_ERASE_WAIT =>
                -- Wait for the Erase Command to end and the SF3 driver to
                -- indicate command ready again. Then transition to incrementing
                -- the next Subsector Address to erase.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= std_logic_vector(
                        unsigned(s_addr_start_aux) +
                        (s_i_aux * c_sf3_subsector_addr_incr));

                if (i_sf3_command_ready = '1') then
                    s_tester_nx_state <= ST_CMD_ERASE_NEXT;
                else
                    s_tester_nx_state <= ST_CMD_ERASE_WAIT;
                end if;

            when ST_CMD_ERASE_NEXT =>
                -- If auxiliary register I has counted to the number of
                -- Subsectors after the starting address, transition to the
                -- Erase Done state, otherwise increment I and transition again
                -- to the Erase Start state.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= x"00000000";
                s_i_val                   <= s_i_aux + 1;

                if (s_i_aux < (c_tester_subsector_cnt_per_iter - 1)) then
                    s_tester_nx_state <= ST_CMD_ERASE_START;
                else
                    s_tester_nx_state <= ST_CMD_ERASE_DONE;
                end if;

            when ST_CMD_ERASE_DONE =>
                -- Erase iterations have completed. Reset the starting value
                -- of the pattern in preparation of programming the pages of
                -- all Subsectors erased.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= x"00000000";
                s_i_val                   <= 0;
                s_pattern_track_val       <= s_pattern_start_aux;

                if (s_t = c_t_max) then -- allow a few seconds of idle for easier SPY capture of the Erase command
                    s_tester_nx_state <= ST_CMD_PAGE_START;
                else
                    s_tester_nx_state <= ST_CMD_ERASE_DONE;
                end if;

            when ST_CMD_PAGE_START =>
                -- Issue an Program Page Command at the starting address
                -- of this iteration. Wait to transition when the SF3 driver
                -- indicates command not ready.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '1';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= std_logic_vector(
                        unsigned(s_addr_start_aux) +
                        (s_i_aux * c_sf3_page_addr_incr));
                s_dat_wr_cntidx_val <= 0;

                if (i_sf3_command_ready = '0') then
                    s_tester_nx_state <= ST_CMD_PAGE_BYTE;
                else
                    s_tester_nx_state <= ST_CMD_PAGE_START;
                end if;

            when ST_CMD_PAGE_BYTE =>
                -- Increment according to the selected pattern and stream a
                -- total of Page size bytes (256) unique values to the FIFO of
                -- the SF3 driver for writing to the currently addressed page.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= std_logic_vector(
                        unsigned(s_addr_start_aux) +
                        (s_i_aux * c_sf3_page_addr_incr));

                if (i_sf3_wr_data_ready = '1') then
                    -- Assign this iterations byte value
                    o_sf3_wr_data_stream <= s_pattern_track_aux;
                    o_sf3_wr_data_valid  <= '1';

                    -- Calculate the next iterations byte value
                    s_pattern_track_val <= std_logic_vector(
                            unsigned(s_pattern_track_aux) +
                            unsigned(s_pattern_incrval_aux));

                    -- Increment counter for next byte
                    if (s_dat_wr_cntidx_aux < 255) then
                        s_dat_wr_cntidx_val <= s_dat_wr_cntidx_aux + 1;
                    end if;

                    -- Check current bytes counter for next FSM state
                    if (s_dat_wr_cntidx_aux = 255) then
                        -- Wrote bytes 0 through 255, totaling at a page lenth
                        -- of 256 bytes. Now advance to the WAIT state.
                        s_tester_nx_state <= ST_CMD_PAGE_WAIT;
                    else
                        s_tester_nx_state <= ST_CMD_PAGE_BYTE;
                    end if;
                else
                    o_sf3_wr_data_stream <= x"00";
                    o_sf3_wr_data_valid  <= '0';
                    s_tester_nx_state    <= ST_CMD_PAGE_BYTE;
                end if;

            when ST_CMD_PAGE_WAIT =>
                -- Wait for the Page Program Command to end and the SF3 driver to
                -- indicate command ready again. Then transition to incrementing
                -- the next Page Address to program.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= std_logic_vector(
                        unsigned(s_addr_start_aux) +
                        (s_i_aux * c_sf3_page_addr_incr));

                if (i_sf3_command_ready = '1') then
                    s_tester_nx_state <= ST_CMD_PAGE_NEXT;
                else
                    s_tester_nx_state <= ST_CMD_PAGE_WAIT;
                end if;

            when ST_CMD_PAGE_NEXT =>
                -- If auxiliary register I has counted to the number of
                -- Pages after the starting address, transition to the
                -- Page Done state, otherwise increment I and transition again
                -- to the Page Start state.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= x"00000000";
                s_i_val                   <= s_i_aux + 1;

                if (s_i_aux < (c_tester_page_cnt_per_iter - 1)) then
                    s_tester_nx_state <= ST_CMD_PAGE_START;
                else
                    s_tester_nx_state <= ST_CMD_PAGE_DONE;
                end if;

            when ST_CMD_PAGE_DONE =>
                -- Page Program iterations have completed. Reset the starting value
                -- of the pattern in preparation of reading the pages of
                -- all Subsectors erased and programmed.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= x"00000000";
                s_i_val                   <= 0;
                s_pattern_track_val       <= s_pattern_start_aux;

                if (s_t = c_t_max) then -- allow a few seconds of idle for easier SPY capture of the Page command
                    s_tester_nx_state <= ST_CMD_READ_START;
                else
                    s_tester_nx_state <= ST_CMD_PAGE_DONE;
                end if;

            when ST_CMD_READ_START =>
                -- Issue an Random Read Command at the starting address
                -- of this iteration. Wait to transition when the SF3 driver
                -- indicates command not ready.
                o_sf3_len_random_read <= std_logic_vector(
                        to_unsigned(c_sf3_page_addr_incr, o_sf3_len_random_read'length));
                o_sf3_cmd_random_read     <= '1';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= std_logic_vector(
                        unsigned(s_addr_start_aux) +
                        (s_i_aux * c_sf3_page_addr_incr));
                s_dat_rd_cntidx_val <= 0;

                if (i_sf3_command_ready = '0') then
                    s_tester_nx_state <= ST_CMD_READ_BYTE;
                else
                    s_tester_nx_state <= ST_CMD_READ_START;
                end if;

            when ST_CMD_READ_BYTE =>
                -- Increment according to the selected pattern and stream a
                -- total of Page size bytes (256) unique values from the FIFO of
                -- the SF3 driver for checking of the currently addressed page
                -- byte read. Compare the value of the incrementing pattern with
                -- the value of the byte read. If they do not match, increment
                -- the error count auxiliary register.
                o_sf3_len_random_read <= std_logic_vector(
                        to_unsigned(c_sf3_page_addr_incr, o_sf3_len_random_read'length));
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= std_logic_vector(
                        unsigned(s_addr_start_aux) +
                        (s_i_aux * c_sf3_page_addr_incr));

                if (i_sf3_rd_data_valid = '1') then
                    -- Compare this iterations byte value
                    if (i_sf3_rd_data_stream /= s_pattern_track_aux) then
                        s_err_count_val <= s_err_count_aux + 1;
                    else
                        -- FIXME: this is to show errors that did not occur to test the error reporting on the LCD and USB=UART
                        s_err_count_val <= s_err_count_aux + 0;
                    end if;

                    -- Calculate the next iterations byte value
                    s_pattern_track_val <= std_logic_vector(
                            unsigned(s_pattern_track_aux) +
                            unsigned(s_pattern_incrval_aux));

                    -- Increment counter for next byte
                    if (s_dat_rd_cntidx_aux < 255) then
                        s_dat_rd_cntidx_val <= s_dat_rd_cntidx_aux + 1;
                    end if;

                    -- Check current bytes counter for next FSM state
                    if (s_dat_rd_cntidx_aux = 255) then
                        -- Read bytes 0 through 255, totaling at a page lenth
                        -- of 256 bytes. Now advance to the WAIT state.
                        s_tester_nx_state <= ST_CMD_READ_WAIT;
                    else
                        s_tester_nx_state <= ST_CMD_READ_BYTE;
                    end if;
                else
                    s_tester_nx_state <= ST_CMD_READ_BYTE;
                end if;

            when ST_CMD_READ_WAIT =>
                -- Wait for the Random Read Command to end and the SF3 driver to
                -- indicate command ready again. Then transition to incrementing
                -- the next Page Address to random read and test with pattern
                -- comparison.
                o_sf3_len_random_read <= std_logic_vector(
                        to_unsigned(c_sf3_page_addr_incr, o_sf3_len_random_read'length));
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= std_logic_vector(
                        unsigned(s_addr_start_aux) +
                        (s_i_aux * c_sf3_page_addr_incr));

                if (i_sf3_command_ready = '1') then
                    s_tester_nx_state <= ST_CMD_READ_NEXT;
                else
                    s_tester_nx_state <= ST_CMD_READ_WAIT;
                end if;

            when ST_CMD_READ_NEXT =>
                -- If auxiliary register I has counted to the number of
                -- pages after the starting address, transition to the
                -- Read Done state, otherwise increment I and transition again
                -- to the Read Start state.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= x"00000000";
                s_i_val                   <= s_i_aux + 1;

                if (s_i_aux < (c_tester_page_cnt_per_iter - 1)) then
                    s_tester_nx_state <= ST_CMD_READ_START;
                else
                    s_tester_nx_state <= ST_CMD_READ_DONE;
                end if;

            when ST_CMD_READ_DONE =>
                -- Random Read iterations have completed. Reset the starting value
                -- of the pattern. Transition to the Display Final state.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= x"00000000";
                s_i_val                   <= 0;
                s_pattern_track_val       <= s_pattern_start_aux;

                if (s_t = c_t_max) then -- allow a few seconds of idle for easier SPY capture of the Read command
                    s_tester_nx_state <= ST_DISPLAY_FINAL;
                else
                    s_tester_nx_state <= ST_CMD_READ_DONE;
                end if;

            when others => -- ST_DISPLAY_FINAL =>
                -- Compare the auxiliary register error count to zero and set
                -- the auxiliary register Test Pass to either true or false.
                -- Wait for the timer to reach its maximum (3 seconds) and then
                -- transition to the Wait for Button or Switch.
                o_sf3_len_random_read     <= (others => '0');
                o_sf3_cmd_random_read     <= '0';
                o_sf3_cmd_page_program    <= '0';
                o_sf3_cmd_erase_subsector <= '0';
                o_sf3_address_of_cmd      <= x"00000000";

                if (s_err_count_aux = 0) then
                    s_test_pass_val <= '1';
                else
                    s_test_pass_val <= '0';
                end if;

                if (s_t = c_t_max) then
                    s_tester_nx_state <= ST_WAIT_BUTTON_DEP;
                else
                    s_tester_nx_state <= ST_DISPLAY_FINAL;
                end if;
        end case;
    end process p_tester_fsm_comb;

end architecture rtl;
--------------------------------------------------------------------------------
