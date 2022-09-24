/*------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2021-2022 Timothy Stotts
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
-- \file pmod_sf3_custom_driver.sv
--
-- \brief A wrapper for the single Chip Select, Extended SPI modules
--        \ref pmod_sf3_stand_spi_solo and \ref pmod_generic_qspi_solo ,
--        implementing a custom multi-mode operation of the PMOD SF3
--        peripheral board by Digilent Inc with SPI bus communication.
--        Note that Extended SPI Mode 0 is implemented currently, and
--        QuadIO SPI is not currently implemented.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//------------------------------------------------------------------------------
//Part 1: Module header:--------------------------------------------------------
module pmod_sf3_custom_driver
	import pmod_quad_spi_solo_pkg::*;
	#(parameter
		// Disable or enable fast FSM delays for simulation instead of impelementation.
		integer parm_fast_simulation = 0,
		// Actual frequency in Hz of \ref i_clk_mhz
		integer parm_FCLK = 20000000,
		// Ratio of i_ext_spi_clk_x to SPI sck bus output.
		integer parm_ext_spi_clk_ratio = 4
		)
	(
		// Clock and reset, with clock at 4 times the frequency of the SPI bus
		input logic i_clk_mhz,
		input logic i_rst_mhz,
		input logic i_ce_mhz_div,
		// Outputs and inputs from the single SPI peripheral
		output logic eio_sck_o,
		output logic eio_sck_t,
		output logic eio_csn_o,
		output logic eio_csn_t,
		output logic eio_copi_dq0_o,
		input logic eio_copi_dq0_i,
		output logic eio_copi_dq0_t,
		output logic eio_cipo_dq1_o,
		input logic eio_cipo_dq1_i,
		output logic eio_cipo_dq1_t,
		output logic eio_wrpn_dq2_o,
		input logic eio_wrpn_dq2_i,
		output logic eio_wrpn_dq2_t,
		output logic eio_hldn_dq3_o,
		input logic eio_hldn_dq3_i,
		output logic eio_hldn_dq3_t,
		// Command ready indication and three possible commands to the driver
		output logic o_command_ready,
		input logic [31:0] i_address_of_cmd,
		input logic i_cmd_erase_subsector,
		input logic i_cmd_page_program,
		input logic i_cmd_random_read,
		input logic [8:0] i_len_random_read,
		input logic [7:0] i_wr_data_stream,
		input logic i_wr_data_valid,
		output logic o_wr_data_ready,
		output logic [7:0] o_rd_data_stream,
		output logic o_rd_data_valid,
		// statuses of the N25Q flash chip
		output logic [7:0] o_reg_status,
		output logic [7:0] o_reg_flag
		);

//Part 2: Declarations----------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

// Pmod ACL2 SPI driver wiring to the Generic SPI driver.
pmod_generic_qspi_solo_intf #(
	.parm_tx_len_bits  (c_pmod_sf3_tx_len_bits),
	.parm_wait_cyc_bits (c_pmod_sf3_wait_cyc_bits),
	.parm_rx_len_bits  (c_pmod_sf3_rx_len_bits)
	)
	intf_sf3_qspi();

// SPI signals to external tri-state
logic sio_sck_fsm_o;
logic sio_sck_fsm_t;
logic sio_sck_out_o;
logic sio_sck_out_t;

logic sio_csn_fsm_o;
logic sio_csn_fsm_t;
logic sio_csn_out_o;
logic sio_csn_out_t;

logic sio_dq0_fsm_o;
logic sio_dq0_fsm_t;
logic sio_dq0_out_o;
logic sio_dq0_out_t;

logic sio_dq0_sync_i;
logic sio_dq0_meta_i;
logic sio_dq0_in_i;

logic sio_dq1_fsm_o;
logic sio_dq1_fsm_t;
logic sio_dq1_out_o;
logic sio_dq1_out_t;

logic sio_dq1_sync_i;
logic sio_dq1_meta_i;
logic sio_dq1_in_i;

logic sio_dq2_fsm_o;
logic sio_dq2_fsm_t;
logic sio_dq2_out_o;
logic sio_dq2_out_t;

logic sio_dq2_sync_i;
logic sio_dq2_meta_i;
logic sio_dq2_in_i;

logic sio_dq3_fsm_o;
logic sio_dq3_fsm_t;
logic sio_dq3_out_o;
logic sio_dq3_out_t;

logic sio_dq3_sync_i;
logic sio_dq3_meta_i;
logic sio_dq3_in_i;


//Part 3: Statements------------------------------------------------------------

// register the SPI FSM outputs to prevent glitches
always_ff @(posedge i_clk_mhz)
begin: p_reg_spi_fsm_out
	if (i_ce_mhz_div) begin : ce_register_spi_outs
		eio_sck_o <= sio_sck_fsm_o;
		eio_sck_t <= sio_sck_fsm_t;

		eio_csn_o <= sio_csn_fsm_o;
		eio_csn_t <= sio_csn_fsm_t;

		eio_copi_dq0_o <= sio_dq0_fsm_o;
		eio_copi_dq0_t <= sio_dq0_fsm_t;

		eio_cipo_dq1_o <= sio_dq1_fsm_o;
		eio_cipo_dq1_t <= sio_dq1_fsm_t;

		eio_wrpn_dq2_o <= sio_dq2_fsm_o;
		eio_wrpn_dq2_t <= sio_dq2_fsm_t;

		eio_hldn_dq3_o <= sio_dq3_fsm_o;
		eio_hldn_dq3_t <= sio_dq3_fsm_t;
	end : ce_register_spi_outs
end : p_reg_spi_fsm_out

// two-stage synchronize the SPI FSM inputs for best practice
always @(posedge i_clk_mhz)
begin: p_sync_spi_in
	if (i_ce_mhz_div) begin : ce_register_spi_ins
		sio_dq0_sync_i <= sio_dq0_meta_i;
		sio_dq0_meta_i <= eio_copi_dq0_i;

		sio_dq1_sync_i <= sio_dq1_meta_i;
		sio_dq1_meta_i <= eio_cipo_dq1_i;

		sio_dq2_sync_i <= sio_dq2_meta_i;
		sio_dq2_meta_i <= eio_wrpn_dq2_i;

		sio_dq3_sync_i <= sio_dq3_meta_i;
		sio_dq3_meta_i <= eio_hldn_dq3_i;
	end : ce_register_spi_ins
end : p_sync_spi_in

// Multiple mode driver to operate the PMOD ACL2 via a stand-alone SPI driver.
pmod_sf3_quad_spi_solo #(
	.parm_fast_simulation (parm_fast_simulation),
	.parm_FCLK (parm_FCLK)
	) u_pmod_sf3_quad_spi_solo (
	.i_ext_spi_clk_x(i_clk_mhz),
	.i_srst(i_rst_mhz),
	.i_spi_ce_4x(i_ce_mhz_div),

	.sdrv(intf_sf3_qspi),

	.o_command_ready(o_command_ready),
	.i_address_of_cmd(i_address_of_cmd),
	.i_cmd_erase_subsector(i_cmd_erase_subsector),
	.i_cmd_page_program(i_cmd_page_program),
	.i_cmd_random_read(i_cmd_random_read),
	.i_len_random_read(i_len_random_read),

	.i_wr_data_stream(i_wr_data_stream),
	.i_wr_data_valid(i_wr_data_valid),
	.o_wr_data_ready(o_wr_data_ready),

	.o_rd_data_stream(o_rd_data_stream),
	.o_rd_data_valid(o_rd_data_valid),

	.o_reg_status(o_reg_status),
	.o_reg_flag(o_reg_flag)
	);

// Stand-alone SPI bus driver for a single bus-peripheral.
pmod_generic_qspi_solo #(
	.parm_ext_spi_clk_ratio (parm_ext_spi_clk_ratio)
	) u_pmod_generic_qspi_solo (
	.i_ext_spi_clk_x(i_clk_mhz),
	.i_srst(i_rst_mhz),
	.i_spi_ce_4x(i_ce_mhz_div), // 20 MHz is 4x the SPI speed, so CE is held '1'

	.sdrv(intf_sf3_qspi),

	.eio_sck_o(sio_sck_fsm_o),
	.eio_sck_t(sio_sck_fsm_t),
	.eio_csn_o(sio_csn_fsm_o),
	.eio_csn_t(sio_csn_fsm_t),
	.eio_copi_dq0_o(sio_dq0_fsm_o),
	.eio_copi_dq0_i(sio_dq0_sync_i),
	.eio_copi_dq0_t(sio_dq0_fsm_t),
	.eio_cipo_dq1_o(sio_dq1_fsm_o),
	.eio_cipo_dq1_i(sio_dq1_sync_i),
	.eio_cipo_dq1_t(sio_dq1_fsm_t),
	.eio_wrpn_dq2_o(sio_dq2_fsm_o),
	.eio_wrpn_dq2_i(sio_dq2_sync_i),
	.eio_wrpn_dq2_t(sio_dq2_fsm_t),
	.eio_hldn_dq3_o(sio_dq3_fsm_o),
	.eio_hldn_dq3_i(sio_dq3_sync_i),
	.eio_hldn_dq3_t(sio_dq3_fsm_t)
	);

endmodule : pmod_sf3_custom_driver
//------------------------------------------------------------------------------
`end_keywords
