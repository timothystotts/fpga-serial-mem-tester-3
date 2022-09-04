/*------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2020-2021 Timothy Stotts
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
------------------------------------------------------------------------------*/
/**-----------------------------------------------------------------------------
-- \file lcd_text_feed.sv
--
-- \brief A timed FSM to feed display updates to a two-line LCD.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//Timed Moore Machine-----------------------------------------------------------
//Part 1: Module header:--------------------------------------------------------
module lcd_text_feed
	#(parameter
		integer parm_fast_simulation = 0,
		integer parm_FCLK_ce)
	(
	input logic i_clk_40mhz,
	input logic i_rst_40mhz,
	input logic i_ce_mhz,
	input logic i_lcd_command_ready,
	output logic o_lcd_wr_clear_display,
	output logic o_lcd_wr_text_line1,
	output logic o_lcd_wr_text_line2,
	output logic o_lcd_feed_is_idle);

//Part 2: Declarations----------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

// Connections and variables for instance of the PMOD CLS SPI SOLO driver. 
`define c_lcd_update_fsm_bits 4

typedef enum logic [(`c_lcd_update_fsm_bits - 1):0] {
	ST_LCD_PAUSE, ST_LCD_CLEAR_RUN, ST_LCD_CLEAR_DLY, ST_LCD_CLEAR_WAIT,
	ST_LCD_LINE1_RUN, ST_LCD_LINE1_DLY, ST_LCD_LINE1_WAIT, ST_LCD_LINE2_RUN,
	ST_LCD_LINE2_DLY
} t_lcd_upd_state;

t_lcd_upd_state s_lcd_upd_pr_state;
t_lcd_upd_state s_lcd_upd_nx_state;

// Timer steps for the continuous refresh of the PMOD CLS display:
// Clear Display
// Wait 1.0 milliseconds
// Write Line 1
// Wait 1.0 milliseconds
// Write Line 2
// Wait 0.198 seconds (or wait 0.008 seconds if parm_fast_simulation)
// Repeat the above. 
localparam c_lcd_update_timer_bits = 26;
// The sub-second refresh is actually 1/5 of a second to have a 5 Hz refresh,
// approximately. If \ref parm_fast_simulation is defined, then tne once
// second refresh is actually 1/100 of a second to have a 100 Hz refresh
// for waveform viewing. 
typedef logic [(c_lcd_update_timer_bits - 1):0] t_cnt_i_value;

localparam t_cnt_i_value c_i_one_ms = (parm_FCLK_ce / 1000);
localparam t_cnt_i_value c_i_subsecond =
	parm_fast_simulation ? ((parm_FCLK_ce / 100) - (2 * c_i_one_ms)) : ((parm_FCLK_ce / 5) - (2 * c_i_one_ms));
localparam t_cnt_i_value c_i_max = c_i_subsecond;

t_cnt_i_value s_i;

//Part 3: Statements------------------------------------------------------------
// Timer (strategy #1) for timing the PMOD CLS display update 
always_ff @(posedge i_clk_40mhz)
begin: p_fsm_timer_run_display_update
	if (i_rst_40mhz) s_i <= 0;
	else
		if (i_ce_mhz)
			if (s_lcd_upd_pr_state != s_lcd_upd_nx_state) begin : if_chg_state
				s_i <= 0;
			end : if_chg_state

			else if (s_i != c_i_max) begin : if_not_iter_max
				s_i <= s_i + 1;
			end : if_not_iter_max

end : p_fsm_timer_run_display_update

// FSM state transition for timing the PMOD CLS display update
always_ff @(posedge i_clk_40mhz)
begin: p_fsm_state_run_display_update
	if (i_rst_40mhz)
		s_lcd_upd_pr_state <= ST_LCD_PAUSE;
	else 
		if (i_ce_mhz)
			s_lcd_upd_pr_state <= s_lcd_upd_nx_state;
end : p_fsm_state_run_display_update

// FSM combinatorial logic for timing the PMOD CLS display update
always_comb
begin: p_fsm_comb_run_display_update
	case (s_lcd_upd_pr_state)
		ST_LCD_CLEAR_RUN: begin // Issue a clear command and wait for
								// the LCD driver to acknowledge a
								// command in progress.
			o_lcd_wr_clear_display = 1'b1;
			o_lcd_wr_text_line1 = 1'b0;
			o_lcd_wr_text_line2 = 1'b0;

			if (! i_lcd_command_ready) s_lcd_upd_nx_state = ST_LCD_CLEAR_DLY;
			else s_lcd_upd_nx_state = ST_LCD_CLEAR_RUN;
		end
		ST_LCD_CLEAR_DLY: begin // Now that the Clear command is running,
								// wait for one millisecond.
			o_lcd_wr_clear_display = 1'b0;
			o_lcd_wr_text_line1 = 1'b0;
			o_lcd_wr_text_line2 = 1'b0;

			if (s_i == c_i_one_ms - 1) s_lcd_upd_nx_state = ST_LCD_CLEAR_WAIT;
			else s_lcd_upd_nx_state = ST_LCD_CLEAR_DLY;
		end			
		ST_LCD_CLEAR_WAIT: begin // Advance to writing LINE 1 when the
								 // LCD driver is ready for input.
			o_lcd_wr_clear_display = 1'b0;
			o_lcd_wr_text_line1 = 1'b0;
			o_lcd_wr_text_line2 = 1'b0;

			if (i_lcd_command_ready) s_lcd_upd_nx_state = ST_LCD_LINE1_RUN;
			else s_lcd_upd_nx_state = ST_LCD_CLEAR_WAIT;
		end			
		ST_LCD_LINE1_RUN: begin // Issue a write Line 1 command and wait for
								// the LCD driver to acknowledge a
								// command in progress.
			o_lcd_wr_clear_display = 1'b0;
			o_lcd_wr_text_line1 = 1'b1;
			o_lcd_wr_text_line2 = 1'b0;

			if (! i_lcd_command_ready) s_lcd_upd_nx_state = ST_LCD_LINE1_DLY;
			else s_lcd_upd_nx_state = ST_LCD_LINE1_RUN;
		end
		ST_LCD_LINE1_DLY: begin // Now that the write Line 1 command is running,
								// wait for one millisecond.
			o_lcd_wr_clear_display = 1'b0;
			o_lcd_wr_text_line1 = 1'b0;
			o_lcd_wr_text_line2 = 1'b0;

			if (s_i == c_i_one_ms - 1) s_lcd_upd_nx_state = ST_LCD_LINE1_WAIT;
			else s_lcd_upd_nx_state = ST_LCD_LINE1_DLY;
		end
		ST_LCD_LINE1_WAIT: begin // Advance to writing LINE 2 when the
								 // LCD driver is ready for input.
			o_lcd_wr_clear_display = 1'b0;
			o_lcd_wr_text_line1 = 1'b0;
			o_lcd_wr_text_line2 = 1'b0;

			if (i_lcd_command_ready) s_lcd_upd_nx_state = ST_LCD_LINE2_RUN;
			else s_lcd_upd_nx_state = ST_LCD_LINE1_WAIT;
		end			
		ST_LCD_LINE2_RUN: begin // Issue a write Line 2 command and wait for
								// the LCD driver to acknowledge a
								// command in progress.
			o_lcd_wr_clear_display = 1'b0;
			o_lcd_wr_text_line1 = 1'b0;
			o_lcd_wr_text_line2 = 1'b1;

			if (! i_lcd_command_ready) s_lcd_upd_nx_state = ST_LCD_LINE2_DLY;
			else s_lcd_upd_nx_state = ST_LCD_LINE2_RUN;
		end
		ST_LCD_LINE2_DLY: begin // Now that the write Line 2 command is running,
								// wait for one millisecond.
			o_lcd_wr_clear_display = 1'b0;
			o_lcd_wr_text_line1 = 1'b0;
			o_lcd_wr_text_line2 = 1'b0;

			if (s_i == c_i_subsecond - 1) s_lcd_upd_nx_state = ST_LCD_PAUSE;
			else s_lcd_upd_nx_state = ST_LCD_LINE2_DLY;
		end
		default: begin // ST_LCD_PAUSE
					   // Step PAUSE, wait until display ready to write again
			o_lcd_wr_clear_display = 1'b0;
			o_lcd_wr_text_line1 = 1'b0;
			o_lcd_wr_text_line2 = 1'b0;

			if (i_lcd_command_ready) s_lcd_upd_nx_state = ST_LCD_CLEAR_RUN;
			else s_lcd_upd_nx_state = ST_LCD_PAUSE;
		end
	endcase
end : p_fsm_comb_run_display_update

// Indicate when the FSM is idle
assign o_lcd_feed_is_idle = (s_lcd_upd_pr_state == ST_LCD_LINE2_DLY) ? 1'b1 : 1'b0;

endmodule : lcd_text_feed
//------------------------------------------------------------------------------
`end_keywords
