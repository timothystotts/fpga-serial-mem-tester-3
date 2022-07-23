--------------------------------------------------------------------------------
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
--------------------------------------------------------------------------------
-- \file sf3_testbench_pkg.vhdl
--
-- \brief OSVVM testbench extras in packages for testing
-- entity fpga_serial_sf3_tester .
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

library work;
--------------------------------------------------------------------------------
package sf3_testbench_types_pkg is
    -- The Pmod SF3 generates register values of 16-bit times 4. This type is
    -- for the raw binary data pushed to the ScoreBoard as well as found from
    -- ScoreBoard.
    subtype t_reg_sb is std_logic_vector(63 downto 0);
end package sf3_testbench_types_pkg;
--------------------------------------------------------------------------------
package body sf3_testbench_types_pkg is
end package body sf3_testbench_types_pkg;
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

library work;
use work.sf3_testbench_types_pkg.all;
-- Creates an instance of the generic ScoreBoard package with usage of scored
-- type is \ref t_reg_sb .
package ScoreBoardPkg_sf3 is new
    osvvm.ScoreBoardGenericPkg
    generic map(
        ExpectedType => t_reg_sb,
        ActualType => t_reg_sb,
        match => ieee.std_logic_1164."=",
        expected_to_string => to_hstring,
        actual_to_string => to_hstring);
---------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

library work;
use work.sf3_testbench_types_pkg.all;
use work.ScoreBoardPkg_sf3.all;
--------------------------------------------------------------------------------
package sf3_testbench_pkg is
    -- ScoreBoard variables for pushing data values from Pmod sf3 and finding
    -- values in each of Board UART and Pmod CLS.
    shared variable SB_UART : ScoreBoardPType;
    shared variable SB_CLS : ScoreBoardPType;

    -- Function to convert a 8-bit logic value to a VHDL character from the
    -- ASCII table. A failure to find the value in the ASCII table causes a
    -- returned character of decimal point.
    function fn_convert_slv_to_ascii(
        char_as_slv : std_logic_vector(7 downto 0))
    return character;

    -- Function to convert a vector of 8-bit logic values to a VHDL character
    -- string from the ASCII table.
    function fn_convert_hex_to_ascii(
        text_as_slv : std_logic_vector;
        text_char_cnt : natural)
    return string;

    -- Function to convert a 8-bit logic value to a 4-bit logic nibble by
    -- matching the 8-bit input to an ASCII table value. If the 8-bit input
    -- is not a hexadecimal value, then the function returns "UUUU".
    function fn_convert_hex_text_to_nibble(
        char_as_slv : std_logic_vector(7 downto 0))
    return std_logic_vector;

    -- Function to convert a vector of 8-bit logic values representing ASCII
    -- hexadecimal characters to a vector of 4-bit logic values (all literal
    -- hexadecimal/binary). Any 8-bit logic values are an ASCII character that
    -- is not a hexadecimal value, then that 8-bit value is skipped and does
    -- not change the output of the function.
    function fn_convert_hex_to_slv32(
        text_as_slv : std_logic_vector;
        slv_nibble_cnt : natural)
    return std_logic_vector;
