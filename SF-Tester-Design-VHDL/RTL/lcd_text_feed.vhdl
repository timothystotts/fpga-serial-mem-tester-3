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
-- \file lcd_text_feed.vhdl
--
-- \brief A timed FSM to feed display updates to a two-line LCD.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--------------------------------------------------------------------------------
entity lcd_text_feed is
	generic(
		parm_fast_simulation : integer := 0;
		parm_FCLK_ce : natural
	);
	port(
		i_clk_40mhz            : in  std_logic;
		i_rst_40mhz            : in  std_logic;
		i_ce_mhz               : in  std_logic;
		i_lcd_command_ready    : in  std_logic;
		o_lcd_wr_clear_display : out std_logic;
		o_lcd_wr_text_line1    : out std_logic;
		o_lcd_wr_text_line2    : out std_logic;
		o_lcd_feed_is_idle     : out std_logic
	);
end entity lcd_text_feed;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
architecture rtl of lcd_text_feed is
	-- Display update FSM state declarations
	type t_lcd_update_state is (ST_LCD_PAUSE, ST_LCD_CLEAR_RUN, ST_LCD_CLEAR_DLY,
			ST_LCD_CLEAR_WAIT, ST_LCD_LINE1_RUN, ST_LCD_LINE1_DLY, ST_LCD_LINE1_WAIT,
			ST_LCD_LINE2_RUN, ST_LCD_LINE2_DLY);

	-- Display update FSM state register
	signal s_lcd_upd_pr_state : t_lcd_update_state;
	signal s_lcd_upd_nx_state : t_lcd_update_state;

	-- Timer steps for the continuous refresh of the PMOD CLS display:
	-- Clear Display
	-- Wait 1.0 milliseconds
	-- Write Line 1
	-- Wait 1.0 milliseconds
	-- Write Line 2
	-- Wait 0.198 seconds
	-- Repeat the above.
	constant c_i_one_ms         : natural := (parm_FCLK_ce / 1000);
	constant c_i_subsecond_fast : natural := (parm_FCLK_ce / 100) - (2 * c_i_one_ms);
	constant c_i_subsecond      : natural := (parm_FCLK_ce / 5) - (2 * c_i_one_ms);
	constant c_i_max            : natural := c_i_subsecond;

	signal s_i : natural range 0 to c_i_max;
