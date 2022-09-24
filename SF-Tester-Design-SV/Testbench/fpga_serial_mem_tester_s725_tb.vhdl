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
-- \file fpga_serial_mem_tester_s725_tb.vhd
--
-- \brief 32 MiB NOR Flash over Quad-SPI as Extended SPI, visual testbench.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--------------------------------------------------------------------------------
entity fpga_serial_mem_tester_s725_tb is
end entity fpga_serial_mem_tester_s725_tb;
--------------------------------------------------------------------------------
architecture simultation of fpga_serial_mem_tester_s725_tb is
	component fpga_serial_mem_tester_s725 is
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
	end component fpga_serial_mem_tester_s725;

	-- module N25QxxxTop (S, C, HOLD_DQ3, DQ0, DQ1, Vcc, Vpp_W_DQ2)
	--component N25Qxxx_wrapper is
	--	port (
	--		S         : in    std_logic;
	--		Clow      : in    std_logic;
	--		HOLD_DQ3  : inout std_logic;
	--		DQ0       : inout std_logic;
	--		DQ1       : inout std_logic;
	--		Vpp_W_DQ2 : inout std_logic
	--	);
	--end component N25Qxxx_wrapper;

	constant c_clock_half_period : time := 5 ns;
	signal run_clock             : boolean;

	signal s_clk          : std_logic;
	signal s_rst          : std_logic;
	signal s_sf3_sck      : std_logic;
	signal s_sf3_csn      : std_logic;
	signal s_sf3_copi_dq0 : std_logic;
	signal s_sf3_cipo_dq1 : std_logic;
	signal s_sf3_wrpn_dq2 : std_logic;
	signal s_sf3_hldn_dq3 : std_logic;
	signal s_led0_b       : std_logic;
	signal s_led1_b       : std_logic;
	signal s_led0_g       : std_logic;
	signal s_led1_g       : std_logic;
	signal s_led0_r       : std_logic;
	signal s_led1_r       : std_logic;
	signal s_led2         : std_logic;
	signal s_led3         : std_logic;
	signal s_led4         : std_logic;
	signal s_led5         : std_logic;
	signal s_bt0          : std_logic;
	signal s_bt1          : std_logic;
	signal s_bt2          : std_logic;
	signal s_bt3          : std_logic;
	signal s_sw0          : std_logic;
	signal s_sw1          : std_logic;
	signal s_sw2          : std_logic;
	signal s_sw3          : std_logic;
	signal s_cls_sck      : std_logic;
	signal s_cls_csn      : std_logic;
	signal s_cls_copi     : std_logic;
	signal s_cls_cipo     : std_logic;
	signal s_uart_tx      : std_logic;
	signal s_uart_rx      : std_logic;
