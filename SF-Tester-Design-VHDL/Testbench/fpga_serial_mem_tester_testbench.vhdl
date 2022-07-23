--------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2021 Timothy Stotts
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
-- \file fpga_serial_mem_tester_testbench.vhdl
--
-- \brief Accelerometer control and reading, testbench.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

library osvvm_uart;
context osvvm_uart.UartContext;

library work;
--------------------------------------------------------------------------------
entity fpga_serial_mem_tester_testbench is
	generic(
		parm_simulation_duration : time    := 7 ms;
		parm_fast_simulation     : integer := 1;
		parm_log_file_name       : string  := "log_fpga_serial_mem_tester_no_test.txt"
	);
end entity fpga_serial_mem_tester_testbench;
--------------------------------------------------------------------------------
architecture simulation of fpga_serial_mem_tester_testbench is
	component fpga_serial_mem_tester is
		generic(
			parm_fast_simulation : integer := 0
		);
		port(
			-- Board clock
			CLK100MHZ : in std_logic;
			i_resetn  : in std_logic;
			-- PMOD SF3 Quad SPI
			eo_pmod_sf3_sck       : out   std_logic;
			eo_pmod_sf3_csn       : out   std_logic;
			eio_pmod_sf3_copi_dq0 : inout std_logic;
			eio_pmod_sf3_cipo_dq1 : inout std_logic;
			eio_pmod_sf3_wrpn_dq2 : inout std_logic;
			eio_pmod_sf3_hldn_dq3 : inout std_logic;
			-- blue LEDs of the multicolor
			eo_led0_b : out std_logic;
			eo_led1_b : out std_logic;
			eo_led2_b : out std_logic;
			eo_led3_b : out std_logic;
			-- red LEDs of the multicolor
			eo_led0_r : out std_logic;
			eo_led1_r : out std_logic;
			eo_led2_r : out std_logic;
			eo_led3_r : out std_logic;
			-- green LEDs of the multicolor
			eo_led0_g : out std_logic;
			eo_led1_g : out std_logic;
			eo_led2_g : out std_logic;
			eo_led3_g : out std_logic;
			-- green LEDs of the regular LEDs
			eo_led4 : out std_logic;
			eo_led5 : out std_logic;
			eo_led6 : out std_logic;
			eo_led7 : out std_logic;
			-- four switches
			ei_sw0 : in std_logic;
			ei_sw1 : in std_logic;
			ei_sw2 : in std_logic;
			ei_sw3 : in std_logic;
			-- four buttons
			ei_bt0 : in std_logic;
			ei_bt1 : in std_logic;
			ei_bt2 : in std_logic;
			ei_bt3 : in std_logic;
			-- PMOD CLS SPI bus 4-wire
			eo_pmod_cls_csn : out std_logic;
			eo_pmod_cls_sck : out std_logic;
			eo_pmod_cls_dq0 : out std_logic;
			ei_pmod_cls_dq1 : in  std_logic;
			-- Arty A7-100T UART TX and RX signals
			eo_uart_tx : out std_logic;
			ei_uart_rx : in  std_logic
		);
	end component fpga_serial_mem_tester;

	component tbc_clock_gen is
		generic(
			parm_main_clock_period : time     := 10 ns;
			parm_reset_cycle_count : positive := 5
		);
		port(
			TBID             : in    AlertLogIDType;
			BarrierTestStart : inout std_logic;
			BarrierLogStart  : inout std_logic;
			co_main_clock    : out   std_logic;
			con_main_reset   : out   std_logic
		);
	end component tbc_clock_gen;

	component tbc_board_ui is
		generic(
			parm_clk_freq                 : natural  := 100_000_000;
			parm_button_count             : positive := 4;
			parm_switch_count             : positive := 4;
			parm_rgb_led_count            : positive := 4;
			parm_basic_led_count          : positive := 4;
			parm_pwm_period_milliseconds  : natural  := 10;
			parm_pwm_color_max_duty_cycle : natural  := 8;
			parm_pwm_basic_max_duty_cycle : natural  := 9
		);
		port(
			TBID             : in    AlertLogIDType;
			BarrierTestStart : inout std_logic;
			BarrierLogStart  : inout std_logic;
			ci_main_clock    : in    std_logic;
			cin_main_reset   : in    std_logic;
			co_buttons       : out   std_logic_vector((parm_button_count - 1) downto 0);
			co_switches      : out   std_logic_vector((parm_switch_count - 1) downto 0);
			ci_led_blue      : in    std_logic_vector((parm_rgb_led_count - 1) downto 0);
			ci_led_red       : in    std_logic_vector((parm_rgb_led_count - 1) downto 0);
			ci_led_green     : in    std_logic_vector((parm_rgb_led_count - 1) downto 0);
			ci_led_basic     : in    std_logic_vector((parm_basic_led_count - 1) downto 0)
		);
	end component tbc_board_ui;

	component tbc_pmod_cls is
		port(
			TBID             : in    AlertLogIDType;
			BarrierTestStart : inout std_logic;
			BarrierLogStart  : inout std_logic;
			ci_sck           : in    std_logic;
			ci_csn           : in    std_logic;
			ci_copi          : in    std_logic;
			co_cipo          : out   std_logic
		);
	end component tbc_pmod_cls;

	component tbc_board_uart is
		port(
			TBID             : in    AlertLogIDType;
			BarrierTestStart : inout std_logic;
			BarrierLogStart  : inout std_logic;
			TransRec         : inout UartRecType;
			ci_rxd           : in    std_logic;
			co_txd           : out   std_logic
		);
	end component tbc_board_uart;

	component tbc_pmod_sf3 is
		port (
			TBID             : in    AlertLogIDType;
			BarrierTestStart : inout std_logic;
			BarrierLogStart  : inout std_logic;
			ci_sck           : in    std_logic;
			ci_csn           : in    std_logic;
			cio_copi         : inout std_logic;
			cio_cipo         : inout std_logic;
			cio_wrpn         : inout std_logic;
			cio_hldn         : inout std_logic
		);
	end component tbc_pmod_sf3;

	component UartRx is
		generic (
			DEFAULT_BAUD          : time    := UART_BAUD_PERIOD_125K ;
			DEFAULT_NUM_DATA_BITS : integer := UARTTB_DATA_BITS_8 ;
			DEFAULT_PARITY_MODE   : integer := UARTTB_PARITY_EVEN ;
			DEFAULT_NUM_STOP_BITS : integer := UARTTB_STOP_BITS_1
		);
		port (
			TransRec     : InOut UartRecType ;
			SerialDataIn : In    std_logic
		);
	end component UartRx ;

	constant c_clock_FREQ        : natural  := 100_000_000;
	constant c_clock_period      : time     := 10 ns;
	constant c_reset_clock_count : positive := 100;

	signal TBID : AlertLogIDType;

	signal run_clock : boolean;

	signal CLK100MHZ         : std_logic;
	signal si_resetn         : std_logic;
	signal so_pmod_sf3_sck   : std_logic;
	signal so_pmod_sf3_csn   : std_logic;
	signal sio_pmod_sf3_copi : std_logic;
	signal sio_pmod_sf3_cipo : std_logic;
	signal sio_pmod_sf3_wrpn : std_logic;
	signal sio_pmod_sf3_hldn : std_logic;
	signal so_led0_b         : std_logic;
	signal so_led1_b         : std_logic;
	signal so_led2_b         : std_logic;
	signal so_led3_b         : std_logic;
	signal so_led0_r         : std_logic;
	signal so_led1_r         : std_logic;
	signal so_led2_r         : std_logic;
	signal so_led3_r         : std_logic;
	signal so_led0_g         : std_logic;
	signal so_led1_g         : std_logic;
	signal so_led2_g         : std_logic;
	signal so_led3_g         : std_logic;
	signal so_led4           : std_logic;
	signal so_led5           : std_logic;
	signal so_led6           : std_logic;
	signal so_led7           : std_logic;
	signal si_sw0            : std_logic;
	signal si_sw1            : std_logic;
	signal si_sw2            : std_logic;
	signal si_sw3            : std_logic;
	signal si_btn0           : std_logic;
	signal si_btn1           : std_logic;
	signal si_btn2           : std_logic;
	signal si_btn3           : std_logic;
	signal so_pmod_cls_csn   : std_logic;
	signal so_pmod_cls_sck   : std_logic;
	signal so_pmod_cls_dq0   : std_logic;
	signal si_pmod_cls_dq1   : std_logic;
	signal so_uart_tx        : std_logic;
	signal si_uart_rx        : std_logic;

	signal si_buttons   : std_logic_vector(3 downto 0);
	signal si_switches  : std_logic_vector(3 downto 0);
	signal so_led_red   : std_logic_vector(3 downto 0);
	signal so_led_green : std_logic_vector(3 downto 0);
	signal so_led_blue  : std_logic_vector(3 downto 0);
	signal so_led_basic : std_logic_vector(3 downto 0);

	signal s_barrier_test_start : std_logic;
	signal s_barrier_log_start  : std_logic;

	signal UartRxTransRec : UartRecType;
