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
-- \file pmod_generic_spi_solo.sv
--
-- \brief A custom SPI driver for generic usage, implementing only Standard
-- SPI operating in Mode 0, without Extended data transfer of more than the
-- standard COPI and CIPO data signals. Note that the bus is only controlled to
-- TX data, optional waiting time, and optional RX data, for a Standard SPI Bus
-- with only one peripheral. This suits the Digilent Inc. SPI-based PMOD
-- peripherals well, but is too simplistic for a board design of one SPI bus
-- with multiple peripherals.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//------------------------------------------------------------------------------
//Multiple Recursive Moore Machines
//Part 1: Module header:--------------------------------------------------------
module pmod_generic_spi_solo
    #(parameter
        // Note that these parameters should be updated to max counts instead of
        // LOG2, and then several localparam compute the LOG2 with $clog2 .
        // Ratio of i_ext_spi_clk_x to SPI sck bus output.
        integer parm_ext_spi_clk_ratio = 32,
        // LOG2 of the TX FIFO max count
        integer parm_tx_len_bits = 11,
        // LOG2 of max Wait Cycles count between end of TX and start of RX
        integer parm_wait_cyc_bits = 2,
        // LOG2 of the RX FIFO max count
        integer parm_rx_len_bits = 11 // now ignored due to usage of MACRO
        )
    (
        // SPI bus outputs and input to top-level
        output logic eo_sck_o,
        output logic eo_sck_t,
        output logic eo_csn_o,
        output logic eo_csn_t,
        output logic eo_copi_o,
        output logic eo_copi_t,
        input logic ei_cipo_i,
        // SPI state machine clock at \ref parm_ext_spi_clk_ratio the SPI bus
        // clock speed, with clock enable at 4x the SPI bus clock speed, and a
        // synchronous reset
        input logic i_ext_spi_clk_x,
        input logic i_srst,
        input logic i_spi_ce_4x,
        // System-side interface with (a) inputs and outputs for triggering a
        // new SPI bus signal, (b) system interfaces to the TX FIFO, and (c)
        // system interfaces to the RX FIFO
        pmod_generic_spi_solo_intf.spi_solo sdrv
    );

// Part 2: Declarations---------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

// SPI FSM state declarations
`define c_spi_state_bits 3
typedef enum logic [(`c_spi_state_bits - 1):0] {
    ST_STAND_IDLE, ST_STAND_START_D, ST_STAND_START_S,
    ST_STAND_TX, ST_STAND_WAIT, ST_STAND_RX,
    ST_STAND_STOP_S, ST_STAND_STOP_D
} t_spi_state;

// Xilinx attributes for gray encoding of the FSM and safe state is
// Default State.
(* fsm_encoding = "gray" *)
(* fsm_safe_state = "default_state" *)
t_spi_state s_spi_pr_state = ST_STAND_IDLE;
t_spi_state s_spi_nx_state = ST_STAND_IDLE;
t_spi_state s_spi_pr_state_delayed1 = ST_STAND_IDLE;
t_spi_state s_spi_pr_state_delayed2 = ST_STAND_IDLE;
t_spi_state s_spi_pr_state_delayed3 = ST_STAND_IDLE;

// Data start FSM state declarations
`define c_dat_state_bits 3
typedef enum logic [(`c_dat_state_bits - 1):0] {
    ST_PULSE_WAIT, ST_PULSE_HOLD_0, ST_PULSE_HOLD_1,
    ST_PULSE_HOLD_2, ST_PULSE_HOLD_3
} t_dat_state;

// Xilinx attributes for Gray encoding of the FSM and safe state is
// Default State.
(* fsm_encoding = "gray" *)
(* fsm_safe_state = "default_state" *)
t_dat_state s_dat_pr_state = ST_PULSE_WAIT;
t_dat_state s_dat_nx_state = ST_PULSE_WAIT;

// Timer signals and constants
localparam integer c_timer_stand_value_maximum = ((512 + 6) * 8);
localparam integer c_timer_stand_value_bits = $clog2(c_timer_stand_value_maximum);
typedef logic [(c_timer_stand_value_bits - 1):0] t_timer_stand_value;

