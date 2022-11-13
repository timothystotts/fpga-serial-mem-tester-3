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
-- \file pmod_generic_spi_solo_intf.sv
--
-- \brief The system-side interface for the custom SPI driver for generic usage
-- in \ref pmod_generic_spi_solo, implementing only a single peripheral wth
-- Standard SPI operating in Mode 0, without Extended data transfer of more
-- than the standard COPI and CIPO data signals.
------------------------------------------------------------------------------*/
`begin_keywords "1800-2012"
//------------------------------------------------------------------------------
interface pmod_generic_spi_solo_intf #(
	parameter integer parm_tx_len_bits = 11,
	/* LOG2 of max Wait Cycles count between end of TX and start of RX */
	integer parm_wait_cyc_bits = 2,
	/* LOG2 of the RX FIFO max count */
	integer parm_rx_len_bits = 11 /* now ignored due to usage of MACRO */
	) ();

	timeunit 1ns;
	timeprecision 1ps;

	/* system interface to the \ref pmod_generic_spi_solo module. */
	logic go_stand;
	logic spi_idle;
	logic [(parm_tx_len_bits - 1):0] tx_len;
	logic [(parm_wait_cyc_bits - 1):0] wait_cyc;
	logic [(parm_rx_len_bits - 1):0] rx_len;

	/* TX FIFO interface to the \ref pmod_generic_spi_solo module. */
	logic [7:0] tx_data;
	logic tx_enqueue;
	logic tx_ready;

	/* RX FIFO interface to the \ref pmod_generic_spi_solo module. */
	logic [7:0] rx_data;
	logic rx_dequeue;
	logic rx_valid;
	logic rx_avail;

	modport spi_solo (
		input go_stand,
		output spi_idle,
		input tx_len, wait_cyc, rx_len,
		input tx_data, tx_enqueue,
		output tx_ready, rx_data,
		input rx_dequeue,
		output rx_valid, rx_avail);

	modport spi_sysdrv (
		output go_stand,
		input spi_idle,
		output tx_len, wait_cyc, rx_len,
		output tx_data, tx_enqueue,
		input tx_ready, rx_data,
		output rx_dequeue,
		input rx_valid, rx_avail);

endinterface : pmod_generic_spi_solo_intf
//------------------------------------------------------------------------------
`end_keywords
