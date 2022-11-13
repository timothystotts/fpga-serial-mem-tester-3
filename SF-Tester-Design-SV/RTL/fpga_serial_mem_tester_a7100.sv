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
-- \file fpga_serial_acl_tester_a7100.sv
--
-- \brief A FPGA top-level design with the PMOD ACL2 custom driver.
-- This design operates the ADXL362 in one of multiple possible operational
-- modes for Accelerometer data capture. The PMOD CLS is used to display raw
-- data for: X-Axis, Y-Axis, Z-Axis, Temperature. Color and basic LEDs
-- are used to display additional information, including Activity and Inactivity
-- motion detection.
------------------------------------------------------------------------------*/
//------------------------------------------------------------------------------
`begin_keywords "1800-2012"
//Multiple Moore Machines
//Part 1: Module header:--------------------------------------------------------
module fpga_serial_mem_tester_a7100
  import pmod_stand_spi_solo_pkg::*;
  import pmod_quad_spi_solo_pkg::*;
  import sf_tester_fsm_pkg::*;
	#(parameter
		integer parm_fast_simulation = 0)
	(
  // external clock and active-low reset 
	input logic CLK100MHZ,
	input logic i_resetn,
	// PMOD ACL2 SPI bus 4-wire and two interrupt signals
	output logic eo_pmod_sf3_sck,
	output logic eo_pmod_sf3_csn,
	inout logic eio_pmod_sf3_copi_dq0,
	inout logic eio_pmod_sf3_cipo_dq1,
  inout logic eio_pmod_sf3_wrpn_dq2,
  inout logic eio_pmod_sf3_hldn_dq3,
	// blue LEDs of the multicolor
	output logic eo_led0_b,
	output logic eo_led1_b,
	output logic eo_led2_b,
	output logic eo_led3_b,
	// red LEDs of the multicolor
	output logic eo_led0_r,
	output logic eo_led1_r,
	output logic eo_led2_r,
	output logic eo_led3_r,
	// green LEDs of the multicolor
	output logic eo_led0_g,
	output logic eo_led1_g,
	output logic eo_led2_g,
	output logic eo_led3_g,
	// green LEDs of the regular LEDs
	output logic eo_led4,
	output logic eo_led5,
	output logic eo_led6,
	output logic eo_led7,
	// four switches
	input logic ei_sw0,
	input logic ei_sw1,
	input logic ei_sw2,
	input logic ei_sw3,
	// four buttons
	input logic ei_bt0,
	input logic ei_bt1,
	input logic ei_bt2,
	input logic ei_bt3,
	// PMOD CLS SPI bus 4-wire
	output logic eo_pmod_cls_csn,
	output logic eo_pmod_cls_sck,
	output logic eo_pmod_cls_dq0,
	input logic ei_pmod_cls_dq1,
	// Arty A7-100T UART TX and RX signals
	output logic eo_uart_tx,
	input logic ei_uart_rx);

//Part 2: Declarations----------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

// Disable or enable fast FSM delays for simulation instead of impelementation. 
localparam integer c_FCLK = 40000000;

// MMCM and Processor System Reset signals for PLL clock generation from the
// Clocking Wizard and Synchronous Reset generation from the Processor System
// Reset module. 
logic s_mmcm_locked;
logic s_clk_40mhz;
logic s_rst_40mhz;
logic s_clk_7_37mhz;
logic s_rst_7_37mhz;
logic s_cls_ce_mhz;
logic s_sf3_ce_div;

// Extra MMCM signals for full port map to the MMCM primative,
// where these signals will remain disconnected. 
logic s_clk_ignore_clk0b;
logic s_clk_ignore_clk1b;
logic s_clk_ignore_clk2;
logic s_clk_ignore_clk2b;
logic s_clk_ignore_clk3;
logic s_clk_ignore_clk3b;
logic s_clk_ignore_clk4;
logic s_clk_ignore_clk5;
logic s_clk_ignore_clk6;
logic s_clk_ignore_clkfboutb;
logic s_clk_clkfbout;
logic s_clk_pwrdwn;
logic s_clk_resetin;

// SPI signals to external tri-state
logic sio_sf3_sck_o;
logic sio_sf3_sck_t;
logic sio_sf3_csn_o;
logic sio_sf3_csn_t;
logic sio_sf3_copi_dq0_o;
logic sio_sf3_copi_dq0_i;
logic sio_sf3_copi_dq0_t;
logic sio_sf3_cipo_dq1_o;
logic sio_sf3_cipo_dq1_i;
logic sio_sf3_cipo_dq1_t;
logic sio_sf3_wrpn_dq2_o;
logic sio_sf3_wrpn_dq2_i;
logic sio_sf3_wrpn_dq2_t;
logic sio_sf3_hldn_dq3_o;
logic sio_sf3_hldn_dq3_i;
logic sio_sf3_hldn_dq3_t;

// Signals for communication with SF3 customer driver
logic s_sf3_command_ready;
logic [31:0] s_sf3_address_of_cmd;
logic s_sf3_cmd_erase_subsector;
logic s_sf3_cmd_page_program;
logic s_sf3_cmd_random_read;
logic [8:0] s_sf3_len_random_read;
logic [7:0] s_sf3_wr_data_stream;
logic s_sf3_wr_data_valid;
logic s_sf3_wr_data_ready;
logic [7:0] s_sf3_rd_data_stream;
logic s_sf3_rd_data_valid;
logic [7:0] s_sf3_reg_status;
logic [7:0] s_sf3_reg_flag;

// CLS Clock Enable speed for driving CE of CLS customer driver
// and text feed.
localparam integer c_cls_display_ce_div_ratio = (c_FCLK / 50000 / 4);

// Signals for controlling the PMOD CLS custom driver.
logic s_cls_command_ready;
logic s_cls_wr_clear_display;
logic s_cls_wr_text_line1;
logic s_cls_wr_text_line2;
logic [(16*8-1):0] s_cls_txt_ascii_line1;
logic [(16*8-1):0] s_cls_txt_ascii_line2;
logic s_cls_feed_is_idle;

// Connections for inferring tri-state buffer for CLS SPI bus outputs. 
logic so_pmod_cls_sck_o;
logic so_pmod_cls_sck_t;
logic so_pmod_cls_csn_o;
logic so_pmod_cls_csn_t;
logic so_pmod_cls_copi_o;
logic so_pmod_cls_copi_t;

// switch inputs debounced 
logic [3:0] si_switches;
logic [3:0] s_sw_deb;

// switch inputs debounced 
logic [3:0] si_buttons;
logic [3:0] s_btns_deb;

// SF3 clock enable division down from 40 MHz
localparam integer c_sf3_tester_ce_div_ratio = (c_FCLK / 5000000 / 4);

// SF3 Tester FSM state outputs
t_tester_state s_sf3_tester_pr_state;
logic [31:0] s_sf3_addr_start;
logic [7:0] s_sf3_pattern_start;
logic [7:0] s_sf3_pattern_incr;
logic [$clog2(c_max_possible_byte_count)-1:0] s_sf3_error_count;
logic s_sf3_test_pass;
logic s_sf3_test_done;

// Color palette signals to connect \ref led_palette_pulser to \ref
// led_pwm_driver . 
logic [(4*8-1):0] s_color_led_red_value;
logic [(4*8-1):0] s_color_led_green_value;
logic [(4*8-1):0] s_color_led_blue_value;
logic [(4*8-1):0] s_basic_led_lumin_value;

/* UART TX signals to connect \ref uart_tx_only and \ref uart_tx_feed */
logic [(35*8-1):0] s_uart_txt_ascii_line;
logic s_uart_tx_go;
logic [7:0] s_uart_txdata;
logic s_uart_txvalid;
logic s_uart_txready;

//Part 3: Statements------------------------------------------------------------
assign s_clk_pwrdwn = 1'b0;
assign s_clk_resetin = (! i_resetn);

// MMCME2_BASE: Base Mixed Mode Clock Manager
//              Artix-7
// Xilinx HDL Language Template, version 2019.1

MMCME2_BASE #(
  .BANDWIDTH("OPTIMIZED"),   // Jitter programming (OPTIMIZED, HIGH, LOW)
  .CLKFBOUT_MULT_F(43.5),  // Multiply value for all CLKOUT (2.000-64.000).
  .CLKFBOUT_PHASE(0.0),      // Phase offset in degrees of CLKFB (-360.000-360.000).
  .CLKIN1_PERIOD(10.0),      // Input clock period in ns to ps resolution (i.e. 33.333 is 30 MHz).
  // CLKOUT0_DIVIDE - CLKOUT6_DIVIDE: Divide amount for each CLKOUT (1-128)
  .CLKOUT1_DIVIDE(118),
  .CLKOUT2_DIVIDE(1),
  .CLKOUT3_DIVIDE(1),
  .CLKOUT4_DIVIDE(1),
  .CLKOUT5_DIVIDE(1),
  .CLKOUT6_DIVIDE(1),
  .CLKOUT0_DIVIDE_F(21.750),  // Divide amount for CLKOUT0 (1.000-128.000).
  // CLKOUT0_DUTY_CYCLE - CLKOUT6_DUTY_CYCLE: Duty cycle for each CLKOUT (0.01-0.99).
  .CLKOUT0_DUTY_CYCLE(0.5),
  .CLKOUT1_DUTY_CYCLE(0.5),
  .CLKOUT2_DUTY_CYCLE(0.5),
  .CLKOUT3_DUTY_CYCLE(0.5),
  .CLKOUT4_DUTY_CYCLE(0.5),
  .CLKOUT5_DUTY_CYCLE(0.5),
  .CLKOUT6_DUTY_CYCLE(0.5),
  // CLKOUT0_PHASE - CLKOUT6_PHASE: Phase offset for each CLKOUT (-360.000-360.000).
  .CLKOUT0_PHASE(0.0),
  .CLKOUT1_PHASE(0.0),
  .CLKOUT2_PHASE(0.0),
  .CLKOUT3_PHASE(0.0),
  .CLKOUT4_PHASE(0.0),
  .CLKOUT5_PHASE(0.0),
  .CLKOUT6_PHASE(0.0),
  .CLKOUT4_CASCADE("FALSE"), // Cascade CLKOUT4 counter with CLKOUT6 (FALSE, TRUE)
  .DIVCLK_DIVIDE(5),         // Master division value (1-106)
  .REF_JITTER1(0.010),       // Reference input jitter in UI (0.000-0.999).
  .STARTUP_WAIT("FALSE")     // Delays DONE until MMCM is locked (FALSE, TRUE)
)
MMCME2_BASE_inst (
  // Clock Outputs: 1-bit (each) output: User configurable clock outputs
  .CLKOUT0(s_clk_40mhz),              // 1-bit output: CLKOUT0
  .CLKOUT0B(s_clk_ignore_clk0b),      // 1-bit output: Inverted CLKOUT0
  .CLKOUT1(s_clk_7_37mhz),            // 1-bit output: CLKOUT1
  .CLKOUT1B(s_clk_ignore_clk1b),      // 1-bit output: Inverted CLKOUT1
  .CLKOUT2(s_clk_ignore_clk2),        // 1-bit output: CLKOUT2
  .CLKOUT2B(s_clk_ignore_clk2b),      // 1-bit output: Inverted CLKOUT2
  .CLKOUT3(s_clk_ignore_clk3),        // 1-bit output: CLKOUT3
  .CLKOUT3B(s_clk_ignore_clk3b),      // 1-bit output: Inverted CLKOUT3
  .CLKOUT4(s_clk_ignore_clk4),        // 1-bit output: CLKOUT4
  .CLKOUT5(s_clk_ignore_clk5),        // 1-bit output: CLKOUT5
  .CLKOUT6(s_clk_ignore_clk6),        // 1-bit output: CLKOUT6
  // Feedback Clocks: 1-bit (each) output: Clock feedback ports
  .CLKFBOUT(s_clk_clkfbout),          // 1-bit output: Feedback clock
  .CLKFBOUTB(s_clk_ignore_clkfboutb), // 1-bit output: Inverted CLKFBOUT
  // Status Ports: 1-bit (each) output: MMCM status ports
  .LOCKED(s_mmcm_locked),             // 1-bit output: LOCK
  // Clock Inputs: 1-bit (each) input: Clock input
  .CLKIN1(CLK100MHZ),                 // 1-bit input: Clock
  // Control Ports: 1-bit (each) input: MMCM control ports
  .PWRDWN(s_clk_pwrdwn),              // 1-bit input: Power-down
  .RST(s_clk_resetin),                // 1-bit input: Reset
  // Feedback Clocks: 1-bit (each) input: Clock feedback ports
  .CLKFBIN(s_clk_clkfbout)            // 1-bit input: Feedback clock
);

// End of MMCME2_BASE_inst instantiation

// Reset Synchronization for 40 MHz clock. 
arty_reset_synchronizer #() u_reset_synch_40mhz(
	.i_clk_mhz(s_clk_40mhz),
	.i_rstn_global(i_resetn),
	.o_rst_mhz(s_rst_40mhz)
	);

// Reset Synchronization for 7.37 MHz clock. 
arty_reset_synchronizer #() u_reset_synch_7_37mhz (
	.i_clk_mhz(s_clk_7_37mhz),
	.i_rstn_global(i_resetn),
	.o_rst_mhz(s_rst_7_37mhz)
	);

// Color and Basic LED operation by 8-bit scalar per emitter
led_pwm_driver #(
  .parm_color_led_count(4),
  .parm_basic_led_count(4),
  .parm_FCLK(c_FCLK),
  .parm_pwm_period_milliseconds(10)
  ) u_led_pwm_driver (
  .i_clk(s_clk_40mhz),
  .i_srst(s_rst_40mhz),
  .i_color_led_red_value(s_color_led_red_value),
  .i_color_led_green_value(s_color_led_green_value),
  .i_color_led_blue_value(s_color_led_blue_value),
  .i_basic_led_lumin_value(s_basic_led_lumin_value),
  .eo_color_leds_r({eo_led3_r, eo_led2_r, eo_led1_r, eo_led0_r}),
  .eo_color_leds_g({eo_led3_g, eo_led2_g, eo_led1_g, eo_led0_g}),
  .eo_color_leds_b({eo_led3_b, eo_led2_b, eo_led1_b, eo_led0_b}),
  .eo_basic_leds_l({eo_led7, eo_led6, eo_led5, eo_led4})
  );

// 4x spi clock enable divider for PMOD CLS SCK output. No
// generated clock constraint. The 40 MHz clock is divided
// down to 2.5 MHz clock enable; and later divided down to
// 625 KHz on the PMOD CLS bus.
clock_enable_divider #(
  .par_ce_divisor(c_cls_display_ce_div_ratio)
  ) u_cls_ce_divider (
	.o_ce_div(s_cls_ce_mhz),
	.i_clk_mhz(s_clk_40mhz),
	.i_rst_mhz(s_rst_40mhz),
	.i_ce_mhz(1'b1));

// 4x spi clock enable divider for PMOD SF3 SCK output. No
// generated clock constraint. The 40 MHz clock is divided
// down to 20 MHz clock enable; and later divided down to
// 5 MHz on the PMOD SF3 bus.
clock_enable_divider #(
  .par_ce_divisor(c_sf3_tester_ce_div_ratio)
  ) u_sf3_ce_divider (
  .o_ce_div(s_sf3_ce_div),
  .i_clk_mhz(s_clk_40mhz),
  .i_rst_mhz(s_rst_40mhz),
  .i_ce_mhz(1'b1));

// Synchronize and debounce the four input buttons on the Arty A7 to be
// debounced and exclusive of each other (ignored if more than one
// selected at the same time).
assign si_buttons = {ei_bt3, ei_bt2, ei_bt1, ei_bt0};

multi_input_debounce #(
  .FCLK(c_FCLK)
  ) u_buttons_deb_0123 (
    .i_clk_mhz(s_clk_40mhz),
    .i_rst_mhz(s_rst_40mhz),
    .ei_buttons(si_buttons),
    .o_btns_deb(s_btns_deb)
    );

// Synchronize and debounce the four input switches on the Arty A7 to be
// debounced and exclusive of each other (ignored if more than one
// selected at the same time).
assign si_switches = {ei_sw3, ei_sw2, ei_sw1, ei_sw0};

multi_input_debounce #(
  .FCLK(c_FCLK)
  ) u_switches_deb_0123 (
    .i_clk_mhz(s_clk_40mhz),
    .i_rst_mhz(s_rst_40mhz),
    .ei_buttons(si_switches),
    .o_btns_deb(s_sw_deb)
    );

// Tri-state outputs of PMOD CLS custom driver.
assign eo_pmod_cls_sck = so_pmod_cls_sck_t ? 1'bz : so_pmod_cls_sck_o;
assign eo_pmod_cls_csn = so_pmod_cls_csn_t ? 1'bz : so_pmod_cls_csn_o;
assign eo_pmod_cls_dq0 = so_pmod_cls_copi_t ? 1'bz : so_pmod_cls_copi_o;

// Instance of the PMOD CLS driver for 16x2 character LCD display for purposes
// of an output display.
pmod_cls_custom_driver #(
  .parm_fast_simulation(parm_fast_simulation),
  .parm_FCLK(c_FCLK),
  .parm_FCLK_ce(c_FCLK / c_cls_display_ce_div_ratio),
  .parm_ext_spi_clk_ratio(c_cls_display_ce_div_ratio * 4)
  // Note: old parameter mapping of *_count_bits was moved to be declared
  // as a SystemVerilog interface defined within package
  // pmod_stand_spi_solo_pkg.
  ) u_pmod_cls_custom_driver (
  .i_clk_40mhz(s_clk_40mhz),
  .i_rst_40mhz(s_rst_40mhz),
  .i_ce_mhz(s_cls_ce_mhz),
  .eo_sck_t(so_pmod_cls_sck_t),
  .eo_sck_o(so_pmod_cls_sck_o),
  .eo_csn_t(so_pmod_cls_csn_t),
  .eo_csn_o(so_pmod_cls_csn_o),
  .eo_copi_t(so_pmod_cls_copi_t),
  .eo_copi_o(so_pmod_cls_copi_o),
  .ei_cipo(ei_pmod_cls_dq1),
  .o_command_ready(s_cls_command_ready),
  .i_cmd_wr_clear_display(s_cls_wr_clear_display),
  .i_cmd_wr_text_line1(s_cls_wr_text_line1),
  .i_cmd_wr_text_line2(s_cls_wr_text_line2),
  .i_dat_ascii_line1(s_cls_txt_ascii_line1),
  .i_dat_ascii_line2(s_cls_txt_ascii_line2));

// Custom driver for the PMOD SF3 enabling erase of a subsector,
// programming the data of a page, and reading the data of a page.
// Note that each subsector contains 16 successive pages.
pmod_sf3_custom_driver #(
  .parm_fast_simulation(parm_fast_simulation),
  .parm_FCLK(c_FCLK),
  .parm_ext_spi_clk_ratio(c_sf3_tester_ce_div_ratio * 4)
  // Note: old parameter mapping of *_count_bits was moved to be declared
  // as a SystemVerilog interface defined within package
  // pmod_quad_spi_solo_pkg.
  ) u_pmod_sf3_custom_driver (
  .i_clk_mhz(s_clk_40mhz),
  .i_rst_mhz(s_rst_40mhz),
  .i_ce_mhz_div(s_sf3_ce_div),
  .eio_sck_o(sio_sf3_sck_o),
  .eio_sck_t(sio_sf3_sck_t),
  .eio_csn_o(sio_sf3_csn_o),
  .eio_csn_t(sio_sf3_csn_t),
  .eio_copi_dq0_o(sio_sf3_copi_dq0_o),
  .eio_copi_dq0_i(sio_sf3_copi_dq0_i),
  .eio_copi_dq0_t(sio_sf3_copi_dq0_t),
  .eio_cipo_dq1_o(sio_sf3_cipo_dq1_o),
  .eio_cipo_dq1_i(sio_sf3_cipo_dq1_i),
  .eio_cipo_dq1_t(sio_sf3_cipo_dq1_t),
  .eio_wrpn_dq2_o(sio_sf3_wrpn_dq2_o),
  .eio_wrpn_dq2_i(sio_sf3_wrpn_dq2_i),
  .eio_wrpn_dq2_t(sio_sf3_wrpn_dq2_t),
  .eio_hldn_dq3_o(sio_sf3_hldn_dq3_o),
  .eio_hldn_dq3_i(sio_sf3_hldn_dq3_i),
  .eio_hldn_dq3_t(sio_sf3_hldn_dq3_t),
  .o_command_ready(s_sf3_command_ready),
  .i_address_of_cmd(s_sf3_address_of_cmd),
  .i_cmd_erase_subsector(s_sf3_cmd_erase_subsector),
  .i_cmd_page_program(s_sf3_cmd_page_program),
  .i_cmd_random_read(s_sf3_cmd_random_read),
  .i_len_random_read(s_sf3_len_random_read),
  .i_wr_data_stream(s_sf3_wr_data_stream),
  .i_wr_data_valid(s_sf3_wr_data_valid),
  .o_wr_data_ready(s_sf3_wr_data_ready),
  .o_rd_data_stream(s_sf3_rd_data_stream),
  .o_rd_data_valid(s_sf3_rd_data_valid),
  .o_reg_status(s_sf3_reg_status),
  .o_reg_flag(s_sf3_reg_flag)
  );

// PMOD SF3 Quad SPI tri-state inout connections for QSPI bus
assign eo_pmod_sf3_sck = sio_sf3_sck_t ? 1'bz : sio_sf3_sck_o;
assign eo_pmod_sf3_csn = sio_sf3_csn_t ? 1'bz : sio_sf3_csn_o;

assign eio_pmod_sf3_copi_dq0 = sio_sf3_copi_dq0_t ? 1'bz : sio_sf3_copi_dq0_o;
assign sio_sf3_copi_dq0_i = eio_pmod_sf3_copi_dq0;

assign eio_pmod_sf3_cipo_dq1 = sio_sf3_cipo_dq1_t ? 1'bz : sio_sf3_cipo_dq1_o;
assign sio_sf3_cipo_dq1_i = eio_pmod_sf3_cipo_dq1;

assign eio_pmod_sf3_wrpn_dq2 = sio_sf3_wrpn_dq2_t ? 1'bz : sio_sf3_wrpn_dq2_o;
assign sio_sf3_wrpn_dq2_i = eio_pmod_sf3_wrpn_dq2;

assign eio_pmod_sf3_hldn_dq3 = sio_sf3_hldn_dq3_t ? 1'bz : sio_sf3_hldn_dq3_o;
assign sio_sf3_hldn_dq3_i = eio_pmod_sf3_hldn_dq3;

/* Tester FSM to operate the states of the Pmod SF3 based on user input */
sf_tester_fsm #(
  .parm_fast_simulation(parm_fast_simulation),
  .parm_FCLK(c_FCLK),
  .parm_sf3_tester_ce_div_ratio(c_sf3_tester_ce_div_ratio),
  .parm_pattern_startval_a(c_tester_pattern_startval_a),
  .parm_pattern_incrval_a(c_tester_pattern_incrval_a),
  .parm_pattern_startval_b(c_tester_pattern_startval_b),
  .parm_pattern_incrval_b(c_tester_pattern_incrval_b),
  .parm_pattern_startval_c(c_tester_pattern_startval_c),
  .parm_pattern_incrval_c(c_tester_pattern_incrval_c),
  .parm_pattern_startval_d(c_tester_pattern_startval_d),
  .parm_pattern_incrval_d(c_tester_pattern_incrval_d),
  .parm_max_possible_byte_count(c_max_possible_byte_count),
  .parm_tester_page_cnt_per_iter(c_tester_page_cnt_per_iter)
  ) u_sf_tester_fsm (
  .i_clk_40mhz(s_clk_40mhz),
  .i_rst_40mhz(s_rst_40mhz),
  .i_ce_div(s_sf3_ce_div),
  .i_sf3_command_ready(s_sf3_command_ready),
  .i_sf3_rd_data_valid(s_sf3_rd_data_valid),
  .i_sf3_rd_data_stream(s_sf3_rd_data_stream),
  .i_sf3_wr_data_ready(s_sf3_wr_data_ready),
  .o_sf3_wr_data_stream(s_sf3_wr_data_stream),
  .o_sf3_wr_data_valid(s_sf3_wr_data_valid),
  .o_sf3_len_random_read(s_sf3_len_random_read),
  .o_sf3_cmd_random_read(s_sf3_cmd_random_read),
  .o_sf3_cmd_page_program(s_sf3_cmd_page_program),
  .o_sf3_cmd_erase_subsector(s_sf3_cmd_erase_subsector),
  .o_sf3_address_of_cmd(s_sf3_address_of_cmd),
  .i_buttons_debounced(s_btns_deb),
  .i_switches_debounced(s_sw_deb),
  .o_tester_pr_state(s_sf3_tester_pr_state),
  .o_addr_start(s_sf3_addr_start),
  .o_pattern_start(s_sf3_pattern_start),
  .o_pattern_incr(s_sf3_pattern_incr),
  .o_error_count(s_sf3_error_count),
  .o_test_pass(s_sf3_test_pass),
  .o_test_done(s_sf3_test_done)
  );

// LED Palette Updater
led_palette_updater #(
  .parm_color_led_count(4),
  .parm_basic_led_count(4)
  ) u_led_palette_updater (
  .i_clk(s_clk_40mhz),
  .i_srst(s_rst_40mhz),
  .o_color_led_red_value(s_color_led_red_value),
  .o_color_led_green_value(s_color_led_green_value),
  .o_color_led_blue_value(s_color_led_blue_value),
  .o_basic_led_lumin_value(s_basic_led_lumin_value),
  .i_test_pass(s_sf3_test_pass),
  .i_test_done(s_sf3_test_done),
  .i_tester_pr_state(s_sf3_tester_pr_state)
  );

// SF3 Testing to ASCII outputs
sf_testing_to_ascii#(
  .parm_pattern_startval_a(c_tester_pattern_startval_a),
  .parm_pattern_incrval_a(c_tester_pattern_incrval_a),
  .parm_pattern_startval_b(c_tester_pattern_startval_b),
  .parm_pattern_incrval_b(c_tester_pattern_incrval_b),
  .parm_pattern_startval_c(c_tester_pattern_startval_c),
  .parm_pattern_incrval_c(c_tester_pattern_incrval_c),
  .parm_pattern_startval_d(c_tester_pattern_startval_d),
  .parm_pattern_incrval_d(c_tester_pattern_incrval_d),
  .parm_max_possible_byte_count(c_max_possible_byte_count)
  ) u_sf_testing_to_ascii (
  .i_clk_40mhz(s_clk_40mhz),
  .i_rst_40mhz(s_rst_40mhz),
  .i_addr_start(s_sf3_addr_start),
  .i_pattern_start(s_sf3_pattern_start),
  .i_pattern_incr(s_sf3_pattern_incr),
  .i_error_count(s_sf3_error_count),
  .i_tester_pr_state(s_sf3_tester_pr_state),
  .o_lcd_ascii_line1(s_cls_txt_ascii_line1),
  .o_lcd_ascii_line2(s_cls_txt_ascii_line2),
  .o_term_ascii_line(s_uart_txt_ascii_line)
  );

// LCD Update FSM
lcd_text_feed #(
  .parm_fast_simulation(parm_fast_simulation),
  .parm_FCLK_ce(c_FCLK / c_cls_display_ce_div_ratio)
  ) u_lcd_text_feed (
  .i_clk_40mhz(s_clk_40mhz),
  .i_rst_40mhz(s_rst_40mhz),
  .i_ce_mhz(s_cls_ce_mhz),
  .i_lcd_command_ready(s_cls_command_ready),
  .o_lcd_wr_clear_display(s_cls_wr_clear_display),
  .o_lcd_wr_text_line1(s_cls_wr_text_line1),
  .o_lcd_wr_text_line2(s_cls_wr_text_line2),
  .o_lcd_feed_is_idle(s_cls_feed_is_idle)
  );

// TX ONLY UART function to print the two lines of the PMOD CLS output as a
// single line on the dumb terminal, at the same rate as the PMOD CLS updates.
// Assembly of UART text line.

assign s_uart_tx_go = s_cls_wr_clear_display;

uart_tx_only #(
  .parm_BAUD(115200)
  ) u_uart_tx_only (
  .i_clk_40mhz  (s_clk_40mhz),
  .i_rst_40mhz  (s_rst_40mhz),
  .i_clk_7_37mhz(s_clk_7_37mhz),
  .i_rst_7_37mhz(s_rst_7_37mhz),
  .eo_uart_tx   (eo_uart_tx),
  .i_tx_data    (s_uart_txdata),
  .i_tx_valid   (s_uart_txvalid),
  .o_tx_ready   (s_uart_txready)
  );

uart_tx_feed #(
  ) u_uart_tx_feed (
  .i_clk_40mhz(s_clk_40mhz),
  .i_rst_40mhz(s_rst_40mhz),
  .o_tx_data(s_uart_txdata),
  .o_tx_valid(s_uart_txvalid),
  .i_tx_ready(s_uart_txready),
  .i_tx_go(s_uart_tx_go),
  .i_dat_ascii_line(s_uart_txt_ascii_line)
  );

endmodule : fpga_serial_mem_tester_a7100
//------------------------------------------------------------------------------
`end_keywords
