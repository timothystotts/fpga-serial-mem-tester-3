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
-- \file lcd_text_functions_pkg.sv
--
-- \brief A timed FSM to feed display updates to a two-line LCD.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
package lcd_text_functions_pkg;
	timeunit 1ns;
	timeprecision 1ps;

	// A re-entrant function that converts a 4-bit vector to an 8-bit ASCII
	// hexadecimal character.
	function automatic [7:0] ascii_of_hdigit(input logic [3:0] bchex_val);
		if (bchex_val < 8'h0A)
			return (8'h30 + bchex_val);
		else
			return (8'h37 + bchex_val);
	endfunction : ascii_of_hdigit
endpackage : lcd_text_functions_pkg
//------------------------------------------------------------------------------
`end_keywords
