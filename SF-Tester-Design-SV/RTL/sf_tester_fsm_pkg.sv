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
-- \file sf_tester_fsm_pkg.sv
--
-- \brief A package of definitions used by the SPI drivers.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//------------------------------------------------------------------------------
package sf_tester_fsm_pkg;
	// The Tester FSM states definition
	typedef enum logic [4:0] {ST_WAIT_BUTTON_DEP, ST_WAIT_BUTTON0_REL,
		ST_WAIT_BUTTON1_REL, ST_WAIT_BUTTON2_REL, ST_WAIT_BUTTON3_REL,
		ST_SET_PATTERN_A, ST_SET_PATTERN_B, ST_SET_PATTERN_C, ST_SET_PATTERN_D,
		ST_SET_START_ADDR_A, ST_SET_START_ADDR_B, ST_SET_START_ADDR_C, 
		ST_SET_START_ADDR_D, ST_SET_START_WAIT_A, ST_SET_START_WAIT_B,
		ST_SET_START_WAIT_C, ST_SET_START_WAIT_D,
		ST_CMD_ERASE_START, ST_CMD_ERASE_WAIT, ST_CMD_ERASE_NEXT,
		ST_CMD_ERASE_DONE, ST_CMD_PAGE_START, ST_CMD_PAGE_BYTE, ST_CMD_PAGE_WAIT,
		ST_CMD_PAGE_NEXT, ST_CMD_PAGE_DONE, ST_CMD_READ_START, ST_CMD_READ_BYTE,
		ST_CMD_READ_WAIT, ST_CMD_READ_NEXT, ST_CMD_READ_DONE, ST_DISPLAY_FINAL}
		t_tester_state;

	// System control of N25Q state machine
	localparam integer c_max_possible_byte_count = 33554432; // 256 Mbit
	localparam integer c_total_iteration_count = 32;
	localparam integer c_per_iteration_byte_count =
		c_max_possible_byte_count / c_total_iteration_count;
	localparam integer c_last_starting_byte_addr =
		c_per_iteration_byte_count * (c_total_iteration_count - 1);

	localparam integer c_sf3_subsector_addr_incr = 4096;
	localparam integer c_sf3_page_addr_incr = 256;

	localparam integer c_tester_subsector_cnt_per_iter =
		8192 / c_total_iteration_count;
	localparam integer c_tester_page_cnt_per_iter =
		131072 / c_total_iteration_count;

	// Testing patterns, the starting byte value and the byte increment value,
	// causing either a sequential counting pattern or a pseudo-random counting
	// pattern.
	localparam [7:0] c_tester_pattern_startval_a = 8'h00;
	localparam [7:0] c_tester_pattern_incrval_a = 8'h01;

	localparam [7:0] c_tester_pattern_startval_b = 8'h08;
	localparam [7:0] c_tester_pattern_incrval_b = 8'h07;

	localparam [7:0] c_tester_pattern_startval_c = 8'h10;
	localparam [7:0] c_tester_pattern_incrval_c = 8'h0F;

	localparam [7:0] c_tester_pattern_startval_d = 8'h18;
	localparam [7:0] c_tester_pattern_incrval_d = 8'h17;

endpackage : sf_tester_fsm_pkg
//------------------------------------------------------------------------------
`end_keywords
