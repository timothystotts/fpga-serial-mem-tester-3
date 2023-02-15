--------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2020,2023 Timothy Stotts
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
-- \file pmod_cls_stand_spi_solo.vhdl
--
-- \brief A SPI interface to Digilent Inc. PMOD CLS lcd display operating in
-- SPI Mode 0. The design only enables clearing the display, or writing a full
-- sixteen character line of one of the two lines of the display at a time.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--------------------------------------------------------------------------------
entity pmod_cls_stand_spi_solo is
    generic(
        -- Disable or enable fast FSM delays for simulation instead of implementation.
        parm_fast_simulation : integer := 0;
        -- Actual frequency in Hz of \ref i_ext_spi_clk_4x
        parm_FCLK : natural := 20_000_000;
        -- Clock enable frequency in Hz of \ref i_ext_spi_clk_4x with i_spi_ce_4x
        parm_FCLK_ce : natural := 2_500_000;
        -- LOG2 of the TX FIFO max count
        parm_tx_len_bits : natural := 11;
        -- LOG2 of max Wait Cycles count between end of TX and start of RX
        parm_wait_cyc_bits : natural := 2;
        -- LOG2 of the RX FIFO max count
        parm_rx_len_bits : natural := 11
    );
    port(
        -- system clock and synchronous reset
        i_ext_spi_clk_x : in std_logic;
        i_srst          : in std_logic;
        -- clock enable that is 4 times the rate of SPI signal sck
        i_spi_ce_4x     : in std_logic;
        -- system interface to the \ref pmod_generic_spi_solo module.
        o_go_stand : out std_logic;
        i_spi_idle : in  std_logic;
        o_tx_len   : out std_logic_vector((parm_tx_len_bits - 1) downto 0);
        o_wait_cyc : out std_logic_vector((parm_wait_cyc_bits - 1) downto 0);
        o_rx_len   : out std_logic_vector((parm_rx_len_bits - 1) downto 0);
        -- TX FIFO interface to the \ref pmod_generic_spi_solo module.
        o_tx_data    : out std_logic_vector(7 downto 0);
        o_tx_enqueue : out std_logic;
        i_tx_ready   : in  std_logic;
        -- RX FIFO interface to the \ref pmod_generic_spi_solo module.
        i_rx_data    : in  std_logic_vector(7 downto 0);
        o_rx_dequeue : out std_logic;
        i_rx_valid   : in  std_logic;
        i_rx_avail   : in  std_logic;
        -- FPGA system interface to CLS operation
        o_command_ready        : out std_logic;
        i_cmd_wr_clear_display : in  std_logic;
        i_cmd_wr_text_line1    : in  std_logic;
        i_cmd_wr_text_line2    : in  std_logic;
        i_dat_ascii_line1      : in  std_logic_vector((16 * 8 - 1) downto 0);
        i_dat_ascii_line2      : in  std_logic_vector((16 * 8 - 1) downto 0)
    );
