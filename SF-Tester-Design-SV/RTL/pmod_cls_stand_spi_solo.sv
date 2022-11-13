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
-- \file pmod_cls_stand_spi_solo.sv
--
-- \brief A SPI interface to Digilent Inc. PMOD CLS lcd display operating in
-- SPI Mode 0. The design only enables clearing the display, or writing a full
-- sixteen character line of one of the two lines of the display at a time.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//------------------------------------------------------------------------------
//Recursive Moore Machine
//Part 1: Module header:--------------------------------------------------------
module pmod_cls_stand_spi_solo
	import pmod_stand_spi_solo_pkg::*;
	#(parameter
		// Disable or enable fast FSM delays for simulation instead of impelementation.
		integer parm_fast_simulation = 0,
		// Actual frequency in Hz of \ref i_ext_spi_clk_4x
		integer parm_FCLK = 20000000,
		// Actual frequency in Hz of \ref i_ext_spi_clk_4x
		integer parm_FCLK_ce = 2500000
		)
	(
		// system clock and synchronous reset
		input logic i_ext_spi_clk_x,
		input logic i_srst,
		input logic i_spi_ce_4x,
		// Interface pmod_generic_spi_solo_intf
		pmod_generic_spi_solo_intf.spi_sysdrv sdrv,
		// FPGA system interface to CLS operation
		output logic o_command_ready,
		input logic i_cmd_wr_clear_display,
		input logic i_cmd_wr_text_line1,
		input logic i_cmd_wr_text_line2,
		input t_pmod_cls_ascii_line_16 i_dat_ascii_line1,
		input t_pmod_cls_ascii_line_16 i_dat_ascii_line2
		);

// Part 2: Declarations---------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

// Timer signals and constants.
localparam integer c_cls_drv_time_value_bits = 24;
typedef logic [(c_cls_drv_time_value_bits - 1):0] t_cls_drv_time_value;

// Boot time should be in hundreds of milliseconds as the PMOD CLS
// datasheet does not indicate boot-up time of the PMOD CLS microcontroller.
localparam t_cls_drv_time_value c_t_pmodcls_boot =
	parm_fast_simulation ? (parm_FCLK_ce / 1000 * 2) : (parm_FCLK_ce / 1000 * 800);
localparam t_cls_drv_time_value c_tmax = c_t_pmodcls_boot - 1;

t_cls_drv_time_value s_t;

// Driver FSM state declarations
localparam integer c_cls_drv_state_bits = 4;

// Xilinx attributes for auto encoding of the FSM and safe state is
// Default State.
(* fsm_encoding = "auto" *)
(* fsm_safe_state = "default_state" *)
typedef enum logic [(c_cls_drv_state_bits - 1):0] {
	ST_CLS_BOOT0, ST_CLS_IDLE, ST_CLS_LOAD_CLEAR, ST_CLS_LOAD_LINE1,
	ST_CLS_LOAD_LINE2, ST_CLS_CMD_RUN, ST_CLS_CMD_WAIT, ST_CLS_DAT_RUN,
	ST_CLS_DAT_WAIT	
} t_cls_drv_state;
t_cls_drv_state s_cls_drv_pr_state = ST_CLS_BOOT0;
t_cls_drv_state s_cls_drv_nx_state = ST_CLS_BOOT0;

/* Auxiliary state machine registers for recursive state machine operation. */
t_pmod_cls_cmd_len s_cls_cmd_len_aux;
t_pmod_cls_cmd_len s_cls_cmd_len_val;
t_pmod_cls_dat_len s_cls_dat_len_aux;
t_pmod_cls_dat_len s_cls_dat_len_val;
t_pmod_cls_ansi_line_7 s_cls_cmd_tx_aux;
t_pmod_cls_ansi_line_7 s_cls_cmd_tx_val;
t_pmod_cls_tx_len s_cls_cmd_txlen_aux;
t_pmod_cls_tx_len s_cls_cmd_txlen_val;
t_pmod_cls_ascii_line_16 s_cls_dat_tx_aux;
t_pmod_cls_ascii_line_16 s_cls_dat_tx_val;
t_pmod_cls_tx_len s_cls_dat_txlen_aux;
t_pmod_cls_tx_len s_cls_dat_txlen_val;

//Part 3: Statements------------------------------------------------------------

// Timer 1 (Strategy #1), for timing the boot wait for PMOD CLS communication
always_ff @(posedge i_ext_spi_clk_x)
begin: p_timer_1
	if (i_srst) s_t <= 0;
	else
		if (i_spi_ce_4x)
			if (s_cls_drv_pr_state != s_cls_drv_nx_state) begin : if_chg_state
				s_t <= 0;
			end : if_chg_state

			else if (s_t < c_tmax) begin : if_lt_timer_max
				s_t <= s_t + 1;
			end : if_lt_timer_max

