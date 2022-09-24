/*------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2022 Timothy Stotts
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
-- \file sf_testing_to_ascii.sv
--
-- \brief A combinatorial block to convert SF3 Testing Status and State to
-- ASCII output for LCD and UART.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//Concurrent logic-------------------------------------------------------
//Part 1: Module header:--------------------------------------------------------
module sf_testing_to_ascii
    import lcd_text_functions_pkg::ascii_of_hdigit;
    import sf_tester_fsm_pkg::*;
    #(parameter
        logic [7:0] parm_pattern_startval_a,
        logic [7:0] parm_pattern_incrval_a,
        logic [7:0] parm_pattern_startval_b,
        logic [7:0] parm_pattern_incrval_b,
        logic [7:0] parm_pattern_startval_c,
        logic [7:0] parm_pattern_incrval_c,
        logic [7:0] parm_pattern_startval_d,
        logic [7:0] parm_pattern_incrval_d,
        integer parm_max_possible_byte_count
        )
    (
        // clock and reset inputs
        input logic i_clk_40mhz,
        input logic i_rst_40mhz,
        // state and status inputs
        input logic [31:0] i_addr_start,
        input logic [7:0] i_pattern_start,
        input logic [7:0] i_pattern_incr,
        input integer i_error_count,
        input t_tester_state i_tester_pr_state,
        // ASCII outputs
        output logic [16*8-1:0] o_lcd_ascii_line1,
        output logic [16*8-1:0] o_lcd_ascii_line2,
        output logic [35*8-1:0] o_term_ascii_line
    );

//Part 2: Declarations----------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

// Signals for text ASCII
logic [7:0] s_txt_ascii_pattern_1char;
logic [8*8-1:0] s_txt_ascii_address_8char;
logic [3*8-1:0] s_txt_ascii_sf3mode_3char;
logic [8*8-1:0] s_txt_ascii_errcntdec_8char;
logic [7:0] s_txt_ascii_errcntdec_char0;
logic [7:0] s_txt_ascii_errcntdec_char1;
logic [7:0] s_txt_ascii_errcntdec_char2;
logic [7:0] s_txt_ascii_errcntdec_char3;
logic [7:0] s_txt_ascii_errcntdec_char4;
logic [7:0] s_txt_ascii_errcntdec_char5;
logic [7:0] s_txt_ascii_errcntdec_char6;
logic [7:0] s_txt_ascii_errcntdec_char7;

// logic [3:0] s_sf3_err_count_divide7;
// logic [3:0] s_sf3_err_count_divide6;
// logic [3:0] s_sf3_err_count_divide5;
// logic [3:0] s_sf3_err_count_divide4;
// logic [3:0] s_sf3_err_count_divide3;
// logic [3:0] s_sf3_err_count_divide2;
// logic [3:0] s_sf3_err_count_divide1;
// logic [3:0] s_sf3_err_count_divide0;
logic [3:0] s_sf3_err_count_digit7;
logic [3:0] s_sf3_err_count_digit6;
logic [3:0] s_sf3_err_count_digit5;
logic [3:0] s_sf3_err_count_digit4;
logic [3:0] s_sf3_err_count_digit3;
logic [3:0] s_sf3_err_count_digit2;
logic [3:0] s_sf3_err_count_digit1;
logic [3:0] s_sf3_err_count_digit0;

// Signals of the final two lines of text
logic [16*8-1:0] s_txt_ascii_line1;
logic [16*8-1:0] s_txt_ascii_line2;

//Part 3: Statements------------------------------------------------------------

// Assembly of LCD 16x2 text lines

// The single character to display if the pattern matches A, B, C, or D.
assign s_txt_ascii_pattern_1char =
    ((i_pattern_start == parm_pattern_startval_a) && (i_pattern_incr == parm_pattern_incrval_a)) ? 8'h41 :
    ((i_pattern_start == parm_pattern_startval_b) && (i_pattern_incr == parm_pattern_incrval_b)) ? 8'h42 :
    ((i_pattern_start == parm_pattern_startval_c) && (i_pattern_incr == parm_pattern_incrval_c)) ? 8'h43 :
    ((i_pattern_start == parm_pattern_startval_d) && (i_pattern_incr == parm_pattern_incrval_d)) ? 8'h44 :
    8'h2A;

// The hexadecimal display value of the Test Starting Address on the text display
assign s_txt_ascii_address_8char = {
    ascii_of_hdigit(i_addr_start[31:28]),
    ascii_of_hdigit(i_addr_start[27:24]),
    ascii_of_hdigit(i_addr_start[23:20]),
    ascii_of_hdigit(i_addr_start[19:16]),
    ascii_of_hdigit(i_addr_start[15:12]),
    ascii_of_hdigit(i_addr_start[11:8]),
    ascii_of_hdigit(i_addr_start[7:4]),
    ascii_of_hdigit(i_addr_start[3:0])
};

// Assembly of Line1 of the LCD display
assign s_txt_ascii_line1 =
    {8'h53, 8'h46, 8'h33, 8'h20,
    8'h50, s_txt_ascii_pattern_1char, 8'h20, 8'h68,
    s_txt_ascii_address_8char};

// The operational mode of tester_pr_state is converted to a 3-character
// display value that indicates the current FSM state.
always_comb
begin : p_sf3mode_3char
    case (i_tester_pr_state)
        ST_WAIT_BUTTON0_REL, ST_SET_PATTERN_A,
        ST_WAIT_BUTTON1_REL, ST_SET_PATTERN_B,
        ST_WAIT_BUTTON2_REL, ST_SET_PATTERN_C,
        ST_WAIT_BUTTON3_REL, ST_SET_PATTERN_D,
        ST_SET_START_ADDR_A, ST_SET_START_WAIT_A,
        ST_SET_START_ADDR_B, ST_SET_START_WAIT_B,
        ST_SET_START_ADDR_C, ST_SET_START_WAIT_C,
        ST_SET_START_ADDR_D, ST_SET_START_WAIT_D: begin
            // text: "GO "
            s_txt_ascii_sf3mode_3char = {8'h47,8'h4F,8'h20};
        end

        ST_CMD_ERASE_START, ST_CMD_ERASE_WAIT,
        ST_CMD_ERASE_NEXT, ST_CMD_ERASE_DONE: begin
            // text: "ERS"
            s_txt_ascii_sf3mode_3char = {8'h45,8'h52,8'h53};
        end

        ST_CMD_PAGE_START, ST_CMD_PAGE_BYTE, ST_CMD_PAGE_WAIT,
        ST_CMD_PAGE_NEXT, ST_CMD_PAGE_DONE: begin
            // text: "PRO"
            s_txt_ascii_sf3mode_3char = {8'h50,8'h52,8'h4F};
        end

        ST_CMD_READ_START, ST_CMD_READ_BYTE, ST_CMD_READ_WAIT,
        ST_CMD_READ_NEXT, ST_CMD_READ_DONE: begin
            // text: "TST"
            s_txt_ascii_sf3mode_3char = {8'h54,8'h53,8'h54};
        end

        ST_DISPLAY_FINAL: begin
            // text: "END"
            s_txt_ascii_sf3mode_3char = {8'h45,8'h4E,8'h44};
        end

        default: begin // ST_WAIT_BUTTON_DEP
            // text: "GO "
            s_txt_ascii_sf3mode_3char = {8'h47,8'h4F,8'h20};
        end
    endcase
end : p_sf3mode_3char

// Registering the error count digits to close timing delays.
// This process converts the Error Count input into a 8-digit decimal ASCII
// number.
always_ff @(posedge i_clk_40mhz)
begin : p_reg_errcnt_digits
    s_sf3_err_count_digit7 <= i_error_count / 10000000 % 10;
    s_sf3_err_count_digit6 <= i_error_count / 1000000 % 10;
    s_sf3_err_count_digit5 <= i_error_count / 100000 % 10;
    s_sf3_err_count_digit4 <= i_error_count / 10000 % 10;
    s_sf3_err_count_digit3 <= i_error_count / 1000 % 10;
    s_sf3_err_count_digit2 <= i_error_count / 100 % 10;
    s_sf3_err_count_digit1 <= i_error_count / 10 % 10;
    s_sf3_err_count_digit0 <= i_error_count % 10;

    s_txt_ascii_errcntdec_char7 <= ascii_of_hdigit(s_sf3_err_count_digit7);
    s_txt_ascii_errcntdec_char6 <= ascii_of_hdigit(s_sf3_err_count_digit6);
    s_txt_ascii_errcntdec_char5 <= ascii_of_hdigit(s_sf3_err_count_digit5);
    s_txt_ascii_errcntdec_char4 <= ascii_of_hdigit(s_sf3_err_count_digit4);
    s_txt_ascii_errcntdec_char3 <= ascii_of_hdigit(s_sf3_err_count_digit3);
    s_txt_ascii_errcntdec_char2 <= ascii_of_hdigit(s_sf3_err_count_digit2);
    s_txt_ascii_errcntdec_char1 <= ascii_of_hdigit(s_sf3_err_count_digit1);
    s_txt_ascii_errcntdec_char0 <= ascii_of_hdigit(s_sf3_err_count_digit0);
end : p_reg_errcnt_digits

// Assembly of the 8-digit error count ASCII value
assign s_txt_ascii_errcntdec_8char = {
        s_txt_ascii_errcntdec_char7,
        s_txt_ascii_errcntdec_char6,
        s_txt_ascii_errcntdec_char5,
        s_txt_ascii_errcntdec_char4,
        s_txt_ascii_errcntdec_char3,
        s_txt_ascii_errcntdec_char2,
        s_txt_ascii_errcntdec_char1,
        s_txt_ascii_errcntdec_char0};

// Assembly of Line2 of the LCD display
assign s_txt_ascii_line2 = {
    s_txt_ascii_sf3mode_3char, 8'h20,
    8'h45, 8'h52, 8'h52, 8'h20, s_txt_ascii_errcntdec_8char};

// Assembly of UART text line and output
assign o_term_ascii_line = {s_txt_ascii_line1, 8'h20, s_txt_ascii_line2, 8'h0D, 8'h0A};

// Output of LCD text lines
assign o_lcd_ascii_line1 = s_txt_ascii_line1;
assign o_lcd_ascii_line2 = s_txt_ascii_line2;

endmodule : sf_testing_to_ascii
//------------------------------------------------------------------------------
`end_keywords
