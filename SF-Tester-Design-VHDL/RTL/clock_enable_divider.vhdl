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
-- \file clock_enable_divider.vhdl
--
-- \brief A clock enable divider for an integer division of the source clock
-- enable. The clock and synchronous reset are kept the same; but the
-- clock enable is further divided.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--------------------------------------------------------------------------------
entity clock_enable_divider is
    generic(
        par_ce_divisor : natural := 1000
    );
    port(
        o_ce_div  : out std_logic;
        i_clk_mhz : in  std_logic;
        i_rst_mhz : in  std_logic;
        i_ce_mhz  : in  std_logic
    );
end entity clock_enable_divider;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
architecture rtl of clock_enable_divider is
    -- A constant representing the counter maximum which is an integer division
    -- of the source clock, per paramter \ref par_clk_divisor .
    constant c_clk_max : natural := par_ce_divisor - 1;

    -- Clock division count, that counts from 0 to \ref c_clk_max and back again
    -- to run the divided clock enable output at a division of i_clk_mhz according
    -- to a down division ratio of \ref i_ce_mhz the source clock.
    signal s_clk_div_cnt : natural range 0 to c_clk_max;

    -- A clock enable at the source clock frequency which issues the periodic
    -- toggle of the divided clock.
    signal s_clk_div_ce : std_logic;

begin

    -- The integer clock frequency division is operated by a clock enable signal
    -- to indicate the upstream clock cycle on which to change the edge of the
    -- downstream clock waveform.
    p_clk_div_cnt : process(i_clk_mhz)
    begin
        if rising_edge(i_clk_mhz) then
            if (i_rst_mhz = '1') then
                s_clk_div_cnt <= 0;
                s_clk_div_ce  <= '1';
            else
                if (i_ce_mhz = '1') then
                    if (s_clk_div_cnt = c_clk_max) then
                        s_clk_div_cnt <= 0;
                        s_clk_div_ce  <= '1';
                    else
                        s_clk_div_cnt <= s_clk_div_cnt + 1;
                        s_clk_div_ce  <= '0';
                    end if;
                else
                    s_clk_div_cnt <= s_clk_div_cnt;
                    s_clk_div_ce  <= '0';
                end if;
            end if;
        end if;
    end process p_clk_div_cnt;

    o_ce_div <= s_clk_div_ce;

end architecture rtl;
--------------------------------------------------------------------------------
