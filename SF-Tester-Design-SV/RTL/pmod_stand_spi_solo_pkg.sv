/*------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2020-2021 Timothy Stotts
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
-- \file pmod_stand_spi_solo_pkg.sv
--
-- \brief A package of definitions used by the SPI drivers.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//------------------------------------------------------------------------------
package pmod_stand_spi_solo_pkg;
	timeunit 1ns;
	timeprecision 1ps;

	// Typedefs for Pmod CLS custom driver
	typedef logic [3:0] t_pmod_cls_cmd_len;
	typedef logic [4:0] t_pmod_cls_dat_len;
	typedef logic [(7 * 8 - 1):0] t_pmod_cls_ansi_line_7;
	typedef logic [(16 * 8 - 1):0] t_pmod_cls_ascii_line_16;

	// LOG2 of the TX FIFO max count
	localparam integer c_pmod_cls_tx_len_bits = 11;
	// LOG2 of max Wait Cycles count between end of TX and start of RX
	localparam integer c_pmod_cls_wait_cyc_bits = 2;
	// LOG2 of the RX FIFO max count
	localparam integer c_pmod_cls_rx_len_bits = 11;

	typedef logic [7:0] t_pmod_cls_data_byte;
	typedef logic [(c_pmod_cls_tx_len_bits - 1):0] t_pmod_cls_tx_len;
	typedef logic [(c_pmod_cls_wait_cyc_bits - 1):0] t_pmod_cls_wait_cyc;
	typedef logic [(c_pmod_cls_rx_len_bits - 1):0] t_pmod_cls_rx_len;

	// ASCII constant characters for ANSI ESC codes.
	localparam [7:0] ASCII_CLS_ESC = 8'h1b;
	localparam [7:0] ASCII_CLS_BRACKET = 8'h5b;
	localparam [7:0] ASCII_CLS_CHAR_ZERO = 8'h30;
	localparam [7:0] ASCII_CLS_CHAR_SEMICOLON = 8'h3b;
	localparam [7:0] ASCII_CLS_DISP_CLR_CMD = 8'h6a;
	localparam [7:0] ASCII_CLS_CURSOR_POS_CMD = 8'h48;

endpackage : pmod_stand_spi_solo_pkg
//------------------------------------------------------------------------------
`end_keywords