begin
	-- Configure alert/log log file
	p_set_logfile : process
		variable ID : AlertLogIDType;
	begin
		ID   := GetAlertLogID(PathTail(fpga_serial_mem_tester_testbench'path_name), ALERTLOG_BASE_ID);
		TBID <= ID;
		wait for 1 ns;
		WaitForBarrier(s_barrier_test_start);

		TranscriptOpen(parm_log_file_name, WRITE_MODE);
		SetTranscriptMirror;
		SetLogEnable(INFO, TRUE);
		SetLogEnable(DEBUG, FALSE);

		Print("FPGA_SERIAL_MEM_TESTER_TESTBENCH starting simulation.");
		Print("Logging enabled for ALWAYS, INFO, DEBUG.");

		wait for 1 ns;
		WaitForBarrier(s_barrier_log_start);

		wait for parm_simulation_duration;
		ReportAlerts;

		std.env.finish;
		wait;
	end process p_set_logfile;

	-- Unit Under Test: fpga_serial_mem_tester
	uut_fpga_serial_mem_tester : fpga_serial_mem_tester
		generic map (
			parm_fast_simulation => parm_fast_simulation)
		port map (
			CLK100MHZ             => CLK100MHZ,
			i_resetn              => si_resetn,
			eo_pmod_sf3_sck       => so_pmod_sf3_sck,
			eo_pmod_sf3_csn       => so_pmod_sf3_csn,
			eio_pmod_sf3_copi_dq0 => sio_pmod_sf3_copi,
			eio_pmod_sf3_cipo_dq1 => sio_pmod_sf3_cipo,
			eio_pmod_sf3_wrpn_dq2 => sio_pmod_sf3_wrpn,
			eio_pmod_sf3_hldn_dq3 => sio_pmod_sf3_hldn,
			eo_led0_b             => so_led0_b,
			eo_led1_b             => so_led1_b,
			eo_led2_b             => so_led2_b,
			eo_led3_b             => so_led3_b,
			eo_led0_r             => so_led0_r,
			eo_led1_r             => so_led1_r,
			eo_led2_r             => so_led2_r,
			eo_led3_r             => so_led3_r,
			eo_led0_g             => so_led0_g,
			eo_led1_g             => so_led1_g,
			eo_led2_g             => so_led2_g,
			eo_led3_g             => so_led3_g,
			eo_led4               => so_led4,
			eo_led5               => so_led5,
			eo_led6               => so_led6,
			eo_led7               => so_led7,
			ei_sw0                => si_sw0,
			ei_sw1                => si_sw1,
			ei_sw2                => si_sw2,
			ei_sw3                => si_sw3,
			ei_bt0                => si_btn0,
			ei_bt1                => si_btn1,
			ei_bt2                => si_btn2,
			ei_bt3                => si_btn3,
			eo_pmod_cls_csn       => so_pmod_cls_csn,
			eo_pmod_cls_sck       => so_pmod_cls_sck,
			eo_pmod_cls_dq0       => so_pmod_cls_dq0,
			ei_pmod_cls_dq1       => si_pmod_cls_dq1,
			eo_uart_tx            => so_uart_tx,
			ei_uart_rx            => si_uart_rx
		);

	-- Main external clock and reset generator
	u_tbc_clock_gen : tbc_clock_gen
		generic map(
			parm_main_clock_period => c_clock_period,
			parm_reset_cycle_count => c_reset_clock_count
		)
		port map(
			TBID             => TBID,
			BarrierTestStart => s_barrier_test_start,
			BarrierLogStart  => s_barrier_log_start,
			co_main_clock    => CLK100MHZ,
			con_main_reset   => si_resetn
		);

	-- Drive and Watch User low-level Interface of FPGA dev-board
	u_tbc_board_ui : tbc_board_ui
		generic map(
			parm_clk_freq        => c_clock_FREQ,
			parm_button_count    => 4,
			parm_switch_count    => 4,
			parm_rgb_led_count   => 4,
			parm_basic_led_count => 4
		)
		port map(
			TBID             => TBID,
			BarrierTestStart => s_barrier_test_start,
			BarrierLogStart  => s_barrier_log_start,
			ci_main_clock    => CLK100MHZ,
			cin_main_reset   => si_resetn,
			co_buttons       => si_buttons,
			co_switches      => si_switches,
			ci_led_blue      => so_led_blue,
			ci_led_red       => so_led_red,
			ci_led_green     => so_led_green,
			ci_led_basic     => so_led_basic
		);

	si_btn0 <= si_buttons(0);
	si_btn1 <= si_buttons(1);
	si_btn2 <= si_buttons(2);
	si_btn3 <= si_buttons(3);

	si_sw0 <= si_switches(0);
	si_sw1 <= si_switches(1);
	si_sw2 <= si_switches(2);
	si_sw3 <= si_switches(3);

	so_led_red(0) <= so_led0_r;
	so_led_red(1) <= so_led1_r;
	so_led_red(2) <= so_led2_r;
	so_led_red(3) <= so_led3_r;

	so_led_green(0) <= so_led0_g;
	so_led_green(1) <= so_led1_g;
	so_led_green(2) <= so_led2_g;
	so_led_green(3) <= so_led3_g;

	so_led_blue(0) <= so_led0_b;
	so_led_blue(1) <= so_led1_b;
	so_led_blue(2) <= so_led2_b;
	so_led_blue(3) <= so_led3_b;

	so_led_basic(0) <= so_led4;
	so_led_basic(1) <= so_led5;
	so_led_basic(2) <= so_led6;
	so_led_basic(3) <= so_led7;

	-- Simulate the Pmod ACL2 peripheral
	u_tbc_pmod_sf3 : tbc_pmod_sf3
		port map(
			TBID             => TBID,
			BarrierTestStart => s_barrier_test_start,
			BarrierLogStart  => s_barrier_log_start,
			ci_sck           => so_pmod_sf3_sck,
			ci_csn           => so_pmod_sf3_csn,
			cio_copi         => sio_pmod_sf3_copi,
			cio_cipo         => sio_pmod_sf3_cipo,
			cio_wrpn         => sio_pmod_sf3_wrpn,
			cio_hldn         => sio_pmod_sf3_hldn
		);

	-- Simulate the Pmod CLS peripheral
	u_tbc_pmod_cls : tbc_pmod_cls
		port map(
			TBID             => TBID,
			BarrierTestStart => s_barrier_test_start,
			BarrierLogStart  => s_barrier_log_start,
			ci_sck           => so_pmod_cls_sck,
			ci_csn           => so_pmod_cls_csn,
			ci_copi          => so_pmod_cls_dq0,
			co_cipo          => si_pmod_cls_dq1
		);

	-- Simulate the board UART peripheral
	u_tbc_board_uart : tbc_board_uart
		port map(
			TBID             => TBID,
			BarrierTestStart => s_barrier_test_start,
			BarrierLogStart  => s_barrier_log_start,
			TransRec         => UartRxTransRec,
			ci_rxd           => so_uart_tx,
			co_txd           => si_uart_rx
		);

	-- Use the OSVVM UART for checking the UART RXD line
	u_osvvm_uart_rx : entity osvvm_uart.UartRx
		generic map(
			DEFAULT_BAUD          => UART_BAUD_PERIOD_115200,
			DEFAULT_NUM_DATA_BITS => UARTTB_DATA_BITS_8,
			DEFAULT_PARITY_MODE   => UARTTB_PARITY_NONE,
			DEFAULT_NUM_STOP_BITS => UARTTB_STOP_BITS_1
		)
		port map(
			TransRec     => UartRxTransRec,
			SerialDataIn => so_uart_tx
		);
end architecture simulation;
--------------------------------------------------------------------------------
