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
-- \file multi_input_debounce.vhdl
--
-- \brief A 4-button multiple input debouncer and filter allowing only one
-- button to be depressed at a time.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--------------------------------------------------------------------------------
entity multi_input_debounce is
    generic(
        FCLK : natural := 20_000_000 -- system clock frequency in Hz
    );
    port(
        i_clk_mhz  : in  std_logic;                    -- system clock
        i_rst_mhz  : in  std_logic;                    -- synchronized reset
        ei_buttons : in  std_logic_vector(3 downto 0); -- the raw buttons input
        o_btns_deb : out std_logic_vector(3 downto 0)  -- logic level buttons value indicator
    );
end entity multi_input_debounce;
--------------------------------------------------------------------------------
architecture moore_fsm of multi_input_debounce is
    -- FSM State enumeration
    type t_minp_state is (ST_A, ST_B, ST_C, ST_D);
    -- FSM State register
    signal s_minp_pr_state : t_minp_state;
    signal s_minp_nx_state : t_minp_state;

    -- Xilinx FSM Encoding attribute:
    attribute fsm_encoding                      : string;
    attribute fsm_encoding of s_minp_pr_state   : signal is "auto";
    attribute fsm_safe_state                    : string;
    attribute fsm_safe_state of s_minp_pr_state : signal is "default_state";

    --Timer-related declarations:
    constant c_T    : natural := FCLK * 1 / 1000; -- 1 millisecond debounce
    constant c_tmax : natural := c_T-1;
    signal s_t      : natural range 0 to c_tmax;

    signal si_buttons_meta  : std_logic_vector(3 downto 0);
    signal si_buttons_sync  : std_logic_vector(3 downto 0);
    signal si_buttons_prev  : std_logic_vector(3 downto 0);
    signal si_buttons_store : std_logic_vector(3 downto 0);
    signal so_btns_deb      : std_logic_vector(3 downto 0);
begin
    -- FSM input signals synchronized to prevent meta-stability
    p_sync_buttons_input : process(i_clk_mhz)
    begin
        if rising_edge(i_clk_mhz) then
            si_buttons_sync <= si_buttons_meta;
            si_buttons_meta <= ei_buttons;
        end if;
    end process p_sync_buttons_input;

    -- FSM Timer (Strategy #1)
    p_fsm_timer1 : process(i_clk_mhz, i_rst_mhz)
    begin
        if rising_edge(i_clk_mhz) then
            if (i_rst_mhz = '1') then
                s_t <= 0;
            else
                if (s_minp_pr_state /= s_minp_nx_state) then
                    s_t <= 0;
                elsif (s_t /= c_tmax) then
                    s_t <= s_t + 1;
                end if;
            end if;
        end if;
    end process p_fsm_timer1;

    -- FSM state register and auxiliary registers
    p_fsm_state : process(i_clk_mhz)
    begin
        if rising_edge(i_clk_mhz) then
            if (i_rst_mhz = '1') then
                s_minp_pr_state  <= ST_A;
                si_buttons_prev  <= "0000";
                si_buttons_store <= "0000";
            else
                if ((s_minp_nx_state = ST_C) and
                        (s_minp_pr_state = ST_B)) then

                    si_buttons_store <= si_buttons_prev;
                end if;

                si_buttons_prev <= si_buttons_sync;

                s_minp_pr_state <= s_minp_nx_state;
            end if;
        end if;
    end process p_fsm_state;

    -- FSM state combinational logic
    p_fsm_comb : process(s_minp_pr_state, s_t, si_buttons_sync, si_buttons_prev,
            si_buttons_store)
    begin
        case (s_minp_pr_state) is
            when ST_B =>
                so_btns_deb <= "0000";
                if (si_buttons_sync /= si_buttons_prev) then
                    s_minp_nx_state <= ST_A;
                elsif (s_t = c_T - 2) then
                    s_minp_nx_state <= ST_C;
                else
                    s_minp_nx_state <= ST_B;
                end if;
            when ST_C =>
                so_btns_deb <= si_buttons_store;
                if (si_buttons_sync /= si_buttons_store) then
                    s_minp_nx_state <= ST_D;
                else
                    s_minp_nx_state <= ST_C;
                end if;
            when ST_D =>
                so_btns_deb <= si_buttons_store;
                if (si_buttons_sync = si_buttons_store) then
                    s_minp_nx_state <= ST_C;
                elsif (s_t = c_T - 3) then
                    s_minp_nx_state <= ST_A;
                else
                    s_minp_nx_state <= ST_D;
                end if;
            when others => -- ST_A
                so_btns_deb <= "0000";
                if ((si_buttons_sync = "0000") or
                        (si_buttons_sync = "1000") or
                        (si_buttons_sync = "0100") or
                        (si_buttons_sync = "0010") or
                        (si_buttons_sync = "0001")) then

                    s_minp_nx_state <= ST_B;
                else
                    s_minp_nx_state <= ST_A;
                end if;
        end case;
    end process p_fsm_comb;

    -- Direct unregistered output with no output registers
    o_btns_deb <= so_btns_deb;
end architecture moore_fsm;
--------------------------------------------------------------------------------