end entity pmod_cls_stand_spi_solo;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
architecture moore_fsm_recursive of pmod_cls_stand_spi_solo is
    -- Timer signals and constants.

    -- Boot time should be in hundreds of milliseconds as the PMOD CLS
    -- datasheet does not indicate boot-up time of the PMOD CLS microcontroller.
    constant c_t_pmodcls_boot_fast_sim : natural := parm_FCLK_ce / 1000 * 2;
    constant c_t_pmodcls_boot          : natural := parm_FCLK_ce / 1000 * 800;
    constant c_tmax                    : natural := c_t_pmodcls_boot - 1;

    signal s_t : natural range 0 to c_tmax;

    -- Driver FSM state declarations
    type t_cls_drv_state is (ST_CLS_BOOT0, ST_CLS_IDLE, ST_CLS_LOAD_CLEAR,
            ST_CLS_LOAD_LINE1, ST_CLS_LOAD_LINE2, ST_CLS_CMD_RUN, ST_CLS_CMD_WAIT,
            ST_CLS_DAT_RUN, ST_CLS_DAT_WAIT);

    signal s_cls_drv_pr_state : t_cls_drv_state := ST_CLS_BOOT0;
    signal s_cls_drv_nx_state : t_cls_drv_state := ST_CLS_BOOT0;

    -- Xilinx attributes for Auto encoding of the FSM and safe state is Default
    -- State.
    attribute fsm_encoding                         : string;
    attribute fsm_safe_state                       : string;
    attribute fsm_encoding of s_cls_drv_pr_state   : signal is "auto";
    attribute fsm_safe_state of s_cls_drv_pr_state : signal is "default_state";

    -- Auxiliary state machine registers for recursive state machine operation.
    signal s_cls_cmd_len_aux   : natural range 0 to 15;
    signal s_cls_cmd_len_val   : natural range 0 to 15;
    signal s_cls_dat_len_aux   : natural range 0 to 31;
    signal s_cls_dat_len_val   : natural range 0 to 31;
    signal s_cls_cmd_tx_aux    : std_logic_vector(55 downto 0);
    signal s_cls_cmd_tx_val    : std_logic_vector(55 downto 0);
    signal s_cls_cmd_txlen_aux : natural range 0 to 31;
    signal s_cls_cmd_txlen_val : natural range 0 to 31;
    signal s_cls_dat_tx_aux    : std_logic_vector(127 downto 0);
    signal s_cls_dat_tx_val    : std_logic_vector(127 downto 0);
    signal s_cls_dat_txlen_aux : natural range 0 to 63;
    signal s_cls_dat_txlen_val : natural range 0 to 63;

    -- ASCII constant characters for ESC codes.
    constant ASCII_CLS_ESC            : std_logic_vector(7 downto 0) := x"1B";
    constant ASCII_CLS_BRACKET        : std_logic_vector(7 downto 0) := x"5B";
    constant ASCII_CLS_CHAR_ZERO      : std_logic_vector(7 downto 0) := x"30";
    constant ASCII_CLS_CHAR_ONE       : std_logic_vector(7 downto 0) := x"31";
    constant ASCII_CLS_CHAR_SEMICOLON : std_logic_vector(7 downto 0) := x"3B";
    constant ASCII_CLS_DISP_CLR_CMD   : std_logic_vector(7 downto 0) := x"6a";
    constant ASCII_CLS_CURSOR_POS_CMD : std_logic_vector(7 downto 0) := x"48";

