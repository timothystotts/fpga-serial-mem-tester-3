/*------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2020-2022 Timothy Stotts
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
-- \file clock_divider.sv
--
-- \brief A clock divider for an even integer division of the source clock.
--
-- \description Generates a single clock cycle synchronous reset and generates
-- a divided-down clock for usage of clock edge sensitivity.
--
-- Note that this module requires the usage of TCL command
-- \ref create_generated_clock to indicate to the Xilinx synthesis tool that
-- this module implements a clock divider.
------------------------------------------------------------------------------*/
//------------------------------------------------------------------------------
`begin_keywords "1800-2012"
//Part 1: Module header:--------------------------------------------------------
module clock_divider
    #(parameter
        integer par_clk_divisor = 1000
        )
    (
        output logic o_clk_div,
        output logic o_rst_div,
        input logic i_clk_mhz,
        input logic i_rst_mhz);

// Part 2: Declarations---------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

// A constant representing the counter maximum which is an even division of the
// source clock, per paramter \ref par_clk_divisor .
localparam integer c_clk_max = (par_clk_divisor / 2) - 1;

// Clock division count, that counts from 0 to \ref c_clk_max and back again
// to run the divided clock output at an even division \par_clk_divisor of
// the source clock.
integer s_clk_div_cnt;

// A clock enable at the source clock frequency which issues the periodic
// toggle of the divided clock.
logic s_clk_div_ce;

// Variables for the divided clock and reset.
logic s_clk_out;
logic s_rst_out;

//Part 3: Statements------------------------------------------------------------
// The even clock frequency division is operated by a clock enable signal to
// indicate the upstream clock cycle for changing the edge of the downstream
// clock waveform.
always_ff @(posedge i_clk_mhz)
begin: p_clk_div_cnt
    if (i_rst_mhz) begin
        s_clk_div_cnt <= 0;
        s_clk_div_ce <= 1'b1;
    end else
        if (s_clk_div_cnt == c_clk_max) begin : if_counter_max_reset
            s_clk_div_cnt <= 0;
            s_clk_div_ce <= 1'b1;
        end : if_counter_max_reset

        else begin : if_counter_lt_max_inc
            s_clk_div_cnt <= s_clk_div_cnt + 1;
            s_clk_div_ce <= 1'b0;
        end : if_counter_lt_max_inc
end : p_clk_div_cnt

// While the upstream clock is executing with reset held, this process will
// hold the clock at zero and the reset at active one. When the upstream reset
// signal is released, the downstream clock will have one positive edge with
// this reset output held active one, and then on the falling edge of the
// downstream clock, the reset will change from active one to inactive low.
always_ff @(posedge i_clk_mhz)
begin: p_clk_div_out
    if (i_rst_mhz) begin
        s_rst_out <= 1'b1;
        s_clk_out <= 1'b0;
    end else
        if (s_clk_div_ce) begin
            s_rst_out <= s_rst_out && (~ s_clk_out);
            s_clk_out <= ~ s_clk_out;
        end
end : p_clk_div_out

assign o_clk_div = s_clk_out;
assign o_rst_div = s_rst_out;

endmodule : clock_divider
//------------------------------------------------------------------------------
`end_keywords
