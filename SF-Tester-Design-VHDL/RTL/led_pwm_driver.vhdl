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
-- \file led_pwm_driver.vhdl
--
-- \brief A 24-bit palette interface to three-filament discrete color LEDs, plus
-- a 8-bit palette interface to one-filament discrete basic LEDs.
--
-- \description A color-mixing solution for color LEDs. Note that the color
-- mixing palette causes more mixing of brightness than color, except at the
-- lower brightness levels.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--------------------------------------------------------------------------------
package led_pwm_driver_pkg is
    subtype t_led_pwm_period is unsigned(31 downto 0);
    type t_led_pwms_period is array(natural range <>) of t_led_pwm_period;

    type t_led_color_values is array(natural range <>) of std_logic_vector(7 downto 0);
end package led_pwm_driver_pkg;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.led_pwm_driver_pkg.all;
--------------------------------------------------------------------------------
entity led_pwm_driver is
    generic(
        -- color emitter and pwm parameters
        parm_color_led_count         : integer := 4;
        parm_basic_led_count         : integer := 4;
        parm_FCLK                    : integer := 40_000_000;
        parm_pwm_period_milliseconds : integer := 10
    );
    port(
        -- clock and reset
        i_clk  : in std_logic;
        i_srst : in std_logic;

        -- pallete input values
        i_color_led_red_value   : in t_led_color_values((parm_color_led_count - 1) downto 0);
        i_color_led_green_value : in t_led_color_values((parm_color_led_count - 1) downto 0);
        i_color_led_blue_value  : in t_led_color_values((parm_color_led_count - 1) downto 0);
        i_basic_led_lumin_value : in t_led_color_values((parm_basic_led_count - 1) downto 0);

        -- led emitter drive values
        eo_color_leds_r : out std_logic_vector((parm_color_led_count - 1) downto 0);
        eo_color_leds_g : out std_logic_vector((parm_color_led_count - 1) downto 0);
        eo_color_leds_b : out std_logic_vector((parm_color_led_count - 1) downto 0);
        eo_basic_leds_l : out std_logic_vector((parm_basic_led_count - 1) downto 0)
    );
end entity led_pwm_driver;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
architecture rtl of led_pwm_driver is
    constant c_pwm_period_ms                    : natural   := parm_FCLK / 1000 * parm_pwm_period_milliseconds;
    constant c_pwm_color_max_duty_cycle         : natural   := c_pwm_period_ms * 5 / 10;
    constant c_pwm_color_max_duty_cycle_ratioed : natural   := c_pwm_color_max_duty_cycle / 256;
    constant c_pwm_basic_max_duty_cycle         : natural   := c_pwm_period_ms * 9 / 10;
    constant c_pwm_basic_max_duty_cycle_ratioed : natural   := c_pwm_basic_max_duty_cycle / 256;
    constant c_emitter_on_value                : std_logic := '1';
    constant c_emitter_off_value               : std_logic := '0';
