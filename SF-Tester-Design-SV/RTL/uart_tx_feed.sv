/*------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2020-2023 Timothy Stotts
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
-- \file uart_tx_feed.sv
--
-- \brief A simple text byte feeder to the UART TX module.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//Recursive Moore Machine-------------------------------------------------------
//Part 1: Module header:--------------------------------------------------------
module uart_tx_feed
    #(parameter
        parm_ascii_line_length = 35
        )
    (
        // system clock and reset
        input logic i_clk_40mhz,
        input logic i_rst_40mhz,
        // data and valid pulse output to the UART TX
        output logic [7:0] o_tx_data,
        output logic o_tx_valid,
        // the TX Ready input from the UART TX
        input logic i_tx_ready,
        // system pulse to start transmit of a new line
        input logic i_tx_go,
        // data captured as next 35 character line to transmit
        input logic [(parm_ascii_line_length*8-1):0] i_dat_ascii_line
    );

//Part 2: Declarations----------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

// UART TX update FSM state declarations
`define c_uarttx_feed_fsm_bits 2

typedef enum logic [(`c_uarttx_feed_fsm_bits - 1):0] {
    ST_UARTFEED_IDLE, ST_UARTFEED_CAPT, ST_UARTFEED_DATA, ST_UARTFEED_WAIT
} t_uartfeed_state;

// UART feed FSM state register
t_uartfeed_state s_uartfeed_pr_state;
t_uartfeed_state s_uartfeed_nx_state;

// preset values on START
localparam [5:0] c_uart_k_preset = parm_ascii_line_length;

// preset values on reset
localparam [(parm_ascii_line_length*8-1):0] c_line_of_spaces =
    280'h2020202020202020202020202020202020202020202020202020202020202020200D0A;

// UART TX signals for UART TX update FSM
logic [5:0] s_uart_k_val;
logic [5:0] s_uart_k_aux;
logic [(parm_ascii_line_length*8-1):0] s_uart_line_val;
logic [(parm_ascii_line_length*8-1):0] s_uart_line_aux;

//Part 3: Statements------------------------------------------------------------
// UART TX machine, the \ref parm_ascii_line_length bytes
// of \ref i_dat_ascii_line
// are feed into out the \ref o_tx_data and \ref o_tx_valid signals.
// Another module receives the bytes, indicates readiness on signal
// \ref i_tx_ready .

// UART TX machine, synchronous state, auxiliary counting register K,
// and auxiliary line data register LINE.
always_ff @(posedge i_clk_40mhz)
begin: p_uartfeed_fsm_state_aux
    if (i_rst_40mhz) begin
        s_uartfeed_pr_state <= ST_UARTFEED_IDLE;
        s_uart_k_aux <= 0;
        s_uart_line_aux <= c_line_of_spaces;
    end
    else begin : if_fsm_state_and_storage
        s_uartfeed_pr_state <= s_uartfeed_nx_state;
        s_uart_k_aux <= s_uart_k_val;
        s_uart_line_aux <= s_uart_line_val;
    end : if_fsm_state_and_storage
end : p_uartfeed_fsm_state_aux

// UART TX machine, combinatorial next state and auxiliary counting register, and
// auxiliary 34 8-bit character line register.
always_comb
begin: p_uartfeed_fsm_nx_out
    case (s_uartfeed_pr_state)
        ST_UARTFEED_CAPT: begin
            // Capture the input ASCII line and the index K.
            // The value of \ref i_tx_ready is also checked as to
            // not overflow the UART TX buffer. Once TX is ready,
            // begin the enqueue of outgoing data. TX Ready is presumed to
            // indicate that the TX FIFO is below the threshold of almost
            // full and that enqueueing the full line will not overflow
            // the TX FIFO.
            o_tx_data = '0;
            o_tx_valid = 1'b0;
            s_uart_k_val = c_uart_k_preset;
            s_uart_line_val = i_dat_ascii_line;

            if (i_tx_ready) s_uartfeed_nx_state = ST_UARTFEED_DATA;
            else s_uartfeed_nx_state = ST_UARTFEED_CAPT;
        end
        ST_UARTFEED_DATA: begin
            // Enqueue the \ref c_uart_k_preset count of bytes from register
            // \ref s_uart_line_aux. Then transition to the WAIT state.
            // To accomplish this, s_uart_line_aux is shifted left, one byte
            // at-a-time.
            o_tx_data = s_uart_line_aux[((8*c_uart_k_preset)-1)-:8];
            o_tx_valid = 1'b1;
            s_uart_k_val = s_uart_k_aux - 1;
            s_uart_line_val = {s_uart_line_aux[(8*(c_uart_k_preset-1)-1)-:(8*(c_uart_k_preset-1))],8'h00};

            if (s_uart_k_aux == 1) s_uartfeed_nx_state = ST_UARTFEED_WAIT;
            else s_uartfeed_nx_state = ST_UARTFEED_DATA;
        end
        ST_UARTFEED_WAIT: begin
            // Wait for the \ref i_tx_go pulse to be low, and then
            // transition to the IDLE state.
            o_tx_data = '0;
            o_tx_valid = 1'b0;
            s_uart_k_val = s_uart_k_aux;
            s_uart_line_val = s_uart_line_aux;

            if (! i_tx_go) s_uartfeed_nx_state = ST_UARTFEED_IDLE;
            else s_uartfeed_nx_state = ST_UARTFEED_WAIT;
        end
        default: begin // ST_UARTFEED_IDLE
            // IDLE the FSM while waiting for a pulse on \ref i_tx_go .
            o_tx_data = '0;
            o_tx_valid = 1'b0;
            s_uart_k_val = s_uart_k_aux;
            s_uart_line_val = s_uart_line_aux;

            if (i_tx_go) s_uartfeed_nx_state = ST_UARTFEED_CAPT;
            else s_uartfeed_nx_state = ST_UARTFEED_IDLE;
        end
    endcase
end : p_uartfeed_fsm_nx_out

endmodule : uart_tx_feed
//------------------------------------------------------------------------------
`end_keywords
