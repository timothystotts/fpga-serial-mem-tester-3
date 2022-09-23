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
-- \file pmod_sf3_quad_spi_solo.sv
--
-- \brief Custom Interface to the PMOD SF3 N25Q flash chip via Ehanced SPI at
-- boot-time and future implementation provision for Quad I/O SPI at run-time.
-- This FSM operates the \ref pmod_generic_qspi_solo module to communicate with
-- the N25Q flash chip for basic random read, subsector erase, and page program.
------------------------------------------------------------------------------*/
//------------------------------------------------------------------------------
`begin_keywords "1800-2012"
//Recursive Moore Machine
//Part 1: Module header:--------------------------------------------------------
module pmod_sf3_quad_spi_solo
	import pmod_quad_spi_solo_pkg::*;
	#(parameter
		// Disable or enable fast FSM delays for simulation instead of impelementation. 
		integer parm_fast_simulation = 0,
		// Actual frequency in Hz of \ref i_ext_spi_clk_4x
		integer parm_FCLK = 20000000
		)
	(
		// system clock and synchronous reset
		input logic i_ext_spi_clk_x,
		input logic i_srst,
		input logic i_spi_ce_4x,
		// Interface pmod_generic_qspi_solo_intf
		pmod_generic_qspi_solo_intf.spi_sysdrv sdrv,
		// FPGA system interface to SF3 operation
		output logic o_command_ready,
		input logic [31:0] i_address_of_cmd,
		input logic i_cmd_erase_subsector,
		input logic i_cmd_page_program,
		input logic i_cmd_random_read,
		input logic [8:0] i_len_random_read,
		// FPGA system interface to SF3 streaming data in to chip (write) and out of chip (read)
		input logic [7:0] i_wr_data_stream,
		input logic i_wr_data_valid,
		output logic o_wr_data_ready,
		output logic [7:0] o_rd_data_stream,
		output logic o_rd_data_valid,
		// statuses of the N25Q flash chip
		output logic [7:0] o_reg_status,
		output logic [7:0] o_reg_flag
		);

// Part 2: Declarations---------------------------------------------------------
timeunit 1ns;
timeprecision 1ps;

// Xilinx attributes for Gray encoding of the FSM and safe state is
// Default State.
/* Driver FSM state declarations */
`define c_drv_state_bits 6
typedef enum logic [(`c_drv_state_bits - 1):0] {
	// check the flag status on power-up
	ST_BOOTA_INIT,
	ST_BOOTA_STATUS_CMD, ST_BOOTA_STATUS_WAIT, ST_BOOTA_STATUS_RX,
	ST_BOOTA_STATUS_CHK0, ST_BOOTA_STATUS_CHK1,
	// Boot init the Status Register
	ST_BOOT0_WEN_STATUS, ST_BOOT0_WEN_STWAIT,
	ST_BOOT0_WR_STATUS_CMD, ST_BOOT0_WR_STATUS_DAT,
	ST_BOOT0_IDLE_STWAIT,
	ST_BOOT0_FLAGST_CMD, ST_BOOT0_FLAGST_WAIT, ST_BOOT0_FLAGST_RX,
	ST_BOOT0_FLAGST_CHK0, ST_BOOT0_FLAGST_CHK1,
	// Idle state
	ST_WAIT_IDLE, ST_IDLE,
	// Read up to one page states
	ST_RD_CMD, ST_RD_ADDR, ST_RD_WAIT_0, ST_RD_STREAM,
	// Erase one subsector states
	ST_WEN_ERASE, ST_WEN_WAIT2, ST_ERASE_CMD, ST_ERASE_ADDR,
	ST_ERASE_WAIT,
	// Status check states
	ST_FLAGST_CMD, ST_FLAGST_WAIT, ST_FLAGST_RX,
	ST_FLAGST_CHK0, ST_FLAGST_CHK1,
	// Write a full page states
	ST_WEN_PROGR, ST_WEN_WAIT3, ST_PAGE_PROGR_CMD, ST_PAGE_PROGR_ADDR,
	ST_PAGE_PROGR_STREAM, ST_PROGR_WAIT
} t_drv_state;

(* fsm_encoding = "auto" *)
(* fsm_safe_state = "default_state" *)
t_drv_state s_drv_pr_state = ST_BOOTA_INIT;
t_drv_state s_drv_nx_state = ST_BOOTA_INIT;

// Timer 1 constants (strategy #1)
localparam integer c_sf3_drv_time_value_bits = $clog2(parm_FCLK * 2 / 10000); // maximum of 200 us
typedef logic [(c_sf3_drv_time_value_bits - 1):0] t_sf3_drv_time_value;

localparam t_sf3_drv_time_value c_t_boot_init0 = parm_FCLK * 2 / 10000; // minimum of 200 us at 120 MHz
localparam t_sf3_drv_time_value c_t_boot_init1 = 20; // a small arbitrary delay, FIXME
localparam t_sf3_drv_time_Value c_t_boot_init2 = 20; // a small arbitrary delay, FIXME
localparam t_sf3_drv_time_value c_t_cmd_addr = 4;
localparam t_sf3_drv_time_value c_tmax = c_t_boot_init0 - 1;
t_sf3_drv_time_value s_t;

// N25Q Command and Data constants
localparam logic [7:0] c_n25q_cmd_write_enable = 8'h06;
localparam logic [7:0] c_n25q_cmd_write_enh_vol_cfg_reg = 8'h61;
localparam logic [7:0] c_n25q_dat_enh_vol_cfg_reg_as_pmod_sf3 = 8'hBF;
localparam logic [7:0] c_n25q_cmd_write_nonvol_cfg_reg = 8'hB1;
localparam logic [15:0] c_n25q_dat_nonvol_cfg_reg_as_pmod_sf3 = 16'b0001111111011111;
localparam logic [7:0] c_n25q_cmd_quadio_read_memory_4byte_addr = 8'hEC;
localparam integer c_n25q_cmd_quadio_read_dummy_cycles = 1;
localparam logic [7:0] c_n25q_cmd_extend_read_memory_4byte_addr = 8'h0C;
localparam integer c_n25q_cmd_extend_read_dummy_cycles = 8;
localparam logic [7:0] c_n25q_cmd_any_erase_subsector = 8'h21;
localparam logic [7:0] c_n25q_cmd_read_status_register = 8'h05;
localparam logic [7:0] c_n25q_cmd_write_status_register = 8'h01;
localparam logic [7:0] c_n25q_dat_status_reg_as_pmod_sf3 = 8'h00;
localparam logic [7:0] c_n25q_cmd_any_page_program = 8'h12;
localparam logic [7:0] c_n25q_cmd_read_flag_status_register = 8'h70;
localparam logic [7:0] c_n25q_cmd_clear_flag_status_register = 8'h50;

localparam integer c_n25q_txlen_cmd_read_status_register = 1;
localparam integer c_n25q_rxlen_cmd_read_status_register = 1;
localparam integer c_n25q_txlen_cmd_write_enable = 1;
localparam integer c_n25q_txlen_cmd_write_status_register = 2;
localparam integer c_n25q_txlen_cmd_read_flag_status_register = 1;
localparam integer c_n25q_rxlen_cmd_read_flag_status_register = 1;
localparam integer c_n25q_txlen_cmd_write_enh_vol_cfg_reg = 2;
localparam integer c_n25q_txlen_cmd_extend_read_memory_4byte_addr = 5;
localparam integer c_n25q_txlen_cmd_any_erase_subsector = 5;
localparam integer c_n25q_txlen_cmd_any_page_program = 5;

localparam integer signed c_addr_byte_index_preset = 3;

integer signed s_wait_len_val;
integer signed s_wait_len_aux;
integer signed s_addr_byte_index_val;
integer signed s_addr_byte_index_aux;
logic [7:0] s_read_status_register_val;
logic [7:0] s_read_status_register_aux;
logic [7:0] s_read_flag_status_register_val;
logic [7:0] s_read_flag_status_register_aux;

localparam logic c_boot_in_quadio = 0;

//Part 3: Statements------------------------------------------------------------

// Strategy #1 timer reseting on change of \ref s_pr_state
always_ff @(posedge i_ext_spi_clk_x)
begin: p_fsm_timer_1
	if (i_srst)	s_t <= 0;
	else
		if (i_spi_ce_4x)
			if (s_drv_pr_state != s_drv_nx_state) begin : if_chg_state
				s_t <= 0;
			end : if_chg_state

			else if (s_t != c_tmax) begin : if_not_timer_max
				s_t <= s_t + 1;
			end : if_not_timer_max

end : p_fsm_timer_1

// FSM state register plus auxiliary registers
always_ff @(posedge i_ext_spi_clk_x)
begin: p_fsm_state_aux
	if (i_srst) begin
		s_drv_pr_state <= ST_BOOTA_INIT;

		s_wait_len_aux <= 0;
		s_addr_byte_index_aux <= 0;
		s_read_status_register_aux <= '0;
		s_read_flag_status_register_aux <= '0;
	end else 
		if (i_spi_ce_4x) begin : if_fsm_state_and_storage
			s_drv_pr_state <= s_drv_nx_state;

			s_wait_len_aux <= s_wait_len_val;
			s_addr_byte_index_aux <= s_addr_byte_index_val;
			s_read_status_register_aux <= s_read_status_register_val;
			s_read_flag_status_register_aux <= s_read_flag_status_register_val;
		end : if_fsm_state_and_storage
end : p_fsm_state_aux

// FSM combinatorial logic providing multiple outputs, assigned in every state,
// as well as changes in auxiliary values, and calculation of the next FSM
// state. Refer to the FSM state machine drawings in document:
// \ref SF-Tester-Design-Diagrams.pdf .
always_comb
begin: p_fsm_comb
	// default values before assignments of current FSM state
	sdrv.tx_data = 8'h00;
	sdrv.tx_enqueue = 1'b0;
	sdrv.rx_dequeue = 1'b0;
	sdrv.tx_len = 0;
	sdrv.rx_len = 0;
	sdrv.wait_cyc = 0;
	sdrv.go_enhan = 1'b0;
	sdrv.go_quadio = 1'b0;
	s_wait_len_val = s_wait_len_aux;
	s_addr_byte_index_val = s_addr_byte_index_aux;
	s_read_status_register_val = s_read_status_register_aux;
	s_read_flag_status_register_val = s_read_status_register_aux;

	o_rd_data_stream = '0;
	o_rd_data_valid = 1'b0;
	o_wr_data_ready = 1'b0;

	// machine
	case (s_drv_pr_state)
		ST_BOOTA_STATUS_CMD: begin
			o_command_ready = 1'b0;
			sdrv.tx_data = c_n25q_cmd_read_status_register;
			sdrv.tx_len= c_n25q_txlen_cmd_read_status_register;
			sdrv.rx_len = c_n25q_rxlen_cmd_read_status_register;
			sdrv.tx_enqueue = sdrv.tx_ready;
			sdrv.go_enhan = sdrv.tx_ready;

			if (sdrv.tx_ready)
				s_drv_nx_state = ST_BOOTA_STATUS_WAIT;
			else
				s_drv_nx_state = ST_BOOTA_STATUS_CMD;
		end

		ST_BOOTA_STATUS_WAIT: begin
			o_command_ready = 1'b0;
			sdrv.rx_dequeue = sdrv.rx_avail && sdrv.spi_idle;

			if (sdrv.rx_avail && sdrv.spi_idle)
				s_drv_nx_state = ST_BOOTA_STATUS_RX;
			else
				s_drv_nx_state = ST_BOOTA_STATUS_WAIT;
		end

		ST_BOOTA_STATUS_RX: begin
			o_command_ready = 1'b0;
			s_read_status_register_val = sdrv.rx_data;

			if (sdrv.rx_valid)
				s_drv_nx_state = ST_BOOTA_STATUS_CHK0;
			else
				s_drv_nx_state = ST_BOOTA_STATUS_RX;
		end

		ST_BOOTA_STATUS_CHK0: begin
			o_command_ready = 1'b0;

			if (sdrv.spi_idle)
				s_drv_nx_state = ST_BOOTA_STATUS_CHK1;
			else
				s_drv_nx_state = ST_BOOTA_STATUS_CHK0;
		end

		ST_BOOTA_STATUS_CHK1: begin
			o_command_ready = 1'b0;

			if (s_read_status_register_aux[0] == 1'b0) // chip is no longer busy
				s_drv_nx_state = ST_BOOT0_WEN_STATUS;
			else // chip is busy, so check again
				s_drv_nx_state = ST_BOOTA_STATUS_CMD;
		end

		ST_BOOT0_WEN_STATUS: begin // step 1 of 4 to write status register
			o_command_ready = 1'b0;
			sdrv.tx_data = c_n25q_cmd_write_enable;
			sdrv.tx_len = c_n25q_txlen_cmd_write_enable;
			sdrv.tx_enqueue = sdrv.tx_ready;
			sdrv.go_enhan = sdrv.tx_ready;

			if (sdrv.tx_ready)
				s_drv_nx_state = ST_BOOT0_WEN_STWAIT;
			else
				s_drv_nx_state = ST_BOOT0_WEN_STATUS;
		end

		ST_BOOT0_WEN_STWAIT: begin // step 2 of 4 to write status register
			o_command_ready = 1'b0;

			if (sdrv.spi_idle)
				s_drv_nx_state = ST_BOOT0_WR_STATUS_CMD;
			else
				s_drv_nx_state = ST_BOOT0_WEN_STWAIT;
		end

		ST_BOOT0_WR_STATUS_CMD: begin // step 3 of 4 to write status register
			o_command_ready = 1'b0;
			sdrv.tx_data = c_n25q_cmd_write_status_register;
			sdrv.tx_enqueue = sdrv.tx_ready;

			if (sdrv.tx_ready)
				s_drv_nx_state = ST_BOOT0_WR_STATUS_DAT;
			else
				s_drv_nx_state = ST_BOOT0_WR_STATUS_CMD;
		end

		ST_BOOT0_WR_STATUS_DAT: begin // step 4 of 4 to switch to Quad I/O SPI
			o_command_ready = 1'b0;
			sdrv.tx_data = c_n25q_dat_status_reg_as_pmod_sf3;
			sdrv.tx_len = c_n25q_txlen_cmd_write_status_register;
			sdrv.tx_enqueue = sdrv.tx_ready && sdrv.spi_idle;
			sdrv.go_enhan = sdrv.tx_ready && sdrv.spi_idle;

			if (sdrv.tx_ready && sdrv.spi_idle)
				s_drv_nx_state = ST_BOOT0_IDLE_STWAIT;
			else
				s_drv_nx_state = ST_BOOT0_WR_STATUS_DAT;
		end

		ST_BOOT0_IDLE_STWAIT: begin
			o_command_ready = 1'b0;

			if (sdrv.spi_idle)
				s_drv_nx_state = ST_BOOT0_FLAGST_CMD;
			else
				s_drv_nx_state = ST_BOOT0_IDLE_STWAIT;
		end

		ST_BOOT0_FLAGST_CMD: begin
			o_command_ready = 1'b0;
			sdrv.tx_data = c_n25q_cmd_read_flag_status_register;
			sdrv.tx_len = c_n25q_txlen_cmd_read_flag_status_register;
			sdrv.rx_len = c_n25q_rxlen_cmd_read_flag_status_register;
			sdrv.tx_enqueue = sdrv.tx_ready;
			sdrv.go_enhan = sdrv.tx_ready;

			if (sdrv.tx_ready)
				s_drv_nx_state = ST_BOOT0_FLAGST_WAIT;
			else
				s_drv_nx_state = ST_BOOT0_FLAGST_CMD;
		end

		ST_BOOT0_FLAGST_WAIT: begin
			o_command_ready = 1'b0;
			sdrv.rx_dequeue = sdrv.rx_avail && sdrv.spi_idle;

			if (sdrv.rx_avail && sdrv.spi_idle)
				s_drv_nx_state = ST_BOOT0_FLAGST_RX;
			else
				s_drv_nx_state = ST_BOOT0_FLAGST_WAIT;
		end

		ST_BOOT0_FLAGST_RX: begin
			o_command_ready = 1'b0;
			s_read_flag_status_register_val = sdrv.rx_data;

			if (sdrv.rx_valid)
				s_drv_nx_state = ST_BOOT0_FLAGST_CHK0;
			else
				s_drv_nx_state = ST_BOOT0_FLAGST_RX;
		end

		ST_BOOT0_FLAGST_CHK0: begin
			o_command_ready = 1'b0;

			if (sdrv.spi_idle)
				s_drv_nx_state = ST_BOOT0_FLAGST_CHK1;
			else
				s_drv_nx_state = ST_BOOT0_FLAGST_CHK0;
		end

		ST_BOOT0_FLAGST_CHK1: begin
			o_command_ready = 1'b0;

			if (s_read_flag_status_register_aux[7] == 1'b1) // chip is in ready state
				s_drv_nx_state = ST_WAIT_IDLE;
			else // chip is not in ready state
				s_drv_nx_state = ST_BOOT0_FLAGST_CMD;
		end

		ST_RD_CMD: begin
			o_command_ready = 1'b0;
			sdrv.tx_data = c_n25q_cmd_extend_read_memory_4byte_addr;
			sdrv.tx_enqueue = sdrv.tx_ready;

			s_addr_byte_index_val = c_addr_byte_index_preset;

			if (sdrv.tx_ready)
				s_drv_nx_state = ST_RD_ADDR;
			else
				s_drv_nx_state = ST_RD_CMD;
		end

		ST_RD_ADDR: begin
			o_command_ready = 1'b0;
			sdrv.tx_data = i_address_of_cmd[(8 * (s_addr_byte_index_aux + 1) - 1)-:8];
			sdrv.tx_enqueue = sdrv.tx_ready;
			sdrv.go_enhan = (s_addr_byte_index_aux == 0) ? 1'b1 : 1'b0;
			s_addr_byte_index_val = sdrv.tx_ready ? (s_addr_byte_index_aux - 1) : s_addr_byte_index_aux;

			sdrv.tx_len = c_n25q_txlen_cmd_extend_read_memory_4byte_addr;
			sdrv.rx_len = i_len_random_read;
			sdrv.wait_cyc = c_n25q_cmd_extend_read_dummy_cycles;
			s_wait_len_val = i_len_random_read;

			if (s_addr_byte_index_aux == 0)
				s_drv_nx_state = ST_RD_WAIT_0;
			else
				s_drv_nx_state = ST_RD_ADDR;
		end

		ST_RD_WAIT_0: begin
			o_command_ready = 1'b0;
			o_rd_data_stream = sdrv.rx_data;
			o_rd_data_valid = sdrv.rx_valid;
			sdrv.rx_dequeue = sdrv.rx_avail;

			s_wait_len_val = sdrv.rx_avail ? (s_wait_len_aux - 1) : s_wait_len_aux;

			if (s_wait_len_aux == 0)
				s_drv_nx_state = ST_WAIT_IDLE;
			else
				s_drv_nx_state = ST_RD_WAIT_0;
		end

		ST_WEN_ERASE: begin
			o_command_ready = 1'b0;
			sdrv.tx_data = c_n25q_cmd_write_enable;
			sdrv.tx_len = c_n25q_txlen_cmd_write_enable;
			sdrv.tx_enqueue = sdrv.tx_ready;
			sdrv.go_enhan = sdrv.tx_ready;

			if (sdrv.tx_ready)
				s_drv_nx_state = ST_WEN_WAIT2;
			else
				s_drv_nx_state = ST_WEN_ERASE;
		end

		ST_WEN_WAIT2: begin
			o_command_ready = 1'b0;

			if (sdrv.spi_idle)
				s_drv_nx_state = ST_ERASE_CMD;
			else
				s_drv_nx_state = ST_WEN_WAIT2;
		end

		ST_ERASE_CMD: begin
			o_command_ready = 1'b0;
			sdrv.tx_data = c_n25q_cmd_any_erase_subsector;
			sdrv.tx_enqueue = sdrv.tx_ready;

			s_addr_byte_index_val = c_addr_byte_index_preset;

			if (sdrv.tx_ready)
				s_drv_nx_state = ST_ERASE_ADDR;
			else
				s_drv_nx_state = ST_ERASE_CMD;			
		end

		ST_ERASE_ADDR: begin
			o_command_ready = 1'b0;
			sdrv.tx_data = i_address_of_cmd[(8 * (s_addr_byte_index_aux + 1) - 1)-:8];
			sdrv.tx_len = c_n25q_txlen_cmd_any_erase_subsector;
			sdrv.tx_enqueue = sdrv.tx_ready;
			sdrv.go_enhan = (s_addr_byte_index_aux == 0) ? 1'b1 : 1'b0;

			s_addr_byte_index_val = sdrv.tx_ready ? (s_addr_byte_index_aux - 1) : s_addr_byte_index_aux;

			if (s_addr_byte_index_aux == 0)
				s_drv_nx_state = ST_ERASE_WAIT;
			else
				s_drv_nx_state = ST_ERASE_ADDR;
		end

		ST_ERASE_WAIT: begin
			o_command_ready = 1'b0;

			if (sdrv.spi_idle)
				s_drv_nx_state = ST_FLAGST_CMD;
			else
				s_drv_nx_state = ST_ERASE_WAIT;
		end

		ST_FLAGST_CMD: begin
			o_command_ready = 1'b0;
			sdrv.tx_data = c_n25q_cmd_read_flag_status_register;
			sdrv.tx_len = c_n25q_txlen_cmd_read_flag_status_register;
			sdrv.rx_len = c_n25q_rxlen_cmd_read_flag_status_register;
			sdrv.tx_enqueue = sdrv.tx_ready;
			sdrv.go_enhan = sdrv.tx_ready;

			if (sdrv.tx_ready)
				s_drv_nx_state = ST_FLAGST_WAIT;
			else
				s_drv_nx_state = ST_FLAGST_CMD;
		end

		ST_FLAGST_WAIT: begin
			o_command_ready = 1'b0;
			sdrv.rx_dequeue = sdrv.rx_avail && sdrv.spi_idle;

			if (sdrv.rx_avail && sdrv.spi_idle)
				s_drv_nx_state = ST_FLAGST_RX;
			else
				s_drv_nx_state = ST_FLAGST_WAIT;
		end

		ST_FLAGST_RX: begin
			o_command_ready = 1'b0;
			s_read_flag_status_register_val = sdrv.rx_data;

			if (sdrv.rx_valid)
				s_drv_nx_state = ST_FLAGST_CHK0;
			else
				s_drv_nx_state = ST_FLAGST_RX;
		end

		ST_FLAGST_CHK0: begin
			o_command_ready = 1'b0;

			if (sdrv.spi_idle)
				s_drv_nx_state = ST_FLAGST_CHK1;
			else
				s_drv_nx_state = ST_FLAGST_CHK0;
		end

		ST_FLAGST_CHK1: begin
			o_command_ready = 1'b0;

			if (s_read_flag_status_register_aux[7] == 1'b1) // erase is done
				s_drv_nx_state = ST_WAIT_IDLE;
			else // erase is not done, so check again
				s_drv_nx_state = ST_FLAGST_CMD;
		end

		ST_WEN_PROGR: begin
			o_command_ready = 1'b0;
			sdrv.tx_data = c_n25q_cmd_write_enable;
			sdrv.tx_len = c_n25q_txlen_cmd_write_enable;
			sdrv.tx_enqueue = sdrv.tx_ready;
			sdrv.go_enhan = sdrv.tx_ready;

			if (sdrv.tx_ready)
				s_drv_nx_state = ST_WEN_WAIT3;
			else
				s_drv_nx_state = ST_WEN_PROGR;
		end

		ST_WEN_WAIT3: begin
			o_command_ready = 1'b0;

			if (sdrv.spi_idle)
				s_drv_nx_state = ST_PAGE_PROGR_CMD;
			else
				s_drv_nx_state = ST_WEN_WAIT3;
		end

		ST_PAGE_PROGR_CMD: begin
			o_command_ready = 1'b0;
			sdrv.tx_data = c_n25q_cmd_any_page_program;
			sdrv.tx_enqueue = sdrv.tx_ready;

			s_addr_byte_index_val = c_addr_byte_index_preset;

			if (sdrv.tx_ready)
				s_drv_nx_state = ST_PAGE_PROGR_ADDR;
			else
				s_drv_nx_state = ST_PAGE_PROGR_CMD;
		end

		ST_PAGE_PROGR_ADDR: begin
			o_command_ready = 1'b0;
			sdrv.tx_data = i_address_of_cmd[(8 * (s_addr_byte_index_aux + 1) - 1)-:8];
			sdrv.tx_len = c_n25q_txlen_cmd_any_page_program;
			sdrv.tx_enqueue = sdrv.tx_ready;
			sdrv.go_enhan = (s_addr_byte_index_aux == 0) ? 1'b1 : 1'b0;

			s_addr_byte_index_val = sdrv.tx_ready ? (s_addr_byte_index_aux - 1) : s_addr_byte_index_aux;
			s_wait_len_val = 256;

			if (s_addr_byte_index_aux == 0)
				s_drv_nx_state = ST_PAGE_PROGR_STREAM;
			else
				s_drv_nx_state = ST_PAGE_PROGR_ADDR;
		end

		ST_PAGE_PROGR_STREAM: begin
			o_command_ready = 1'b0;
			o_wr_data_ready = sdrv.tx_ready;
			sdrv.tx_data = i_wr_data_stream;
			sdrv.tx_enqueue = i_wr_data_valid;

			s_wait_len_val = (i_wr_data_valid && (s_wait_len_aux >= 1)) ? (s_wait_len_aux - 1)  : s_wait_len_aux;

			if (sdrv.spi_idle && (s_wait_len_aux <= 1))
				s_drv_nx_state = ST_FLAGST_CMD;
			else
				s_drv_nx_state = ST_PAGE_PROGR_STREAM;
		end

		ST_WAIT_IDLE: begin
			o_command_ready = 1'b0;

			if (sdrv.spi_idle)
				s_drv_nx_state = ST_IDLE;
			else
				s_drv_nx_state = ST_WAIT_IDLE;
		end

		ST_IDLE: begin
			o_command_ready = sdrv.spi_idle;

			if (i_cmd_random_read)
				s_drv_nx_state = ST_RD_CMD;
			else if (i_cmd_erase_subsector)
				s_drv_nx_state = ST_WEN_ERASE;
			else if (i_cmd_page_program)
				s_drv_nx_state = ST_WEN_PROGR;
			else
				s_drv_nx_state = ST_IDLE;
		end

		default: begin // ST_BOOTA_INIT
			o_command_ready = 1'b0;

			if (s_t >= c_t_boot_init0 - 1)
				s_drv_nx_state = ST_BOOTA_STATUS_CMD;
			else
				s_drv_nx_state = ST_BOOTA_INIT;
		end
	endcase
end : p_fsm_comb

assign o_reg_status = s_read_status_register_aux;
assign o_reg_flag = s_read_flag_status_register_aux;

endmodule : pmod_sf3_quad_spi_solo
//------------------------------------------------------------------------------
`end_keywords
