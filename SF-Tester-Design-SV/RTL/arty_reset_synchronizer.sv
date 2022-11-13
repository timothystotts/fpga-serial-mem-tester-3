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
-- \file arty_reset_synchronizer.sv
--
-- \brief A simple non-generic reset synchronizer for the Arty A7 board.
-- Credit is due to a non-copied examination of VHDL EXTRAS repo on GitHub, VHDL
-- reset_synchronizer.vhdl source at:
-- https://github.com/kevinpt/vhdl-extras/blob/master/rtl/extras/synchronizing.vhdl
-- The reference is MIT License Copyright 2010 Kevin Thibedeau
--
-- Note that this module does not track the clock locking of the MMCM.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//Reset Synchronizer------------------------------------------------------------
//Part 1: Module header:--------------------------------------------------------
module arty_reset_synchronizer(
	input logic i_clk_mhz,
	input logic i_rstn_global,
	output logic o_rst_mhz);

//Part 2: Declarations----------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

localparam integer c_RESET_STAGES = 14;

logic [(c_RESET_STAGES - 1):0] s_rst_shift;

//Part 3: Statements------------------------------------------------------------
always_ff @(posedge i_clk_mhz, negedge i_rstn_global)
begin: p_sync_reset_shift
	if (! i_rstn_global)
		s_rst_shift <= { c_RESET_STAGES{1'b1} };
	else
		s_rst_shift <= {s_rst_shift[(c_RESET_STAGES - 2)-:(c_RESET_STAGES - 1)], 1'b0};
end

assign o_rst_mhz = s_rst_shift[c_RESET_STAGES - 1];

endmodule : arty_reset_synchronizer
//------------------------------------------------------------------------------
`end_keywords
