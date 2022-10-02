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
-- \file sf_tester_fsm.sv
--
-- \brief A FSM to control the testing operation of the SF Tester Design.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//Recursive Moore Machine-------------------------------------------------------
//Part 1: Module header:--------------------------------------------------------
module sf_tester_fsm
    import sf_tester_fsm_pkg::*;
    #(parameter
        // define as non-zero for a fast simulation that is faster than
        // synthesis timing for the purpose of displaying SPI bus with a visual
        // testbench.
        integer parm_fast_simulation = 0,
        // Frequency of the clock
        integer parm_FCLK = 40000000,
        // Ratio of the clock enable to the clock
        integer parm_sf3_tester_ce_div_ratio = 2,
        // Patterns A, B, C, D
        logic [7:0] parm_pattern_startval_a,
        logic [7:0] parm_pattern_incrval_a,
        logic [7:0] parm_pattern_startval_b,
        logic [7:0] parm_pattern_incrval_b,
        logic [7:0] parm_pattern_startval_c,
        logic [7:0] parm_pattern_incrval_c,
        logic [7:0] parm_pattern_startval_d,
        logic [7:0] parm_pattern_incrval_d,
        // Maximum byte count of the memory being operated
        integer parm_max_possible_byte_count,
        integer parm_tester_page_cnt_per_iter
        )
    (
        // clock and reset
        input logic i_clk_40mhz,
        input logic i_rst_40mhz,
        input logic i_ce_div,
        // interface to Pmod SF3 Custom Driver
        input logic i_sf3_command_ready,
        input logic i_sf3_rd_data_valid,
        input logic [7:0] i_sf3_rd_data_stream,
        input logic i_sf3_wr_data_ready,
        output logic [7:0] o_sf3_wr_data_stream,
        output logic o_sf3_wr_data_valid,
        output logic [8:0] o_sf3_len_random_read,
        output logic o_sf3_cmd_random_read,
        output logic o_sf3_cmd_page_program,
        output logic o_sf3_cmd_erase_subsector,
        output logic [31:0] o_sf3_address_of_cmd,
        // interface to user I/O
        input logic [3:0] i_buttons_debounced,
        input logic [3:0] i_switches_debounced,
        // state and status outputs
        output t_tester_state o_tester_pr_state,
        output logic [31:0] o_addr_start,
        output logic [7:0] o_pattern_start,
        output logic [7:0] o_pattern_incr,
        output logic [$clog2(parm_max_possible_byte_count)-1:0] o_error_count,
        output logic o_test_pass,
        output logic o_test_done
    );

//Part 2: Declarations----------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

// Maximum count is three seconds c_FCLK / c_sf3_tester_ce_div_ratio * 3 - 1;
localparam integer c_t_max = fn_set_t_max(parm_FCLK, parm_sf3_tester_ce_div_ratio, parm_fast_simulation);

// Timer variable
logic [$clog2(c_t_max)-1:0] s_t;

// Tester state value
t_tester_state s_tester_pr_state;
t_tester_state s_tester_nx_state;

// Tester auxiliary registers
logic [7:0] s_dat_wr_cntidx_val;
logic [7:0] s_dat_wr_cntidx_aux;
logic [7:0] s_dat_rd_cntidx_val;
logic [7:0] s_dat_rd_cntidx_aux;
logic s_test_pass_val;
logic s_test_pass_aux;
logic s_test_done_val;
logic s_test_done_aux;
logic [$clog2(parm_max_possible_byte_count)-1:0] s_err_count_val;
logic [$clog2(parm_max_possible_byte_count)-1:0] s_err_count_aux;
logic [7:0] s_pattern_start_val;
logic [7:0] s_pattern_start_aux;
logic [7:0] s_pattern_incr_val;
logic [7:0] s_pattern_incrval_aux;
logic [7:0] s_pattern_track_val;
logic [7:0] s_pattern_track_aux;
logic [31:0] s_addr_start_val;
logic [31:0] s_addr_start_aux;
logic s_start_at_zero_val;
logic s_start_at_zero_aux;
logic [$clog2(parm_tester_page_cnt_per_iter)-1:0] s_i_val;
logic [$clog2(parm_tester_page_cnt_per_iter)-1:0] s_i_aux;

