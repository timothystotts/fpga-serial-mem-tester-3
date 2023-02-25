--------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2020,2023 Timothy Stotts
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
-- \file sf_testing_to_ascii.vhdl
--
-- \brief A combinatorial block to convert SF3 Testing Status and State to
-- ASCII output for LCD and UART.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.lcd_text_functions_pkg.ascii_of_hdigit;
use work.sf_tester_fsm_pkg.t_tester_state;
--------------------------------------------------------------------------------
entity sf_testing_to_ascii is
    generic(
        parm_pattern_startval_a      : unsigned(7 downto 0);
        parm_pattern_incrval_a       : unsigned(7 downto 0);
        parm_pattern_startval_b      : unsigned(7 downto 0);
        parm_pattern_incrval_b       : unsigned(7 downto 0);
        parm_pattern_startval_c      : unsigned(7 downto 0);
        parm_pattern_incrval_c       : unsigned(7 downto 0);
        parm_pattern_startval_d      : unsigned(7 downto 0);
        parm_pattern_incrval_d       : unsigned(7 downto 0);
        parm_max_possible_byte_count : natural
    );
    port(
        -- clock and reset inputs
        i_clk_40mhz : in std_logic;
        i_rst_40mhz : in std_logic;
        -- state and status inputs
        i_addr_start      : in std_logic_vector(31 downto 0);
        i_pattern_start   : in std_logic_vector(7 downto 0);
        i_pattern_incr    : in std_logic_vector(7 downto 0);
        i_error_count     : in natural range 0 to parm_max_possible_byte_count;
        i_tester_pr_state : in t_tester_state;
        -- ASCII outputs
        o_lcd_ascii_line1 : out std_logic_vector((16*8-1) downto 0);
        o_lcd_ascii_line2 : out std_logic_vector((16*8-1) downto 0);
        o_term_ascii_line : out std_logic_vector((35*8-1) downto 0)
    );
end entity sf_testing_to_ascii;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
architecture rtl of sf_testing_to_ascii is
    -- Signals for text ASCII
    signal s_txt_ascii_pattern_1char   : std_logic_vector(7 downto 0);
    signal s_txt_ascii_address_8char   : std_logic_vector((8*8-1) downto 0);
    signal s_txt_ascii_sf3mode_3char   : std_logic_vector((3*8-1) downto 0);
    signal s_txt_ascii_errcntdec_8char : std_logic_vector(8*8-1 downto 0);
    signal s_txt_ascii_errcntdec_char0 : std_logic_vector(7 downto 0);
    signal s_txt_ascii_errcntdec_char1 : std_logic_vector(7 downto 0);
    signal s_txt_ascii_errcntdec_char2 : std_logic_vector(7 downto 0);
    signal s_txt_ascii_errcntdec_char3 : std_logic_vector(7 downto 0);
    signal s_txt_ascii_errcntdec_char4 : std_logic_vector(7 downto 0);
    signal s_txt_ascii_errcntdec_char5 : std_logic_vector(7 downto 0);
    signal s_txt_ascii_errcntdec_char6 : std_logic_vector(7 downto 0);
    signal s_txt_ascii_errcntdec_char7 : std_logic_vector(7 downto 0);

    signal s_sf3_err_count_divide7 : natural range 0 to 9;
    signal s_sf3_err_count_divide6 : natural range 0 to 9;
    signal s_sf3_err_count_divide5 : natural range 0 to 9;
    signal s_sf3_err_count_divide4 : natural range 0 to 9;
    signal s_sf3_err_count_divide3 : natural range 0 to 9;
    signal s_sf3_err_count_divide2 : natural range 0 to 9;
    signal s_sf3_err_count_divide1 : natural range 0 to 9;
    signal s_sf3_err_count_divide0 : natural range 0 to 9;
    signal s_sf3_err_count_digit7  : std_logic_vector(3 downto 0);
    signal s_sf3_err_count_digit6  : std_logic_vector(3 downto 0);
    signal s_sf3_err_count_digit5  : std_logic_vector(3 downto 0);
    signal s_sf3_err_count_digit4  : std_logic_vector(3 downto 0);
    signal s_sf3_err_count_digit3  : std_logic_vector(3 downto 0);
    signal s_sf3_err_count_digit2  : std_logic_vector(3 downto 0);
    signal s_sf3_err_count_digit1  : std_logic_vector(3 downto 0);
    signal s_sf3_err_count_digit0  : std_logic_vector(3 downto 0);

    -- Signals of the final two lines of text
    signal s_txt_ascii_line1 : std_logic_vector((16*8-1) downto 0);
    signal s_txt_ascii_line2 : std_logic_vector((16*8-1) downto 0);