begin
	-- Timer (strategy #1) for timing the LCD display update commands
	p_fsm_timer_run_display_update : process(i_clk_40mhz)
	begin
		if rising_edge(i_clk_40mhz) then
			if (i_rst_40mhz = '1') then
				s_i <= 0;
			elsif (i_ce_mhz = '1') then
				if (s_lcd_upd_pr_state /= s_lcd_upd_nx_state) then
					s_i <= 0;
				elsif (s_i /= c_i_max) then
					s_i <= s_i + 1;
				end if;
			end if;
		end if;
	end process p_fsm_timer_run_display_update;

	-- FSM state transition for operating the FSM state register
	p_fsm_state_run_display_update : process(i_clk_40mhz)
	begin
		if rising_edge(i_clk_40mhz) then
			if (i_rst_40mhz = '1') then
				s_lcd_upd_pr_state <= ST_LCD_PAUSE;
			elsif (i_ce_mhz = '1') then
				s_lcd_upd_pr_state <= s_lcd_upd_nx_state;
			end if;
		end if;
	end process p_fsm_state_run_display_update;

	-- FSM combinatorial logic for operating the FSM updated commands
	p_fsm_comb_run_display_update : process(s_lcd_upd_pr_state,
			i_lcd_command_ready, s_i)
	begin
		case (s_lcd_upd_pr_state) is
			when ST_LCD_CLEAR_RUN => -- Issue a clear command and wait for
				                     -- the LCD driver to acknowledge a
				                     -- command in progress.
				o_lcd_wr_clear_display <= '1';
				o_lcd_wr_text_line1    <= '0';
				o_lcd_wr_text_line2    <= '0';

				if (i_lcd_command_ready = '0') then
					s_lcd_upd_nx_state <= ST_LCD_CLEAR_DLY;
				else
					s_lcd_upd_nx_state <= ST_LCD_CLEAR_RUN;
				end if;

			when ST_LCD_CLEAR_DLY => -- Now that the Clear command is running,
				                     -- wait for one millisecond.
				o_lcd_wr_clear_display <= '0';
				o_lcd_wr_text_line1    <= '0';
				o_lcd_wr_text_line2    <= '0';

				if (s_i = c_i_one_ms - 1) then
					s_lcd_upd_nx_state <= ST_LCD_CLEAR_WAIT;
				else
					s_lcd_upd_nx_state <= ST_LCD_CLEAR_DLY;
				end if;

			when ST_LCD_CLEAR_WAIT => -- Advance to writing LINE 1 when the
				                      -- LCD driver is ready for input.
				o_lcd_wr_clear_display <= '0';
				o_lcd_wr_text_line1    <= '0';
				o_lcd_wr_text_line2    <= '0';

				if (i_lcd_command_ready = '1') then
					s_lcd_upd_nx_state <= ST_LCD_LINE1_RUN;
				else
					s_lcd_upd_nx_state <= ST_LCD_CLEAR_WAIT;
				end if;

			when ST_LCD_LINE1_RUN => -- Issue a write Line 1 command and wait for
				                     -- the LCD driver to acknowledge a
				                     -- command in progress.
				o_lcd_wr_clear_display <= '0';
				o_lcd_wr_text_line1    <= '1';
				o_lcd_wr_text_line2    <= '0';

				if (i_lcd_command_ready = '0') then
					s_lcd_upd_nx_state <= ST_LCD_LINE1_DLY;
				else
					s_lcd_upd_nx_state <= ST_LCD_LINE1_RUN;
				end if;

			when ST_LCD_LINE1_DLY => -- Now that the write Line 1 command is running,
				                     -- wait for one millisecond.
				o_lcd_wr_clear_display <= '0';
				o_lcd_wr_text_line1    <= '0';
				o_lcd_wr_text_line2    <= '0';

				if (s_i = c_i_one_ms - 1) then
					s_lcd_upd_nx_state <= ST_LCD_LINE1_WAIT;
				else
					s_lcd_upd_nx_state <= ST_LCD_LINE1_DLY;
				end if;

			when ST_LCD_LINE1_WAIT => -- Advance to writing LINE 2 when the
				                      -- LCD driver is ready for input.
				o_lcd_wr_clear_display <= '0';
				o_lcd_wr_text_line1    <= '0';
				o_lcd_wr_text_line2    <= '0';

				if (i_lcd_command_ready = '1') then
					s_lcd_upd_nx_state <= ST_LCD_LINE2_RUN;
				else
					s_lcd_upd_nx_state <= ST_LCD_LINE1_WAIT;
				end if;

			when ST_LCD_LINE2_RUN => -- Issue a write Line 2 command and wait for
				                     -- the LCD driver to acknowledge a
				                     -- command in progress.
				o_lcd_wr_clear_display <= '0';
				o_lcd_wr_text_line1    <= '0';
				o_lcd_wr_text_line2    <= '1';

				if (i_lcd_command_ready = '0') then
					s_lcd_upd_nx_state <= ST_LCD_LINE2_DLY;
				else
					s_lcd_upd_nx_state <= ST_LCD_LINE2_RUN;
				end if;

			when ST_LCD_LINE2_DLY => -- Now that the write Line 2 command is running,
				                     -- wait for one millisecond.
				o_lcd_wr_clear_display <= '0';
				o_lcd_wr_text_line1    <= '0';
				o_lcd_wr_text_line2    <= '0';

				if (parm_fast_simulation = 0) then
					if (s_i = c_i_subsecond - 1) then
						s_lcd_upd_nx_state <= ST_LCD_PAUSE;
					else
						s_lcd_upd_nx_state <= ST_LCD_LINE2_DLY;
					end if;
				else
					if (s_i = c_i_subsecond_fast - 1) then
						s_lcd_upd_nx_state <= ST_LCD_PAUSE;
					else
						s_lcd_upd_nx_state <= ST_LCD_LINE2_DLY;
					end if;
				end if;
			when others => -- ST_LCD_PAUSE
				           -- Step PAUSE, wait until display ready to write again.
				o_lcd_wr_clear_display <= '0';
				o_lcd_wr_text_line1    <= '0';
				o_lcd_wr_text_line2    <= '0';

				if (i_lcd_command_ready = '1') then
					s_lcd_upd_nx_state <= ST_LCD_CLEAR_RUN;
				else
					s_lcd_upd_nx_state <= ST_LCD_PAUSE;
				end if;

		end case;
	end process p_fsm_comb_run_display_update;

	-- Indicate when the FSM is idle
	o_lcd_feed_is_idle <= '1' when (s_lcd_upd_pr_state = ST_LCD_LINE2_DLY) else '0';
end architecture rtl;
--------------------------------------------------------------------------------
