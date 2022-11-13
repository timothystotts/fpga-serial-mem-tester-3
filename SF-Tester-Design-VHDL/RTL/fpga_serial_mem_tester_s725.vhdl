--------------------------------------------------------------------------------
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
--------------------------------------------------------------------------------
-- \file fpga_serial_mem_tester_s725.vhdl
--
-- \brief A FPGA top-level design with the PMOD SF3 custom driver.
-- This design erases a subsector, programs the subsector, and then byte
-- compares the contents of the subsector. The data is displayed on a PMOD
-- CLS 16x2 dot-matrix LCD.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library UNIMACRO;
use UNIMACRO.vcomponents.all;

library work;
use work.lcd_text_functions_pkg.all;
use work.led_pwm_driver_pkg.all;
use work.sf_tester_fsm_pkg.all;
--------------------------------------------------------------------------------
entity fpga_serial_mem_tester_s725 is
	generic(
		parm_fast_simulation : integer := 0
	);
	port(
		-- Board clock
		CLK12MHZ : in std_logic;
		i_resetn : in std_logic;
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
		-- red LEDs of the multicolor
		eo_led0_r : out std_logic;
		eo_led1_r : out std_logic;
		-- green LEDs of the multicolor
		eo_led0_g : out std_logic;
		eo_led1_g : out std_logic;
		-- green LEDs of the regular LEDs
		eo_led2 : out std_logic;
		eo_led3 : out std_logic;
		eo_led4 : out std_logic;
		eo_led5 : out std_logic;
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
end entity fpga_serial_mem_tester_s725;
--------------------------------------------------------------------------------
architecture rtl of fpga_serial_mem_tester_s725 is

	-- Frequency of the clk_out1 clock output
	constant c_FCLK : natural := 40_000_000;

	-- MMCM and Processor System Reset signals for PLL clock generation from the
	-- Clocking Wizard and Synchronous Reset generation from the Processor System
	-- Reset module.
	signal s_mmcm_locked : std_logic;
	signal s_clk_40mhz   : std_logic;
	signal s_rst_40mhz   : std_logic;
	signal s_clk_7_37mhz : std_logic;
	signal s_rst_7_37mhz : std_logic;
	signal s_cls_ce_mhz   : std_logic;
	signal s_sf3_ce_div  : std_logic;

	-- Extra MMCM signals for full port map to the MMCM primative, where
	-- these signals will remain disconnected.
	signal s_clk_ignore_clk0b     : std_logic;
	signal s_clk_ignore_clk1b     : std_logic;
	signal s_clk_ignore_clk2      : std_logic;
	signal s_clk_ignore_clk2b     : std_logic;
	signal s_clk_ignore_clk3      : std_logic;
	signal s_clk_ignore_clk3b     : std_logic;
	signal s_clk_ignore_clk4      : std_logic;
	signal s_clk_ignore_clk5      : std_logic;
	signal s_clk_ignore_clk6      : std_logic;
	signal s_clk_ignore_clkfboutb : std_logic;
	signal s_clk_clkfbout         : std_logic;
	signal s_clk_pwrdwn           : std_logic;
	signal s_clk_resetin          : std_logic;

	-- Definitions of the Quad SPI driver to pass to the SF3 driver
	constant c_quad_spi_tx_fifo_count_bits : natural := 9;
	constant c_quad_spi_rx_fifo_count_bits : natural := 9;
	constant c_quad_spi_wait_count_bits    : natural := 9;

	-- Definitions of the Standard SPI driver to pass to the CLS driver
	constant c_stand_spi_tx_fifo_count_bits : natural := 11;
	constant c_stand_spi_rx_fifo_count_bits : natural := 11;
	constant c_stand_spi_wait_count_bits    : natural := 2;

	-- SPI signals to external tri-state
	signal sio_sf3_sck_o      : std_logic;
	signal sio_sf3_sck_t      : std_logic;
	signal sio_sf3_csn_o      : std_logic;
	signal sio_sf3_csn_t      : std_logic;
	signal sio_sf3_copi_dq0_o : std_logic;
	signal sio_sf3_copi_dq0_i : std_logic;
	signal sio_sf3_copi_dq0_t : std_logic;
	signal sio_sf3_cipo_dq1_o : std_logic;
	signal sio_sf3_cipo_dq1_i : std_logic;
	signal sio_sf3_cipo_dq1_t : std_logic;
	signal sio_sf3_wrpn_dq2_o : std_logic;
	signal sio_sf3_wrpn_dq2_i : std_logic;
	signal sio_sf3_wrpn_dq2_t : std_logic;
	signal sio_sf3_hldn_dq3_o : std_logic;
	signal sio_sf3_hldn_dq3_i : std_logic;
	signal sio_sf3_hldn_dq3_t : std_logic;

	signal s_sf3_command_ready       : std_logic;
	signal s_sf3_address_of_cmd      : std_logic_vector(31 downto 0);
	signal s_sf3_cmd_erase_subsector : std_logic;
	signal s_sf3_cmd_page_program    : std_logic;
	signal s_sf3_cmd_random_read     : std_logic;
	signal s_sf3_len_random_read     : std_logic_vector(8 downto 0);
	signal s_sf3_wr_data_stream      : std_logic_vector(7 downto 0);
	signal s_sf3_wr_data_valid       : std_logic;
	signal s_sf3_wr_data_ready       : std_logic;
	signal s_sf3_rd_data_stream      : std_logic_vector(7 downto 0);
	signal s_sf3_rd_data_valid       : std_logic;
	signal s_sf3_reg_status          : std_logic_vector(7 downto 0);
	signal s_sf3_reg_flag            : std_logic_vector(7 downto 0);

	-- Display update FSM state declarations
	type t_cls_update_state is (ST_CLS_IDLE, ST_CLS_CLEAR, ST_CLS_LINE1, ST_CLS_LINE2);

	signal s_cls_upd_pr_state : t_cls_update_state;
	signal s_cls_upd_nx_state : t_cls_update_state;

    -- CLS 
    constant c_cls_display_ce_div_ratio : natural := (c_FCLK / 50000 / 4);
    
	-- Signals for controlling the PMOD CLS custom driver.
	signal s_cls_command_ready     : std_logic;
	signal s_cls_wr_clear_display  : std_logic;
	signal s_cls_wr_text_line1     : std_logic;
	signal s_cls_wr_text_line2     : std_logic;
	signal s_cls_txt_ascii_line1   : std_logic_vector((16*8-1) downto 0);
	signal s_cls_txt_ascii_line2   : std_logic_vector((16*8-1) downto 0);
	signal s_cls_feed_is_idle      : std_logic;


	-- UART TX update FSM state declarations
	type t_uarttx_feed_state is (ST_UARTFEED_IDLE, ST_UARTFEED_DATA, ST_UARTFEED_WAIT);

	signal s_uartfeed_pr_state : t_uarttx_feed_state;
	signal s_uartfeed_nx_state : t_uarttx_feed_state;

	constant c_uart_k_preset : natural := 34;

	-- Signals for inferring tri-state buffer for CLS SPI bus outputs.
	signal so_pmod_cls_sck_o  : std_logic;
	signal so_pmod_cls_sck_t  : std_logic;
	signal so_pmod_cls_csn_o  : std_logic;
	signal so_pmod_cls_csn_t  : std_logic;
	signal so_pmod_cls_copi_o : std_logic;
	signal so_pmod_cls_copi_t : std_logic;

	-- switch inputs debounced
	signal si_switches : std_logic_vector(3 downto 0);
	signal s_sw_deb    : std_logic_vector(3 downto 0);

	-- button inputs debounced
	signal si_buttons : std_logic_vector(3 downto 0);
	signal s_btns_deb : std_logic_vector(3 downto 0);

	-- SF3 division down from 40 MHz
	constant c_sf3_tester_ce_div_ratio : natural := (c_FCLK / 5000000 / 4);

	-- SF3 Tester FSM state outputs
	signal s_sf3_tester_pr_state : t_tester_state;
	signal s_sf3_addr_start      : std_logic_vector(31 downto 0);
	signal s_sf3_pattern_start   : std_logic_vector(7 downto 0);
	signal s_sf3_pattern_incr    : std_logic_vector(7 downto 0);
	signal s_sf3_error_count     : natural range 0 to c_max_possible_byte_count;
	signal s_sf3_test_pass       : std_logic;
	signal s_sf3_test_done       : std_logic;

	-- LED color palletes
	signal s_color_led_red_value   : t_led_color_values((2 - 1) downto 0);
	signal s_color_led_green_value : t_led_color_values((2 - 1) downto 0);
	signal s_color_led_blue_value  : t_led_color_values((2 - 1) downto 0);
	signal s_basic_led_lumin_value : t_led_color_values((4 - 1) downto 0);

	-- UART TX signals to connect \ref uart_tx_only and \ref uart_tx_feed .
	signal s_uart_txt_ascii_line : std_logic_vector((35*8-1) downto 0);
	signal s_uart_tx_go          : std_logic;
	signal s_uart_txdata         : std_logic_vector(7 downto 0);
	signal s_uart_txvalid        : std_logic;
	signal s_uart_txready        : std_logic;

begin
	s_clk_pwrdwn  <= '0';
	s_clk_resetin <= not i_resetn;

	-- MMCME2_BASE: Base Mixed Mode Clock Manager
	--              Artix-7
	-- Xilinx HDL Language Template, version 2019.1

	MMCME2_BASE_inst : MMCME2_BASE
		generic map (
			BANDWIDTH       => "OPTIMIZED", -- Jitter programming (OPTIMIZED, HIGH, LOW)
			CLKFBOUT_MULT_F => 63.750,        -- Multiply value for all CLKOUT (2.000-64.000).
			CLKFBOUT_PHASE  => 0.0,         -- Phase offset in degrees of CLKFB (-360.000-360.000).
			CLKIN1_PERIOD   => 83.333,        -- Input clock period in ns to ps resolution (i.e. 33.333 is 30 MHz).
			                                -- CLKOUT0_DIVIDE - CLKOUT6_DIVIDE: Divide amount for each CLKOUT (1-128)
			CLKOUT1_DIVIDE   => 104,
			CLKOUT2_DIVIDE   => 1,
			CLKOUT3_DIVIDE   => 1,
			CLKOUT4_DIVIDE   => 1,
			CLKOUT5_DIVIDE   => 1,
			CLKOUT6_DIVIDE   => 1,
			CLKOUT0_DIVIDE_F => 19.125, -- Divide amount for CLKOUT0 (1.000-128.000).
			                            -- CLKOUT0_DUTY_CYCLE - CLKOUT6_DUTY_CYCLE: Duty cycle for each CLKOUT (0.01-0.99).
			CLKOUT0_DUTY_CYCLE => 0.5,
			CLKOUT1_DUTY_CYCLE => 0.5,
			CLKOUT2_DUTY_CYCLE => 0.5,
			CLKOUT3_DUTY_CYCLE => 0.5,
			CLKOUT4_DUTY_CYCLE => 0.5,
			CLKOUT5_DUTY_CYCLE => 0.5,
			CLKOUT6_DUTY_CYCLE => 0.5,
			-- CLKOUT0_PHASE - CLKOUT6_PHASE: Phase offset for each CLKOUT (-360.000-360.000).
			CLKOUT0_PHASE   => 0.0,
			CLKOUT1_PHASE   => 0.0,
			CLKOUT2_PHASE   => 0.0,
			CLKOUT3_PHASE   => 0.0,
			CLKOUT4_PHASE   => 0.0,
			CLKOUT5_PHASE   => 0.0,
			CLKOUT6_PHASE   => 0.0,
			CLKOUT4_CASCADE => FALSE, -- Cascade CLKOUT4 counter with CLKOUT6 (FALSE, TRUE)
			DIVCLK_DIVIDE   => 1,     -- Master division value (1-106)
			REF_JITTER1     => 0.010, -- Reference input jitter in UI (0.000-0.999).
			STARTUP_WAIT    => FALSE  -- Delays DONE until MMCM is locked (FALSE, TRUE)
		)
		port map (
			-- Clock Outputs: 1-bit (each) output: User configurable clock outputs
			CLKOUT0  => s_clk_40mhz,             -- 1-bit output: CLKOUT0
			CLKOUT0B => s_clk_ignore_clk0b,      -- 1-bit output: Inverted CLKOUT0
			CLKOUT1  => s_clk_7_37mhz,           -- 1-bit output: CLKOUT1
			CLKOUT1B => s_clk_ignore_clk1b,      -- 1-bit output: Inverted CLKOUT1
			CLKOUT2  => s_clk_ignore_clk2,       -- 1-bit output: CLKOUT2
			CLKOUT2B => s_clk_ignore_clk2b,      -- 1-bit output: Inverted CLKOUT2
			CLKOUT3  => s_clk_ignore_clk3,       -- 1-bit output: CLKOUT3
			CLKOUT3B => s_clk_ignore_clk3b,      -- 1-bit output: Inverted CLKOUT3
			CLKOUT4  => s_clk_ignore_clk4,       -- 1-bit output: CLKOUT4
			CLKOUT5  => s_clk_ignore_clk5,       -- 1-bit output: CLKOUT5
			CLKOUT6  => s_clk_ignore_clk6,       -- 1-bit output: CLKOUT6
			                                     -- Feedback Clocks: 1-bit (each) output: Clock feedback ports
			CLKFBOUT  => s_clk_clkfbout,         -- 1-bit output: Feedback clock
			CLKFBOUTB => s_clk_ignore_clkfboutb, -- 1-bit output: Inverted CLKFBOUT
			                                     -- Status Ports: 1-bit (each) output: MMCM status ports
			LOCKED => s_mmcm_locked,             -- 1-bit output: LOCK
			                                     -- Clock Inputs: 1-bit (each) input: Clock input
			CLKIN1 => CLK12MHZ,                 -- 1-bit input: Clock
			                                     -- Control Ports: 1-bit (each) input: MMCM control ports
			PWRDWN => s_clk_pwrdwn,              -- 1-bit input: Power-down
			RST    => s_clk_resetin,             -- 1-bit input: Reset
			                                     -- Feedback Clocks: 1-bit (each) input: Clock feedback ports
			CLKFBIN => s_clk_clkfbout            -- 1-bit input: Feedback clock
		);
	-- End of MMCME2_BASE_inst instantiation

	-- Reset Synchronization for 20 MHz clock
	u_reset_sync_40mhz : entity work.arty_reset_synchronizer(rtl)
		port map(
			i_clk_mhz     => s_clk_40mhz,
			i_rstn_global => i_resetn,
			o_rst_mhz     => s_rst_40mhz
		);

	-- Reset Synchronization for 20 MHz clock
	u_reset_sync_7_37mhz : entity work.arty_reset_synchronizer(rtl)
		port map(
			i_clk_mhz     => s_clk_7_37mhz,
			i_rstn_global => i_resetn,
			o_rst_mhz     => s_rst_7_37mhz
		);

	-- Color and Basic LED operation by 8-bit scalar per filament
	u_led_pwm_driver : entity work.led_pwm_driver(rtl)
		generic map (
			parm_color_led_count         => 2,
			parm_basic_led_count         => 4,
			parm_FCLK                    => c_FCLK,
			parm_pwm_period_milliseconds => 10
		)
		port map (
			i_clk                   => s_clk_40mhz,
			i_srst                  => s_rst_40mhz,
			i_color_led_red_value   => s_color_led_red_value,
			i_color_led_green_value => s_color_led_green_value,
			i_color_led_blue_value  => s_color_led_blue_value,
			i_basic_led_lumin_value => s_basic_led_lumin_value,
			eo_color_leds_r(1)      => eo_led1_r,
			eo_color_leds_r(0)      => eo_led0_r,
			eo_color_leds_g(1)      => eo_led1_g,
			eo_color_leds_g(0)      => eo_led0_g,
			eo_color_leds_b(1)      => eo_led1_b,
			eo_color_leds_b(0)      => eo_led0_b,
			eo_basic_leds_l(3)      => eo_led5,
			eo_basic_leds_l(2)      => eo_led4,
			eo_basic_leds_l(1)      => eo_led3,
			eo_basic_leds_l(0)      => eo_led2
		);

	-- 4x spi clock enable divider for PMOD CLS SCK output. No
	-- generated clock constraint. The 80 MHz or 20 MHz clock is divided
	-- down to 2.5 MHz; and later divided down to 625 KHz on
	-- the PMOD CLS bus.
	u_cls_ce_divider : entity work.clock_enable_divider(rtl)
		generic map(
			par_ce_divisor => c_cls_display_ce_div_ratio
		)
		port map(
			o_ce_div  => s_cls_ce_mhz,
			i_clk_mhz => s_clk_40mhz,
			i_rst_mhz => s_rst_40mhz,
			i_ce_mhz  => '1'
		);

	u_sf3_ce_divider : entity work.clock_enable_divider(rtl)
		generic map(
			par_ce_divisor => c_sf3_tester_ce_div_ratio
		)
		port map(
			o_ce_div  => s_sf3_ce_div,
			i_clk_mhz => s_clk_40mhz,
			i_rst_mhz => s_rst_40mhz,
			i_ce_mhz  => '1'
		);

	-- Synchronize and debounce the four input buttons on the Arty A7 to be
	-- debounced and exclusive of each other (ignored if more than one
	-- depressed at the same time).
	si_buttons <= ei_bt3 & ei_bt2 & ei_bt1 & ei_bt0;

	u_buttons_deb_0123 : entity work.multi_input_debounce(moore_fsm)
		generic map(
			FCLK => c_FCLK
		)
		port map(
			i_clk_mhz  => s_clk_40mhz,
			i_rst_mhz  => s_rst_40mhz,
			ei_buttons => si_buttons,
			o_btns_deb => s_btns_deb
		);

	-- Synchronize and debounce the four input switches on the Arty A7 to be
	-- debounced and exclusive of each other (ignored if more than one
	-- selected at the same time).
	si_switches <= ei_sw3 & ei_sw2 & ei_sw1 & ei_sw0;

	u_switches_deb_0123 : entity work.multi_input_debounce(moore_fsm)
		generic map(
			FCLK => c_FCLK
		)
		port map(
			i_clk_mhz  => s_clk_40mhz,
			i_rst_mhz  => s_rst_40mhz,
			ei_buttons => si_switches,
			o_btns_deb => s_sw_deb
		);

	-- Tri-state outputs of PMOD CLS custom driver.
	eo_pmod_cls_sck <= so_pmod_cls_sck_o  when so_pmod_cls_sck_t = '0' else 'Z';
	eo_pmod_cls_csn <= so_pmod_cls_csn_o  when so_pmod_cls_csn_t = '0' else 'Z';
	eo_pmod_cls_dq0 <= so_pmod_cls_copi_o when so_pmod_cls_copi_t = '0' else 'Z';

	-- Instance of the PMOD CLS driver for 16x2 character LCD display for purposes
	-- of an output display.
	u_pmod_cls_custom_driver : entity work.pmod_cls_custom_driver(rtl)
		generic map (
			parm_fast_simulation   => parm_fast_simulation,
			parm_FCLK              => c_FCLK,
			parm_FCLK_ce           => (c_FCLK / c_cls_display_ce_div_ratio),
			parm_ext_spi_clk_ratio => (c_cls_display_ce_div_ratio * 4),
			parm_tx_len_bits       => c_stand_spi_tx_fifo_count_bits,
			parm_wait_cyc_bits     => c_stand_spi_wait_count_bits,
			parm_rx_len_bits       => c_stand_spi_rx_fifo_count_bits
		)
		port map (
			i_clk_40mhz            => s_clk_40mhz,
			i_rst_40mhz            => s_rst_40mhz,
			i_ce_mhz               => s_cls_ce_mhz,
			eo_sck_t               => so_pmod_cls_sck_t,
			eo_sck_o               => so_pmod_cls_sck_o,
			eo_csn_t               => so_pmod_cls_csn_t,
			eo_csn_o               => so_pmod_cls_csn_o,
			eo_copi_t              => so_pmod_cls_copi_t,
			eo_copi_o              => so_pmod_cls_copi_o,
			ei_cipo                => ei_pmod_cls_dq1,
			o_command_ready        => s_cls_command_ready,
			i_cmd_wr_clear_display => s_cls_wr_clear_display,
			i_cmd_wr_text_line1    => s_cls_wr_text_line1,
			i_cmd_wr_text_line2    => s_cls_wr_text_line2,
			i_dat_ascii_line1      => s_cls_txt_ascii_line1,
			i_dat_ascii_line2      => s_cls_txt_ascii_line2
		);

	-- Custom driver for the PMOD SF3 enabling erase of a subsector,
	-- programming the data of a page, and reading the data of a page.
	-- Note that each subsector contains 16 successive pages.
	u_pmod_sf3_custom_driver : entity work.pmod_sf3_custom_driver
		generic map (
			parm_fast_simulation   => parm_fast_simulation,
			parm_FCLK              => c_FCLK,
			parm_ext_spi_clk_ratio => (c_sf3_tester_ce_div_ratio * 4),
			parm_tx_len_bits       => c_quad_spi_tx_fifo_count_bits,
			parm_wait_cyc_bits     => c_quad_spi_wait_count_bits,
			parm_rx_len_bits       => c_quad_spi_rx_fifo_count_bits
		)
		port map (
			i_clk_mhz             => s_clk_40mhz,
			i_rst_mhz             => s_rst_40mhz,
			i_ce_mhz_div          => s_sf3_ce_div,
			eio_sck_o             => sio_sf3_sck_o,
			eio_sck_t             => sio_sf3_sck_t,
			eio_csn_o             => sio_sf3_csn_o,
			eio_csn_t             => sio_sf3_csn_t,
			eio_copi_dq0_o        => sio_sf3_copi_dq0_o,
			eio_copi_dq0_i        => sio_sf3_copi_dq0_i,
			eio_copi_dq0_t        => sio_sf3_copi_dq0_t,
			eio_cipo_dq1_o        => sio_sf3_cipo_dq1_o,
			eio_cipo_dq1_i        => sio_sf3_cipo_dq1_i,
			eio_cipo_dq1_t        => sio_sf3_cipo_dq1_t,
			eio_wrpn_dq2_o        => sio_sf3_wrpn_dq2_o,
			eio_wrpn_dq2_i        => sio_sf3_wrpn_dq2_i,
			eio_wrpn_dq2_t        => sio_sf3_wrpn_dq2_t,
			eio_hldn_dq3_o        => sio_sf3_hldn_dq3_o,
			eio_hldn_dq3_i        => sio_sf3_hldn_dq3_i,
			eio_hldn_dq3_t        => sio_sf3_hldn_dq3_t,
			o_command_ready       => s_sf3_command_ready,
			i_address_of_cmd      => s_sf3_address_of_cmd,
			i_cmd_erase_subsector => s_sf3_cmd_erase_subsector,
			i_cmd_page_program    => s_sf3_cmd_page_program,
			i_cmd_random_read     => s_sf3_cmd_random_read,
			i_len_random_read     => s_sf3_len_random_read,
			i_wr_data_stream      => s_sf3_wr_data_stream,
			i_wr_data_valid       => s_sf3_wr_data_valid,
			o_wr_data_ready       => s_sf3_wr_data_ready,
			o_rd_data_stream      => s_sf3_rd_data_stream,
			o_rd_data_valid       => s_sf3_rd_data_valid,
			o_reg_status          => s_sf3_reg_status,
			o_reg_flag            => s_sf3_reg_flag
		);

	-- PMOD SF3 Quad SPI tri-state inout connections for QSPI bus
	eo_pmod_sf3_sck <= sio_sf3_sck_o when sio_sf3_sck_t = '0' else 'Z';

	eo_pmod_sf3_csn <= sio_sf3_csn_o when sio_sf3_csn_t = '0' else 'Z';

	eio_pmod_sf3_copi_dq0 <= sio_sf3_copi_dq0_o when sio_sf3_copi_dq0_t = '0' else 'Z';
	sio_sf3_copi_dq0_i    <= eio_pmod_sf3_copi_dq0;

	eio_pmod_sf3_cipo_dq1 <= sio_sf3_cipo_dq1_o when sio_sf3_cipo_dq1_t = '0' else 'Z';
	sio_sf3_cipo_dq1_i    <= eio_pmod_sf3_cipo_dq1;

	eio_pmod_sf3_wrpn_dq2 <= sio_sf3_wrpn_dq2_o when sio_sf3_wrpn_dq2_t = '0' else 'Z';
	sio_sf3_wrpn_dq2_i    <= eio_pmod_sf3_wrpn_dq2;

	eio_pmod_sf3_hldn_dq3 <= sio_sf3_hldn_dq3_o when sio_sf3_hldn_dq3_t = '0' else 'Z';
	sio_sf3_hldn_dq3_i    <= eio_pmod_sf3_hldn_dq3;

	-- SF3 Tester FSM
	u_sf_tester_fsm : entity work.sf_tester_fsm(rtl)
		generic map (
			parm_fast_simulation         => parm_fast_simulation,
			parm_FCLK                    => c_FCLK,
			parm_sf3_tester_ce_div_ratio => c_sf3_tester_ce_div_ratio,
			parm_pattern_startval_a      => c_tester_pattern_startval_a,
			parm_pattern_incrval_a       => c_tester_pattern_incrval_a,
			parm_pattern_startval_b      => c_tester_pattern_startval_b,
			parm_pattern_incrval_b       => c_tester_pattern_incrval_b,
			parm_pattern_startval_c      => c_tester_pattern_startval_c,
			parm_pattern_incrval_c       => c_tester_pattern_incrval_c,
			parm_pattern_startval_d      => c_tester_pattern_startval_d,
			parm_pattern_incrval_d       => c_tester_pattern_incrval_d,
			parm_max_possible_byte_count => c_max_possible_byte_count
		)
		port map (
			i_clk_40mhz               => s_clk_40mhz,
			i_rst_40mhz               => s_rst_40mhz,
			i_ce_div                  => s_sf3_ce_div,
			i_sf3_command_ready       => s_sf3_command_ready,
			i_sf3_rd_data_valid       => s_sf3_rd_data_valid,
			i_sf3_rd_data_stream      => s_sf3_rd_data_stream,
			i_sf3_wr_data_ready       => s_sf3_wr_data_ready,
			o_sf3_wr_data_stream      => s_sf3_wr_data_stream,
			o_sf3_wr_data_valid       => s_sf3_wr_data_valid,
			o_sf3_len_random_read     => s_sf3_len_random_read,
			o_sf3_cmd_random_read     => s_sf3_cmd_random_read,
			o_sf3_cmd_page_program    => s_sf3_cmd_page_program,
			o_sf3_cmd_erase_subsector => s_sf3_cmd_erase_subsector,
			o_sf3_address_of_cmd      => s_sf3_address_of_cmd,
			i_buttons_debounced       => s_btns_deb,
			i_switches_debounced      => s_sw_deb,
			o_tester_pr_state         => s_sf3_tester_pr_state,
			o_addr_start              => s_sf3_addr_start,
			o_pattern_start           => s_sf3_pattern_start,
			o_pattern_incr            => s_sf3_pattern_incr,
			o_error_count             => s_sf3_error_count,
			o_test_pass               => s_sf3_test_pass,
			o_test_done               => s_sf3_test_done
		);

	-- LED Palette Updater
	u_led_palette_updater : entity work.led_palette_updater(rtl)
		generic map (
			parm_color_led_count => 2,
			parm_basic_led_count => 4
		)
		port map (
			i_clk                   => s_clk_40mhz,
			i_srst                  => s_rst_40mhz,
			o_color_led_red_value   => s_color_led_red_value,
			o_color_led_green_value => s_color_led_green_value,
			o_color_led_blue_value  => s_color_led_blue_value,
			o_basic_led_lumin_value => s_basic_led_lumin_value,
			i_test_pass             => s_sf3_test_pass,
			i_test_done             => s_sf3_test_done,
			i_tester_pr_state       => s_sf3_tester_pr_state
		);

	-- SF3 Testing to ASCII outputs
	u_sf_testing_to_ascii : entity work.sf_testing_to_ascii(rtl)
		generic map (
			parm_pattern_startval_a      => c_tester_pattern_startval_a,
			parm_pattern_incrval_a       => c_tester_pattern_incrval_a,
			parm_pattern_startval_b      => c_tester_pattern_startval_b,
			parm_pattern_incrval_b       => c_tester_pattern_incrval_b,
			parm_pattern_startval_c      => c_tester_pattern_startval_c,
			parm_pattern_incrval_c       => c_tester_pattern_incrval_c,
			parm_pattern_startval_d      => c_tester_pattern_startval_d,
			parm_pattern_incrval_d       => c_tester_pattern_incrval_d,
			parm_max_possible_byte_count => c_max_possible_byte_count
		)
		port map (
			i_clk_40mhz       => s_clk_40mhz,
			i_rst_40mhz       => s_rst_40mhz,
			i_addr_start      => s_sf3_addr_start,
			i_pattern_start   => s_sf3_pattern_start,
			i_pattern_incr    => s_sf3_pattern_incr,
			i_error_count     => s_sf3_error_count,
			i_tester_pr_state => s_sf3_tester_pr_state,
			o_lcd_ascii_line1 => s_cls_txt_ascii_line1,
			o_lcd_ascii_line2 => s_cls_txt_ascii_line2,
			o_term_ascii_line => s_uart_txt_ascii_line
		);

	-- LCD Update FSM
	u_lcd_text_feed : entity work.lcd_text_feed(rtl)
		generic map (
			parm_fast_simulation => parm_fast_simulation,
			parm_FCLK_ce         => (c_FCLK / c_cls_display_ce_div_ratio)
		)
		port map (
			i_clk_40mhz            => s_clk_40mhz,
			i_rst_40mhz            => s_rst_40mhz,
			i_ce_mhz               => s_cls_ce_mhz,
			i_lcd_command_ready    => s_cls_command_ready,
			o_lcd_wr_clear_display => s_cls_wr_clear_display,
			o_lcd_wr_text_line1    => s_cls_wr_text_line1,
			o_lcd_wr_text_line2    => s_cls_wr_text_line2,
			o_lcd_feed_is_idle     => s_cls_feed_is_idle
		);

	-- TX ONLY UART function to print the two lines of the PMOD CLS output as a
	-- single line on the dumb terminal, at the same rate as the PMOD CLS updates.
	s_uart_tx_go <= s_cls_wr_clear_display;

	u_uart_tx_only : entity work.uart_tx_only(moore_fsm_recursive)
		generic map (
			parm_BAUD => 115200
		)
		port map (
			i_clk_40mhz   => s_clk_40mhz,
			i_rst_40mhz   => s_rst_40mhz,
			i_clk_7_37mhz => s_clk_7_37mhz,
			i_rst_7_37mhz => s_rst_7_37mhz,
			eo_uart_tx    => eo_uart_tx,
			i_tx_data     => s_uart_txdata,
			i_tx_valid    => s_uart_txvalid,
			o_tx_ready    => s_uart_txready
		);

	u_uart_tx_feed : entity work.uart_tx_feed(rtl)
		port map (
			i_clk_40mhz      => s_clk_40mhz,
			i_rst_40mhz      => s_rst_40mhz,
			o_tx_data        => s_uart_txdata,
			o_tx_valid       => s_uart_txvalid,
			i_tx_ready       => s_uart_txready,
			i_tx_go          => s_uart_tx_go,
			i_dat_ascii_line => s_uart_txt_ascii_line
		);

end architecture rtl;
--------------------------------------------------------------------------------