localparam t_timer_stand_value c_t_stand_wait_ss = 4;
localparam t_timer_stand_value c_t_stand_max_tx = (512 + 6) * 8;
localparam t_timer_stand_value c_t_stand_max_wait = 31;
localparam t_timer_stand_value c_t_stand_max_rx = (512 + 5) * 8;
localparam t_timer_stand_value c_tmax = c_t_stand_max_tx;
localparam t_timer_stand_value c_t_inc = 1;

t_timer_stand_value s_t;
t_timer_stand_value s_t_delayed1;
t_timer_stand_value s_t_delayed2;
t_timer_stand_value s_t_delayed3;

// SPI 4x and 1x clocking signals and enables
logic s_spi_ce_4x;
logic s_spi_clk_1x;

logic s_spi_clk_ce0;
logic s_spi_clk_ce1;
logic s_spi_clk_ce2;
logic s_spi_clk_ce3;

// FSM pulse stretched signal
logic s_go_stand;

// FSM auxiliary registers
logic [(parm_tx_len_bits - 1):0] s_tx_len_val;
logic [(parm_tx_len_bits - 1):0] s_tx_len_aux;
logic [(parm_rx_len_bits - 1):0] s_rx_len_val;
logic [(parm_rx_len_bits - 1):0] s_rx_len_aux;
logic [(parm_wait_cyc_bits - 1):0] s_wait_cyc_val;
logic [(parm_wait_cyc_bits - 1):0] s_wait_cyc_aux;
logic s_go_stand_val;
logic s_go_stand_aux;

// FSM output status
logic s_spi_idle;

// Mapping for FIFO RX
logic [7:0] s_data_fifo_rx_in;
logic [7:0] s_data_fifo_rx_out;
logic s_data_fifo_rx_re;
logic s_data_fifo_rx_we;
logic s_data_fifo_rx_full;
logic s_data_fifo_rx_empty;
logic s_data_fifo_rx_valid;
logic [10:0] s_data_fifo_rx_rdcount;
logic [10:0] s_data_fifo_rx_wrcount;
logic s_data_fifo_rx_almostfull;
logic s_data_fifo_rx_almostempty;
logic s_data_fifo_rx_wrerr;
logic s_data_fifo_rx_rderr;

// Mapping for FIFO TX
logic [7:0] s_data_fifo_tx_in;
logic [7:0] s_data_fifo_tx_out;
logic s_data_fifo_tx_re;
logic s_data_fifo_tx_we;
logic s_data_fifo_tx_full;
logic s_data_fifo_tx_empty;
// logic s_data_fifo_tx_valid;
logic [10:0] s_data_fifo_tx_rdcount;
logic [10:0] s_data_fifo_tx_wrcount;
logic s_data_fifo_tx_almostfull;
logic s_data_fifo_tx_almostempty;
logic s_data_fifo_tx_wrerr;
logic s_data_fifo_tx_rderr;

// A counter for tracking 4 phases of the clock enable against the bus
// output clock
integer v_phase_counter;

