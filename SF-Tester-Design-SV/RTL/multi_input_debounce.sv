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
-- \file multi_input_debounce.sv
--
-- \module multi_input_debounce
--
-- \brief This FSM is the full 4-button mutual-exclusive debouncer, level
-- output, without embedded one-shot, with 1 millisecond debounce.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//Timed FSM---------------------------------------------------------------------
//Part 1: Module header:--------------------------------------------------------
module multi_input_debounce
	#(parameter
		integer FCLK = 20000000 // system clock frequency in Hz
		)
	(	
		input logic i_clk_mhz, // system clock
		input logic i_rst_mhz, // synchronized reset
		input logic [3:0] ei_buttons, // the raw signals input
		output logic [3:0] o_btns_deb // logic level signals value indicator
		);

//Part 2: Declarations----------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

// Xilinx FSM Encoding attributes
(* fsm_encoding = "auto" *)
(* fsm_safe_state = "default_state" *)
typedef enum logic [1:0] {ST_A, ST_B, ST_C, ST_D} t_mideb_state;
t_mideb_state s_mideb_pr_state;
t_mideb_state s_mideb_nx_state;

// Timer-related declarations
localparam integer c_T = FCLK * 1 / 1000; // 1 millisecond debounce
localparam integer c_tmax = c_T - 1;

integer s_t;

logic [3:0] si_buttons_meta;
logic [3:0] si_buttons_sync;
logic [3:0] si_buttons_prev;
logic [3:0] si_buttons_store;
logic [3:0] so_btns_deb;

//Part 3: Statements------------------------------------------------------------

// FSM input signals synchronized to prevent meta-stability
always_ff @(posedge i_clk_mhz)
begin: p_sync_buttons_input
	si_buttons_sync <= si_buttons_meta;
	si_buttons_meta <= ei_buttons;
end : p_sync_buttons_input

// FSM Timer (Strategy #1)
always_ff @(posedge i_clk_mhz)
begin: p_fsm_timer1
	if (i_rst_mhz)
		s_t <= 0;
	else
		if (s_mideb_pr_state != s_mideb_nx_state) begin : if_chg_state
			s_t <= 0;
		end : if_chg_state

		else if (s_t != c_tmax) begin : if_not_timer_max
			s_t <= s_t + 1;
		end : if_not_timer_max
end : p_fsm_timer1

// FSM state register:
always_ff @(posedge i_clk_mhz)
begin: p_fsm_state
	if (i_rst_mhz) begin
		s_mideb_pr_state <= ST_A;
		si_buttons_prev <= 4'b0000;
		si_buttons_store <= 4'b0000;
	end else begin : if_fsm_state_and_storage
		if ((s_mideb_nx_state == ST_C) && (s_mideb_pr_state == ST_B))
			si_buttons_store <= si_buttons_prev;

		si_buttons_prev <= si_buttons_sync;

		s_mideb_pr_state <= s_mideb_nx_state;
	end : if_fsm_state_and_storage
end : p_fsm_state

// FSM combinational logic:
always_comb
begin: p_fsm_comb
	case (s_mideb_pr_state)
		ST_B: begin
			so_btns_deb <= 4'b0000;
			if (si_buttons_sync != si_buttons_prev)
				s_mideb_nx_state <= ST_A;
			else if (s_t == c_T - 2)
				s_mideb_nx_state <= ST_C;
			else
				s_mideb_nx_state <= ST_B;
		end
		ST_C: begin
			so_btns_deb <= si_buttons_store;
			if (si_buttons_sync != si_buttons_store)
				s_mideb_nx_state <= ST_D;
			else
				s_mideb_nx_state <= ST_C;
		end
		ST_D: begin
			so_btns_deb <= si_buttons_store;
			if (si_buttons_sync == si_buttons_store)
				s_mideb_nx_state <= ST_C;
			else if (s_t == c_T - 3)
				s_mideb_nx_state <= ST_A;
			else
				s_mideb_nx_state <= ST_D;
		end
		default: begin // ST_A
			so_btns_deb <= 4'b0000;
			if ((si_buttons_sync == 4'b0000) ||
				(si_buttons_sync == 4'b1000) ||
				(si_buttons_sync == 4'b0100) ||
				(si_buttons_sync == 4'b0010) ||
				(si_buttons_sync == 4'b0001))
				s_mideb_nx_state <= ST_B;
			else
				s_mideb_nx_state <= ST_A;
		end
	endcase
end : p_fsm_comb

assign o_btns_deb = so_btns_deb;

endmodule : multi_input_debounce
//------------------------------------------------------------------------------
`end_keywords