end : p_timer_1

// FSM state register plus auxiliary registers, for propagating the next state
// as well as the next recursive auxiliary register value for use within
// one or more state combinatorial logic decisions.
always_ff @(posedge i_ext_spi_clk_x)
begin: p_fsm_state_aux
	if (i_srst) begin
		s_cls_drv_pr_state <= ST_CLS_BOOT0;

		s_cls_cmd_len_aux <= 0;
		s_cls_dat_len_aux <= 0;
		s_cls_cmd_tx_aux <= '0;
		s_cls_dat_tx_aux <= '0;
		s_cls_cmd_txlen_aux <= 0;
		s_cls_dat_txlen_aux <= 0;
	end else
		if (i_spi_ce_4x) begin : if_fsm_state_and_storage
			s_cls_drv_pr_state <= s_cls_drv_nx_state;

			s_cls_cmd_len_aux <= s_cls_cmd_len_val;
			s_cls_dat_len_aux <= s_cls_dat_len_val;
			s_cls_cmd_tx_aux <= s_cls_cmd_tx_val;
			s_cls_dat_tx_aux <= s_cls_dat_tx_val;
			s_cls_cmd_txlen_aux <= s_cls_cmd_txlen_val;
			s_cls_dat_txlen_aux <= s_cls_dat_txlen_val;
		end : if_fsm_state_and_storage
end : p_fsm_state_aux


