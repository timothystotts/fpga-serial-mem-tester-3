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
-- \file led_palette_updater.vhdl
--
-- \brief A simple updater to generate palette values for \ref led_pwm_driver.vhdl
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.led_pwm_driver_pkg.all;
use work.sf_tester_fsm_pkg.t_tester_state;
--------------------------------------------------------------------------------
entity led_palette_updater is
	generic(
		-- color filament and pwm parameters
		parm_color_led_count : integer := 4;
		parm_basic_led_count : integer := 4
	);
	port(
		-- clock and reset
		i_clk  : in std_logic;
		i_srst : in std_logic;
		-- pallete output values
		o_color_led_red_value   : out t_led_color_values((parm_color_led_count - 1) downto 0);
		o_color_led_green_value : out t_led_color_values((parm_color_led_count - 1) downto 0);
		o_color_led_blue_value  : out t_led_color_values((parm_color_led_count - 1) downto 0);
		o_basic_led_lumin_value : out t_led_color_values((parm_basic_led_count - 1) downto 0);
		-- SF Tester FSM state and status inputs
		i_test_pass       : in std_logic;
		i_test_done       : in std_logic;
		i_tester_pr_state : in t_tester_state
	);
end entity led_palette_updater;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
architecture rtl of led_palette_updater is
begin
	-- Basic LED outputs to indicate test passed or failed
	o_basic_led_lumin_value(0) <= x"FF" when i_test_pass = '1' else x"00";
	o_basic_led_lumin_value(1) <= x"FF" when i_test_done = '1' else x"00";
	o_basic_led_lumin_value(2) <= x"00";
	o_basic_led_lumin_value(3) <= x"00";

	-- Color LED stage output indication for the PMOD SF Tester FSM progress
	-- and current state group.
	p_tester_fsm_progress : process(i_tester_pr_state)
	begin
		o_color_led_red_value   <= (x"00", x"00", x"00", x"00");
		o_color_led_green_value <= (x"00", x"00", x"00", x"00");
		o_color_led_blue_value  <= (x"00", x"00", x"00", x"00");

		case (i_tester_pr_state) is
			when ST_WAIT_BUTTON0_REL | ST_SET_PATTERN_A |
				ST_SET_START_ADDR_A | ST_SET_START_WAIT_A =>
				o_color_led_green_value(0) <= x"FF";

			when ST_WAIT_BUTTON1_REL | ST_SET_PATTERN_B |
				ST_SET_START_ADDR_B | ST_SET_START_WAIT_B =>
				o_color_led_green_value(1) <= x"FF";

			when ST_WAIT_BUTTON2_REL | ST_SET_PATTERN_C |
				ST_SET_START_ADDR_C | ST_SET_START_WAIT_C =>
				o_color_led_green_value(2) <= x"FF";

			when ST_WAIT_BUTTON3_REL | ST_SET_PATTERN_D |
				ST_SET_START_ADDR_D | ST_SET_START_WAIT_D =>
				o_color_led_green_value(3) <= x"FF";

			when ST_CMD_ERASE_START | ST_CMD_ERASE_WAIT |
				ST_CMD_ERASE_NEXT =>
				o_color_led_red_value(0)   <= x"80";
				o_color_led_green_value(0) <= x"80";
				o_color_led_blue_value(0)  <= x"80";

            when ST_CMD_ERASE_DONE =>
                o_color_led_red_value(0)   <= x"70";
				o_color_led_green_value(0) <= x"10";
				o_color_led_blue_value(0)  <= x"00";
				
			when ST_CMD_PAGE_START | ST_CMD_PAGE_BYTE | ST_CMD_PAGE_WAIT |
				ST_CMD_PAGE_NEXT =>
				o_color_led_red_value(1)   <= x"80";
				o_color_led_green_value(1) <= x"80";
				o_color_led_blue_value(1)  <= x"80";

            when ST_CMD_PAGE_DONE =>
                o_color_led_red_value(1)   <= x"70";
				o_color_led_green_value(1) <= x"10";
				o_color_led_blue_value(1)  <= x"00";
				
			when ST_CMD_READ_START | ST_CMD_READ_BYTE | ST_CMD_READ_WAIT |
				ST_CMD_READ_NEXT =>
				o_color_led_red_value(2)   <= x"80";
				o_color_led_green_value(2) <= x"80";
				o_color_led_blue_value(2)  <= x"80";

            when ST_CMD_READ_DONE =>
                o_color_led_red_value(2)   <= x"70";
				o_color_led_green_value(2) <= x"10";
				o_color_led_blue_value(2)  <= x"00";
				
			when ST_DISPLAY_FINAL =>
				o_color_led_red_value(3)   <= x"A0";
				o_color_led_green_value(3) <= x"A0";
				o_color_led_blue_value(3)  <= x"50";

			when others => -- ST_WAIT_BUTTON_DEP =>
				o_color_led_red_value <= (x"FF", x"FF", x"FF", x"FF");
		end case;
	end process p_tester_fsm_progress;

end architecture rtl;
--------------------------------------------------------------------------------