begin
    -- Timer 1 (Strategy #1), for timing the boot wait for PMOD CLS communication
    p_timer_1 : process(i_ext_spi_clk_x)
    begin
        if rising_edge(i_ext_spi_clk_x) then
            if (i_srst = '1') then
                s_t <= 0;
            elsif (i_spi_ce_4x = '1') then
                if (s_cls_drv_pr_state /= s_cls_drv_nx_state) then
                    s_t <= 0;
                elsif (s_t < c_tmax) then
                    s_t <= s_t + 1;
                end if;
            end if;
        end if;
    end process p_timer_1;

    -- FSM state register plus auxiliary registers, for propagating the next state
    -- as well as the next recursive auxiliary register values for use within
    -- one or more state combinatorial logic decisions.
    p_fsm_state_aux : process(i_ext_spi_clk_x)
    begin
        if rising_edge(i_ext_spi_clk_x) then
            if (i_srst = '1') then
                s_cls_drv_pr_state <= ST_CLS_BOOT0;

                s_cls_cmd_len_aux   <= 0;
                s_cls_dat_len_aux   <= 0;
                s_cls_cmd_tx_aux    <= (others => '0');
                s_cls_dat_tx_aux    <= (others => '0');
                s_cls_cmd_txlen_aux <= 0;
                s_cls_dat_txlen_aux <= 0;

            elsif (i_spi_ce_4x = '1') then
                s_cls_drv_pr_state <= s_cls_drv_nx_state;

                s_cls_cmd_len_aux   <= s_cls_cmd_len_val;
                s_cls_dat_len_aux   <= s_cls_dat_len_val;
                s_cls_cmd_tx_aux    <= s_cls_cmd_tx_val;
                s_cls_dat_tx_aux    <= s_cls_dat_tx_val;
                s_cls_cmd_txlen_aux <= s_cls_cmd_txlen_val;
                s_cls_dat_txlen_aux <= s_cls_dat_txlen_val;
            end if;
        end if;
    end process p_fsm_state_aux;

    -- FSM combinatorial logic providing multiple outputs, assigned in every state,
    -- as well as changes in auxiliary values, and calculation of the next FSM
    -- state. Refer to the FSM state machine drawings.
    p_fsm_comb : process(s_cls_drv_pr_state,
            s_cls_cmd_len_aux, s_cls_dat_len_aux, s_cls_cmd_tx_aux, s_cls_dat_tx_aux,
            s_cls_cmd_txlen_aux, s_cls_dat_txlen_aux,
            s_t,
            i_cmd_wr_clear_display, i_cmd_wr_text_line1, i_cmd_wr_text_line2,
            i_dat_ascii_line1, i_dat_ascii_line2,
            i_tx_ready, i_spi_idle)
    begin
        case (s_cls_drv_pr_state) is
            when ST_CLS_LOAD_CLEAR =>
                -- Load the 4-byte ASCII escape sequence for clearing the display into
                -- the \ref s_cls_cmd_tx_aux auxiliary register, and load nothing into
                -- the \ref s_cls_dat_tx_aux auxiliary register for additional data
                -- transfer.
                o_command_ready     <= '0';
                o_tx_data           <= x"00";
                o_tx_enqueue        <= '0';
                o_tx_len            <= (others => '0');
                o_rx_len            <= (others => '0');
                o_wait_cyc          <= (others => '0');
                o_rx_dequeue        <= '0';
                o_go_stand          <= '0';
                s_cls_cmd_len_val   <= 4;
                s_cls_cmd_tx_val    <= x"000000" & ASCII_CLS_ESC & ASCII_CLS_BRACKET & ASCII_CLS_CHAR_ZERO & ASCII_CLS_DISP_CLR_CMD;
                s_cls_dat_len_val   <= 0;
                s_cls_dat_tx_val    <= (others => '0');
                s_cls_cmd_txlen_val <= 4;
                s_cls_dat_txlen_val <= 0;

                s_cls_drv_nx_state <= ST_CLS_CMD_RUN;

            when ST_CLS_LOAD_LINE1 =>
                -- Load the 7-byte ASCII escape sequence for writing display line 1 into
                -- the \ref s_cls_cmd_tx_aux auxiliary register, and load the 16-byte text into
                -- the \ref s_cls_dat_tx_aux auxiliary register for additional data transfer.
                o_command_ready     <= '0';
                o_tx_data           <= x"00";
                o_tx_enqueue        <= '0';
                o_tx_len            <= (others => '0');
                o_rx_len            <= (others => '0');
                o_wait_cyc          <= (others => '0');
                o_rx_dequeue        <= '0';
                o_go_stand          <= '0';
                s_cls_cmd_len_val   <= 7;
                s_cls_cmd_tx_val    <= ASCII_CLS_ESC & ASCII_CLS_BRACKET & ASCII_CLS_CHAR_ZERO & ASCII_CLS_CHAR_SEMICOLON & ASCII_CLS_CHAR_ZERO & ASCII_CLS_CHAR_ZERO & ASCII_CLS_CURSOR_POS_CMD;
                s_cls_dat_len_val   <= 16;
                s_cls_dat_tx_val    <= i_dat_ascii_line1;
                s_cls_cmd_txlen_val <= 7;
                s_cls_dat_txlen_val <= 16;

                s_cls_drv_nx_state <= ST_CLS_CMD_RUN;

            when ST_CLS_LOAD_LINE2 =>
                -- Load the 7-byte ASCII escape sequence for writing display line 2 into
                -- the \ref s_cls_cmd_tx_aux auxiliary register, and load the 16-byte text into
                -- the \ref s_cls_dat_tx_aux auxiliary register for additional data transfer.
                o_command_ready     <= '0';
                o_tx_data           <= x"00";
                o_tx_enqueue        <= '0';
                o_tx_len            <= (others => '0');
                o_rx_len            <= (others => '0');
                o_wait_cyc          <= (others => '0');
                o_rx_dequeue        <= '0';
                o_go_stand          <= '0';
                s_cls_cmd_len_val   <= 7;
                s_cls_cmd_tx_val    <= ASCII_CLS_ESC & ASCII_CLS_BRACKET & ASCII_CLS_CHAR_ONE & ASCII_CLS_CHAR_SEMICOLON & ASCII_CLS_CHAR_ZERO & ASCII_CLS_CHAR_ZERO & ASCII_CLS_CURSOR_POS_CMD;
                s_cls_dat_len_val   <= 16;
                s_cls_dat_tx_val    <= i_dat_ascii_line2;
                s_cls_cmd_txlen_val <= 7;
                s_cls_dat_txlen_val <= 16;

                s_cls_drv_nx_state <= ST_CLS_CMD_RUN;

            when ST_CLS_CMD_RUN =>
                -- Run the loading into the SPI TX FIFO of the command from the
                -- \ref s_cls_cmd_tx_aux auxiliary register, and then on the
                -- loading of the last byte, command the SPI operation to start.
                o_command_ready     <= '0';
                o_tx_data           <= s_cls_cmd_tx_aux((s_cls_cmd_len_aux * 8 - 1) downto ((s_cls_cmd_len_aux - 1) * 8));
                o_tx_enqueue        <= i_tx_ready;
                o_tx_len            <= std_logic_vector(to_unsigned(s_cls_cmd_txlen_aux, o_tx_len'length));
                o_rx_len            <= (others => '0');
                o_wait_cyc          <= (others => '0');
                o_rx_dequeue        <= '0';
                o_go_stand          <= '1' when ((s_cls_cmd_len_aux <= 1) and (i_tx_ready = '1')) else '0';
                s_cls_cmd_tx_val    <= s_cls_cmd_tx_aux;
                s_cls_cmd_len_val   <= (s_cls_cmd_len_aux - 1) when (i_tx_ready = '1') else s_cls_cmd_len_aux;
                s_cls_dat_len_val   <= s_cls_dat_len_aux;
                s_cls_dat_tx_val    <= s_cls_dat_tx_aux;
                s_cls_cmd_txlen_val <= s_cls_cmd_txlen_aux;
                s_cls_dat_txlen_val <= s_cls_dat_txlen_aux;

                if ((s_cls_cmd_len_aux <= 1) and (i_tx_ready = '1')) then
                    s_cls_drv_nx_state <= ST_CLS_CMD_WAIT;
                else
                    s_cls_drv_nx_state <= ST_CLS_CMD_RUN;
                end if;

            when ST_CLS_CMD_WAIT =>
                -- Wait for the command sequence to end and for the SPI operation
                -- to return to IDLE. Then move to the data sequence or to IDLE.
                o_command_ready     <= '0';
                o_tx_enqueue        <= '0';
                o_tx_data           <= x"00";
                o_tx_len            <= (others => '0');
                o_rx_len            <= (others => '0');
                o_wait_cyc          <= (others => '0');
                o_rx_dequeue        <= '0';
                o_go_stand          <= '0';
                s_cls_cmd_len_val   <= s_cls_cmd_len_aux;
                s_cls_cmd_tx_val    <= s_cls_cmd_tx_aux;
                s_cls_dat_len_val   <= s_cls_dat_len_aux;
                s_cls_dat_tx_val    <= s_cls_dat_tx_aux;
                s_cls_cmd_txlen_val <= s_cls_cmd_txlen_aux;
                s_cls_dat_txlen_val <= s_cls_dat_txlen_aux;

                if (i_spi_idle = '1') then
                    if (s_cls_dat_txlen_aux > 0) then
                        s_cls_drv_nx_state <= ST_CLS_DAT_RUN;
                    else
                        s_cls_drv_nx_state <= ST_CLS_IDLE;
                    end if;
                else
                    s_cls_drv_nx_state <= ST_CLS_CMD_WAIT;
                end if;

            when ST_CLS_DAT_RUN =>
                -- Run the loading into the SPI TX FIFO of the data from the
                -- \ref s_cls_dat_tx_aux auxiliary register, and then on the
                -- loading of the last byte, command the SPI operation to start.
                o_command_ready     <= '0';
                o_tx_data           <= s_cls_dat_tx_aux((s_cls_dat_len_aux * 8 - 1) downto ((s_cls_dat_len_aux - 1) * 8));
                o_tx_enqueue <= i_tx_ready;
                o_tx_len            <= std_logic_vector(to_unsigned(s_cls_dat_txlen_aux, o_tx_len'length));
                o_rx_len            <= (others => '0');
                o_wait_cyc          <= (others => '0');
                o_rx_dequeue        <= '0';
                o_go_stand          <= '1' when ((s_cls_dat_len_aux <= 1) and (i_tx_ready = '1')) else '0';
                s_cls_cmd_len_val   <= s_cls_cmd_len_aux;
                s_cls_dat_len_val   <= (s_cls_dat_len_aux - 1) when (i_tx_ready = '1') else s_cls_dat_len_aux;
                s_cls_cmd_tx_val    <= s_cls_cmd_tx_aux;
                s_cls_dat_tx_val    <= s_cls_dat_tx_aux;
                s_cls_cmd_txlen_val <= s_cls_cmd_txlen_aux;
                s_cls_dat_txlen_val <= s_cls_dat_txlen_aux;

                if ((s_cls_dat_len_aux <= 1) and (i_tx_ready = '1')) then
                    s_cls_drv_nx_state <= ST_CLS_DAT_WAIT;
                else
                    s_cls_drv_nx_state <= ST_CLS_DAT_RUN;
                end if;

            when ST_CLS_DAT_WAIT =>
                -- Wait for the data sequence to end and for the SPI operation
                -- to return to IDLE.
                o_command_ready     <= '0';
                o_tx_enqueue        <= '0';
                o_tx_data           <= x"00";
                o_tx_len            <= (others => '0');
                o_rx_len            <= (others => '0');
                o_wait_cyc          <= (others => '0');
                o_rx_dequeue        <= '0';
                o_go_stand          <= '0';
                s_cls_cmd_len_val   <= s_cls_cmd_len_aux;
                s_cls_cmd_tx_val    <= s_cls_cmd_tx_aux;
                s_cls_dat_len_val   <= s_cls_dat_len_aux;
                s_cls_dat_tx_val    <= s_cls_dat_tx_aux;
                s_cls_cmd_txlen_val <= s_cls_cmd_txlen_aux;
                s_cls_dat_txlen_val <= s_cls_dat_txlen_aux;

                if (i_spi_idle = '1') then
                    s_cls_drv_nx_state <= ST_CLS_IDLE;
                else
                    s_cls_drv_nx_state <= ST_CLS_DAT_WAIT;
                end if;

            when ST_CLS_IDLE =>
                -- IDLE the PMOD CLS driver FSM and wait for one of the three commands:
                -- (a) clear the display
                -- (b) write display text line 1
                -- (c) write display text line 2
                o_command_ready     <= '1';
                o_tx_enqueue        <= '0';
                o_tx_data           <= x"00";
                o_tx_len            <= (others => '0');
                o_rx_len            <= (others => '0');
                o_wait_cyc          <= (others => '0');
                o_rx_dequeue        <= '0';
                o_go_stand          <= '0';
                s_cls_cmd_len_val   <= s_cls_cmd_len_aux;
                s_cls_cmd_tx_val    <= s_cls_cmd_tx_aux;
                s_cls_dat_len_val   <= s_cls_dat_len_aux;
                s_cls_dat_tx_val    <= s_cls_dat_tx_aux;
                s_cls_cmd_txlen_val <= s_cls_cmd_txlen_aux;
                s_cls_dat_txlen_val <= s_cls_dat_txlen_aux;

                if (i_cmd_wr_clear_display = '1') then
                    s_cls_drv_nx_state <= ST_CLS_LOAD_CLEAR;
                elsif (i_cmd_wr_text_line1 = '1') then
                    s_cls_drv_nx_state <= ST_CLS_LOAD_LINE1;
                elsif (i_cmd_wr_text_line2 = '1') then
                    s_cls_drv_nx_state <= ST_CLS_LOAD_LINE2;
                else
                    s_cls_drv_nx_state <= ST_CLS_IDLE;
                end if;

            when others => -- ST_CLS_BOOT0
                -- The datasheet for the PMOD CLS does not indicate the boot-up time
                -- required for the PMOD CLS microcontroller. At boot-up, wait a
                -- a time of \ref c_t_pmodcls_boot before this FSM accepts commands
                -- to operate the PMOD CLS display.
                o_command_ready     <= '0';
                o_tx_data           <= x"00";
                o_tx_enqueue        <= '0';
                o_tx_len            <= (others => '0');
                o_rx_len            <= (others => '0');
                o_wait_cyc          <= (others => '0');
                o_rx_dequeue        <= '0';
                o_go_stand          <= '0';
                s_cls_cmd_len_val   <= s_cls_cmd_len_aux;
                s_cls_cmd_tx_val    <= s_cls_cmd_tx_aux;
                s_cls_dat_len_val   <= s_cls_dat_len_aux;
                s_cls_dat_tx_val    <= s_cls_dat_tx_aux;
                s_cls_cmd_txlen_val <= s_cls_cmd_txlen_aux;
                s_cls_dat_txlen_val <= s_cls_dat_txlen_aux;

                -- The fast simulation parameter is used here as VHDL does not define
                -- a ternary operator.
                if (parm_fast_simulation = 0) then
                    if (s_t = c_t_pmodcls_boot - 1) then
                        s_cls_drv_nx_state <= ST_CLS_IDLE;
                    else
                        s_cls_drv_nx_state <= ST_CLS_BOOT0;
                    end if;
                else
                    if (s_t = c_t_pmodcls_boot_fast_sim - 1) then
                        s_cls_drv_nx_state <= ST_CLS_IDLE;
                    else
                        s_cls_drv_nx_state <= ST_CLS_BOOT0;
                    end if;
                end if;
        end case;
    end process p_fsm_comb;

end architecture moore_fsm_recursive;
--------------------------------------------------------------------------------
