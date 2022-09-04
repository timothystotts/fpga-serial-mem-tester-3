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
-- \file uart_tx_only.sv
--
-- \brief A simplified UART function to drive TX characters on a UART board
--        connection, independent of any RX function (presumed to be ingored).
--        Maximum baudrate is 115200; input clock is 7.37 MHz to support divison
--        to modem clock rates.
------------------------------------------------------------------------------*/
//------------------------------------------------------------------------------
`begin_keywords "1800-2012"
//Recursive Moore Machine-------------------------------------------------------
//Part 1: Module header:--------------------------------------------------------
module uart_tx_only
	#(parameter
		// the Modem Baud Rate of the UART TX machine, max 115200
		parm_BAUD = 115200,
		// the ASCII line length
		parm_ascii_line_length = 35,
		// the almost full threshold for FIFO byte count range 0 to 2047
		[10:0] parm_almost_full_thresh = {3'b111,8'hDC}
		)
	(
		// system clock
		input logic i_clk_40mhz,
		input logic i_rst_40mhz,
		// modem clock from MMCM divided down
		input logic i_clk_7_37mhz,
		input logic i_rst_7_37mhz,
		// the output to connect to USB-UART RXD pin
		output logic eo_uart_tx,
		// data to transmit out the UART
		input logic [7:0] i_tx_data,
		input logic i_tx_valid,
		// indication that the FIFO is not almost full and can receive a line of data
		output logic o_tx_ready
		);


//Part 2: Declarations----------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

/* State Machine constants and variables */
`define c_uarttxonly_fsm_state_bits 2