begin

    g_operate_color_red_pwm : for redidx in (parm_color_led_count - 1) downto 0 generate
    begin
        bl_operate_color_red_pwm : block is
            signal s_color_red_pwm_period_count  : t_led_pwm_period;
            signal s_color_red_pwm_duty_cycles   : t_led_pwm_period;
            signal s_color_red_pwm_duty_cycles_1 : t_led_pwm_period;
            signal s_color_red_pwm_duty_cycles_2 : t_led_pwm_period;
            signal s_color_led_red_value_0       : unsigned(7 downto 0);
        begin

            p_operate_color_red_pwm : process(i_clk)
            begin
                if rising_edge(i_clk) then
                    if (i_srst = '1') then
                        eo_color_leds_r(redidx)       <= c_emitter_off_value;
                        s_color_red_pwm_period_count  <= to_unsigned(c_pwm_period_ms - 1, t_led_pwm_period'length);
                        s_color_red_pwm_duty_cycles   <= to_unsigned(0, t_led_pwm_period'length);
                        s_color_led_red_value_0       <= x"00";
                        s_color_red_pwm_duty_cycles_1 <= to_unsigned(0, t_led_pwm_period'length);
                        s_color_red_pwm_duty_cycles_2 <= to_unsigned(0, t_led_pwm_period'length);

                    else
                        if (s_color_red_pwm_period_count > 0) then
                            if (s_color_red_pwm_period_count < s_color_red_pwm_duty_cycles) then
                                eo_color_leds_r(redidx) <= c_emitter_on_value;
                            else
                                eo_color_leds_r(redidx) <= c_emitter_off_value;
                            end if;

                            s_color_red_pwm_period_count <= s_color_red_pwm_period_count- 1;
                        else
                            eo_color_leds_r(redidx)      <= c_emitter_on_value;
                            s_color_red_pwm_period_count <= to_unsigned(c_pwm_period_ms - 1, t_led_pwm_period'length);

                            -- Register the DSP48E1 output
                            s_color_red_pwm_duty_cycles <= s_color_red_pwm_duty_cycles_2;
                        end if;

                        -- Register inferred DSP48E1 Register B
                        s_color_led_red_value_0 <= unsigned(i_color_led_red_value(redidx));

                        -- Register inferred DSP48E1 Register A or D
                        -- Register inferred DSP48E1: Multiply
                        s_color_red_pwm_duty_cycles_1 <= to_unsigned(c_pwm_color_max_duty_cycle_ratioed * to_integer(s_color_led_red_value_0), t_led_pwm_period'length);

                        -- Register the inferred DSP48E1 output P
                        s_color_red_pwm_duty_cycles_2 <= s_color_red_pwm_duty_cycles_1;
                    end if;
                end if;
            end process p_operate_color_red_pwm;

        end block bl_operate_color_red_pwm;

    end generate g_operate_color_red_pwm;

    g_operate_color_green_pwm : for greenidx in (parm_color_led_count - 1) downto 0 generate
    begin
        bl_operate_color_green_pwm : block is
            signal s_color_green_pwm_period_count  : t_led_pwm_period;
            signal s_color_green_pwm_duty_cycles   : t_led_pwm_period;
            signal s_color_green_pwm_duty_cycles_1 : t_led_pwm_period;
            signal s_color_green_pwm_duty_cycles_2 : t_led_pwm_period;
            signal s_color_led_green_value_0       : unsigned(7 downto 0);
        begin

            p_operate_color_green_pwm : process(i_clk)
            begin
                if rising_edge(i_clk) then
                    if (i_srst = '1') then
                        eo_color_leds_g(greenidx)       <= c_emitter_off_value;
                        s_color_green_pwm_period_count  <= to_unsigned(c_pwm_period_ms - 1, t_led_pwm_period'length);
                        s_color_green_pwm_duty_cycles   <= to_unsigned(0, t_led_pwm_period'length);
                        s_color_led_green_value_0       <= x"00";
                        s_color_green_pwm_duty_cycles_1 <= to_unsigned(0, t_led_pwm_period'length);
                        s_color_green_pwm_duty_cycles_2 <= to_unsigned(0, t_led_pwm_period'length);
                    else
                        if (s_color_green_pwm_period_count > 0) then
                            if (s_color_green_pwm_period_count < s_color_green_pwm_duty_cycles) then
                                eo_color_leds_g(greenidx) <= c_emitter_on_value;
                            else
                                eo_color_leds_g(greenidx) <= c_emitter_off_value;
                            end if;

                            s_color_green_pwm_period_count <= s_color_green_pwm_period_count - 1;
                        else
                            eo_color_leds_g(greenidx)      <= c_emitter_on_value;
                            s_color_green_pwm_period_count <= to_unsigned(c_pwm_period_ms - 1, t_led_pwm_period'length);

                            -- Register the DSP48E1 output
                            s_color_green_pwm_duty_cycles <= s_color_green_pwm_duty_cycles_2;
                        end if;

                        -- Register inferred DSP48E1 Register B
                        s_color_led_green_value_0 <= unsigned(i_color_led_green_value(greenidx));

                        -- Register inferred DSP48E1 Register A or D
                        -- Register inferred DSP48E1: Multiply
                        s_color_green_pwm_duty_cycles_1 <= to_unsigned(c_pwm_color_max_duty_cycle_ratioed * to_integer(s_color_led_green_value_0), t_led_pwm_period'length);

                        -- Register the inferred DSP48E1 output P
                        s_color_green_pwm_duty_cycles_2 <= s_color_green_pwm_duty_cycles_1;
                    end if;
                end if;
            end process p_operate_color_green_pwm;

        end block bl_operate_color_green_pwm;
    end generate g_operate_color_green_pwm;

    g_operate_color_blue_pwm : for blueidx in (parm_color_led_count - 1) downto 0 generate
    begin
        bl_operate_color_blue_pwm : block is
            signal s_color_blue_pwm_period_count  : t_led_pwm_period;
            signal s_color_blue_pwm_duty_cycles   : t_led_pwm_period;
            signal s_color_blue_pwm_duty_cycles_1 : t_led_pwm_period;
            signal s_color_blue_pwm_duty_cycles_2 : t_led_pwm_period;
            signal s_color_led_blue_value_0       : unsigned(7 downto 0);
        begin

            p_operate_color_blue_pwm : process(i_clk)
            begin
                if rising_edge(i_clk) then
                    if (i_srst = '1') then
                        eo_color_leds_b(blueidx)       <= c_emitter_off_value;
                        s_color_blue_pwm_period_count  <= to_unsigned(c_pwm_period_ms - 1, t_led_pwm_period'length);
                        s_color_blue_pwm_duty_cycles   <= to_unsigned(0, t_led_pwm_period'length);
                        s_color_led_blue_value_0       <= x"00";
                        s_color_blue_pwm_duty_cycles_1 <= to_unsigned(0, t_led_pwm_period'length);
                        s_color_blue_pwm_duty_cycles_2 <= to_unsigned(0, t_led_pwm_period'length);
                    else
                        if (s_color_blue_pwm_period_count > 0) then
                            if (s_color_blue_pwm_period_count < s_color_blue_pwm_duty_cycles) then
                                eo_color_leds_b(blueidx) <= c_emitter_on_value;
                            else
                                eo_color_leds_b(blueidx) <= c_emitter_off_value;
                            end if;

                            s_color_blue_pwm_period_count <= s_color_blue_pwm_period_count - 1;
                        else
                            eo_color_leds_b(blueidx)      <= c_emitter_on_value;
                            s_color_blue_pwm_period_count <= to_unsigned(c_pwm_period_ms - 1, t_led_pwm_period'length);

                            -- Register the DSP48E1 output
                            s_color_blue_pwm_duty_cycles <= s_color_blue_pwm_duty_cycles_2;
                        end if;

                        -- Register inferred DSP48E1 Register B
                        s_color_led_blue_value_0 <= unsigned(i_color_led_blue_value(blueidx));

                        -- Register inferred DSP48E1 Register A or D
                        -- Register inferred DSP48E1: Multiply
                        s_color_blue_pwm_duty_cycles_1 <= to_unsigned(c_pwm_color_max_duty_cycle_ratioed * to_integer(s_color_led_blue_value_0), t_led_pwm_period'length);

                        -- Register the inferred DSP48E1 output P
                        s_color_blue_pwm_duty_cycles_2 <= s_color_blue_pwm_duty_cycles_1;
                    end if;
                end if;
            end process p_operate_color_blue_pwm;

        end block bl_operate_color_blue_pwm;
    end generate g_operate_color_blue_pwm;

    g_operate_basic_lumin_pwm : for basicidx in (parm_basic_led_count - 1) downto 0 generate
    begin
        bl_operate_basic_lumin_pwm : block is
            signal s_basic_lumin_pwm_period_count  : t_led_pwm_period;
            signal s_basic_lumin_pwm_duty_cycles   : t_led_pwm_period;
            signal s_basic_lumin_pwm_duty_cycles_1 : t_led_pwm_period;
            signal s_basic_lumin_pwm_duty_cycles_2 : t_led_pwm_period;
            signal s_basic_led_lumin_value_0       : unsigned(7 downto 0);
        begin

            p_operate_basic_lumin_pwm : process(i_clk)
            begin
                if rising_edge(i_clk) then
                    if (i_srst = '1') then
                        eo_basic_leds_l(basicidx)       <= c_emitter_off_value;
                        s_basic_lumin_pwm_period_count  <= to_unsigned(c_pwm_period_ms - 1, t_led_pwm_period'length);
                        s_basic_lumin_pwm_duty_cycles   <= to_unsigned(0, t_led_pwm_period'length);
                        s_basic_led_lumin_value_0       <= x"00";
                        s_basic_lumin_pwm_duty_cycles_1 <= to_unsigned(0, t_led_pwm_period'length);
                        s_basic_lumin_pwm_duty_cycles_2 <= to_unsigned(0, t_led_pwm_period'length);

                    else
                        if (s_basic_lumin_pwm_period_count > 0) then
                            if (s_basic_lumin_pwm_period_count < s_basic_lumin_pwm_duty_cycles) then
                                eo_basic_leds_l(basicidx) <= c_emitter_on_value;
                            else
                                eo_basic_leds_l(basicidx) <= c_emitter_off_value;
                            end if;

                            s_basic_lumin_pwm_period_count <= s_basic_lumin_pwm_period_count - 1;
                        else
                            eo_basic_leds_l(basicidx)      <= c_emitter_on_value;
                            s_basic_lumin_pwm_period_count <= to_unsigned(c_pwm_period_ms - 1, t_led_pwm_period'length);

                            -- Register the DSP48E1 output
                            s_basic_lumin_pwm_duty_cycles <= s_basic_lumin_pwm_duty_cycles_2;
                        end if;

                        -- Register inferred DSP48E1 Register B
                        s_basic_led_lumin_value_0 <= unsigned(i_basic_led_lumin_value(basicidx));

                        -- Register inferred DSP48E1 Register A or D
                        -- Register inferred DSP48E1: Multiply
                        s_basic_lumin_pwm_duty_cycles_1 <= to_unsigned(c_pwm_basic_max_duty_cycle_ratioed * to_integer(s_basic_led_lumin_value_0), t_led_pwm_period'length);

                        -- Register the inferred DSP48E1 output P
                        s_basic_lumin_pwm_duty_cycles_2 <= s_basic_lumin_pwm_duty_cycles_1;
                    end if;
                end if;
            end process p_operate_basic_lumin_pwm;

        end block bl_operate_basic_lumin_pwm;
    end generate g_operate_basic_lumin_pwm;

end architecture rtl;
--------------------------------------------------------------------------------
