/*------------------------------------------------------------------------------
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
------------------------------------------------------------------------------*/
/**-----------------------------------------------------------------------------
-- \file pmod_quad_spi_solo_pkg.sv
--
-- \brief A package of definitions used by the SPI drivers.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//------------------------------------------------------------------------------
package pmod_quad_spi_solo_pkg;
	timeunit 1ns;
	timeprecision 1ps;

	// LOG2 of the TX FIFO max count
	localparam integer c_pmod_sf3_tx_len_bits = 11;
	// LOG2 of max Wait Cycles count between end of TX and start of RX
	localparam integer c_pmod_sf3_wait_cyc_bits = 9;
	// LOG2 of the RX FIFO max count
	localparam integer c_pmod_sf3_rx_len_bits = 11;

	typedef logic [7:0] t_pmod_sf3_data_byte;
	typedef logic [(c_pmod_sf3_tx_len_bits - 1):0] t_pmod_sf3_tx_len;
	typedef logic [(c_pmod_sf3_wait_cyc_bits - 1):0] t_pmod_sf3_wait_cyc;
	typedef logic [(c_pmod_sf3_rx_len_bits - 1):0] t_pmod_sf3_rx_len;

endpackage : pmod_quad_spi_solo_pkg
//------------------------------------------------------------------------------
`end_keywords
