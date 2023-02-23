/*------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2020-2023 Timothy Stotts
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
-- \file pulse_stretcher_synch.sv
--
-- \brief A synchronous pulse stretcher implementation.
--
-- \description  This FSM for \ref par_T_stretch_val of 2 or more implements
-- the FSM of Figure 8.28a from the text Finite State Machines in Hardware:
-- Theory and Design (with VHDL and SystemVerilog) by Volnei A. Pedroni.
-- For a count of 1, the module implements a single D-FF between input and
-- output, and for a count of 0, the module implements a pass-through.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//Timed Moore machine with timer control strategy #1
//Part 1: Module header:--------------------------------------------------------
module pulse_stretcher_synch
    #(parameter
        // The exact count of clock cycles to hold Y as a one immediately after
        // a single clock cycle of X being a value of one.
        integer par_T_stretch_val = 64,
        integer par_T_stretch_bits = $clog2(par_T_stretch_val) // LOG2 of \ref par_T_stretch_val
        )
    (
        // The stretched output
        output logic o_y,
        // Clock and reset
        input logic i_clk,
        input logic i_rst,
        // The input value to stretch upon value of one.
        input logic i_x
        );

// Part 2: Declarations---------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

// Stretcher FSM state values
typedef enum logic [0:0] {ST_A, ST_B} t_stretch_state;

// Stretcher FSM time type and constants
typedef logic [(par_T_stretch_bits - 1):0] t_fsm_counter;
localparam t_fsm_counter c_t_stretch = par_T_stretch_val;
localparam t_fsm_counter c_tmax = c_t_stretch - 1;

// Stretcher FSM state register and next state signal
(* fsm_encoding = "auto" *)
(* fsm_safe_state = "default_state" *)
t_stretch_state s_stretch_pr_state;
t_stretch_state s_stretch_nx_state;

// Stretcher FSM timing signal
t_fsm_counter s_t;

//Part 3: Statements------------------------------------------------------------
// Timer with strategy #1 implementation. The timer re-zeroes on a Stretch FSM
// state transition; and it caps at the constant parameter c_tmax.
generate
    if (par_T_stretch_val < 1) begin
        assign o_y = i_x;
    end
endgenerate

generate
    if (par_T_stretch_val == 1) begin
        always_ff @(posedge i_clk)
        begin : p_reg_x
            if (i_rst)
                o_y <= 1'b0;
            else
                o_y <= i_x;
        end : p_reg_x
    end
endgenerate

generate
    if (par_T_stretch_val > 1) begin
        // Timer (strategy #1)
        always_ff @(posedge i_clk)
        begin: p_fsm_timer
            if (i_rst)
                s_t <= 0;
            else
                // reset and increment the timer
                if (s_stretch_pr_state != s_stretch_nx_state) begin : if_chg_state
                    s_t <= 0;
                end : if_chg_state

                else if (s_t != c_tmax) begin : if_not_timer_max
                    s_t <= s_t + 1;
                end : if_not_timer_max
        end : p_fsm_timer

        // FSM state register
        always_ff @(posedge i_clk)
        begin: p_fsm_state
            if (i_rst) s_stretch_pr_state <= ST_A;
            else s_stretch_pr_state <= s_stretch_nx_state;
        end : p_fsm_state

        // FSM combinatorial
        always_comb
        begin: p_fsm_comb
            case (s_stretch_pr_state)
                ST_B: begin
                    // State B. Hold the output as one and test if the time
                    // constant for stretching the output has elapsed. Upon
                    // elapse, transition back to State A.
                    o_y = 1'b1;
                    if (s_t >= c_t_stretch - 1) s_stretch_nx_state = ST_A;
                    else s_stretch_nx_state = ST_B;
                end
                default: begin // ST_A
                    // State A. Hold the output as zero and test if the input
                    // has dhanged to one. Upon change, transition to state B.
                    o_y = 1'b0;
                    if (i_x) s_stretch_nx_state = ST_B;
                    else s_stretch_nx_state = ST_A;
                end
            endcase // s_stretch_pr_state
        end : p_fsm_comb
    end
endgenerate

endmodule : pulse_stretcher_synch
//------------------------------------------------------------------------------
`end_keywords
