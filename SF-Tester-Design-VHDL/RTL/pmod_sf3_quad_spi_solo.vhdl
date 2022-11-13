--------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2020 Timothy Stotts
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
-- \file pmod_sf3_quad_spi_solo.vhd
--
-- \brief Custom Interface to the PMOD SF3 N25Q flash chip via Ehanced SPI at
-- boot-time and future implementation provision for Quad I/O SPI at run-time.
-- This FSM operates the \ref pmod_generic_qspi_solo module to communicate with
-- the N25Q flash chip for basic random read, subsector erase, and page program.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--------------------------------------------------------------------------------
entity pmod_sf3_quad_spi_solo is
	generic(
		-- Disable or enable fast FSM delays for simulation instead of impelementation.
		parm_fast_simulation : integer := 0;
		-- Actual frequency in Hz of \ref i_ext_spi_clk_4x
		parm_FCLK : natural := 20_000_000;
		-- LOG2 of the TX FIFO max count
		parm_tx_len_bits : natural := 9;
		-- LOG2 of max Wait Cycles count between end of TX and start of RX
		parm_wait_cyc_bits : natural := 9;
		-- LOG2 of the RX FIFO max count
		parm_rx_len_bits : natural := 9
	);
	port(
		-- FPGA system clock and reset
		i_ext_spi_clk_x : in std_logic;
		i_srst          : in std_logic;
		i_spi_ce_4x     : in std_logic;
		-- system interface to the \ref pmod_generic_spi_solo
		o_go_enhan  : out std_logic;
		o_go_quadio : out std_logic;
		i_spi_idle  : in  std_logic;
		o_tx_len    : out std_logic_vector((parm_tx_len_bits - 1) downto 0);
		o_wait_cyc  : out std_logic_vector((parm_wait_cyc_bits - 1) downto 0);
		o_rx_len    : out std_logic_vector((parm_rx_len_bits - 1) downto 0);
		-- TX interface to the \ref pmod_generic_spi_solo
		o_tx_data    : out std_logic_vector(7 downto 0);
		o_tx_enqueue : out std_logic;
		i_tx_ready   : in  std_logic;
		-- RX interface to the \ref pmod_generic_spi_solo
		i_rx_data    : in  std_logic_vector(7 downto 0);
		o_rx_dequeue : out std_logic;
		i_rx_valid   : in  std_logic;
		i_rx_avail   : in  std_logic;
		-- FPGA system interface
		o_command_ready       : out std_logic;
		i_address_of_cmd      : in  std_logic_vector(31 downto 0);
		i_cmd_erase_subsector : in  std_logic;
		i_cmd_page_program    : in  std_logic;
		i_cmd_random_read     : in  std_logic;
		i_len_random_read     : in  std_logic_vector(8 downto 0);
		i_wr_data_stream      : in  std_logic_vector(7 downto 0);
		i_wr_data_valid       : in  std_logic;
		o_wr_data_ready       : out std_logic;
		o_rd_data_stream      : out std_logic_vector(7 downto 0);
		o_rd_data_valid       : out std_logic;
		-- statuses of the N25Q flash chip
		o_reg_status : out std_logic_vector(7 downto 0);
		o_reg_flag   : out std_logic_vector(7 downto 0)
	);
