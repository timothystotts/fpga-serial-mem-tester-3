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
-- \file lcd_text_functions_pkg.vhdl
--
-- \brief A package of functions for converting between internal signal values
-- and ASCII values for the purpose of generating lines of ASCII text for
-- display on a text display peripheral.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--------------------------------------------------------------------------------
package lcd_text_functions_pkg is
	function ascii_of_hdigit(bchex_val : std_logic_vector(3 downto 0))
		return std_logic_vector;
end package lcd_text_functions_pkg;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
package body lcd_text_functions_pkg is
	-- A re-entrant function that converts a 4-bit vector to an 8-bit ASCII
	-- hexadecimal character.
	function ascii_of_hdigit(bchex_val : std_logic_vector(3 downto 0))
		return std_logic_vector is
		variable v_bcd_nibble : unsigned(bchex_val'range);
		variable v_ascii_byte : std_logic_vector(7 downto 0);
	begin
		v_bcd_nibble := unsigned(bchex_val);
		if (v_bcd_nibble < 10) then
			v_ascii_byte := std_logic_vector(unsigned'(x"30") + (unsigned'(x"0") & unsigned(bchex_val)));
		else
			v_ascii_byte := std_logic_vector(unsigned'(x"37") + (unsigned'(x"0") & unsigned(bchex_val)));
		end if;

		return v_ascii_byte;
	end function ascii_of_hdigit;
end package body lcd_text_functions_pkg;
--------------------------------------------------------------------------------