// FSM combinatorial logic providing multiple outputs, assigned in every state,
// as well as changes in auxiliary values, and calculation of the next FSM
// state. Refer to the FSM state machine drawings in document:
// \ref exercise-14-10-drawing.pdf .
always_comb
begin: p_fsm_comb
	case (s_cls_drv_pr_state)
		ST_CLS_LOAD_CLEAR: begin
			// Load the 4-byte ASCII escape sequence for clearing the display into
			// the \ref s_cls_cmd_tx_aux auxiliary register, and load nothing into
			// the \ref s_cls_dat_tx_aux auxiliary register for additional data
			// transfer.
			o_command_ready = 1'b0;
			sdrv.tx_data = 8'h00;
			sdrv.tx_enqueue = 1'b0;
			sdrv.tx_len = 0;
			sdrv.rx_len = 0;
			sdrv.wait_cyc = 0;
			sdrv.rx_dequeue = 1'b0;
			sdrv.go_stand = 1'b0;
			s_cls_cmd_len_val = 4;
			s_cls_cmd_tx_val = {24'h000000,
				ASCII_CLS_ESC,
				ASCII_CLS_BRACKET,
				ASCII_CLS_CHAR_ZERO,
				ASCII_CLS_DISP_CLR_CMD};
			s_cls_dat_len_val = 0;
			s_cls_dat_tx_val = '0;
			s_cls_cmd_txlen_val = 4;
			s_cls_dat_txlen_val = 0;

			s_cls_drv_nx_state = ST_CLS_CMD_RUN;
		end

		ST_CLS_LOAD_LINE1: begin
			// Load the 7-byte ASCII escape sequence for writing display line 1 into
			// the \ref s_cls_cmd_tx_aux auxiliary register, and load the 16-byte text into
			// the \ref s_cls_dat_tx_aux auxiliary register for additional data transfer.
			o_command_ready = 1'b0;
			sdrv.tx_data = 8'h00;
			sdrv.tx_enqueue = 1'b0;
			sdrv.tx_len = 0;
			sdrv.rx_len = 0;
			sdrv.wait_cyc = 0;
			sdrv.rx_dequeue = 1'b0;
			sdrv.go_stand = 1'b0;
			s_cls_cmd_len_val = 7;
			s_cls_cmd_tx_val = {
				ASCII_CLS_ESC,
				ASCII_CLS_BRACKET,
				ASCII_CLS_CHAR_ZERO, 
				ASCII_CLS_CHAR_SEMICOLON,
				ASCII_CLS_CHAR_ZERO,
				ASCII_CLS_CHAR_ZERO,
				ASCII_CLS_CURSOR_POS_CMD};
			s_cls_dat_len_val = 16;
			s_cls_dat_tx_val = i_dat_ascii_line1;
			s_cls_cmd_txlen_val = 7;
			s_cls_dat_txlen_val = 16;

			s_cls_drv_nx_state = ST_CLS_CMD_RUN;
		end

		ST_CLS_LOAD_LINE2: begin
			// Load the 7-byte ASCII escape sequence for writing display line 2 into
			// the \ref s_cls_cmd_tx_aux auxiliary register, and load the 16-byte text into
			// the \ref s_cls_dat_tx_aux auxiliary register for additional data transfer.
			o_command_ready = 1'b0;
			sdrv.tx_data = 8'h00;
			sdrv.tx_enqueue = 1'b0;
			sdrv.tx_len = 0;
			sdrv.rx_len = 0;
			sdrv.wait_cyc = 0;
			sdrv.rx_dequeue = 1'b0;
			sdrv.go_stand = 1'b0;
			s_cls_cmd_len_val = 7;
			s_cls_cmd_tx_val = {
				ASCII_CLS_ESC,
				ASCII_CLS_BRACKET,
				(ASCII_CLS_CHAR_ZERO + 8'd1), 
				ASCII_CLS_CHAR_SEMICOLON,
				ASCII_CLS_CHAR_ZERO,
				ASCII_CLS_CHAR_ZERO,
				ASCII_CLS_CURSOR_POS_CMD};
			s_cls_dat_len_val = 16;
			s_cls_dat_tx_val = i_dat_ascii_line2;
			s_cls_cmd_txlen_val = 7;
			s_cls_dat_txlen_val = 16;

			s_cls_drv_nx_state = ST_CLS_CMD_RUN;
		end

		ST_CLS_CMD_RUN: begin
			// Run the loading into the SPI TX FIFO of the command from the
			// \ref s_cls_cmd_tx_aux auxiliary register, and then on the
			// loading of the last byte, command the SPI operation to start.
			o_command_ready = 1'b0;
			sdrv.tx_data = s_cls_cmd_tx_aux[((s_cls_cmd_len_aux * 8) - 1) -: 8];
			sdrv.tx_enqueue = sdrv.tx_ready;
			sdrv.tx_len = s_cls_cmd_txlen_aux;
			sdrv.rx_len = 0;
			sdrv.wait_cyc = 0;
			sdrv.rx_dequeue = 1'b0;
			sdrv.go_stand = (s_cls_cmd_len_aux > 1) ? 1'b0 : (sdrv.tx_ready ? 1'b1 : 1'b0);
			s_cls_cmd_tx_val = s_cls_cmd_tx_aux;
			s_cls_cmd_len_val = sdrv.tx_ready ? (s_cls_cmd_len_aux - 1) : s_cls_cmd_len_aux;
			s_cls_dat_len_val = s_cls_dat_len_aux;
			s_cls_dat_tx_val = s_cls_dat_tx_aux;
			s_cls_cmd_txlen_val = s_cls_cmd_txlen_aux;
			s_cls_dat_txlen_val = s_cls_dat_txlen_aux;

			if ((sdrv.tx_ready == 1'b1) && (s_cls_cmd_len_aux <= 1))
				s_cls_drv_nx_state = ST_CLS_CMD_WAIT;
			else
				s_cls_drv_nx_state = ST_CLS_CMD_RUN;
		end

		ST_CLS_CMD_WAIT: begin
			// Wait for the command sequence to end and for the SPI operation
			// to return to IDLE. */
			o_command_ready = 1'b0;
			sdrv.tx_enqueue = 1'b0;
			sdrv.tx_data = 8'h00;
			sdrv.tx_len = 0;
			sdrv.rx_len = 0;
			sdrv.wait_cyc = 0;
			sdrv.rx_dequeue = 1'b0;
			sdrv.go_stand = 1'b0;
			s_cls_cmd_len_val = s_cls_cmd_len_aux;
			s_cls_cmd_tx_val = s_cls_cmd_tx_aux;
			s_cls_dat_len_val = s_cls_dat_len_aux;
			s_cls_dat_tx_val = s_cls_dat_tx_aux;
			s_cls_cmd_txlen_val = s_cls_cmd_txlen_aux;
			s_cls_dat_txlen_val = s_cls_dat_txlen_aux;

			if (sdrv.spi_idle)
				if (s_cls_dat_txlen_aux > 0)
					s_cls_drv_nx_state = ST_CLS_DAT_RUN;
				else
					s_cls_drv_nx_state = ST_CLS_IDLE;
			else
				s_cls_drv_nx_state = ST_CLS_CMD_WAIT;
		end

		ST_CLS_DAT_RUN: begin
			// Run the loading into the SPI TX FIFO of the data from the
			// \ref s_cls_dat_tx_aux auxiliary register, and then on the
			// loading of the last byte, command the SPI operation to start.
			o_command_ready = 1'b0;
			sdrv.tx_data = s_cls_dat_tx_aux[((s_cls_dat_len_aux * 8) - 1) -: 8];
			sdrv.tx_enqueue = sdrv.tx_ready;
			sdrv.tx_len = s_cls_dat_txlen_aux;
			sdrv.rx_len = 0;
			sdrv.wait_cyc = 0;
			sdrv.rx_dequeue = 1'b0;
			sdrv.go_stand = (s_cls_dat_len_aux > 1) ? 1'b0 : (sdrv.tx_ready ? 1'b1 : 1'b0);
			s_cls_cmd_len_val = s_cls_cmd_len_aux;
			s_cls_dat_len_val = sdrv.tx_ready ? (s_cls_dat_len_aux - 1) : s_cls_dat_len_aux;
			s_cls_cmd_tx_val = s_cls_cmd_tx_aux;
			s_cls_dat_tx_val = s_cls_dat_tx_aux;
			s_cls_cmd_txlen_val = s_cls_cmd_txlen_aux;
			s_cls_dat_txlen_val = s_cls_dat_txlen_aux;

			if ((sdrv.tx_ready == 1'b1) && (s_cls_dat_len_aux <= 1))
				s_cls_drv_nx_state = ST_CLS_DAT_WAIT;
			else
				s_cls_drv_nx_state = ST_CLS_DAT_RUN;
		end

		ST_CLS_DAT_WAIT: begin
			// Wait for the data sequence to end and for the SPI operation
			// to return to IDLE.
			o_command_ready = 1'b0;
			sdrv.tx_enqueue = 1'b0;
			sdrv.tx_data = 8'h00;
			sdrv.tx_len = 0;
			sdrv.rx_len = 0;
			sdrv.wait_cyc = 0;
			sdrv.rx_dequeue = 1'b0;
			sdrv.go_stand = 1'b0;
			s_cls_cmd_len_val = s_cls_cmd_len_aux;
			s_cls_cmd_tx_val = s_cls_cmd_tx_aux;
			s_cls_dat_len_val = s_cls_dat_len_aux;
			s_cls_dat_tx_val = s_cls_dat_tx_aux;
			s_cls_cmd_txlen_val = s_cls_cmd_txlen_aux;
			s_cls_dat_txlen_val = s_cls_dat_txlen_aux;

			if (sdrv.spi_idle) s_cls_drv_nx_state = ST_CLS_IDLE;
			else s_cls_drv_nx_state = ST_CLS_DAT_WAIT;
		end

		ST_CLS_IDLE: begin
			// IDLE the PMOD CLS driver FSM and wait for one of the three commands:
			// (a) clear the display
			// (b) write display text line 1
			// (c) write display text line 2
			o_command_ready = 1'b1;
			sdrv.tx_enqueue = 1'b0;
			sdrv.tx_data = 8'h00;
			sdrv.tx_len = 0;
			sdrv.rx_len = 0;
			sdrv.wait_cyc = 0;
			sdrv.rx_dequeue = 1'b0;
			sdrv.go_stand = 1'b0;
			s_cls_cmd_len_val = s_cls_cmd_len_aux;
			s_cls_cmd_tx_val = s_cls_cmd_tx_aux;
			s_cls_dat_len_val = s_cls_dat_len_aux;
			s_cls_dat_tx_val = s_cls_dat_tx_aux;
			s_cls_cmd_txlen_val = s_cls_cmd_txlen_aux;
			s_cls_dat_txlen_val = s_cls_dat_txlen_aux;

			if (i_cmd_wr_clear_display) s_cls_drv_nx_state = ST_CLS_LOAD_CLEAR;
			else if (i_cmd_wr_text_line1) s_cls_drv_nx_state = ST_CLS_LOAD_LINE1;
			else if (i_cmd_wr_text_line2) s_cls_drv_nx_state = ST_CLS_LOAD_LINE2;
			else s_cls_drv_nx_state = ST_CLS_IDLE;
		end

		default: begin // ST_CLS_BOOT0
			// The datasheet for the PMOD CLS does not indicate the boot-up time
			// required for the PMOD CLS microcontroller. At boot-up, wait a
			// a time of \ref c_t_pmodcls_boot before accepting commands to operate
			// the PMOD CLS display.
			o_command_ready = 1'b0;
			sdrv.tx_data = 8'h00;
			sdrv.tx_enqueue = 1'b0;
			sdrv.tx_len = 0;
			sdrv.rx_len = 0;
			sdrv.wait_cyc = 0;
			sdrv.rx_dequeue = 1'b0;
			sdrv.go_stand = 1'b0;
			s_cls_cmd_len_val = s_cls_cmd_len_aux;
			s_cls_cmd_tx_val = s_cls_cmd_tx_aux;
			s_cls_dat_len_val = s_cls_dat_len_aux;
			s_cls_dat_tx_val = s_cls_dat_tx_aux;
			s_cls_cmd_txlen_val = s_cls_cmd_txlen_aux;
			s_cls_dat_txlen_val = s_cls_dat_txlen_aux;

			if (s_t == c_t_pmodcls_boot - 1) s_cls_drv_nx_state = ST_CLS_IDLE;
			else s_cls_drv_nx_state = ST_CLS_BOOT0;
		end
	endcase
end : p_fsm_comb

endmodule : pmod_cls_stand_spi_solo
//------------------------------------------------------------------------------
`end_keywords