begin
	-- N25Q flash part model
	--u_n25q_part : N25Qxxx_wrapper
	--	port map(
	--		S => s_sf3_csn,
	--		Clow => s_sf3_sck,
	--		HOLD_DQ3 => s_sf3_hldn_dq3,
	--		DQ0 => s_sf3_copi_dq0,
	--		DQ1 => s_sf3_cipo_dq1,
	--		Vpp_W_DQ2 => s_wrpn_dq2);

	-- UUT: unit under test
	u_fpga_serial_mem_tester_s725 : fpga_serial_mem_tester_s725
		generic map (
			parm_fast_simulation => 1
		)
		port map (
			CLK100MHZ             => s_clk,
			i_resetn              => s_rst,
			eo_pmod_sf3_sck       => s_sf3_sck,
			eo_pmod_sf3_csn       => s_sf3_csn,
			eio_pmod_sf3_copi_dq0 => s_sf3_copi_dq0,
			eio_pmod_sf3_cipo_dq1 => s_sf3_cipo_dq1,
			eio_pmod_sf3_wrpn_dq2 => s_sf3_wrpn_dq2,
			eio_pmod_sf3_hldn_dq3 => s_sf3_hldn_dq3,
			eo_led0_b             => s_led0_b,
			eo_led1_b             => s_led1_b,
			eo_led0_r             => s_led0_r,
			eo_led1_r             => s_led1_r,
			eo_led0_g             => s_led0_g,
			eo_led1_g             => s_led1_g,
			eo_led2               => s_led2,
			eo_led3               => s_led3,
			eo_led4               => s_led4,
			eo_led5               => s_led5,
			ei_bt0                => s_bt0,
			ei_bt1                => s_bt1,
			ei_bt2                => s_bt2,
			ei_bt3                => s_bt3,
			ei_sw0                => s_sw0,
			ei_sw1                => s_sw1,
			ei_sw2                => s_sw2,
			ei_sw3                => s_sw3,
			eo_pmod_cls_csn       => s_cls_csn,
			eo_pmod_cls_sck       => s_cls_sck,
			eo_pmod_cls_dq0       => s_cls_copi,
			ei_pmod_cls_dq1       => s_cls_cipo,
			eo_uart_tx            => s_uart_tx,
			ei_uart_rx            => s_uart_rx
		);

	-- Signal hold values for constant input into UUT
	s_bt0      <= '0';
	s_bt1      <= '0';
	s_bt2      <= '0';
	s_bt3      <= '0';
	s_sw0      <= '1'; -- hold switch 0 to ON position to execute test for Pattern A
	s_sw1      <= '0';
	s_sw2      <= '0';
	s_sw3      <= '0';
	s_cls_cipo <= '0';
	s_uart_rx  <= '1';

	-- Simulated data response of N25Q just to show visiual data on the waveform
	-- with no meaning other than if the Finite State Machines properly capture
	-- the received data from the bus and pass it on in-tact in the system
	-- interface. The Micron memory model cannot be used at this time as its
	-- Verilog model uses signal forcing, and Vivado 2019.1 does not support
	-- signal forcing in Mixed Language simulation. This is a cheap,
	-- inexpensive way to use the visual waveform to debug a great deal of
	-- the N25Q driver without a real memory model. For a full automated
	-- testbench, it will be necessary to create a cheap or realistic memory
	-- model with either ideal or datasheet-oriented timing of the signals.
	-- Consider having the event on signals s_quadio_highz and s_sf3_csn instead.
	p_extend_seq_dat : process
		variable v_seq       : unsigned(7 downto 0) := x"00";
		variable v_cnt_msb   : natural range 0 to 7 := 0;
		variable v_track_cmd : std_logic            := '1';
	begin
		s_sf3_hldn_dq3 <= 'Z';
		s_sf3_wrpn_dq2 <= 'Z';
		s_sf3_cipo_dq1 <= 'Z';
		s_sf3_copi_dq0 <= 'Z';

		loop_forever : loop
			wait on s_sf3_csn, s_sf3_sck;

			-- on the falling edge of SCK, setup and hold a reply value on the
			-- SPI quad i/o to simulate answers back from the SPI Flash
			if s_sf3_sck'event and (s_sf3_sck = '0') then
				if (s_sf3_csn = '0') then
					wait for 10 ns;

					if (v_cnt_msb > 0) then
						v_cnt_msb := v_cnt_msb - 1;
						if (v_track_cmd = '0') then
							s_sf3_cipo_dq1 <= std_logic(v_seq(v_cnt_msb));
						else
							s_sf3_cipo_dq1 <= 'Z';
						end if;
					else
						v_cnt_msb      := 7;
						v_track_cmd    := '0';
						v_seq          := v_seq + unsigned'(x"01");
						s_sf3_cipo_dq1 <= std_logic(v_seq(v_cnt_msb));
					end if;
				end if;
			-- on the event of s_sf3_sck 4x clock or change of slave select, test if
			-- necessary to High-Z the Quad I/O bus.
			elsif s_sf3_sck'event or s_sf3_csn'event then
				if (s_sf3_csn = '1') then
					wait for 10 ns;

					s_sf3_hldn_dq3 <= 'Z';
					s_sf3_wrpn_dq2 <= 'Z';
					s_sf3_cipo_dq1 <= 'Z';
					s_sf3_copi_dq0 <= 'Z';
					v_track_cmd    := '1';
					-- start one nibble before 0x00 as to simulate a working Flash
					-- chip response for a Quad I/O READ command reponse with a
					-- single SPI clock wait cycle after the 5 byte command.
					v_seq     := x"EF";
					v_cnt_msb := 7;
				end if;
			end if;
		end loop loop_forever;
	end process p_extend_seq_dat;

	-- toggling clock until boolean run_clock goes false, then halt
	p_run_clock : process
	begin
		s_clk <= '0';
		wait for c_clock_half_period;

		forever_loop : while run_clock loop
			s_clk <= not s_clk;
			wait for c_clock_half_period;
		end loop forever_loop;

		wait;
	end process p_run_clock;

	-- reset signal that waits four clocks, asserts high four clocks, then
	-- deasserts
	p_run_rst : process
	begin
		run_clock <= true;

		s_rst <= '1';

		wait_loop_1 : for iter in 1 to 100 loop
			wait until rising_edge(s_clk);
		end loop wait_loop_1;

		s_rst <= '0';

		wait_loop_0 : for iter in 1 to 100 loop
			wait until rising_edge(s_clk);
		end loop wait_loop_0;

		s_rst <= '1';

		wait_loop_run_b : for iter2 in 1 to 60 loop
			wait_loop_run_a : for iter in 1 to 100000000 loop
				wait until rising_edge(s_clk);
			end loop wait_loop_run_a;
		end loop wait_loop_run_b;

		run_clock <= false;
		wait;
	end process p_run_rst;

end architecture simultation;
--------------------------------------------------------------------------------