typedef enum logic [(`c_uarttxonly_fsm_state_bits - 1):0] {
	ST_IDLE, ST_START, ST_DATA, ST_STOP
} t_uarttxonly_state;

// Xilinx state machine register attributes.
(* fsm_encoding = "gray" *)
(* fsm_safe_state = "default_state" *)
// State machine state register.
t_uarttxonly_state s_uarttxonly_pr_state;
t_uarttxonly_state s_uarttxonly_nx_state;

/* State machine output and auxiliary registers */
logic so_uart_tx;
logic [3:0] s_i_val;
logic [3:0] s_i_aux;
logic [7:0] s_data_val;
logic [7:0] s_data_aux;

/* internal clock for 1x the baud rate */
logic s_ce_baud_1x;

/* Mapping for FIFO TX */
logic [7:0] s_data_fifo_tx_in;
logic [7:0] s_data_fifo_tx_out;
logic s_data_fifo_tx_re;
logic s_data_fifo_tx_we;
logic s_data_fifo_tx_full;
logic s_data_fifo_tx_empty;
logic s_data_fifo_tx_valid;
logic [10:0] s_data_fifo_tx_wr_count;
logic [10:0] s_data_fifo_tx_rd_count;
logic s_data_fifo_tx_almostempty;
logic s_data_fifo_tx_almostfull;
logic s_data_fifo_tx_rd_err;
logic s_data_fifo_tx_wr_err;

//Part 3: Statements------------------------------------------------------------

// clock enable for 1x times the baud rate: no oversampling for TX ONLY
clock_enable_divider #(.par_ce_divisor(4 * 16 * 115200 / parm_BAUD))
	u_baud_1x_ce_divider (
	.o_ce_div(s_ce_baud_1x),
	.i_clk_mhz(i_clk_7_37mhz),
	.i_rst_mhz(i_rst_7_37mhz),
	.i_ce_mhz(1'b1));

/* FIFO to receive from system and gradually transmit to UART. 
   The FIFO must implement read-ahead output on rd_en. */
assign s_data_fifo_tx_in = i_tx_data;
assign s_data_fifo_tx_we = i_tx_valid;
assign o_tx_ready = ((! s_data_fifo_tx_full) && (! s_data_fifo_tx_almostfull));

/*
always_ff @(posedge i_clk_7_37mhz)
begin: p_gen_fifo_tx_valid
	s_data_fifo_tx_valid <= s_data_fifo_tx_re;
end : p_gen_fifo_tx_valid
*/

// FIFO_DUALCLOCK_MACRO: Dual Clock First-In, First-Out (FIFO) RAM Buffer
//                       Artix-7
// Xilinx HDL Language Template, version 2019.1

/////////////////////////////////////////////////////////////////
// DATA_WIDTH | FIFO_SIZE | FIFO Depth | RDCOUNT/WRCOUNT Width //
// ===========|===========|============|=======================//
//   37-72    |  "36Kb"   |     512    |         9-bit         //
//   19-36    |  "36Kb"   |    1024    |        10-bit         //
//   19-36    |  "18Kb"   |     512    |         9-bit         //
//   10-18    |  "36Kb"   |    2048    |        11-bit         //
//   10-18    |  "18Kb"   |    1024    |        10-bit         //
//    5-9     |  "36Kb"   |    4096    |        12-bit         //
//    5-9     |  "18Kb"   |    2048    |        11-bit         //
//    1-4     |  "36Kb"   |    8192    |        13-bit         //
//    1-4     |  "18Kb"   |    4096    |        12-bit         //
/////////////////////////////////////////////////////////////////

FIFO_DUALCLOCK_MACRO  #(
  .ALMOST_EMPTY_OFFSET(11'h023),                 // Sets the almost empty threshold
  .ALMOST_FULL_OFFSET(parm_almost_full_thresh),  // Sets almost full threshold
  .DATA_WIDTH(8),                                // Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
  .DEVICE("7SERIES"),                            // Target device: "7SERIES" 
  .FIFO_SIZE ("18Kb"),                           // Target BRAM: "18Kb" or "36Kb" 
  .FIRST_WORD_FALL_THROUGH ("TRUE")              // Sets the FIFO FWFT to "TRUE" or "FALSE" 
) u_fifo_uart_tx_0 (
  .ALMOSTEMPTY(s_data_fifo_tx_almostempty), // 1-bit output almost empty
  .ALMOSTFULL(s_data_fifo_tx_almostfull),   // 1-bit output almost full
  .DO(s_data_fifo_tx_out),                  // Output data, width defined by DATA_WIDTH parameter
  .EMPTY(s_data_fifo_tx_empty),             // 1-bit output empty
  .FULL(s_data_fifo_tx_full),               // 1-bit output full
  .RDCOUNT(s_data_fifo_tx_rd_count),        // Output read count, width determined by FIFO depth
  .RDERR(s_data_fifo_tx_rd_err),            // 1-bit output read error
  .WRCOUNT(s_data_fifo_tx_wr_count),        // Output write count, width determined by FIFO depth
  .WRERR(s_data_fifo_tx_wr_err),            // 1-bit output write error
  .DI(s_data_fifo_tx_in),                   // Input data, width defined by DATA_WIDTH parameter
  .RDCLK(i_clk_7_37mhz),                    // 1-bit input read clock
  .RDEN(s_data_fifo_tx_re),                 // 1-bit input read enable
  .RST(i_rst_7_37mhz),                      // 1-bit input reset
  .WRCLK(i_clk_40mhz),                      // 1-bit input write clock
  .WREN(s_data_fifo_tx_we)                  // 1-bit input write enable
);

// End of FIFO_DUALCLOCK_MACRO_inst instantiation
				

/* FSM register and auxiliary registers */
always_ff @(posedge i_clk_7_37mhz)
begin: p_uarttxonly_fsm_state_aux
	if (i_rst_7_37mhz) begin
		s_uarttxonly_pr_state <= ST_IDLE;

		s_i_aux <= 0;
		s_data_aux <= 8'h00;
	end
	else if (s_ce_baud_1x) begin : if_fsm_state_and_storage
		s_uarttxonly_pr_state <= s_uarttxonly_nx_state;

		s_i_aux <= s_i_val;
		s_data_aux <= s_data_val;
	end : if_fsm_state_and_storage
end : p_uarttxonly_fsm_state_aux

/* FSM combinatorial logic with output and auxiliary registers */
always_comb
begin: p_uarttxonly_fsm_nx_out
	case (s_uarttxonly_pr_state)
		ST_START: begin
			/* Transmit the UART serial START bit '0' and load the 
			   next TX FIFO byte on transition. */
			s_data_fifo_tx_re = s_ce_baud_1x;
			s_data_val = s_data_fifo_tx_out;
			s_i_val = 0;

			so_uart_tx = 1'b0;

			s_uarttxonly_nx_state = ST_DATA;
		end
		ST_DATA: begin
			/* Transmit the byte data to UART serial, least significant
			   bit first, index 0 to 7. */
			s_data_fifo_tx_re = 1'b0;
			s_data_val = s_data_aux;
			s_i_val = s_i_aux + 1;

			// Note that it may be more efficient to make this a shift register.
			so_uart_tx = s_data_aux[s_i_aux];

			if (s_i_aux == 7) s_uarttxonly_nx_state = ST_STOP;
			else s_uarttxonly_nx_state = ST_DATA;
		end
		ST_STOP: begin
			/* Transmit the UART serial STOP bit '1'. Check the FIFO
			   status. If FIFO contains more data, then transition
			   directly back to the START bit. Otherwise, transition
			   to the IDLE state. */
			s_data_fifo_tx_re = 1'b0;
			s_data_val = s_data_aux;
			s_i_val = s_i_aux;

			so_uart_tx = 1'b1;

			if (! s_data_fifo_tx_empty) s_uarttxonly_nx_state = ST_START;
			else s_uarttxonly_nx_state = ST_IDLE;
		end
		default: begin // ST_IDLE
			/* The IDLE state holds a continuous high value on the
			   serial line to indicate UART signal is IDLE. */
			s_data_fifo_tx_re = 1'b0;
			s_data_val = s_data_aux;
			s_i_val = s_i_aux;

			so_uart_tx = 1'b1;

			if (! s_data_fifo_tx_empty) s_uarttxonly_nx_state = ST_START;
			else s_uarttxonly_nx_state = ST_IDLE;
		end
	endcase
end : p_uarttxonly_fsm_nx_out

/* Registered output for timing closure and glitch removal on the output pin */
always_ff @(posedge i_clk_7_37mhz)
begin: p_fsm_out_reg
	if (i_rst_7_37mhz) eo_uart_tx <= 1'b1;
	else if (s_ce_baud_1x) eo_uart_tx <= so_uart_tx;
end : p_fsm_out_reg

endmodule : uart_tx_only
//------------------------------------------------------------------------------
`end_keywords