begin
    -- This architecture: Assembly of LCD 16x2 text lines

    -- The single character to display if the pattern matches A, B, C, or D.
    s_txt_ascii_pattern_1char <=
        x"41" when ((unsigned(i_pattern_start) = parm_pattern_startval_a) and (unsigned(i_pattern_incr) = parm_pattern_incrval_a)) else
        x"42" when ((unsigned(i_pattern_start) = parm_pattern_startval_b) and (unsigned(i_pattern_incr) = parm_pattern_incrval_b)) else
        x"43" when ((unsigned(i_pattern_start) = parm_pattern_startval_c) and (unsigned(i_pattern_incr) = parm_pattern_incrval_c)) else
        x"44" when ((unsigned(i_pattern_start) = parm_pattern_startval_d) and (unsigned(i_pattern_incr) = parm_pattern_incrval_d)) else
        x"2A";

    -- The hexadecimal display value of the Test Starting Address on the text display
    s_txt_ascii_address_8char <=
        ascii_of_hdigit(i_addr_start(31 downto 28)) &
        ascii_of_hdigit(i_addr_start(27 downto 24)) &
        ascii_of_hdigit(i_addr_start(23 downto 20)) &
        ascii_of_hdigit(i_addr_start(19 downto 16)) &
        ascii_of_hdigit(i_addr_start(15 downto 12)) &
        ascii_of_hdigit(i_addr_start(11 downto 8)) &
        ascii_of_hdigit(i_addr_start(7 downto 4)) &
        ascii_of_hdigit(i_addr_start(3 downto 0));

    -- Assembly of Line1 of the LCD display
    s_txt_ascii_line1 <= (x"53" & x"46" & x"33" & x"20" &
            x"50" & s_txt_ascii_pattern_1char & x"20" & x"68" &
            s_txt_ascii_address_8char);

    -- The operational mode of tester_pr_state is converted to a 3-character
    -- display value that indicates the current FSM state.
    p_sf3mode_3char : process (i_tester_pr_state)
    begin
        case(i_tester_pr_state) is
            when ST_WAIT_BUTTON0_REL | ST_SET_PATTERN_A
                | ST_WAIT_BUTTON1_REL | ST_SET_PATTERN_B
                | ST_WAIT_BUTTON2_REL | ST_SET_PATTERN_C
                | ST_WAIT_BUTTON3_REL | ST_SET_PATTERN_D
                | ST_SET_START_ADDR_A | ST_SET_START_WAIT_A
                | ST_SET_START_ADDR_B | ST_SET_START_WAIT_B
                | ST_SET_START_ADDR_C | ST_SET_START_WAIT_C
                | ST_SET_START_ADDR_D | ST_SET_START_WAIT_D =>
                -- text: "GO "
                s_txt_ascii_sf3mode_3char <= (x"47" & x"4F" & x"20");
            when ST_CMD_ERASE_START | ST_CMD_ERASE_WAIT |
                ST_CMD_ERASE_NEXT | ST_CMD_ERASE_DONE =>
                -- text: "ERS"
                s_txt_ascii_sf3mode_3char <= (x"45" & x"52" & x"53");
            when ST_CMD_PAGE_START | ST_CMD_PAGE_BYTE | ST_CMD_PAGE_WAIT |
                ST_CMD_PAGE_NEXT | ST_CMD_PAGE_DONE =>
                -- text: "PRO"
                s_txt_ascii_sf3mode_3char <= (x"50" & x"52" & x"4F");
            when ST_CMD_READ_START | ST_CMD_READ_BYTE | ST_CMD_READ_WAIT |
                ST_CMD_READ_NEXT | ST_CMD_READ_DONE =>
                -- text: "TST"
                s_txt_ascii_sf3mode_3char <= (x"54" & x"53" & x"54");
            when ST_DISPLAY_FINAL =>
                -- text: "END"
                s_txt_ascii_sf3mode_3char <= (x"45" & x"4E" & x"44");
            when others => -- ST_WAIT_BUTTON_DEP =>
                           -- text: "GO ""
                s_txt_ascii_sf3mode_3char <= (x"47" & x"4F" & x"20");
        end case;
    end process p_sf3mode_3char;

    -- Registering the error count digits to close timing delays.
    -- This process converts the Error Count input into a 8-digit decimal ASCII
    -- number.
    s_sf3_err_count_divide7 <= i_error_count / 10000000 mod 10;
    s_sf3_err_count_divide6 <= i_error_count / 1000000 mod 10;
    s_sf3_err_count_divide5 <= i_error_count / 100000 mod 10;
    s_sf3_err_count_divide4 <= i_error_count / 10000 mod 10;
    s_sf3_err_count_divide3 <= i_error_count / 1000 mod 10;
    s_sf3_err_count_divide2 <= i_error_count / 100 mod 10;
    s_sf3_err_count_divide1 <= i_error_count / 10 mod 10;
    s_sf3_err_count_divide0 <= i_error_count mod 10;

    p_reg_errcnt_digits : process(i_clk_40mhz)
    begin
        if rising_edge(i_clk_40mhz) then
            s_txt_ascii_errcntdec_char7 <= ascii_of_hdigit(s_sf3_err_count_digit7);
            s_txt_ascii_errcntdec_char6 <= ascii_of_hdigit(s_sf3_err_count_digit6);
            s_txt_ascii_errcntdec_char5 <= ascii_of_hdigit(s_sf3_err_count_digit5);
            s_txt_ascii_errcntdec_char4 <= ascii_of_hdigit(s_sf3_err_count_digit4);
            s_txt_ascii_errcntdec_char3 <= ascii_of_hdigit(s_sf3_err_count_digit3);
            s_txt_ascii_errcntdec_char2 <= ascii_of_hdigit(s_sf3_err_count_digit2);
            s_txt_ascii_errcntdec_char1 <= ascii_of_hdigit(s_sf3_err_count_digit1);
            s_txt_ascii_errcntdec_char0 <= ascii_of_hdigit(s_sf3_err_count_digit0);

            s_sf3_err_count_digit7  <= std_logic_vector(to_unsigned(s_sf3_err_count_divide7, 4));
            s_sf3_err_count_digit6  <= std_logic_vector(to_unsigned(s_sf3_err_count_divide6, 4));
            s_sf3_err_count_digit5  <= std_logic_vector(to_unsigned(s_sf3_err_count_divide5, 4));
            s_sf3_err_count_digit4  <= std_logic_vector(to_unsigned(s_sf3_err_count_divide4, 4));
            s_sf3_err_count_digit3  <= std_logic_vector(to_unsigned(s_sf3_err_count_divide3, 4));
            s_sf3_err_count_digit2  <= std_logic_vector(to_unsigned(s_sf3_err_count_divide2, 4));
            s_sf3_err_count_digit1  <= std_logic_vector(to_unsigned(s_sf3_err_count_divide1, 4));
            s_sf3_err_count_digit0  <= std_logic_vector(to_unsigned(s_sf3_err_count_divide0, 4));
        end if;
    end process p_reg_errcnt_digits;

    -- Assembly of the 8-digit error count ASCII value
    s_txt_ascii_errcntdec_8char <=
        s_txt_ascii_errcntdec_char7 &
        s_txt_ascii_errcntdec_char6 &
        s_txt_ascii_errcntdec_char5 &
        s_txt_ascii_errcntdec_char4 &
        s_txt_ascii_errcntdec_char3 &
        s_txt_ascii_errcntdec_char2 &
        s_txt_ascii_errcntdec_char1 &
        s_txt_ascii_errcntdec_char0;

    -- Assembly of Line2 of the LCD display
    s_txt_ascii_line2 <= (s_txt_ascii_sf3mode_3char & x"20" &
            x"45" & x"52" & x"52" & x"20" & s_txt_ascii_errcntdec_8char);

    -- Assembly of UART text line and output
    o_term_ascii_line <= (s_txt_ascii_line1 & std_logic_vector'(x"20") & s_txt_ascii_line2 & std_logic_vector'(x"0D") & std_logic_vector'(x"0A"));

    -- Output of LCD text lines
    o_lcd_ascii_line1 <= s_txt_ascii_line1;
    o_lcd_ascii_line2 <= s_txt_ascii_line2;

end architecture rtl;
--------------------------------------------------------------------------------