//Part 3: Statements------------------------------------------------------------
// Outputs for other modules to read
assign o_tester_pr_state = s_tester_pr_state;
assign o_addr_start      = s_addr_start_aux;
assign o_pattern_start   = s_pattern_start_aux;
assign o_pattern_incr    = s_pattern_incrval_aux;
assign o_error_count     = s_err_count_aux;
assign o_test_pass       = s_test_pass_aux;
assign o_test_done       = s_test_done_aux;

// Timer strategy #1 for the serial flash tester FSM
always_ff @(posedge i_clk_40mhz)
begin : p_tester_timer
    if (i_rst_40mhz)
        s_t <= 0;
    else if (i_ce_div) begin
        if (s_tester_pr_state != s_tester_nx_state)
            s_t <= 0;
        else if (s_t < c_t_max)
            s_t <= s_t + 1;
    end
end : p_tester_timer

// State and auxiliary registers for the serial flash tester FSM
always_ff @(posedge  i_clk_40mhz)
begin : p_tester_fsm_state
    if (i_rst_40mhz) begin
        s_tester_pr_state <= ST_WAIT_BUTTON_DEP;

        s_dat_wr_cntidx_aux   <= 0;
        s_dat_rd_cntidx_aux   <= 0;
        s_test_pass_aux       <= 1'b0;
        s_test_done_aux       <= 1'b0;
        s_err_count_aux       <= 0;
        s_pattern_start_aux   <= parm_pattern_startval_a;
        s_pattern_incrval_aux <= parm_pattern_incrval_a;
        s_pattern_track_aux   <= 8'h00;
        s_addr_start_aux      <= 32'h00000000;
        s_start_at_zero_aux   <= 1'b1;
        s_i_aux               <= 0;

    end else if (i_ce_div) begin
        s_tester_pr_state <= s_tester_nx_state;

        s_dat_wr_cntidx_aux   <= s_dat_wr_cntidx_val;
        s_dat_rd_cntidx_aux   <= s_dat_rd_cntidx_val;
        s_test_pass_aux       <= s_test_pass_val;
        s_test_done_aux       <= s_test_done_val;
        s_err_count_aux       <= s_err_count_val;
        s_pattern_start_aux   <= s_pattern_start_val;
        s_pattern_incrval_aux <= s_pattern_incr_val;
        s_pattern_track_aux   <= s_pattern_track_val;
        s_addr_start_aux      <= s_addr_start_val;
        s_start_at_zero_aux   <= s_start_at_zero_val;
        s_i_aux               <= s_i_val;
    end
end : p_tester_fsm_state

