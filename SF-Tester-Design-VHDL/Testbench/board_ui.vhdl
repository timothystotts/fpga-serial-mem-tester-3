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
-- \file board_ui.vhdl
--
-- \brief OSVVM testbench component: FPGA development board User Interface
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

library work;
--------------------------------------------------------------------------------
entity tbc_board_ui is
	generic(
        parm_clk_freq : natural := 100_000_000;
        parm_button_count : positive := 4;
        parm_switch_count : positive := 4;
        parm_rgb_led_count : positive := 4;
        parm_basic_led_count : positive := 4;
        parm_pwm_period_milliseconds : natural := 10;
        parm_pwm_color_max_duty_cycle : natural := 8;
        parm_pwm_basic_max_duty_cycle : natural := 9
        );
    port(
        TBID : in AlertLogIDType;
        BarrierTestStart : inout std_logic;
        BarrierLogStart : inout std_logic;
        ci_main_clock : in std_logic;
        cin_main_reset : in std_logic;
        co_buttons : out std_logic_vector((parm_button_count - 1) downto 0);
        co_switches : out std_logic_vector((parm_switch_count - 1) downto 0);
        ci_led_blue : in std_logic_vector((parm_rgb_led_count - 1) downto 0);
        ci_led_red : in std_logic_vector((parm_rgb_led_count - 1) downto 0);
        ci_led_green : in std_logic_vector((parm_rgb_led_count - 1) downto 0);
        ci_led_basic : in std_logic_vector((parm_basic_led_count - 1) downto 0)
        );