//Part 3: Statements------------------------------------------------------------
// The SPI driver is IDLE only if the state signals as IDLE and more than four
// clock cycles have elapsed since a system clock pulse on input
// \ref sdrv.go_stand.
assign sdrv.spi_idle = ((s_spi_idle == 1'b1) &&
                        (s_dat_pr_state == ST_PULSE_WAIT)) ? 1'b1 : 1'b0;

// In this implementation, the 4x SPI clock is operated by a clock enable against
// the system clock \ref i_ext_spi_clk_x .
assign s_spi_ce_4x = i_spi_ce_4x;

// Mapping of the RX FIFO to external control and reception of data for
// reading operations
assign sdrv.rx_avail = (~ s_data_fifo_rx_empty) & s_spi_ce_4x;
assign sdrv.rx_valid = s_data_fifo_rx_valid & s_spi_ce_4x;
assign s_data_fifo_rx_re = sdrv.rx_dequeue & s_spi_ce_4x;
assign sdrv.rx_data = s_data_fifo_rx_out;

always_ff @(posedge i_ext_spi_clk_x)
begin: p_gen_fifo_rx_valid
    s_data_fifo_rx_valid <= s_data_fifo_rx_re;
end : p_gen_fifo_rx_valid

// FIFO_SYNC_MACRO: Synchronous First-In, First-Out (FIFO) RAM Buffer
//                  Artix-7
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

FIFO_SYNC_MACRO  #(
  .DEVICE("7SERIES"), // Target Device: "7SERIES"
  .ALMOST_EMPTY_OFFSET(11'h080), // Sets the almost empty threshold
  .ALMOST_FULL_OFFSET(11'h080),  // Sets almost full threshold
  .DATA_WIDTH(8), // Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
  .DO_REG(0),     // Optional output register (0 or 1)
  .FIFO_SIZE ("18Kb")  // Target BRAM: "18Kb" or "36Kb"
) u_fifo_rx_0 (
  .ALMOSTEMPTY(s_data_fifo_rx_almostempty), // 1-bit output almost empty
  .ALMOSTFULL(s_data_fifo_rx_almostfull),   // 1-bit output almost full
  .DO(s_data_fifo_rx_out),                  // Output data, width defined by DATA_WIDTH parameter
  .EMPTY(s_data_fifo_rx_empty),             // 1-bit output empty
  .FULL(s_data_fifo_rx_full),               // 1-bit output full
  .RDCOUNT(s_data_fifo_rx_rdcount),         // Output read count, width determined by FIFO depth
  .RDERR(s_data_fifo_rx_rderr),             // 1-bit output read error
  .WRCOUNT(s_data_fifo_rx_wrcount),         // Output write count, width determined by FIFO depth
  .WRERR(s_data_fifo_rx_wrerr),             // 1-bit output write error
  .CLK(i_ext_spi_clk_x),                    // 1-bit input clock
  .DI(s_data_fifo_rx_in),                   // Input data, width defined by DATA_WIDTH parameter
  .RDEN(s_data_fifo_rx_re),                 // 1-bit input read enable
  .RST(i_srst),                             // 1-bit input reset
  .WREN(s_data_fifo_rx_we)                  // 1-bit input write enable
);
// End of FIFO_SYNC_MACRO_inst instantiation

// Mapping of the TX FIFO to external control and transmission of data for
// writing operations
assign s_data_fifo_tx_in = sdrv.tx_data;
assign s_data_fifo_tx_we = sdrv.tx_enqueue & s_spi_ce_4x;
assign sdrv.tx_ready = (~ s_data_fifo_tx_full) & s_spi_ce_4x;

// always_ff @(posedge i_ext_spi_clk_x)
// begin: p_gen_fifo_tx_valid
//     s_data_fifo_tx_valid <= s_data_fifo_tx_re;
// end : p_gen_fifo_tx_valid

// FIFO_SYNC_MACRO: Synchronous First-In, First-Out (FIFO) RAM Buffer
//                  Artix-7
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

FIFO_SYNC_MACRO  #(
  .DEVICE("7SERIES"), // Target Device: "7SERIES"
  .ALMOST_EMPTY_OFFSET(11'h080), // Sets the almost empty threshold
  .ALMOST_FULL_OFFSET(11'h080),  // Sets almost full threshold
  .DATA_WIDTH(8), // Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
  .DO_REG(0),     // Optional output register (0 or 1)
  .FIFO_SIZE ("18Kb")  // Target BRAM: "18Kb" or "36Kb"
) u_fifo_tx_0 (
  .ALMOSTEMPTY(s_data_fifo_tx_almostempty), // 1-bit output almost empty
  .ALMOSTFULL(s_data_fifo_tx_almostfull),   // 1-bit output almost full
  .DO(s_data_fifo_tx_out),                  // Output data, width defined by DATA_WIDTH parameter
  .EMPTY(s_data_fifo_tx_empty),             // 1-bit output empty
  .FULL(s_data_fifo_tx_full),               // 1-bit output full
  .RDCOUNT(s_data_fifo_tx_rdcount),         // Output read count, width determined by FIFO depth
  .RDERR(s_data_fifo_tx_rderr),             // 1-bit output read error
  .WRCOUNT(s_data_fifo_tx_wrcount),         // Output write count, width determined by FIFO depth
  .WRERR(s_data_fifo_tx_wrerr),             // 1-bit output write error
  .CLK(i_ext_spi_clk_x),                    // 1-bit input clock
  .DI(s_data_fifo_tx_in),                   // Input data, width defined by DATA_WIDTH parameter
  .RDEN(s_data_fifo_tx_re),                 // 1-bit input read enable
  .RST(i_srst),                             // 1-bit input reset
  .WREN(s_data_fifo_tx_we)                  // 1-bit input write enable
);
// End of FIFO_SYNC_MACRO_inst instantiation

// spi clock for SCK output, generated clock
// requires create_generated_clock constraint in XDC
clock_divider #(.par_clk_divisor(parm_ext_spi_clk_ratio)
    ) u_spi_1x_clock_divider (
    .o_clk_div(s_spi_clk_1x),
    .o_rst_div(),
    .i_clk_mhz(i_ext_spi_clk_x),
    .i_rst_mhz(i_srst));

// 25% point clock enables for period of 4 times SPI CLK output based on s_spi_ce_4x
always_ff @(posedge i_ext_spi_clk_x)
begin: p_phase_4x_ce
    if (i_srst)
        v_phase_counter <= 0;
    else
        if (v_phase_counter < parm_ext_spi_clk_ratio - 1)
            v_phase_counter <= v_phase_counter + 1;
        else
            v_phase_counter <= 0;
end : p_phase_4x_ce

assign s_spi_clk_ce0 = (v_phase_counter == parm_ext_spi_clk_ratio / 4 * 0) && s_spi_ce_4x;
assign s_spi_clk_ce1 = (v_phase_counter == parm_ext_spi_clk_ratio / 4 * 1) && s_spi_ce_4x;
assign s_spi_clk_ce2 = (v_phase_counter == parm_ext_spi_clk_ratio / 4 * 2) && s_spi_ce_4x;
assign s_spi_clk_ce3 = (v_phase_counter == parm_ext_spi_clk_ratio / 4 * 3) && s_spi_ce_4x;

// Timer 1 (Strategy #1) with constant timer increment
always_ff @(posedge i_ext_spi_clk_x)
begin: p_timer_1
    if (i_srst) begin
        s_t <= 0;
        s_t_delayed1 <= 0;
        s_t_delayed2 <= 0;
        s_t_delayed3 <= 0;
    end else begin
        if (i_spi_ce_4x) begin
            s_t_delayed3 <= s_t_delayed2;
            s_t_delayed2 <= s_t_delayed1;
            s_t_delayed1 <= s_t;
        end

        // clock enable on falling SPI edge for timer change
        if (s_spi_clk_ce2)
            if (s_spi_pr_state != s_spi_nx_state) s_t <= 0;
            else if (s_t < c_tmax) s_t <= s_t + c_t_inc;
    end
end : p_timer_1

// System Data GO data value holder and sdrv.go_stand pulse stretcher for duration
// of all four clock enables duration of the 4x clock, starting at a clock
// enable position. State assignment and Auxiliary register assignment.
always_ff @(posedge i_ext_spi_clk_x)
begin: p_dat_fsm_state_aux
    if (i_srst) begin
        s_dat_pr_state <= ST_PULSE_WAIT;

        s_tx_len_aux <= 0;
        s_rx_len_aux <= 0;
        s_wait_cyc_aux <= 0;
        s_go_stand_aux <= 1'b0;
    end else
        if (s_spi_ce_4x) begin : if_fsm_state_and_storage
            // no clock enable as this is a system-side interface
            s_dat_pr_state <= s_dat_nx_state;

            // auxiliary assignments
            s_tx_len_aux <= s_tx_len_val;
            s_rx_len_aux <= s_rx_len_val;
            s_wait_cyc_aux <= s_wait_cyc_val;
            s_go_stand_aux <= s_go_stand_val;
        end : if_fsm_state_and_storage
end : p_dat_fsm_state_aux

// Pass the auxiliary signal that lasts for a single iteration of all four
// s_spi_clk_4x clock enables on to the \ref p_spi_fsm_comb machine.
assign s_go_stand = s_go_stand_aux;

// System Data GO data value holder and sdrv.go_stand pulse stretcher for all
// four clock enables duration of the 4x clock, starting at an clock enable
// position. Combinatorial logic paired with the \ref p_dat_fsm_state
// assignments.
always_comb
begin: p_dat_fsm_comb
    case (s_dat_pr_state)
        ST_PULSE_HOLD_0: begin
            // Hold the GO signal and auxiliary for this cycle.
            s_go_stand_val = s_go_stand_aux;
            s_tx_len_val = s_tx_len_aux;
            s_rx_len_val = s_rx_len_aux;
            s_wait_cyc_val = s_wait_cyc_aux;
            s_dat_nx_state = ST_PULSE_HOLD_1;
        end
        ST_PULSE_HOLD_1: begin
            // Hold the GO signal and auxiliary for this cycle.
            s_go_stand_val = s_go_stand_aux;
            s_tx_len_val = s_tx_len_aux;
            s_rx_len_val = s_rx_len_aux;
            s_wait_cyc_val = s_wait_cyc_aux;
            s_dat_nx_state = ST_PULSE_HOLD_2;
        end
        ST_PULSE_HOLD_2: begin
            // Hold the GO signal and auxiliary for this cycle.
            s_go_stand_val = s_go_stand_aux;
            s_tx_len_val = s_tx_len_aux;
            s_rx_len_val = s_rx_len_aux;
            s_wait_cyc_val = s_wait_cyc_aux;
            s_dat_nx_state = ST_PULSE_HOLD_3;
        end
        ST_PULSE_HOLD_3: begin
            // Reset the GO signal and and hold the auxiliary for this cycle.
            s_go_stand_val = 1'b0;
            s_tx_len_val = s_tx_len_aux;
            s_rx_len_val = s_rx_len_aux;
            s_wait_cyc_val = s_wait_cyc_aux;
            s_dat_nx_state = ST_PULSE_WAIT;
        end

        default: begin // ST_PULSE_WAIT
            // If GO signal is 1, assign it and the auxiliary on the
            // transition to the first HOLD state. Otherwise, hold
            // the values already assigned.
            if (sdrv.go_stand) begin
                s_go_stand_val = sdrv.go_stand;
                s_tx_len_val = sdrv.tx_len;
                s_rx_len_val = sdrv.rx_len;
                s_wait_cyc_val = sdrv.wait_cyc;
                s_dat_nx_state = ST_PULSE_HOLD_0;
            end else begin
                s_go_stand_val = s_go_stand_aux;
                s_tx_len_val = s_tx_len_aux;
                s_rx_len_val = s_rx_len_aux;
                s_wait_cyc_val = s_wait_cyc_aux;
                s_dat_nx_state = ST_PULSE_WAIT;
            end
        end
    endcase
end : p_dat_fsm_comb

// SPI bus control state machine assignments for falling edge of 1x clock
// assignment of state value, plus delayed state value for the RX capture
// on the SPI rising edge of 1x clock in a different process.
always_ff @(posedge i_ext_spi_clk_x)
begin: p_spi_fsm_state
    if (i_srst) begin
        s_spi_pr_state_delayed3 <= ST_STAND_IDLE;
        s_spi_pr_state_delayed2 <= ST_STAND_IDLE;
        s_spi_pr_state_delayed1 <= ST_STAND_IDLE;
        s_spi_pr_state <= ST_STAND_IDLE;
    end else begin  : if_fsm_state_and_delayed
        // The delayed state value allows for registration of TX clock
        // and double registration of RX value to capture after the
        // registration of outputs and synchronization of inputs.
        if (s_spi_ce_4x) begin
            s_spi_pr_state_delayed3 <= s_spi_pr_state_delayed2;
            s_spi_pr_state_delayed2 <= s_spi_pr_state_delayed1;
            s_spi_pr_state_delayed1 <= s_spi_pr_state;
        end

        // clock enable on falling SPI edge for state change
        if (s_spi_clk_ce2)
            s_spi_pr_state <= s_spi_nx_state;
    end : if_fsm_state_and_delayed
end : p_spi_fsm_state

// SPI bus control state machine assignments for combinatorial assignment to
// SPI bus outputs, timing of chip select, transmission of TX data,
// holding for wait cycles, and timing for RX data where RX data is captured
// in a different synchronous state machine delayed from the state of this
// machine.
always_comb
begin: p_spi_fsm_comb
    case (s_spi_pr_state)
        ST_STAND_START_D: begin
            // halt clock at Mode 0
            eo_sck_o = 1'b0;
            eo_sck_t = 1'b0;
            // no chip select
            eo_csn_o = 1'b1;
            eo_csn_t = 1'b0;
            // zero value for COPI
            eo_copi_o = 1'b0;
            eo_copi_t = 1'b0;
            // hold not reading the TX FIFO
            s_data_fifo_tx_re = 1'b0;
            // machine is not idle
            s_spi_idle = 1'b0;

            // time the chip not selected start time
            if (s_t == c_t_stand_wait_ss - c_t_inc)
                s_spi_nx_state = ST_STAND_START_S;
            else s_spi_nx_state = ST_STAND_START_D;
        end

        ST_STAND_START_S: begin
            // halt clock at Mode 0
            eo_sck_o = 1'b0;
            eo_sck_t = 1'b0;
            // assert chip select
            eo_csn_o = 1'b0;
            eo_csn_t = 1'b0;
            // zero value for COPI
            eo_copi_o = 1'b0;
            eo_copi_t = 1'b0;
            // hold not reading the TX FIFO
            s_data_fifo_tx_re = 1'b0;
            // machine is not idle
            s_spi_idle = 1'b0;

            // start reading the TX FIFO only on transition to next state
            s_data_fifo_tx_re = ((s_t == c_t_stand_wait_ss - c_t_inc) &&
                (s_data_fifo_tx_empty == 1'b0)) ? s_spi_clk_ce3 : 1'b0;

            // time the chip selected start time
            if (s_t == c_t_stand_wait_ss - c_t_inc)
                s_spi_nx_state = ST_STAND_TX;
            else s_spi_nx_state = ST_STAND_START_S;
        end

        ST_STAND_TX: begin
            // run clock at Mode 0
            eo_sck_o = s_spi_clk_1x;
            eo_sck_t = 1'b0;
            // assert chip select
            eo_csn_o = 1'b0;
            eo_csn_t = 1'b0;
            // data value for COPI, muxing the TX FIFO 8-bits ready to TX
            eo_copi_o = (s_t < 8 * s_tx_len_aux) ? s_data_fifo_tx_out[7 - (s_t % 8)] : 1'b0;
            eo_copi_t = 1'b0;

            // machine is not idle
            s_spi_idle = 1'b0;

            // read byte by byte from the TX FIFO
            // only if on last bit, dequeue another byte
            s_data_fifo_tx_re = ((s_t != (8 * s_tx_len_aux) - c_t_inc) && (s_t % 8 == 7) &&
                (s_data_fifo_tx_empty == 1'b0)) ? s_spi_clk_ce2 : 1'b0;

            // If every bit from the FIFO according to sdrv.tx_len value captured
            // in s_tx_len_aux, then move to either WAIT, RX, or STOP.
            if (s_t == (8 * s_tx_len_aux) - c_t_inc)
                if (s_rx_len_aux > 0)
                    if (s_wait_cyc_aux > 0)
                        s_spi_nx_state = ST_STAND_WAIT;
                    else
                        s_spi_nx_state = ST_STAND_RX;
                else
                    s_spi_nx_state = ST_STAND_STOP_S;
            else
                s_spi_nx_state = ST_STAND_TX;
        end

        ST_STAND_WAIT: begin
            // run clock at Mode 0
            eo_sck_o = s_spi_clk_1x;
            eo_sck_t = 1'b0;
            // assert chip select
            eo_csn_o = 1'b0;
            eo_csn_t = 1'b0;
            // zero value for COPI
            eo_copi_o = 1'b0;
            eo_copi_t = 1'b0;
            // hold not reading the TX FIFO
            s_data_fifo_tx_re = 1'b0;
            // machine is not idle
            s_spi_idle = 1'b0;

            // time the wait duration and then move to RX
            if (s_t == s_wait_cyc_aux - c_t_inc) s_spi_nx_state = ST_STAND_RX;
            else s_spi_nx_state = ST_STAND_WAIT;
        end

        ST_STAND_RX: begin
            // run clock at Mode 0
            eo_sck_o = s_spi_clk_1x;
            eo_sck_t = 1'b0;
            // assert chip select
            eo_csn_o = 1'b0;
            eo_csn_t = 1'b0;
            // zero value for COPI
            eo_copi_o = 1'b0;
            eo_copi_t = 1'b0;
            // hold not reading the TX FIFO
            s_data_fifo_tx_re = 1'b0;
            // machine is not idle
            s_spi_idle = 1'b0;

            // time the RX bit count and then begin deselect SPI chip
            if (s_t == (8 * s_rx_len_aux) - c_t_inc)
                s_spi_nx_state = ST_STAND_STOP_S;
            else s_spi_nx_state = ST_STAND_RX;
        end

        ST_STAND_STOP_S: begin
            // halt clock at Mode 0
            eo_sck_o = 1'b0;
            eo_sck_t = 1'b0;
            // assert chip select
            eo_csn_o = 1'b0;
            eo_csn_t = 1'b0;
            // zero value for COPI
            eo_copi_o = 1'b0;
            eo_copi_t = 1'b0;
            // hold not reading the TX FIFO
            s_data_fifo_tx_re = 1'b0;
            // machine is not idle
            s_spi_idle = 1'b0;

            // wait the chip selected delay time
            if (s_t == c_t_stand_wait_ss - c_t_inc)
                s_spi_nx_state = ST_STAND_STOP_D;
            else s_spi_nx_state = ST_STAND_STOP_S;
        end

        ST_STAND_STOP_D: begin
            // halt clock at Mode 0
            eo_sck_o = 1'b0;
            eo_sck_t = 1'b0;
            // no chip select
            eo_csn_o = 1'b1;
            eo_csn_t = 1'b0;
            // zero value for COPI
            eo_copi_o = 1'b0;
            eo_copi_t = 1'b0;
            // hold not reading the TX FIFO
            s_data_fifo_tx_re = 1'b0;
            // machine is not idle
            s_spi_idle = 1'b0;

            // the chip not selected stop time
            if (s_t == c_t_stand_wait_ss - c_t_inc)
                s_spi_nx_state = ST_STAND_IDLE;
            else s_spi_nx_state = ST_STAND_STOP_D;
        end

        default: begin // ST_STAND_IDLE
            // halt clock at Mode 0
            eo_sck_o = 1'b0;
            eo_sck_t = 1'b0;
            // no chip select
            eo_csn_o = 1'b1;
            eo_csn_t = 1'b0;
            // zero value for COPI
            eo_copi_o = 1'b0;
            eo_copi_t = 1'b0;
            // hold not reading the TX FIFO
            s_data_fifo_tx_re = 1'b0;
            // machine is idle
            s_spi_idle = 1'b1;

            // run the SPI cycle only if \ref s_go_stand is pulsed while idle
            if (s_go_stand) s_spi_nx_state = ST_STAND_START_D;
            else s_spi_nx_state = ST_STAND_IDLE;
        end
    endcase
end : p_spi_fsm_comb

// Captures the RX inputs into the RX fifo.
// Note that the RX inputs are delayed by 3 clk_4x clock cycles
// before the delay, the falling edge would occur at the capture of
// clock enable 0; but with the delay of registering output and double
// registering input, the FSM state is delayed by 3 clock cycles for
// RX only and the clock enable to process on the effective falling edge of
// the bus SCK as perceived from propagation out and back in, is 3 clock
// cycles, thus CE 3 instead of CE 0.
always_ff @(posedge i_ext_spi_clk_x)
begin: p_spi_fsm_inputs
    if (i_srst) begin
        s_data_fifo_rx_we <= 1'b0;
        s_data_fifo_rx_in <= 8'h00;
    end else
        if (s_spi_clk_ce3)
            if (s_spi_pr_state_delayed3 == ST_STAND_RX) begin : if_shift_in_rx_data_to_fifo
                // input current byte to enqueue, one bit at a time, shifting
                s_data_fifo_rx_in <= (s_t_delayed3 < (8 * s_rx_len_aux)) ?
                    {s_data_fifo_rx_in[6-:7], ei_cipo_i} : 8'h00;

                // only if on last bit, enqueue another byte
                // only if RX FIFO is not full, enqueue another byte
                s_data_fifo_rx_we <= ((s_t_delayed3 % 8 == 7) &&
                    (s_data_fifo_rx_full == 1'b0)) ? 1'b1 : 1'b0;
            end : if_shift_in_rx_data_to_fifo
            else begin : if_rx_hold_we_low_without_data
                s_data_fifo_rx_we <= 1'b0;
                s_data_fifo_rx_in <= 8'h00;
            end : if_rx_hold_we_low_without_data
        else begin : if_rx_hold_we_low_with_data
            s_data_fifo_rx_we <= 1'b0;
            s_data_fifo_rx_in <= s_data_fifo_rx_in;
        end : if_rx_hold_we_low_with_data
end : p_spi_fsm_inputs

endmodule : pmod_generic_spi_solo
//------------------------------------------------------------------------------
`end_keywords