// Combinatorial logic for the serial flash tester FSM
always_comb
begin : p_tester_fsm_comb
    // Default auxiliary register no-change values for briefer code
    s_dat_wr_cntidx_val = s_dat_wr_cntidx_aux;
    s_dat_rd_cntidx_val = s_dat_rd_cntidx_aux;
    s_test_pass_val     = s_test_pass_aux;
    s_test_done_val     = s_test_done_aux;
    s_err_count_val     = s_err_count_aux;
    s_pattern_start_val = s_pattern_start_aux;
    s_pattern_incr_val  = s_pattern_incrval_aux;
    s_pattern_track_val = s_pattern_track_aux;
    s_addr_start_val    = s_addr_start_aux;
    s_start_at_zero_val = s_start_at_zero_aux;
    s_i_val             = s_i_aux;

    // Default data writing values as zero and not writing
    o_sf3_wr_data_stream = 8'h00;
    o_sf3_wr_data_valid  = 1'b0;

    case (s_tester_pr_state)
        ST_WAIT_BUTTON_DEP: begin
            // Wait for a button depress or a switch position before
            // performing the next test iteration
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 32'h00000000;

            s_test_done_val = (s_addr_start_aux < c_last_starting_byte_addr) ? 1'b0 : 1'b1;

            if (s_addr_start_aux < c_last_starting_byte_addr) begin
                if ((i_buttons_debounced == 4'b0001) || (i_switches_debounced == 4'b0001))
                    s_tester_nx_state = ST_WAIT_BUTTON0_REL;
                else if ((i_buttons_debounced == 4'b0010) || (i_switches_debounced == 4'b0010))
                    s_tester_nx_state = ST_WAIT_BUTTON1_REL;
                else if ((i_buttons_debounced == 4'b0100) || (i_switches_debounced == 4'b0100))
                    s_tester_nx_state = ST_WAIT_BUTTON2_REL;
                else if ((i_buttons_debounced == 4'b1000) || (i_switches_debounced == 4'b1000))
                    s_tester_nx_state = ST_WAIT_BUTTON3_REL;
                else
                    s_tester_nx_state = ST_WAIT_BUTTON_DEP;
            end else begin
                s_tester_nx_state = ST_WAIT_BUTTON_DEP;
            end
        end

        ST_WAIT_BUTTON0_REL: begin
            // Button 0 or Switch 0 was selected.
            // Choose the pattern as A and transition when no buttons are
            // depressed.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;

            if (i_buttons_debounced == 4'b0000)
                s_tester_nx_state = ST_SET_PATTERN_A;
            else
                s_tester_nx_state = ST_WAIT_BUTTON0_REL;
        end

        ST_WAIT_BUTTON1_REL: begin
            // Button 1 or Switch 1 was selected.
            // Choose the pattern as B and transition when no buttons are
            // depressed.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;

            if (i_buttons_debounced == 4'b0000)
                s_tester_nx_state = ST_SET_PATTERN_B;
            else
                s_tester_nx_state = ST_WAIT_BUTTON1_REL;
        end

        ST_WAIT_BUTTON2_REL: begin
            // Button 2 or Switch 2 was selected.
            // Choose the pattern as C and transition when no buttons are
            // depressed.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;

            if (i_buttons_debounced == 4'b0000)
                s_tester_nx_state = ST_SET_PATTERN_C;
            else
                s_tester_nx_state = ST_WAIT_BUTTON2_REL;
        end

        ST_WAIT_BUTTON3_REL: begin
            // Button 3 or Switch 3 was selected.
            // Choose the pattern as D and transition when no buttons are
            // depressed.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;

            if (i_buttons_debounced == 4'b0000)
                s_tester_nx_state = ST_SET_PATTERN_D;
            else
                s_tester_nx_state = ST_WAIT_BUTTON3_REL;
        end

        ST_SET_PATTERN_A: begin
            // Set the Pattern as A and transition when the SF3 driver is
            // ready for a command.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;

            s_pattern_start_val = parm_pattern_startval_a;
            s_pattern_incr_val  = parm_pattern_incrval_a;

            if (i_sf3_command_ready)
                s_tester_nx_state = ST_SET_START_ADDR_A;
            else
                s_tester_nx_state = ST_SET_PATTERN_A;
        end

        ST_SET_PATTERN_B: begin
            // Set the Pattern as A and transition when the SF3 driver is
            // ready for a command.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;

            s_pattern_start_val = parm_pattern_startval_b;
            s_pattern_incr_val  = parm_pattern_incrval_b;

            if (i_sf3_command_ready)
                s_tester_nx_state = ST_SET_START_ADDR_B;
            else
                s_tester_nx_state = ST_SET_PATTERN_B;
        end

        ST_SET_PATTERN_C: begin
            // Set the Pattern as C and transition when the SF3 driver is
            // ready for a command.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;

            s_pattern_start_val = parm_pattern_startval_c;
            s_pattern_incr_val  = parm_pattern_incrval_c;

            if (i_sf3_command_ready)
                s_tester_nx_state = ST_SET_START_ADDR_C;
            else
                s_tester_nx_state = ST_SET_PATTERN_C;
        end

        ST_SET_PATTERN_D: begin
            // Set the Pattern as D and transition when the SF3 driver is
            // ready for a command.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;

            s_pattern_start_val = parm_pattern_startval_d;
            s_pattern_incr_val  = parm_pattern_incrval_d;

            if (i_sf3_command_ready)
                s_tester_nx_state = ST_SET_START_ADDR_D;
            else
                s_tester_nx_state = ST_SET_PATTERN_D;
        end

        ST_SET_START_ADDR_A: begin
            // If not first iteration of erase/program/test-read cycle,
            // increment the starting address and then transition to a
            // wait state.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;
            s_start_at_zero_val       = 1'b0;
            s_i_val                   = 0;

            // Increment the address for the next iteration
            if (s_start_at_zero_aux) begin
                s_addr_start_val  = 8'h00000000;
                s_test_done_val   = 1'b0;
                s_tester_nx_state = ST_SET_START_WAIT_A;
            end else if (s_addr_start_aux < c_last_starting_byte_addr) begin
                s_addr_start_val  = s_addr_start_aux + c_per_iteration_byte_count;
                s_test_done_val   = 1'b0;
                s_tester_nx_state = ST_SET_START_WAIT_A;
            end else begin
                s_test_done_val   = 1'b1;
                s_tester_nx_state = ST_WAIT_BUTTON_DEP;
            end
        end

        ST_SET_START_ADDR_B: begin
            // If not first iteration of erase/program/test-read cycle,
            // increment the starting address and then transition to a
            // wait state.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;
            s_start_at_zero_val       = 1'b0;
            s_i_val                   = 0;

            // Increment the address for the next iteration
            if (s_start_at_zero_aux) begin
                s_addr_start_val  = 8'h00000000;
                s_test_done_val   = 1'b0;
                s_tester_nx_state = ST_SET_START_WAIT_B;
            end else if (s_addr_start_aux < c_last_starting_byte_addr) begin
                s_addr_start_val  = s_addr_start_aux + c_per_iteration_byte_count;
                s_test_done_val   = 1'b0;
                s_tester_nx_state = ST_SET_START_WAIT_B;
            end else begin
                s_test_done_val   = 1'b1;
                s_tester_nx_state = ST_WAIT_BUTTON_DEP;
            end
        end

        ST_SET_START_ADDR_C: begin
            // If not first iteration of erase/program/test-read cycle,
            // increment the starting address and then transition to a
            // wait state.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;
            s_start_at_zero_val       = 1'b0;
            s_i_val                   = 0;

            // Increment the address for the next iteration
            if (s_start_at_zero_aux) begin
                s_addr_start_val  = 8'h00000000;
                s_test_done_val   = 1'b0;
                s_tester_nx_state = ST_SET_START_WAIT_C;
            end else if (s_addr_start_aux < c_last_starting_byte_addr) begin
                s_addr_start_val  = s_addr_start_aux + c_per_iteration_byte_count;
                s_test_done_val   = 1'b0;
                s_tester_nx_state = ST_SET_START_WAIT_C;
            end else begin
                s_test_done_val   = 1'b1;
                s_tester_nx_state = ST_WAIT_BUTTON_DEP;
            end
        end

        ST_SET_START_ADDR_D: begin
            // If not first iteration of erase/program/test-read cycle,
            // increment the starting address and then transition to a
            // wait state.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;
            s_start_at_zero_val       = 1'b0;
            s_i_val                   = 0;

            // Increment the address for the next iteration
            if (s_start_at_zero_aux) begin
                s_addr_start_val  = 8'h00000000;
                s_test_done_val   = 1'b0;
                s_tester_nx_state = ST_SET_START_WAIT_D;
            end else if (s_addr_start_aux < c_last_starting_byte_addr) begin
                s_addr_start_val  = s_addr_start_aux + c_per_iteration_byte_count;
                s_test_done_val   = 1'b0;
                s_tester_nx_state = ST_SET_START_WAIT_D;
            end else begin
                s_test_done_val   = 1'b1;
                s_tester_nx_state = ST_WAIT_BUTTON_DEP;
            end
        end

        ST_SET_START_WAIT_A: begin
            // Wait for half of the 3 second timer and transition to the
            // Erase command. Pause in this state for purpose of lighting
            // LED to indicate pattern A is starting.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;

            if (s_t == c_t_max / 2)
                s_tester_nx_state = ST_CMD_ERASE_START;
            else
                s_tester_nx_state = ST_SET_START_WAIT_A;
        end

        ST_SET_START_WAIT_B: begin
            // Wait for half of the 3 second timer and transition to the
            // Erase command. Pause in this state for purpose of lighting
            // LED to indicate pattern B is starting.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;

            if (s_t == c_t_max / 2)
                s_tester_nx_state = ST_CMD_ERASE_START;
            else
                s_tester_nx_state = ST_SET_START_WAIT_B;
        end

        ST_SET_START_WAIT_C: begin
            // Wait for half of the 3 second timer and transition to the
            // Erase command. Pause in this state for purpose of lighting
            // LED to indicate pattern C is starting.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;

            if (s_t == c_t_max / 2)
                s_tester_nx_state = ST_CMD_ERASE_START;
            else
                s_tester_nx_state = ST_SET_START_WAIT_C;
        end

        ST_SET_START_WAIT_D: begin
            // Wait for half of the 3 second timer and transition to the
            // Erase command. Pause in this state for purpose of lighting
            // LED to indicate pattern D is starting.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 8'h00000000;

            if (s_t == c_t_max / 2)
                s_tester_nx_state = ST_CMD_ERASE_START;
            else
                s_tester_nx_state = ST_SET_START_WAIT_D;
        end

        ST_CMD_ERASE_START: begin
            // Issue an Erase Subsector Command at the starting address
            // of this iteration. Wait to transition when the SF3 driver
            // indicates command not ready.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b1;
            o_sf3_address_of_cmd      = 
                s_addr_start_aux + (s_i_aux * c_sf3_subsector_addr_incr);

            if (! i_sf3_command_ready)
                s_tester_nx_state = ST_CMD_ERASE_WAIT;
            else
                s_tester_nx_state = ST_CMD_ERASE_START;
        end

        ST_CMD_ERASE_WAIT: begin
            // Wait for the Erase Command to end and the SF3 driver to
            // indicate command ready again. Then transition to incrementing
            // the next Subsector Address to erase.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      =
                    s_addr_start_aux + (s_i_aux * c_sf3_subsector_addr_incr);

            if (i_sf3_command_ready)
                s_tester_nx_state = ST_CMD_ERASE_NEXT;
            else
                s_tester_nx_state = ST_CMD_ERASE_WAIT;
        end

        ST_CMD_ERASE_NEXT: begin
            // If auxiliary register I has counted to the number of
            // Subsectors after the starting address, transition to the
            // Erase Done state, otherwise increment I and transition again
            // to the Erase Start state.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 32'h00000000;
            s_i_val                   = s_i_aux + 1;

            if (s_i_aux < (c_tester_subsector_cnt_per_iter - 1))
                s_tester_nx_state = ST_CMD_ERASE_START;
            else
                s_tester_nx_state = ST_CMD_ERASE_DONE;
        end

        ST_CMD_ERASE_DONE: begin
            // Erase iterations have completed. Reset the starting value
            // of the pattern in preparation of programming the pages of
            // all Subsectors erased.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 32'h00000000;
            s_i_val                   = 0;
            s_pattern_track_val       = s_pattern_start_aux;

            if (s_t == c_t_max) // allow a few seconds of idle for easier SPY capture of the Erase command
                s_tester_nx_state = ST_CMD_PAGE_START;
            else
                s_tester_nx_state = ST_CMD_ERASE_DONE;
        end

        ST_CMD_PAGE_START: begin
            // Issue an Program Page Command at the starting address
            // of this iteration. Wait to transition when the SF3 driver
            // indicates command not ready.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      =
                s_addr_start_aux + (s_i_aux * c_sf3_page_addr_incr);
            s_dat_wr_cntidx_val       = 0;

            if (! i_sf3_command_ready)
                s_tester_nx_state = ST_CMD_PAGE_BYTE;
            else
                s_tester_nx_state = ST_CMD_PAGE_START;
        end

        ST_CMD_PAGE_BYTE: begin
            // Increment according to the selected pattern and stream a
            // total of Page size bytes (256) unique values to the FIFO of
            // the SF3 driver for writing to the currently addressed page.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      =
                s_addr_start_aux + (s_i_aux * c_sf3_page_addr_incr);

            if (i_sf3_wr_data_ready) begin
                // Assign this iterations byte value
                o_sf3_wr_data_stream = s_pattern_track_aux;
                o_sf3_wr_data_valid  = 1'b1;

                // Calculate the next iterations byte value
                s_pattern_track_val = 
                    s_pattern_track_aux + s_pattern_incrval_aux;

                // Increment counter for next byte
                if (s_dat_wr_cntidx_aux < 255)
                    s_dat_wr_cntidx_val = s_dat_wr_cntidx_aux + 1;

                // Check current bytes counter for next FSM state
                if (s_dat_wr_cntidx_aux == 255)
                    // Wrote bytes 0 through 255, totaling at a page lenth
                    // of 256 bytes. Now advance to the WAIT state.
                    s_tester_nx_state = ST_CMD_PAGE_WAIT;
                else
                    s_tester_nx_state = ST_CMD_PAGE_BYTE;
            end else begin
                o_sf3_wr_data_stream = 8'h00;
                o_sf3_wr_data_valid  = 1'b0;
                s_tester_nx_state    = ST_CMD_PAGE_BYTE;
            end
        end

        ST_CMD_PAGE_WAIT: begin
            // Wait for the Page Program Command to end and the SF3 driver to
            // indicate command ready again. Then transition to incrementing
            // the next Page Address to program.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      =
                s_addr_start_aux + (s_i_aux * c_sf3_page_addr_incr);

            if (i_sf3_command_ready)
                s_tester_nx_state = ST_CMD_PAGE_NEXT;
            else
                s_tester_nx_state = ST_CMD_PAGE_WAIT;
        end

        ST_CMD_PAGE_NEXT: begin
            // If auxiliary register I has counted to the number of
            // Pages after the starting address, transition to the
            // Page Done state, otherwise increment I and transition again
            // to the Page Start state.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 32'h00000000;
            s_i_val                   = s_i_aux + 1;

            if (s_i_aux < (c_tester_page_cnt_per_iter - 1))
                s_tester_nx_state = ST_CMD_PAGE_START;
            else
                s_tester_nx_state = ST_CMD_PAGE_DONE;
        end

        ST_CMD_PAGE_DONE: begin
            // Page Program iterations have completed. Reset the starting value
            // of the pattern in preparation of reading the pages of
            // all Subsectors erased and programmed.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 32'h00000000;
            s_i_val                   = 0;
            s_pattern_track_val       = s_pattern_start_aux;

            if (s_t == c_t_max) // allow a few seconds of idle for easier SPY capture of the Page command
                s_tester_nx_state = ST_CMD_READ_START;
            else
                s_tester_nx_state = ST_CMD_PAGE_DONE;
        end

        ST_CMD_READ_START: begin
            // Issue an Random Read Command at the starting address
            // of this iteration. Wait to transition when the SF3 driver
            // indicates command not ready.
            o_sf3_len_random_read     = c_sf3_page_addr_incr;
            o_sf3_cmd_random_read     = 1'b1;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      =
                s_addr_start_aux + (s_i_aux * c_sf3_page_addr_incr);
            s_dat_rd_cntidx_val       = 0;

            if (! i_sf3_command_ready)
                s_tester_nx_state = ST_CMD_READ_BYTE;
            else
                s_tester_nx_state = ST_CMD_READ_START;
        end

        ST_CMD_READ_BYTE: begin
            // Increment according to the selected pattern and stream a
            // total of Page size bytes (256) unique values from the FIFO of
            // the SF3 driver for checking of the currently addressed page
            // byte read. Compare the value of the incrementing pattern with
            // the value of the byte read. If they do not match, increment
            // the error count auxiliary register.
            o_sf3_len_random_read     = c_sf3_page_addr_incr;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      =
                s_addr_start_aux + (s_i_aux * c_sf3_page_addr_incr);

            if (i_sf3_rd_data_valid) begin
                // Compare this iterations byte value
                if (i_sf3_rd_data_stream != s_pattern_track_aux)
                    s_err_count_val = s_err_count_aux + 1;
                else
                    // FIXME: this is to show errors that did not occur to test the error reporting on the LCD and USB=UART
                    s_err_count_val = s_err_count_aux + 0;

                // Calculate the next iterations byte value
                s_pattern_track_val = s_pattern_track_aux + s_pattern_incrval_aux;

                // Increment counter for next byte
                if (s_dat_rd_cntidx_aux < 255)
                    s_dat_rd_cntidx_val = s_dat_rd_cntidx_aux + 1;

                // Check current bytes counter for next FSM state
                if (s_dat_rd_cntidx_aux == 255)
                    // Wrote bytes 0 through 255, totaling at a page lenth
                    // of 256 bytes. Now advance to the WAIT state.
                    s_tester_nx_state = ST_CMD_READ_WAIT;
                else
                    s_tester_nx_state = ST_CMD_READ_BYTE;
            end else begin
                s_tester_nx_state = ST_CMD_READ_BYTE;
            end
        end

        ST_CMD_READ_WAIT: begin
            // Wait for the Random Read Command to end and the SF3 driver to
            // indicate command ready again. Then transition to incrementing
            // the next Page Address to random read and test with pattern
            // comparison.
            o_sf3_len_random_read     = c_sf3_page_addr_incr;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      =
                s_addr_start_aux + (s_i_aux * c_sf3_page_addr_incr);

            if (i_sf3_command_ready)
                s_tester_nx_state = ST_CMD_READ_NEXT;
            else
                s_tester_nx_state = ST_CMD_READ_WAIT;
        end

        ST_CMD_READ_NEXT: begin
            // If auxiliary register I has counted to the number of
            // pages after the starting address, transition to the
            // Read Done state, otherwise increment I and transition again
            // to the Read Start state.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 32'h00000000;
            s_i_val                   = s_i_aux + 1;

            if (s_i_aux < (c_tester_page_cnt_per_iter - 1))
                s_tester_nx_state = ST_CMD_READ_START;
            else
                s_tester_nx_state = ST_CMD_READ_DONE;
        end

        ST_CMD_READ_DONE: begin
            // Random Read iterations have completed. Reset the starting value
            // of the pattern. Transition to the Display Final state.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 32'h00000000;
            s_i_val                   = 0;
            s_pattern_track_val       = s_pattern_start_aux;

            if (s_t == c_t_max) // allow a few seconds of idle for easier SPY capture of the Read command
                s_tester_nx_state = ST_DISPLAY_FINAL;
            else
                s_tester_nx_state = ST_CMD_READ_DONE;
        end

        default: begin // ST_DISPLAY_FINAL
            // Compare the auxiliary register error count to zero and set
            // the auxiliary register test done to either true or false.
            // Wait for the timer to reach its maximum (3 seconds) and then
            // transition to the Wait for Button or Switch.
            o_sf3_len_random_read     = 0;
            o_sf3_cmd_random_read     = 1'b0;
            o_sf3_cmd_page_program    = 1'b0;
            o_sf3_cmd_erase_subsector = 1'b0;
            o_sf3_address_of_cmd      = 32'h00000000;

            if (s_err_count_aux == 0)
                s_test_pass_val = 1'b1;
            else
                s_test_pass_val = 1'b0;

            if (s_t == c_t_max)
                s_tester_nx_state = ST_WAIT_BUTTON_DEP;
            else
                s_tester_nx_state = ST_DISPLAY_FINAL;
        end

    endcase;
end : p_tester_fsm_comb

endmodule : sf_tester_fsm
//------------------------------------------------------------------------------
`end_keywords