end entity tbc_board_ui;
--------------------------------------------------------------------------------
architecture simulation_default of tbc_board_ui is
    -- A custom type to aggregate the RGB LEDs into one signal.
    type t_rgb_led_arrray is array (natural range <>) of
        std_logic_vector(2 downto 0);

    -- Simulation logging ID for this architecture.
    signal ModelID : AlertLogIDType;

    -- Internal signal for driving buttons
    signal so_buttons : std_logic_vector(co_buttons'range);

    -- Internal signal for driving switches
    signal so_switches : std_logic_vector(co_switches'range);

    -- Internal signal for inputting RGB LED emitter trace values.
    signal si_rbg_leds : t_rgb_led_arrray((parm_rgb_led_count - 1) downto 0);
begin
    -- Simulation initialization for the tbc_board_ui component.
    p_sim_init : process
        variable ID : AlertLogIDType;
    begin
        wait for 0 ns;
        WaitForBarrier(BarrierTestStart);
        ID := GetAlertLogID(PathTail(tbc_board_ui'path_name), TBID);
        ModelID <= ID;

        wait on ModelID;
        Log(ModelID, "Starting board user interface emulation, " &
        to_string(parm_button_count) & " buttons, " &
        to_string(parm_switch_count) & " switches, " &
        to_string(parm_rgb_led_count) & " RGB LEDs, " &
        to_string(parm_basic_led_count) & " Basic LEDs.", ALWAYS);
        wait;
    end process p_sim_init;

    -- Input the RGB LEDs into an aggregate signal.
    g_rgb_leds : for i_rgb in ci_led_red'range generate
    begin
        si_rbg_leds(i_rgb) <= (ci_led_red(i_rgb),
                                ci_led_green(i_rgb),
                                ci_led_blue(i_rgb));
    end generate g_rgb_leds;

    -- Default initialization of the buttons on the board.
    p_set_buttons : process
    begin
        wait for 0 ns;
        WaitForBarrier(BarrierLogStart);
        Log(ModelID, "Entering emulation of buttons 0,1,2,3 .", ALWAYS);

        -- Buttons are set to zero before reset to properly simulate the
        -- FPGA board.
        so_buttons <= (others => '0');
        Log(ModelID, "BOARD UI buttons 0,1,2,3 released at startup.", INFO);

        -- Wait for reset to be held, then released for 100 clock cycles.
        WaitForClock(ci_main_clock, 1);
        WaitForLevel(cin_main_reset, '0');
        WaitForClock(ci_main_clock, 1);
        WaitForLevel(cin_main_reset, '1');
        WaitForClock(ci_main_clock, 100);

        -- Do not depress a button.
        wait;
    end process p_set_buttons;

    co_buttons <= so_buttons;

    -- Default initialization of the switches on the board.
    p_set_switches : process
    begin
        wait for 0 ns;
        WaitForBarrier(BarrierLogStart);
        Log(ModelID, "Entering emulation of switches 0,1,2,3 .", ALWAYS);

        -- Switches are set to zero before reset to properly simulate a default
        -- state of the FPGA board.
        so_switches <= (others => '0');
        Log(ModelID, "BOARD UI switches 0,1,2,3 unselected at startup.", INFO);        

        -- Wait for reset to be held, then released for 100 clock cycles.
        WaitForClock(ci_main_clock, 1);
        WaitForLevel(cin_main_reset, '0');
        WaitForClock(ci_main_clock, 1);        
        WaitForLevel(cin_main_reset, '1');
        WaitForClock(ci_main_clock, 100);

        -- Wait for 5 milliseconds (based on parm_clk_freq); then assert the
        -- Switch 0 is held selected on the board.
        WaitForClock(ci_main_clock, parm_clk_freq / 1000 * 5);
        so_switches(0) <= '1';        
        Log(ModelID, "BOARD UI switch 0 selected.", INFO);
        wait;
    end process p_set_switches;

    co_switches <= so_switches;

    -- Log the changes on the RGB LEDs.
    -- Generate logic process for each of the \ref parm_rgb_led_count , to
    -- monitor and characterize the RGB emitter trace assertions, which are PWM
    -- signals.
    g_log_rgb_leds : for i_rgb in ci_led_red'range generate
    begin

        -- Monitor and characterize the RGB emitter trace assertions, presuming
        -- that they are PWM signals.
        p_log_rgb_leds : process
            type t_have_emitter is array(2 downto 0) of boolean;
            type t_have_time is array(2 downto 0) of time;

            constant c_pwm_period : time := parm_pwm_color_max_duty_cycle * 1 ms;
            variable v_have_on : t_have_emitter := (false, false, false);
            variable v_have_off : t_have_emitter := (false, false, false);
            variable v_time_on : t_have_time := (0 ms, 0 ms, 0 ms);
            variable v_time_off : t_have_time := (0 ms, 0 ms, 0 ms);
            variable v_time_delta : t_have_time := (0 ms, 0 ms, 0 ms);
        begin
            wait on si_rbg_leds(i_rgb); -- wait on the aggregate signal, part

            Log(ModelID, "RGB LED emitter " & to_string(i_rgb) & " changed to:" &
                " R:" & to_string(si_rbg_leds(i_rgb)(2)) &
                " G:" & to_string(si_rbg_leds(i_rgb)(1)) &
                " B:" & to_string(si_rbg_leds(i_rgb)(0)),
                DEBUG);

            -- For each emitter, toggle between measuring time that the
            -- the emitter is asserted ON, once per PWM cycle.
            for i_idx in 2 downto 0 loop
                if si_rbg_leds(i_rgb)(i_idx) = '1' then
                    if not v_have_on(i_idx) then
                        v_have_on(i_idx) := true;
                        v_time_on(i_idx) := NOW;
                    end if;
                elsif v_have_on(i_idx) then
                    if not v_have_off(i_idx) then
                        v_have_off(i_idx) := true;
                        v_time_off(i_idx) := NOW;
                    end if;
                end if;
            end loop;

            -- If the PWM has been measured from the ON state to the OFF state,
            -- for each of the RGB emitters
            if (v_have_on(2) and v_have_on(1) and v_have_on(0) and v_have_off(2)
                and v_have_off(1) and v_have_off(0)) then

                -- Compute the delta time of ON to OFF.
                -- Reset tracking for next iteration.
                for i_idx in 2 downto 0 loop
                    v_time_delta(i_idx) := abs(v_time_off(i_idx) - v_time_on(i_idx));
                    v_have_on(i_idx) := false;
                    v_have_off(i_idx) := false;
                    v_time_on(i_idx) := 0 ms;
                    v_time_off(i_idx) := 0 ms;
                end loop;

                -- Log the eitter time deltas
                Log(ModelID, "RGB LED PWM " & to_string(i_rgb) & " lasted for:" &
                    " R:" & to_string(v_time_delta(2)) &
                    " G:" & to_string(v_time_delta(1)) &
                    " B:" & to_string(v_time_delta(0)),
                    INFO);

                -- Log the emitter time deltas as 8-bit magnitudes, indicating
                -- the likely RGB magnitudes sent to the led_pwm_driver module
                -- inside the FPGA.
                Log(ModelID, "RGB LED PWM " & to_string(i_rgb) & " changed to:" &
                    " R:" & to_string(integer(real(v_time_delta(2) * 256 / c_pwm_period))) &
                    " G:" & to_string(integer(real(v_time_delta(1) * 256 / c_pwm_period))) &
                    " B:" & to_string(integer(real(v_time_delta(0) * 256 / c_pwm_period))),
                    INFO);
            end if;
        end process p_log_rgb_leds;

    end generate g_log_rgb_leds;

    -- Log the changes on the Basic LEDs.
    -- Generate logic process for each of the \ref parm_basic_led_count , to
    -- monitor and characterize the Basic emitter trace assertion, which are PWM
    -- signals.
    g_log_basic_leds : for i_basic in ci_led_basic'range generate
    begin

        -- Monitor and characterize the Basic emitter trace assertions,
        -- presuming that they are PWM signals.
        p_log_basic_leds : process
            constant c_pwm_period : time := parm_pwm_basic_max_duty_cycle * 1 ms;
            variable v_have_on : boolean := false;
            variable v_have_off : boolean := false;
            variable v_time_on : time := 0 ms;
            variable v_time_off : time := 0 ms;
            variable v_time_delta : time := 0 ms;
        begin
            wait on ci_led_basic(i_basic); -- wait on the emitter signal
            Log(ModelID, "BASIC LED emitter " & to_string(i_basic) &
                " changed to: " & to_string(ci_led_basic(i_basic)),
                DEBUG);

            -- For the one emitter, toggle between measuring time that the
            -- the emitter is asserted ON, once per PWM cycle.
            if ci_led_basic(i_basic) = '1' then
                if not v_have_on then
                    v_have_on := true;
                    v_time_on := NOW;
                end if;
            elsif v_have_on then
                if not v_have_off then
                    v_have_off := true;
                    v_time_off := NOW;
                end if;
            end if;

            -- If the PWM has been measured from the ON state to the OFF state.
            if (v_have_on and v_have_off) then
                v_time_delta := v_time_off - v_time_on;
                v_have_on := false;
                v_have_off := false;
                v_time_on := 0 ms;
                v_time_off := 0 ms;

                -- Log the eitter time delta
                Log(ModelID, "BASIC LED PWM " & to_string(i_basic) &
                    " lasted for:" & " L:" & to_string(v_time_delta),
                    INFO);

                -- Log the emitter time delta as 8-bit magnitude, indicating
                -- the likely basic magnitude sent to the led_pwm_driver module
                -- inside the FPGA.
                Log(ModelID, "BASIC LED PWM " & to_string(i_basic) &
                    " changed to:" & " L:" &
                    to_string(integer(real(v_time_delta * 256 / c_pwm_period))),
                    INFO);
            end if;

        end process p_log_basic_leds;
    end generate g_log_basic_leds;

end architecture simulation_default;
--------------------------------------------------------------------------------