end package sf3_testbench_pkg;
--------------------------------------------------------------------------------
package body sf3_testbench_pkg is
    function fn_convert_slv_to_ascii(
        char_as_slv : std_logic_vector(7 downto 0)
    ) return character is
        variable ret_char : character := ' ';
    begin
        case char_as_slv is
            when x"20" => ret_char := ' ';
            when x"21" => ret_char := '!';
            when x"22" => ret_char := '"';
            when x"23" => ret_char := '#';
            when x"24" => ret_char := '$';
            when x"25" => ret_char := '%';
            when x"26" => ret_char := '&';
            when x"27" => ret_char := ''';
            when x"28" => ret_char := '(';
            when x"29" => ret_char := ')';
            when x"2A" => ret_char := '*';
            when x"2B" => ret_char := '+';
            when x"2C" => ret_char := ',';
            when x"2D" => ret_char := '~';
            when x"2E" => ret_char := '.';
            when x"2F" => ret_char := '/';

            when x"30" => ret_char := '0';
            when x"31" => ret_char := '1';
            when x"32" => ret_char := '2';
            when x"33" => ret_char := '3';
            when x"34" => ret_char := '4';
            when x"35" => ret_char := '5';
            when x"36" => ret_char := '6';
            when x"37" => ret_char := '7';
            when x"38" => ret_char := '8';
            when x"39" => ret_char := '9';
            when x"3A" => ret_char := ':';
            when x"3B" => ret_char := ';';
            when x"3C" => ret_char := '<';
            when x"3D" => ret_char := '=';
            when x"3E" => ret_char := '>';
            when x"3F" => ret_char := '?';

            when x"40" => ret_char := '@';
            when x"41" => ret_char := 'A';
            when x"42" => ret_char := 'B';
            when x"43" => ret_char := 'C';
            when x"44" => ret_char := 'D';
            when x"45" => ret_char := 'E';
            when x"46" => ret_char := 'F';
            when x"47" => ret_char := 'G';
            when x"48" => ret_char := 'H';
            when x"49" => ret_char := 'I';
            when x"4A" => ret_char := 'J';
            when x"4B" => ret_char := 'K';
            when x"4C" => ret_char := 'L';
            when x"4D" => ret_char := 'M';
            when x"4E" => ret_char := 'N';
            when x"4F" => ret_char := 'O';

            when x"50" => ret_char := 'P';
            when x"51" => ret_char := 'Q';
            when x"52" => ret_char := 'R';
            when x"53" => ret_char := 'S';
            when x"54" => ret_char := 'T';
            when x"55" => ret_char := 'U';
            when x"56" => ret_char := 'V';
            when x"57" => ret_char := 'W';
            when x"58" => ret_char := 'X';
            when x"59" => ret_char := 'Y';
            when x"5A" => ret_char := 'Z';
            when x"5B" => ret_char := '[';
            when x"5C" => ret_char := '\';
            when x"5D" => ret_char := ']';
            when x"5E" => ret_char := '^';
            when x"5F" => ret_char := '_';

            when x"60" => ret_char := '`';
            when x"61" => ret_char := 'a';
            when x"62" => ret_char := 'b';
            when x"63" => ret_char := 'c';
            when x"64" => ret_char := 'd';
            when x"65" => ret_char := 'e';
            when x"66" => ret_char := 'f';
            when x"67" => ret_char := 'g';
            when x"68" => ret_char := 'h';
            when x"69" => ret_char := 'i';
            when x"6A" => ret_char := 'j';
            when x"6B" => ret_char := 'k';
            when x"6C" => ret_char := 'l';
            when x"6D" => ret_char := 'm';
            when x"6E" => ret_char := 'n';
            when x"6F" => ret_char := 'o';

            when x"70" => ret_char := 'p';
            when x"71" => ret_char := 'q';
            when x"72" => ret_char := 'r';
            when x"73" => ret_char := 's';
            when x"74" => ret_char := 't';
            when x"75" => ret_char := 'u';
            when x"76" => ret_char := 'v';
            when x"77" => ret_char := 'w';
            when x"78" => ret_char := 'x';
            when x"79" => ret_char := 'y';
            when x"7A" => ret_char := 'z';
            when x"7B" => ret_char := '{';
            when x"7C" => ret_char := '|';
            when x"7D" => ret_char := '}';
            when x"7E" => ret_char := '~';

            when others => ret_char := '.';
        end case;

        return ret_char;
    end function fn_convert_slv_to_ascii;

    function fn_convert_hex_to_ascii(
        text_as_slv : std_logic_vector;
        text_char_cnt : natural)
    return string is
        alias buf_slv : std_logic_vector(text_as_slv'length - 1 downto 0) is text_as_slv;
        variable char_cnt : natural := 1;
        variable char_pos : natural := 0;
        variable char_str : string(1 to text_char_cnt);
    begin
        while (char_cnt <= text_char_cnt) loop
            char_pos := text_char_cnt - char_cnt;
            char_str(char_cnt) := fn_convert_slv_to_ascii(
                buf_slv(char_pos * 8 + 7 downto char_pos * 8)
            );
            char_cnt := char_cnt + 1;
        end loop;

        return char_str;
    end function fn_convert_hex_to_ascii;

    function fn_convert_hex_text_to_nibble(
        char_as_slv : std_logic_vector(7 downto 0))
    return std_logic_vector is
        variable ret_nibble : std_logic_vector(3 downto 0);
    begin
        case char_as_slv is
            when x"30" => ret_nibble := x"0";
            when x"31" => ret_nibble := x"1";
            when x"32" => ret_nibble := x"2";
            when x"33" => ret_nibble := x"3";
            when x"34" => ret_nibble := x"4";
            when x"35" => ret_nibble := x"5";
            when x"36" => ret_nibble := x"6";
            when x"37" => ret_nibble := x"7";
            when x"38" => ret_nibble := x"8";
            when x"39" => ret_nibble := x"9";

            when x"41" => ret_nibble := x"A";
            when x"42" => ret_nibble := x"B";
            when x"43" => ret_nibble := x"C";
            when x"44" => ret_nibble := x"D";
            when x"45" => ret_nibble := x"E";
            when x"46" => ret_nibble := x"F";

            when x"61" => ret_nibble := x"a";
            when x"62" => ret_nibble := x"b";
            when x"63" => ret_nibble := x"c";
            when x"64" => ret_nibble := x"d";
            when x"65" => ret_nibble := x"e";
            when x"66" => ret_nibble := x"f";

            when others => ret_nibble := "UUUU";
        end case;

        return ret_nibble;    
    end function fn_convert_hex_text_to_nibble;

    function fn_convert_hex_to_slv32(
        text_as_slv : std_logic_vector;
        slv_nibble_cnt : natural)
    return std_logic_vector is
        alias buf_slv : std_logic_vector(text_as_slv'length - 1 downto 0) is text_as_slv;
        variable nibble_pos : natural := 0;
        variable value_slv : std_logic_vector(3 downto 0);
        variable ret_cnt : natural := 0;
        variable ret_slv : std_logic_vector(slv_nibble_cnt * 4 - 1 downto 0) := (others => 'U');
    begin
        while ((ret_cnt < slv_nibble_cnt) and ((nibble_pos + 1) * 8 <= buf_slv'length)) loop
            value_slv := fn_convert_hex_text_to_nibble(
                buf_slv((buf_slv'length - 1 - (nibble_pos * 8)) downto (buf_slv'length - ((nibble_pos + 1) * 8)))
                );

            nibble_pos := nibble_pos + 1;

            if (value_slv /= "UUUU") then
                ret_slv((ret_slv'length - 1 - (4 * ret_cnt)) downto (ret_slv'length - (4 * (ret_cnt + 1)))) := value_slv;
                ret_cnt := ret_cnt + 1;
            end if;
        end loop;

        return ret_slv;
    end function fn_convert_hex_to_slv32;

end package body sf3_testbench_pkg;
--------------------------------------------------------------------------------
