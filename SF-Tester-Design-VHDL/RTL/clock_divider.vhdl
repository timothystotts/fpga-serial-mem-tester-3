--------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2020.2022 Timothy Stotts
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
-- \file clock_divider.vhdl
--
-- \brief A clock divider for an even integer division of the source clock.
--
-- \description Generates a single clock cycle synchronous reset and generates
-- a divided-down clock for usage of clock edge sensitivity.
--
-- Note that this module requires the usage of TCL command
-- \ref create_generated_clock to indicate to the Xilinx synthesis tool that
-- this module implements a clock divider.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--------------------------------------------------------------------------------
entity clock_divider is
    generic(
        par_clk_divisor : natural := 1000
    );
    port(
        o_clk_div : out std_logic;
        o_rst_div : out std_logic;
        i_clk_mhz : in  std_logic;
        i_rst_mhz : in  std_logic
    );
end entity clock_divider;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
architecture rtl of clock_divider is
    -- A constant representing the counter maximum which is an even division of the
    -- source clock, per paramter \ref par_clk_divisor .
    constant c_clk_max : natural := (par_clk_divisor / 2) - 1;

    -- Clock division count, that counts from 0 to \ref c_clk_max and back again
    -- to run the divided clock output at an even division \par_clk_divisor of
    -- the source clock.
    signal s_clk_div_cnt : natural range 0 to c_clk_max;

    -- A clock enable at the source clock frequency which issues the periodic
    -- toggle of the divided clock.
    signal s_clk_div_ce : std_logic;

    -- Signals for the divided clock and reset.
    signal s_clk_out : std_logic;
    signal s_rst_out : std_logic;
begin

    -- The even clock frequency division is operated by a clock enable signal to
    -- indicate the upstream clock cycle for changing the edge of the downstream
    -- clock waveform.
    p_clk_div_cnt : process(i_clk_mhz)
    begin
        if rising_edge(i_clk_mhz) then
            if (i_rst_mhz = '1') then
                s_clk_div_cnt <= 0;
                s_clk_div_ce  <= '1';
            else
                if (s_clk_div_cnt = c_clk_max) then
                    s_clk_div_cnt <= 0;
                    s_clk_div_ce  <= '1';
                else
                    s_clk_div_cnt <= s_clk_div_cnt + 1;
                    s_clk_div_ce  <= '0';
                end if;
            end if;
        end if;
    end process p_clk_div_cnt;

    -- While the upstream clock is executing with reset held, this process will
    -- hold the clock at zero and the reset at active one. When the upstream reset
    -- signal is released, the downstream clock will have one positive edge with
    -- this reset output held active one, and then on the falling edge of the
    -- downstream clock, the reset will change from active one to inactive low.
    p_clk_div_out : process(i_clk_mhz)
    begin
        if rising_edge(i_clk_mhz) then
            if (i_rst_mhz = '1') then
                s_rst_out <= '1';
                s_clk_out <= '0';
            else
                if (s_clk_div_ce = '1') then
                    s_rst_out <= s_rst_out and (not s_clk_out);
                    s_clk_out <= not s_clk_out;
                end if;
            end if;
        end if;
    end process p_clk_div_out;

    o_clk_div <= s_clk_out;
    o_rst_div <= s_rst_out;

end architecture rtl;
--------------------------------------------------------------------------------
