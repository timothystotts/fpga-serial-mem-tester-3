--------------------------------------------------------------------------------
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
--------------------------------------------------------------------------------
-- \file pmod_sf3_custom_driver.vhdl
--
-- \brief A wrapper for the single Chip Select, Extended SPI components
--        \ref pmod_sf3_quad_spi_solo and \ref pmod_generic_qspi_solo ,
--        implementing a custom multi-command N25Q operation of the PMOD SF3
--        peripheral board by Digilent Inc with only SPI bus communication.
--        Note that Extended SPI Mode 0 is implemented currently, and
--        QuadIO SPI is not currently implemented.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--------------------------------------------------------------------------------
entity pmod_sf3_custom_driver is
    generic(
        -- Disable or enable fast FSM delays for simulation instead of
        -- impelementation.
        parm_fast_simulation : integer := 0;
        -- Actual frequency in Hz of \ref i_clk_mhz
        parm_FCLK : natural := 20_000_000;
        -- Ratio of i_ext_spi_clk_x to SPI sck bus output. */
        parm_ext_spi_clk_ratio : integer := 32;
        -- LOG2 of the TX FIFO max count
        parm_tx_len_bits : natural := 9;
        -- LOG2 of max Wait Cycles count between end of TX and start of RX
        parm_wait_cyc_bits : natural := 9;
        -- LOG2 of the RX FIFO max count
        parm_rx_len_bits : natural := 9
    );
    port(
        -- Clock and reset, with clock at 4^N times the frequency of the SPI bus
        i_clk_mhz    : in std_logic;
        i_rst_mhz    : in std_logic;
        -- Clock enable that divides i_clk_mhz further. Can be held at 1'b1 to
        -- operate the SPI bus as fast as possible, assuming that the SPI
        -- peripheral is rated to run at that speed. The SPI bus will operate
        -- at 1/4 the rate of this clock enable.
        i_ce_mhz_div : in std_logic;
        -- SPI machine external interface to top-level
        eio_sck_o      : out std_logic;
        eio_sck_t      : out std_logic;
        eio_csn_o      : out std_logic;
        eio_csn_t      : out std_logic;
        eio_copi_dq0_o : out std_logic;
        eio_copi_dq0_i : in  std_logic;
        eio_copi_dq0_t : out std_logic;
        eio_cipo_dq1_o : out std_logic;
        eio_cipo_dq1_i : in  std_logic;
        eio_cipo_dq1_t : out std_logic;
        eio_wrpn_dq2_o : out std_logic;
        eio_wrpn_dq2_i : in  std_logic;
        eio_wrpn_dq2_t : out std_logic;
        eio_hldn_dq3_o : out std_logic;
        eio_hldn_dq3_i : in  std_logic;
        eio_hldn_dq3_t : out std_logic;
        -- Command ready indication and possible commands to the driver
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
end entity pmod_sf3_custom_driver;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
architecture rtl of pmod_sf3_custom_driver is
    -- SPI signals to external tri-state
    signal sio_sck_fsm_o : std_logic;
    signal sio_sck_fsm_t : std_logic;

    signal sio_csn_fsm_o : std_logic;
    signal sio_csn_fsm_t : std_logic;

    signal sio_dq0_fsm_o : std_logic;
    signal sio_dq0_fsm_t : std_logic;

    signal sio_dq0_sync_i : std_logic;
    signal sio_dq0_meta_i : std_logic;

    signal sio_dq1_fsm_o : std_logic;
    signal sio_dq1_fsm_t : std_logic;

    signal sio_dq1_sync_i : std_logic;
    signal sio_dq1_meta_i : std_logic;

    signal sio_dq2_fsm_o : std_logic;
    signal sio_dq2_fsm_t : std_logic;

    signal sio_dq2_sync_i : std_logic;
    signal sio_dq2_meta_i : std_logic;

    signal sio_dq3_fsm_o : std_logic;
    signal sio_dq3_fsm_t : std_logic;

    signal sio_dq3_sync_i : std_logic;
    signal sio_dq3_meta_i : std_logic;

    -- system SPI control signals and data
    signal s_go_enhan   : std_logic;
    signal s_go_quadio  : std_logic;
    signal s_spi_idle   : std_logic;
    signal s_tx_len     : std_logic_vector(8 downto 0);
    signal s_wait_cyc   : std_logic_vector(8 downto 0);
    signal s_rx_len     : std_logic_vector(8 downto 0);
    signal s_tx_data    : std_logic_vector(7 downto 0);
    signal s_tx_enqueue : std_logic;
    signal s_tx_ready   : std_logic;
    signal s_rx_data    : std_logic_vector(7 downto 0);
    signal s_rx_dequeue : std_logic;
    signal s_rx_valid   : std_logic;
    signal s_rx_avail   : std_logic;

begin

    -- Register the SPI FSM outputs to prevent glitches.
    -- Note that the QSPI driver assumes this with its clock-enable phase
    -- timings.
    p_reg_spi_fsm_out : process(i_clk_mhz)
    begin
        if rising_edge(i_clk_mhz) then
            if (i_ce_mhz_div = '1') then
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
            end if;
        end if;
    end process p_reg_spi_fsm_out;

    -- Two-stage synchronize the SPI FSM inputs for best practice.
    -- Note that the QSPI driver assumes this with its clock-enable phase
    -- timings.
    p_sync_spi_in : process(i_clk_mhz)
    begin
        if rising_edge(i_clk_mhz) then
            if (i_ce_mhz_div = '1') then
                sio_dq0_sync_i <= sio_dq0_meta_i;
                sio_dq0_meta_i <= eio_copi_dq0_i;

                sio_dq1_sync_i <= sio_dq1_meta_i;
                sio_dq1_meta_i <= eio_cipo_dq1_i;

                sio_dq2_sync_i <= sio_dq2_meta_i;
                sio_dq2_meta_i <= eio_wrpn_dq2_i;

                sio_dq3_sync_i <= sio_dq3_meta_i;
                sio_dq3_meta_i <= eio_hldn_dq3_i;
            end if;
        end if;
    end process p_sync_spi_in;

    -- PMOD SF3 driver for N25Q flash family.
    u_pmod_sf3_quad_spi_solo : entity work.pmod_sf3_quad_spi_solo(hybrid_fsm)
        generic map (
            parm_fast_simulation => parm_fast_simulation,
            parm_FCLK            => parm_FCLK,
            parm_tx_len_bits     => parm_tx_len_bits,
            parm_wait_cyc_bits   => parm_wait_cyc_bits,
            parm_rx_len_bits     => parm_rx_len_bits
        )
        port map (
            i_ext_spi_clk_x       => i_clk_mhz,
            i_srst                => i_rst_mhz,
            i_spi_ce_4x           => i_ce_mhz_div,
            o_go_enhan            => s_go_enhan,
            o_go_quadio           => s_go_quadio,
            i_spi_idle            => s_spi_idle,
            o_tx_len              => s_tx_len,
            o_wait_cyc            => s_wait_cyc,
            o_rx_len              => s_rx_len,
            o_tx_data             => s_tx_data,
            o_tx_enqueue          => s_tx_enqueue,
            i_tx_ready            => s_tx_ready,
            i_rx_data             => s_rx_data,
            o_rx_dequeue          => s_rx_dequeue,
            i_rx_valid            => s_rx_valid,
            i_rx_avail            => s_rx_avail,
            o_command_ready       => o_command_ready,
            i_address_of_cmd      => i_address_of_cmd,
            i_cmd_erase_subsector => i_cmd_erase_subsector,
            i_cmd_page_program    => i_cmd_page_program,
            i_cmd_random_read     => i_cmd_random_read,
            i_len_random_read     => i_len_random_read,
            i_wr_data_stream      => i_wr_data_stream,
            i_wr_data_valid       => i_wr_data_valid,
            o_wr_data_ready       => o_wr_data_ready,
            o_rd_data_stream      => o_rd_data_stream,
            o_rd_data_valid       => o_rd_data_valid,
            o_reg_status          => o_reg_status,
            o_reg_flag            => o_reg_flag
        );

    -- Quad bus Extended SPI driver for generic usage, for use with a single
    -- peripheral.
    u_pmod_generic_qspi_solo : entity work.pmod_generic_qspi_solo(spi_hybrid_fsm)
        generic map(
            parm_ext_spi_clk_ratio => parm_ext_spi_clk_ratio,
            parm_tx_len_bits       => parm_tx_len_bits,
            parm_wait_cyc_bits     => parm_wait_cyc_bits,
            parm_rx_len_bits       => parm_rx_len_bits
        )
        port map (
            i_ext_spi_clk_x => i_clk_mhz,
            i_srst          => i_rst_mhz,
            i_spi_ce_4x     => i_ce_mhz_div,
            i_go_enhan      => s_go_enhan,
            i_go_quadio     => s_go_quadio,
            o_spi_idle      => s_spi_idle,
            i_tx_len        => s_tx_len,
            i_wait_cyc      => s_wait_cyc,
            i_rx_len        => s_rx_len,
            i_tx_data       => s_tx_data,
            i_tx_enqueue    => s_tx_enqueue,
            o_tx_ready      => s_tx_ready,
            o_rx_data       => s_rx_data,
            i_rx_dequeue    => s_rx_dequeue,
            o_rx_valid      => s_rx_valid,
            o_rx_avail      => s_rx_avail,
            eio_sck_o       => sio_sck_fsm_o,
            eio_sck_t       => sio_sck_fsm_t,
            eio_csn_o       => sio_csn_fsm_o,
            eio_csn_t       => sio_csn_fsm_t,
            eio_copi_dq0_o  => sio_dq0_fsm_o,
            eio_copi_dq0_i  => sio_dq0_sync_i,
            eio_copi_dq0_t  => sio_dq0_fsm_t,
            eio_cipo_dq1_o  => sio_dq1_fsm_o,
            eio_cipo_dq1_i  => sio_dq1_sync_i,
            eio_cipo_dq1_t  => sio_dq1_fsm_t,
            eio_wrpn_dq2_o  => sio_dq2_fsm_o,
            eio_wrpn_dq2_i  => sio_dq2_sync_i,
            eio_wrpn_dq2_t  => sio_dq2_fsm_t,
            eio_hldn_dq3_o  => sio_dq3_fsm_o,
            eio_hldn_dq3_i  => sio_dq3_sync_i,
            eio_hldn_dq3_t  => sio_dq3_fsm_t
        );

end architecture rtl;
--------------------------------------------------------------------------------
