/*------------------------------------------------------------------------------
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
------------------------------------------------------------------------------*/
/**-----------------------------------------------------------------------------
-- \file led_palette_updater.sv
--
-- \brief A simple updater to generate palette values for
-- \ref led_pwm_driver.sv .
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//D-FF based LED pulsing--------------------------------------------------------
//Part 1: Module header:--------------------------------------------------------
module led_palette_updater
	import sf_tester_fsm_pkg::*;
	#(parameter
		// color filament and pwm parameters
		integer parm_color_led_count = 4,
		integer parm_basic_led_count = 4,
		// calculated constants that should not be overridden
		integer c_color_value_upper = 8 * parm_color_led_count - 1,
		integer c_basic_value_upper = 8 * parm_basic_led_count - 1,
		integer c_color_count_upper = parm_color_led_count - 1,
		integer c_basic_count_upper = parm_basic_led_count - 1
		)
	(
		// clock and reset
		input logic i_clk,
		input logic i_srst,
		// palette output values
		output logic [c_color_value_upper:0] o_color_led_red_value,
		output logic [c_color_value_upper:0] o_color_led_green_value,
		output logic [c_color_value_upper:0] o_color_led_blue_value,
		output logic [c_basic_value_upper:0] o_basic_led_lumin_value,
		// SF Tester FSM state and status inputs
		input logic i_test_pass,
		input logic i_test_done,
		input t_tester_state i_tester_pr_state
		);

//Part 2: Declarations----------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

// Basic LED outputs to indicate test passed or failed
generate
	if ((parm_color_led_count == 2) && (parm_basic_led_count == 4)) begin: g_2rgb_4basic_updater
		assign o_basic_led_lumin_value = {
			8'h00, 8'h00, (i_test_done ? 8'hFF : 8'h00), (i_test_pass ? 8'hFF : 8'h00)
		};

		// Color LED stage output indication for the PMOD SF Tester FSM progress
		// and current state group.
		always_comb
		begin : p_tester_fsm_progress
			o_color_led_red_value = {8'h00, 8'h00};
			o_color_led_green_value = {8'h00, 8'h00};
			o_color_led_blue_value = {8'h00, 8'h00};

			case (i_tester_pr_state)
				ST_WAIT_BUTTON0_REL, ST_SET_PATTERN_A,	ST_SET_START_ADDR_A, ST_SET_START_WAIT_A :
					o_color_led_green_value[7-:8] = 8'hFF;

				ST_WAIT_BUTTON1_REL, ST_SET_PATTERN_B, ST_SET_START_ADDR_B, ST_SET_START_WAIT_B :
					o_color_led_green_value[15-:8] = 8'hFF;

				ST_WAIT_BUTTON2_REL, ST_SET_PATTERN_C, ST_SET_START_ADDR_C, ST_SET_START_WAIT_C :
					o_color_led_blue_value[7-:8] = 8'hFF;

				ST_WAIT_BUTTON3_REL, ST_SET_PATTERN_D, ST_SET_START_ADDR_D, ST_SET_START_WAIT_D :
					o_color_led_blue_value[15-:8] = 8'hFF;

				ST_CMD_ERASE_START, ST_CMD_ERASE_WAIT, ST_CMD_ERASE_NEXT : begin
					o_color_led_red_value[7-:8] = 8'h80;
					o_color_led_green_value[7-:8] = 8'h80;
					o_color_led_blue_value[7-:8] = 8'h80;
				end

				ST_CMD_ERASE_DONE : begin
					o_color_led_red_value[7-:8] = 8'h70;
					o_color_led_green_value[7-:8] = 8'h10;
				end

				ST_CMD_PAGE_START, ST_CMD_PAGE_BYTE, ST_CMD_PAGE_WAIT,
				ST_CMD_PAGE_NEXT : begin
					o_color_led_red_value[15-:8] = 8'h80;
					o_color_led_green_value[15-:8] = 8'h80;
					o_color_led_blue_value[15-:8] = 8'h80;
				end

				ST_CMD_PAGE_DONE : begin
					o_color_led_red_value[15-:8] = 8'h70;
					o_color_led_green_value[15-:8] = 8'h10;
				end

				ST_CMD_READ_START, ST_CMD_READ_BYTE, ST_CMD_READ_WAIT,
				ST_CMD_READ_NEXT : begin
					o_color_led_green_value[7-:8] = 8'h80;
					o_color_led_blue_value[7-:8] = 8'h80;
				end

				ST_CMD_READ_DONE : begin
					o_color_led_red_value[7-:8] = 8'h70;
					o_color_led_green_value[7-:8] = 8'h10;
				end

				ST_DISPLAY_FINAL : begin
					o_color_led_green_value[15-:8] = 8'h80;
					o_color_led_blue_value[15-:8] = 8'h80;
				end

				default : // ST_WAIT_BUTTON_DEP
					o_color_led_red_value = {2{8'hFF}};
			endcase

		end : p_tester_fsm_progress
	end : g_2rgb_4basic_updater
endgenerate

generate
	if ((parm_color_led_count == 4)  && (parm_basic_led_count == 4)) begin: g_4rgb_4basic_updater
		assign o_basic_led_lumin_value = {
			8'h00, 8'h00, (i_test_done ? 8'hFF : 8'h00), (i_test_pass ? 8'hFF : 8'h00)
		};

		// Color LED stage output indication for the PMOD SF Tester FSM progress
		// and current state group.
		always_comb
		begin : p_tester_fsm_progress
			o_color_led_red_value = {8'h00, 8'h00, 8'h00, 8'h00};
			o_color_led_green_value = {8'h00, 8'h00, 8'h00, 8'h00};
			o_color_led_blue_value = {8'h00, 8'h00, 8'h00, 8'h00};

			case (i_tester_pr_state)
				ST_WAIT_BUTTON0_REL, ST_SET_PATTERN_A,	ST_SET_START_ADDR_A, ST_SET_START_WAIT_A :
					o_color_led_green_value[7-:8] = 8'hFF;

				ST_WAIT_BUTTON1_REL, ST_SET_PATTERN_B, ST_SET_START_ADDR_B, ST_SET_START_WAIT_B :
					o_color_led_green_value[15-:8] = 8'hFF;

				ST_WAIT_BUTTON2_REL, ST_SET_PATTERN_C, ST_SET_START_ADDR_C, ST_SET_START_WAIT_C :
					o_color_led_green_value[23-:8] = 8'hFF;

				ST_WAIT_BUTTON3_REL, ST_SET_PATTERN_D, ST_SET_START_ADDR_D, ST_SET_START_WAIT_D :
					o_color_led_green_value[31-:8] = 8'hFF;

				ST_CMD_ERASE_START, ST_CMD_ERASE_WAIT, ST_CMD_ERASE_NEXT : begin
					o_color_led_red_value[7-:8] = 8'h80;
					o_color_led_green_value[7-:8] = 8'h80;
					o_color_led_blue_value[7-:8] = 8'h80;
				end

				ST_CMD_ERASE_DONE : begin
					o_color_led_red_value[7-:8] = 8'h70;
					o_color_led_green_value[7-:8] = 8'h10;
					o_color_led_blue_value[7-:8] = 8'h00;
				end

				ST_CMD_PAGE_START, ST_CMD_PAGE_BYTE, ST_CMD_PAGE_WAIT,
				ST_CMD_PAGE_NEXT : begin
					o_color_led_red_value[15-:8] = 8'h80;
					o_color_led_green_value[15-:8] = 8'h80;
					o_color_led_blue_value[15-:8] = 8'h80;
				end

				ST_CMD_PAGE_DONE : begin
					o_color_led_red_value[15-:8] = 8'h70;
					o_color_led_green_value[15-:8] = 8'h10;
					o_color_led_blue_value[15-:8] = 8'h00;
				end

				ST_CMD_READ_START, ST_CMD_READ_BYTE, ST_CMD_READ_WAIT,
				ST_CMD_READ_NEXT : begin
					o_color_led_red_value[23-:8] = 8'h80;
					o_color_led_green_value[23-:8] = 8'h80;
					o_color_led_blue_value[23-:8] = 8'h80;
				end

				ST_CMD_READ_DONE : begin
					o_color_led_red_value[23-:8] = 8'h70;
					o_color_led_green_value[23-:8] = 8'h10;
					o_color_led_blue_value[23-:8] = 8'h00;
				end

				ST_DISPLAY_FINAL : begin
					o_color_led_red_value[31-:8] = 8'hA0;
					o_color_led_green_value[31-:8] = 8'hA0;
					o_color_led_blue_value[31-:8] = 8'h50;
				end

				default : // ST_WAIT_BUTTON_DEP
					o_color_led_red_value = {4{8'hFF}};
			endcase

		end : p_tester_fsm_progress
	end : g_4rgb_4basic_updater
endgenerate

endmodule : led_palette_updater
//------------------------------------------------------------------------------
`end_keywords
