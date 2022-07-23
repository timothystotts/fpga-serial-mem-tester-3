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
-- \file N25Qxxx_wrapper.v
--
-- \brief A Verilog-2001 wrapper around the Micro vendor module N25Qxxx.v , thus
-- allowing this wrapper to be instantiated as a component inside of a
-- VHDL test-bench.
------------------------------------------------------------------------------*/
//------------------------------------------------------------------------------
//Part 1: Module header:--------------------------------------------------------
`timescale 1ns / 1ps

module N25Qxxx_wrapper(
	S, C, HOLD_DQ3, DQ0, DQ1, W_DQ2
	);

parameter time powerup_time = 150e0;

input S;
input C;
inout HOLD_DQ3;
inout DQ0;
inout DQ1;
inout W_DQ2;

//Part 2: Declarations----------------------------------------------------------
`define VoltageRange 31:0
reg [`VoltageRange] Vcc;
wire RESET2;

//Part 3: Statements------------------------------------------------------------
assign RESET2 = 1'b1;

initial
begin
    Vcc = 'd3300;
	#(powerup_time+100);
end

N25Qxxx #() u_N25Qxxx (
	.S(S),
	.C_(C),
	.HOLD_DQ3(HOLD_DQ3),
	.DQ0(DQ0),
	.DQ1(DQ1),
	.Vcc(Vcc),
	.Vpp_W_DQ2(W_DQ2),
	.RESET2(RESET2)
	);

endmodule
//------------------------------------------------------------------------------