end entity pmod_sf3_quad_spi_solo;
--------------------------------------------------------------------------------
architecture hybrid_fsm of pmod_sf3_quad_spi_solo is
	-- FSM-related declarations
	type t_state is (
			-- check the flag status on power-up
			ST_BOOTA_INIT,
			ST_BOOTA_STATUS_CMD, ST_BOOTA_STATUS_WAIT, ST_BOOTA_STATUS_RX,
			ST_BOOTA_STATUS_CHK0, ST_BOOTA_STATUS_CHK1,
			-- Boot init the Status Register
			ST_BOOT0_WEN_STATUS, ST_BOOT0_WEN_STWAIT,
			ST_BOOT0_WR_STATUS_CMD, ST_BOOT0_WR_STATUS_DAT,
			ST_BOOT0_IDLE_STWAIT,
			ST_BOOT0_FLAGST_CMD, ST_BOOT0_FLAGST_WAIT, ST_BOOT0_FLAGST_RX,
			ST_BOOT0_FLAGST_CHK0, ST_BOOT0_FLAGST_CHK1,
			-- Idle state
			ST_WAIT_IDLE, ST_IDLE,
			-- Read up to one page states
			ST_RD_CMD, ST_RD_ADDR, ST_RD_WAIT_0, ST_RD_STREAM,
			-- Erase one subsector states
			ST_WEN_ERASE, ST_WEN_WAIT2, ST_ERASE_CMD, ST_ERASE_ADDR,
			ST_ERASE_WAIT,
			-- Status check states
			ST_FLAGST_CMD, ST_FLAGST_WAIT, ST_FLAGST_RX,
			ST_FLAGST_CHK0, ST_FLAGST_CHK1,
			-- Write a full page states
			ST_WEN_PROGR, ST_WEN_WAIT3, ST_PAGE_PROGR_CMD, ST_PAGE_PROGR_ADDR,
			ST_PAGE_PROGR_STREAM, ST_PROGR_WAIT
		);

	signal s_pr_state                      : t_state := ST_BOOTA_INIT;
	signal s_nx_state                      : t_state := ST_BOOTA_INIT;
	attribute fsm_encoding                 : string;
	attribute fsm_encoding of s_pr_state   : signal is "auto";
	attribute fsm_safe_state               : string;
	attribute fsm_safe_state of s_pr_state : signal is "default_state";

	-- Timer 1 constants (strategy #1)
	constant c_t_boot_init0 : natural := parm_FCLK * 2 / 10000; -- minimum of 200 us at 120 MHz
	constant c_t_boot_init1 : natural := 20;                    -- a small arbitrary delay, FIXME
	constant c_t_boot_init2 : natural := 20;                    -- a small arbitrary delay, FIXME
	constant c_t_cmd_addr : natural := 4;
	constant c_tmax       : natural := c_t_boot_init0 - 1;
	signal s_t            : natural range 0 to c_tmax;

	constant c_n25q_cmd_write_enable                  : std_logic_vector(7 downto 0)  := x"06";
	constant c_n25q_cmd_write_enh_vol_cfg_reg         : std_logic_vector(7 downto 0)  := x"61";
	constant c_n25q_dat_enh_vol_cfg_reg_as_pmod_sf3   : std_logic_vector(7 downto 0)  := x"BF";
	constant c_n25q_cmd_write_nonvol_cfg_reg          : std_logic_vector(7 downto 0)  := x"B1";
	constant c_n25q_dat_nonvol_cfg_reg_as_pmod_sf3    : std_logic_vector(15 downto 0) := "0001111111011111";
	constant c_n25q_cmd_quadio_read_memory_4byte_addr : std_logic_vector(7 downto 0)  := x"EC";
	constant c_n25q_cmd_quadio_read_dummy_cycles      : natural                       := 1;
	constant c_n25q_cmd_extend_read_memory_4byte_addr : std_logic_vector(7 downto 0)  := x"0C";
	constant c_n25q_cmd_extend_read_dummy_cycles      : natural                       := 8;
	constant c_n25q_cmd_any_erase_subsector           : std_logic_vector(7 downto 0)  := x"21";
	constant c_n25q_cmd_read_status_register          : std_logic_vector(7 downto 0)  := x"05";
	constant c_n25q_cmd_write_status_register         : std_logic_vector(7 downto 0)  := x"01";
	constant c_n25q_dat_status_reg_as_pmod_sf3        : std_logic_vector(7 downto 0)  := x"00";
	constant c_n25q_cmd_any_page_program              : std_logic_vector(7 downto 0)  := x"12";
	constant c_n25q_cmd_read_flag_status_register     : std_logic_vector(7 downto 0)  := x"70";
	constant c_n25q_cmd_clear_flag_status_register    : std_logic_vector(7 downto 0)  := x"50";

	constant c_n25q_txlen_cmd_read_status_register          : natural := 1;
	constant c_n25q_rxlen_cmd_read_status_register          : natural := 1;
	constant c_n25q_txlen_cmd_write_enable                  : natural := 1;
	constant c_n25q_txlen_cmd_write_status_register         : natural := 2;
	constant c_n25q_txlen_cmd_read_flag_status_register     : natural := 1;
	constant c_n25q_rxlen_cmd_read_flag_status_register     : natural := 1;
	constant c_n25q_txlen_cmd_write_enh_vol_cfg_reg         : natural := 2;
	constant c_n25q_txlen_cmd_extend_read_memory_4byte_addr : natural := 5;
	constant c_n25q_txlen_cmd_any_erase_subsector           : natural := 5;
	constant c_n25q_txlen_cmd_any_page_program              : natural := 5;

	constant c_addr_byte_index_preset : integer := 3;

	signal s_wait_len_val                  : integer range -1 to 511;
	signal s_wait_len_aux                  : integer range -1 to 511;
	signal s_addr_byte_index_val           : integer range -1 to 3;
	signal s_addr_byte_index_aux           : integer range -1 to 3;
	signal s_read_status_register_val      : std_logic_vector(7 downto 0);
	signal s_read_status_register_aux      : std_logic_vector(7 downto 0);
	signal s_read_flag_status_register_val : std_logic_vector(7 downto 0);
	signal s_read_flag_status_register_aux : std_logic_vector(7 downto 0);

	constant c_boot_in_quadio : boolean := false;
begin
	-- Strategy #1 timer
	p_fsm_timer1 : process(i_ext_spi_clk_x)
	begin
		if rising_edge(i_ext_spi_clk_x) then
			if (i_srst = '1') then
				s_t <= 0;
			elsif (i_spi_ce_4x = '1') then
				if (s_nx_state /= s_pr_state) then
					s_t <= 0;
				elsif (s_t /= c_tmax) then
					s_t <= s_t + 1;
				end if;
			end if;
		end if;
	end process p_fsm_timer1;

	-- FSM state register plus auxiliary registers
	p_fsm_state_aux : process(i_ext_spi_clk_x)
	begin
		if rising_edge(i_ext_spi_clk_x) then
			if (i_srst = '1') then
				s_pr_state <= ST_BOOTA_INIT;

				s_wait_len_aux                  <= 0;
				s_addr_byte_index_aux           <= 0;
				s_read_status_register_aux      <= x"00";
				s_read_flag_status_register_aux <= x"00";
			elsif (i_spi_ce_4x = '1') then
				s_pr_state <= s_nx_state;

				s_wait_len_aux                  <= s_wait_len_val;
				s_addr_byte_index_aux           <= s_addr_byte_index_val;
				s_read_status_register_aux      <= s_read_status_register_val;
				s_read_flag_status_register_aux <= s_read_flag_status_register_val;
			end if;
		end if;
	end process p_fsm_state_aux;

	-- FSM combinatorial logic providing multiple outputs, assigned in every state,
	-- as well as changes in auxiliary values, and calculation of the next FSM
	-- state. Refer to the FSM state machine drawings in document:
	-- \ref SF-Tester-Design-Diagrams.pdf .
	p_fsm_comb : process(s_pr_state, i_tx_ready, s_t, i_rx_avail, i_spi_idle,
			i_address_of_cmd, i_len_random_read, i_rx_data, i_rx_valid,
			s_wait_len_aux, s_addr_byte_index_aux,
			s_read_status_register_aux, s_read_flag_status_register_aux,
			i_cmd_random_read, i_cmd_erase_subsector, i_cmd_page_program,
			i_wr_data_stream, i_wr_data_valid)
	begin
		-- defaults
		o_tx_data                       <= x"00";
		o_tx_enqueue                    <= '0';
		o_rx_dequeue                    <= '0';
		o_tx_len                        <= std_logic_vector(to_unsigned(0, o_tx_len'length));
		o_rx_len                        <= std_logic_vector(to_unsigned(0, o_rx_len'length));
		o_wait_cyc                      <= std_logic_vector(to_unsigned(0, o_wait_cyc'length));
		o_go_enhan                      <= '0';
		o_go_quadio                     <= '0';
		s_wait_len_val                  <= s_wait_len_aux;
		s_addr_byte_index_val           <= s_addr_byte_index_aux;
		s_read_status_register_val      <= s_read_status_register_aux;
		s_read_flag_status_register_val <= s_read_flag_status_register_aux;

		o_rd_data_stream <= (others => '0');
		o_rd_data_valid  <= '0';
		o_wr_data_ready  <= '0';

		-- machine
		case (s_pr_state) is
			when ST_BOOTA_STATUS_CMD =>
				o_command_ready <= '0';
				o_tx_data       <= c_n25q_cmd_read_status_register;
				o_tx_len        <= std_logic_vector(to_unsigned(c_n25q_txlen_cmd_read_status_register, o_tx_len'length));
				o_rx_len        <= std_logic_vector(to_unsigned(c_n25q_rxlen_cmd_read_status_register, o_rx_len'length));
				o_tx_enqueue    <= i_tx_ready;
				o_go_enhan      <= i_tx_ready;

				if (i_tx_ready = '1') then
					s_nx_state <= ST_BOOTA_STATUS_WAIT;
				else
					s_nx_state <= ST_BOOTA_STATUS_CMD;
				end if;

			when ST_BOOTA_STATUS_WAIT =>
				o_command_ready <= '0';
				o_rx_dequeue    <= i_rx_avail and i_spi_idle;

				if ((i_rx_avail = '1') and (i_spi_idle = '1')) then
					s_nx_state <= ST_BOOTA_STATUS_RX;
				else
					s_nx_state <= ST_BOOTA_STATUS_WAIT;
				end if;

			when ST_BOOTA_STATUS_RX =>
				o_command_ready            <= '0';
				s_read_status_register_val <= i_rx_data;

				if (i_rx_valid = '1') then
					s_nx_state <= ST_BOOTA_STATUS_CHK0;
				else
					s_nx_state <= ST_BOOTA_STATUS_RX;
				end if;

			when ST_BOOTA_STATUS_CHK0 =>
				o_command_ready <= '0';

				if (i_spi_idle = '1') then
					s_nx_state <= ST_BOOTA_STATUS_CHK1;
				else
					s_nx_state <= ST_BOOTA_STATUS_CHK0;
				end if;

			when ST_BOOTA_STATUS_CHK1 =>
				o_command_ready <= '0';

				if (s_read_status_register_aux(0) = '0') then
					-- chip is no longer busy
					s_nx_state <= ST_BOOT0_WEN_STATUS;
				elsE
					-- chip is busy, so check again
					s_nx_state <= ST_BOOTA_STATUS_CMD;
				end if;

			when ST_BOOT0_WEN_STATUS => -- step 1 of 4 to write status register
				o_command_ready <= '0';
				o_tx_data       <= c_n25q_cmd_write_enable;
				o_tx_len        <= std_logic_vector(to_unsigned(c_n25q_txlen_cmd_write_enable, o_tx_len'length));
				o_tx_enqueue    <= i_tx_ready;
				o_go_enhan      <= i_tx_ready;

				if (i_tx_ready = '1') then
					s_nx_state <= ST_BOOT0_WEN_STWAIT;
				else
					s_nx_state <= ST_BOOT0_WEN_STATUS;
				end if;

			when ST_BOOT0_WEN_STWAIT => -- step 2 of 4 to write status register
				o_command_ready <= '0';

				if (i_spi_idle = '1') then
					s_nx_state <= ST_BOOT0_WR_STATUS_CMD;
				else
					s_nx_state <= ST_BOOT0_WEN_STWAIT;
				end if;

			when ST_BOOT0_WR_STATUS_CMD => -- step 3 of 4 to write status register
				o_command_ready <= '0';
				o_tx_data       <= c_n25q_cmd_write_status_register;
				o_tx_enqueue    <= i_tx_ready;

				if (i_tx_ready = '1') then
					s_nx_state <= ST_BOOT0_WR_STATUS_DAT;
				else
					s_nx_state <= ST_BOOT0_WR_STATUS_CMD;
				end if;

			when ST_BOOT0_WR_STATUS_DAT => -- step 4 of 4 to switch to Quad I/O SPI
				o_command_ready <= '0';
				o_tx_data       <= c_n25q_dat_status_reg_as_pmod_sf3;
				o_tx_len        <= std_logic_vector(to_unsigned(c_n25q_txlen_cmd_write_status_register, o_tx_len'length));
				o_tx_enqueue    <= i_tx_ready and i_spi_idle;
				o_go_enhan      <= i_tx_ready and i_spi_idle;

				if ((i_tx_ready = '1') and (i_spi_idle = '1')) then
					s_nx_state <= ST_BOOT0_IDLE_STWAIT;
				else
					s_nx_state <= ST_BOOT0_WR_STATUS_DAT;
				end if;

			when ST_BOOT0_IDLE_STWAIT =>
				o_command_ready <= '0';

				if (i_spi_idle = '1') then
					s_nx_state <= ST_BOOT0_FLAGST_CMD;
				else
					s_nx_state <= ST_BOOT0_IDLE_STWAIT;
				end if;

			when ST_BOOT0_FLAGST_CMD =>
				o_command_ready <= '0';
				o_tx_data       <= c_n25q_cmd_read_flag_status_register;
				o_tx_len        <= std_logic_vector(to_unsigned(c_n25q_txlen_cmd_read_flag_status_register, o_tx_len'length));
				o_rx_len        <= std_logic_vector(to_unsigned(c_n25q_rxlen_cmd_read_flag_status_register, o_rx_len'length));
				o_tx_enqueue    <= i_tx_ready;
				o_go_enhan      <= i_tx_ready;

				if (i_tx_ready = '1') then
					s_nx_state <= ST_BOOT0_FLAGST_WAIT;
				else
					s_nx_state <= ST_BOOT0_FLAGST_CMD;
				end if;

			when ST_BOOT0_FLAGST_WAIT =>
				o_command_ready <= '0';
				o_rx_dequeue    <= i_rx_avail and i_spi_idle;

				if ((i_rx_avail = '1') and (i_spi_idle = '1')) then
					s_nx_state <= ST_BOOT0_FLAGST_RX;
				else
					s_nx_state <= ST_BOOT0_FLAGST_WAIT;
				end if;

			when ST_BOOT0_FLAGST_RX =>
				o_command_ready                 <= '0';
				s_read_flag_status_register_val <= i_rx_data;

				if (i_rx_valid = '1') then
					s_nx_state <= ST_BOOT0_FLAGST_CHK0;
				else
					s_nx_state <= ST_BOOT0_FLAGST_RX;
				end if;

			when ST_BOOT0_FLAGST_CHK0 =>
				o_command_ready <= '0';

				if (i_spi_idle = '1') then
					s_nx_state <= ST_BOOT0_FLAGST_CHK1;
				else
					s_nx_state <= ST_BOOT0_FLAGST_CHK0;
				end if;

			when ST_BOOT0_FLAGST_CHK1 =>
				o_command_ready <= '0';

				if (s_read_flag_status_register_aux(7) = '1') then
					-- chip is in ready state
					s_nx_state <= ST_WAIT_IDLE;
				elsE
					-- chip is not in ready state
					s_nx_state <= ST_BOOT0_FLAGST_CMD;
				end if;

			when ST_RD_CMD =>
				o_command_ready <= '0';
				o_tx_data       <= c_n25q_cmd_extend_read_memory_4byte_addr;
				o_tx_enqueue    <= i_tx_ready;

				s_addr_byte_index_val <= c_addr_byte_index_preset;

				if (i_tx_ready = '1') then
					s_nx_state <= ST_RD_ADDR;
				else
					s_nx_state <= ST_RD_CMD;
				end if;

			when ST_RD_ADDR =>
				o_command_ready       <= '0';
				o_tx_data             <= i_address_of_cmd((8 * (s_addr_byte_index_aux + 1) - 1) downto (8 * s_addr_byte_index_aux));
				o_tx_enqueue          <= i_tx_ready;
				o_go_enhan            <= '1'                         when (s_addr_byte_index_aux = 0) else '0';
				s_addr_byte_index_val <= (s_addr_byte_index_aux - 1) when (i_tx_ready = '1') else s_addr_byte_index_aux;

				o_tx_len <= std_logic_vector(
						to_unsigned(c_n25q_txlen_cmd_extend_read_memory_4byte_addr, o_tx_len'length));
				o_rx_len   <= i_len_random_read;
				o_wait_cyc <= std_logic_vector(
						to_unsigned(c_n25q_cmd_extend_read_dummy_cycles, o_wait_cyc'length));
				s_wait_len_val <= to_integer(unsigned(i_len_random_read));

				if (s_addr_byte_index_aux = 0) then
					s_nx_state <= ST_RD_WAIT_0;
				else
					s_nx_state <= ST_RD_ADDR;
				end if;

			when ST_RD_WAIT_0 =>
				o_command_ready  <= '0';
				o_rd_data_stream <= i_rx_data;
				o_rd_data_valid  <= i_rx_valid;
				o_rx_dequeue     <= i_rx_avail;

				s_wait_len_val <= (s_wait_len_aux - 1) when (i_rx_avail = '1') else s_wait_len_aux;

				if (s_wait_len_aux = 0) then
					s_nx_state <= ST_WAIT_IDLE;
				else
					s_nx_state <= ST_RD_WAIT_0;
				end if;

			when ST_WEN_ERASE =>
				o_command_ready <= '0';
				o_tx_data       <= c_n25q_cmd_write_enable;
				o_tx_len        <= std_logic_vector(to_unsigned(c_n25q_txlen_cmd_write_enable, o_tx_len'length));
				o_tx_enqueue    <= i_tx_ready;
				o_go_enhan      <= i_tx_ready;

				if (i_tx_ready = '1') then
					s_nx_state <= ST_WEN_WAIT2;
				else
					s_nx_state <= ST_WEN_ERASE;
				end if;

			when ST_WEN_WAIT2 =>
				o_command_ready <= '0';

				if (i_spi_idle = '1') then
					s_nx_state <= ST_ERASE_CMD;
				else
					s_nx_state <= ST_WEN_WAIT2;
				end if;

			when ST_ERASE_CMD =>
				o_command_ready <= '0';
				o_tx_data       <= c_n25q_cmd_any_erase_subsector;
				o_tx_enqueue    <= i_tx_ready;

				s_addr_byte_index_val <= c_addr_byte_index_preset;

				if (i_tx_ready = '1') then
					s_nx_state <= ST_ERASE_ADDR;
				else
					s_nx_state <= ST_ERASE_CMD;
				end if;

			when ST_ERASE_ADDR =>
				o_command_ready <= '0';
				o_tx_data       <= i_address_of_cmd((8 * (s_addr_byte_index_aux + 1) - 1) downto (8 * s_addr_byte_index_aux));
				o_tx_len        <= std_logic_vector(to_unsigned(c_n25q_txlen_cmd_any_erase_subsector, o_tx_len'length));
				o_tx_enqueue    <= i_tx_ready;
				o_go_enhan      <= '1' when (s_addr_byte_index_aux = 0) else '0';

				s_addr_byte_index_val <= (s_addr_byte_index_aux - 1) when (i_tx_ready = '1') else s_addr_byte_index_aux;

				if (s_addr_byte_index_aux = 0) then
					s_nx_state <= ST_ERASE_WAIT;
				else
					s_nx_state <= ST_ERASE_ADDR;
				end if;

			when ST_ERASE_WAIT =>
				o_command_ready <= '0';

				if (i_spi_idle = '1') then
					s_nx_state <= ST_FLAGST_CMD;
				else
					s_nx_state <= ST_ERASE_WAIT;
				end if;

			when ST_FLAGST_CMD =>
				o_command_ready <= '0';
				o_tx_data       <= c_n25q_cmd_read_flag_status_register;
				o_tx_len        <= std_logic_vector(to_unsigned(c_n25q_txlen_cmd_read_flag_status_register, o_tx_len'length));
				o_rx_len        <= std_logic_vector(to_unsigned(c_n25q_rxlen_cmd_read_flag_status_register, o_rx_len'length));
				o_tx_enqueue    <= i_tx_ready;
				o_go_enhan      <= i_tx_ready;

				if (i_tx_ready = '1') then
					s_nx_state <= ST_FLAGST_WAIT;
				else
					s_nx_state <= ST_FLAGST_CMD;
				end if;

			when ST_FLAGST_WAIT =>
				o_command_ready <= '0';
				o_rx_dequeue    <= i_rx_avail and i_spi_idle;

				if ((i_rx_avail = '1') and (i_spi_idle = '1')) then
					s_nx_state <= ST_FLAGST_RX;
				else
					s_nx_state <= ST_FLAGST_WAIT;
				end if;

			when ST_FLAGST_RX =>
				o_command_ready                 <= '0';
				s_read_flag_status_register_val <= i_rx_data;

				if (i_rx_valid = '1') then
					s_nx_state <= ST_FLAGST_CHK0;
				else
					s_nx_state <= ST_FLAGST_RX;
				end if;

			when ST_FLAGST_CHK0 =>
				o_command_ready <= '0';

				if (i_spi_idle = '1') then
					s_nx_state <= ST_FLAGST_CHK1;
				else
					s_nx_state <= ST_FLAGST_CHK0;
				end if;

			when ST_FLAGST_CHK1 =>
				o_command_ready <= '0';

				if (s_read_flag_status_register_aux(7) = '1') then
					-- erase is done
					s_nx_state <= ST_WAIT_IDLE;
				elsE
					-- erase is not done, so check again
					s_nx_state <= ST_FLAGST_CMD;
				end if;

			when ST_WEN_PROGR =>
				o_command_ready <= '0';
				o_tx_data       <= c_n25q_cmd_write_enable;
				o_tx_len        <= std_logic_vector(to_unsigned(c_n25q_txlen_cmd_write_enable, o_tx_len'length));
				o_tx_enqueue    <= i_tx_ready;
				o_go_enhan      <= i_tx_ready;

				if (i_tx_ready = '1') then
					s_nx_state <= ST_WEN_WAIT3;
				else
					s_nx_state <= ST_WEN_PROGR;
				end if;

			when ST_WEN_WAIT3 =>
				o_command_ready <= '0';

				if (i_spi_idle = '1') then
					s_nx_state <= ST_PAGE_PROGR_CMD;
				else
					s_nx_state <= ST_WEN_WAIT3;
				end if;

			when ST_PAGE_PROGR_CMD =>
				o_command_ready <= '0';
				o_tx_data       <= c_n25q_cmd_any_page_program;
				o_tx_enqueue    <= i_tx_ready;

				s_addr_byte_index_val <= c_addr_byte_index_preset;

				if (i_tx_ready = '1') then
					s_nx_state <= ST_PAGE_PROGR_ADDR;
				else
					s_nx_state <= ST_PAGE_PROGR_CMD;
				end if;

			when ST_PAGE_PROGR_ADDR =>
				o_command_ready <= '0';
				o_tx_data       <= i_address_of_cmd((8 * (s_addr_byte_index_aux + 1) - 1) downto (8 * s_addr_byte_index_aux));
				o_tx_len        <= std_logic_vector(to_unsigned(c_n25q_txlen_cmd_any_page_program + 256, o_tx_len'length));
				o_tx_enqueue    <= i_tx_ready;
				o_go_enhan      <= '1' when (s_addr_byte_index_aux = 0) else '0';

				s_addr_byte_index_val <= (s_addr_byte_index_aux - 1) when (i_tx_ready = '1') else s_addr_byte_index_aux;
				s_wait_len_val        <= 256;

				if (s_addr_byte_index_aux = 0) then
					s_nx_state <= ST_PAGE_PROGR_STREAM;
				else
					s_nx_state <= ST_PAGE_PROGR_ADDR;
				end if;

			when ST_PAGE_PROGR_STREAM =>
				o_command_ready <= '0';
				o_wr_data_ready <= i_tx_ready;
				o_tx_data       <= i_wr_data_stream;
				o_tx_enqueue    <= i_wr_data_valid;

				s_wait_len_val <= (s_wait_len_aux - 1) when ((i_wr_data_valid = '1') and (s_wait_len_aux >= 1)) else s_wait_len_aux;

				if ((s_wait_len_aux <= 1) and (i_spi_idle = '1')) then
					s_nx_state <= ST_FLAGST_CMD;
				else
					s_nx_state <= ST_PAGE_PROGR_STREAM;
				end if;

			when ST_WAIT_IDLE =>
				o_command_ready <= '0';

				if (i_spi_idle = '1') then
					s_nx_state <= ST_IDLE;
				else
					s_nx_state <= ST_WAIT_IDLE;
				end if;

			when ST_IDLE =>
				o_command_ready <= i_spi_idle;

				if (i_cmd_random_read = '1') then
					s_nx_state <= ST_RD_CMD;
				elsif (i_cmd_erase_subsector = '1') then
					s_nx_state <= ST_WEN_ERASE;
				elsif (i_cmd_page_program = '1') then
					s_nx_state <= ST_WEN_PROGR;
				else
					s_nx_state <= ST_IDLE;
				end if;

			when others => -- ST_BOOTA_INIT
				o_command_ready <= '0';
				if (s_t >= c_t_boot_init0 - 1) then
					s_nx_state <= ST_BOOTA_STATUS_CMD;
				else
					s_nx_state <= ST_BOOTA_INIT;
				end if;
		end case;

	end process p_fsm_comb;

	o_reg_status <= s_read_status_register_aux;
	o_reg_flag   <= s_read_flag_status_register_aux;

end architecture hybrid_fsm;
--------------------------------------------------------------------------------
