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
-- \file pmod_cls.vhdl
--
-- \brief OSVVM testbench component: incomplete Simulation Model of Digilent Inc.
-- Pmod CLS external peripheral in SPI mode. The ScoreBoard is configured to
-- work with Pmod SF3 with testing patterns and the DUT instructing the Pmod CLS
-- to display two 16x2 lines of text that contain the user operator information
-- regarding the current test results.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

library work;
use work.sf3_testbench_pkg.all;
--------------------------------------------------------------------------------
package tbc_pmod_cls_pkg is
    procedure pr_spi_recv_only(
        signal sck : in std_logic;
        signal csn : in std_logic;
        signal copi : in std_logic;
        variable input_buffer : inout std_logic_vector;
        variable buffer_len : out natural;
        variable buffer_ovr : out natural
    );
end package tbc_pmod_cls_pkg;
--------------------------------------------------------------------------------
package body tbc_pmod_cls_pkg is
    -- A procedure to implement the behavior of an SPI Peripheral receiving,
    -- and not transmitting, serial data periodically. The procedure recieves
    -- into a buffer the data between CSN fall and CSN rise. Designed for SPI
    -- Mode 0; should work for Mode 3.
    procedure pr_spi_recv_only(
        signal sck : in std_logic;
        signal csn : in std_logic;
        signal copi : in std_logic;
        variable input_buffer : inout std_logic_vector;
        variable buffer_len : out natural;
        variable buffer_ovr : out natural) is
        alias in_buf : std_logic_vector(input_buffer'length downto 1) is input_buffer;
    begin
        -- initialize counters
        buffer_len := 0;
        buffer_ovr := 0;
        -- wait for CSN to fall
        wait until csn = '0';

        in_buf := (others => '0');

        -- Receive a stream of bits until CSN rises.
        l_spi_recv : loop
            wait on sck, csn;

            if (sck'event and sck = '1') then
                -- Implement the input buffer as a running shift register,
                -- right to left.
                in_buf := in_buf(in_buf'left - 1 downto 1) & copi;

                -- Track the number of bytes shifted into the input buffer,
                -- and if the input count goes beyond the length of the input
                -- buffer, then count the bytes as Overrun bytes, even though
                -- that were still shifted into the input buffer.
                if (buffer_len < in_buf'length) then
                    buffer_len := buffer_len + 1;
                else
                    buffer_ovr := buffer_ovr + 1;
                end if;
            end if;

            -- Exit when CSN rises.
            if (csn = '1') then
                exit;
            end if;

            wait for 0 ns;
        end loop l_spi_recv;
    end procedure pr_spi_recv_only;
end package body tbc_pmod_cls_pkg;
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.standard.all;

library osvvm;
context osvvm.OsvvmContext;

library work;
use work.sf3_testbench_pkg.all;
use work.ScoreBoardPkg_sf3.all;
use work.tbc_pmod_cls_pkg.all;
--------------------------------------------------------------------------------
entity tbc_pmod_cls is
    port(
        TBID : in AlertLogIDType;
        BarrierTestStart : inout std_logic;
        BarrierLogStart : inout std_logic;
        ci_sck : in std_logic;
        ci_csn : in std_logic;
        ci_copi : in std_logic;
        co_cipo : out std_logic
        );
end entity tbc_pmod_cls;
--------------------------------------------------------------------------------
architecture simulation_default of tbc_pmod_cls is
    -- The vector value for a byte of \x ESC character.
    constant ASCII_CLS_ESC : std_logic_vector(7 downto 0) := x"1B";
    -- The vector value for a byte of ':' colon character.
    constant ASCII_CLS_COLON : std_logic_vector(7 downto 0) := x"3A";
    -- The vector value for a byte of 'X' letter character.
    constant ASCII_CLS_X : std_logic_vector(7 downto 0) := x"58";
    -- The vector value for a byte of 'Z' letter character.
    constant ASCII_CLS_Z : std_logic_vector(7 downto 0) := x"5A";

    -- Simulation logging ID for this architecture.
    signal ModelID : AlertLogIDType;
begin
    -- Simulation initialization for the tbc_pmod_cls component.
    p_sim_init : process
        variable ID : AlertLogIDType;
    begin
        wait for 0 ns;
        WaitForBarrier(BarrierTestStart);
        ID := GetAlertLogID(PathTail(tbc_pmod_cls'path_name), TBID);
        ModelID <= ID;

        wait on ModelID;
        Log(ModelID, "Starting Pmod CLS emulation with SPI mode 0 bus.",
            ALWAYS);
        wait;
    end process p_sim_init;

    -- Just hold outputs at zero
    co_cipo <= '0';

    -- An infinite loop process to receive SPI data from the DUT, determine if
    -- the data is ANSI control sequences or plain ASCII text, and then for the
    -- plain ASCII text compare it with the Pmod CLS ScoreBoard.
    p_spi_recv : process
        -- An input buffer that can hold up to 16 bytes. The data is presumed
        -- to be ASCII values.
        variable input_buffer : std_logic_vector(127 downto 0);
        -- An integer to track the length of the current buffer contents.
        variable buf_len : natural := 0;
        -- An integer to track the overflow of the current buffer contents.
        -- Overflow is meant the number of bits that were received past the
        -- length of the \ref input_buffer, and thus the earliest bits lost.
        variable buf_ovr : natural := 0;
        -- A variable to track the first byte of the ASCII text. It is used to
        -- distinguish between a line of text being an ANSI control sequence or
        -- 16 characters of a LCD text line.
        variable start_char : std_logic_vector(7 downto 0);
        -- A variable to track the second byte of the ASCII text. It is used to
        -- distinguish between the first line of text, starting with 'X', and
        -- the second line of text, starting with 'Z'.
        variable start_char2 : std_logic_vector(7 downto 0);
        -- A vector to track the hexadecimal bytes of the 16x2 lines of text,
        -- which are 32 ASCII bytes containing 16 bytes of hexadecimal.
        variable scored_receipt : std_logic_vector(63 downto 0);
        -- A flag to indicate whether the current SPI text receipt was the first
        -- or second line of 16x2 text.
        variable scored_first : boolean;
        -- An integer to track what position in ScoreBoard FIFO history contains
        -- a matching \ref scored_receipt value.
        variable found_pos : integer := 0;
        -- A constant to compare with the \ref scored_recipt. Will only match
        -- the \ref scored_receipt if the \ref input_buffer contains no
        -- hexadecimal ASCII bytes.
        constant c_all_undef : std_logic_vector(63 downto 0) := (others => 'U');
    begin
        wait for 0 ns;
        WaitForBarrier(BarrierLogStart);
        Log(ModelID, "Entering Pmod CLS emulation with SPI mode 0 bus.",
            ALWAYS);
        SB_CLS.SetAlertLogID("MemTestPmodCls", ModelID);

        -- An infinite loop to continuously receive ASCII text from the DUT and
        -- track it as ANSI control plus 16x2 text lines.
        l_spi_recv : loop
            -- Initialize buffer to zero.
            input_buffer := (others => '0');
            buf_len := 0;
            buf_ovr := 0;
            start_char := x"20";

            -- Receive one SPI transmission.
            pr_spi_recv_only(ci_sck, ci_csn, ci_copi, input_buffer, buf_len,
                buf_ovr);

            if (buf_len < 8) then
                -- If the buffer length is less than 8 bits, the transmission
                -- was unsuccessful.
                Alert(ModelID, "PMOD CLS failed a SPI transfer with a short " &
                    "buffer length of " & to_string(buf_len) & " bits",
                    ERROR);
            elsif (buf_len mod 8 /= 0) then
                -- If the buffer length does not equally divide by 8 bits, the
                -- transmision was unsuccessful as the data should always be
                -- a count of whole bytes.
                Alert(ModelID, "PMOD CLS failed a SPI transfer with a uneven " &
                    "buffer length of " & to_string(buf_len) & " bits",
                    ERROR);
            elsif (buf_ovr > 0) then
                -- If the buffer overflowed, data was lost, and the transmission
                -- was unsuccessful.
                Alert(ModelID, "PMOD CLS failed a SPI transfer with a " &
                    "tbc_pmod_cls buffer overflow of " & to_string(buf_len) &
                    " bits",
                    ERROR);
            else
                -- Select the first and second ASCII character in the buffer
                -- vector for ease of comparsion in the IF branches following.
                start_char := input_buffer(buf_len - 1 downto buf_len - 8);
                start_char2 := input_buffer(buf_len - 9 downto buf_len - 16);

                if (start_char = ASCII_CLS_ESC) then
                    -- Log the ANSI control line.
                    Log(ModelID, "PMOD CLS received control line of " &
                        to_string(real(buf_len) / real(8)) & " bytes: " &
                        to_hstring(input_buffer(buf_len - 1 downto 0)) &
                        " decoded: \x" &
                        fn_convert_hex_to_ascii(input_buffer, (buf_len - 8) / 8),
                        INFO);

                    -- Set initial scoring values upon receiving the clear
                    -- screen ANSI sequence. This only checks for a 4-byte
                    -- control sequence. It could be expanded to check for the
                    -- whole sequence by comparing all 4 bytes.
                    if (buf_len = 4) then
                        scored_receipt := (others => 'U');
                        scored_first := true;
                    end if;
                else
                    -- The ASCII text does not start with ESC ('\x'). Thus, it
                    -- is presumed to be a 16 character text line.
                    Log(ModelID, "PMOD CLS received text line of " &
                        to_string(real(buf_len) / real(8)) & " bytes: " &
                        to_hstring(input_buffer(buf_len - 1 downto 0)) &
                        " decoded: " &
                        fn_convert_hex_to_ascii(input_buffer, buf_len / 8),
                        INFO);

                    --if (start_char = ASCII_CLS_X) then
                    --    -- If the text line starts with character 'X' it is
                    --    -- presumed to be the first line of 16x2.
                    --    scored_receipt(63 downto 32) :=
                    --        fn_convert_hex_to_slv32(input_buffer, 8);
                    --    scored_first := false;

                    --elsif (start_char = ASCII_CLS_Z) then
                    --    -- If the text line starts with character 'X' it is
                    --    -- presumed to be the second line of 16x2.
                    --    scored_receipt(31 downto 0) :=
                    --        fn_convert_hex_to_slv32(input_buffer, 8);

                    --    if (scored_receipt /= c_all_undef) then
                    --        -- If the \ref scored_receipt contains real data,
                    --        -- then it is presumed that 16 bytes of data were
                    --        -- parsed from the 32 bytes of ASCII text. The
                    --        -- real data is searched for in the ScoreBoard.
                    --        found_pos := SB_CLS.Find(scored_receipt);
                    --        Log(ModelID,
                    --            "PMOD CLS Text lines matched ScoreBoard " &
                    --            "history: " & to_string(found_pos),
                    --            INFO);
                    --        SB_CLS.Flush(found_pos);
                    --    else
                    --        -- The \ref scored_receipt does not contain real
                    --        -- data as the two ASCII lines did not display
                    --        -- the raw register value 16 hexadecimal characters.
                            Alert(ModelID, "PMOD CLS text lines not tested " &
                                "with ScoreBoard history.",
                                WARNING);
                        --end if;
                    --end if;
                end if;
            end if;
        end loop l_spi_recv;
    end process p_spi_recv;
end architecture simulation_default;
--------------------------------------------------------------------------------
