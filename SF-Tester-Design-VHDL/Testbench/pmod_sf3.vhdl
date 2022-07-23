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
-- \file pmod_sf3.vhdl
--
-- \brief OSVVM testbench component: incomplete Simulation Model of Digilent Inc.
-- Pmod SF3 external peripheral, using vendor's Verilog model for
-- Micron N25Q256A83E.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

library work;
--------------------------------------------------------------------------------
package tbc_pmod_sf3_types_pkg is
end package tbc_pmod_sf3_types_pkg;
--------------------------------------------------------------------------------
package body tbc_pmod_sf3_types_pkg is
end package body tbc_pmod_sf3_types_pkg;
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

library work;
use work.tbc_pmod_sf3_types_pkg.all;
--------------------------------------------------------------------------------
package tbc_pmod_sf3_pkg is
end package tbc_pmod_sf3_pkg;
--------------------------------------------------------------------------------
package body tbc_pmod_sf3_pkg is
end package body tbc_pmod_sf3_pkg;
---------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

library work;
use work.sf3_testbench_types_pkg.all;
use work.sf3_testbench_pkg.all;
use work.tbc_pmod_sf3_types_pkg.all;
use work.tbc_pmod_sf3_pkg.all;
--------------------------------------------------------------------------------
entity tbc_pmod_sf3 is
	port(
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
end entity tbc_pmod_sf3;
--------------------------------------------------------------------------------
architecture simulation_default of tbc_pmod_sf3 is
	component N25Qxxx_wrapper is
		port(
			S        : in    std_logic;
			C        : in    std_logic;
			HOLD_DQ3 : inout std_logic;
			DQ0      : inout std_logic;
			DQ1      : inout std_logic;
			W_DQ2    : inout std_logic);
	end component N25Qxxx_wrapper;

	signal ModelID : AlertLogIDType;
begin
	-- Simulation initialization
	p_sim_init : process
		variable ID : AlertLogIDType;
	begin
		wait for 0 ns;
		WaitForBarrier(BarrierTestStart);
		ID      := GetAlertLogID(PathTail(tbc_pmod_sf3'path_name), TBID);
		ModelID <= ID;

		wait on ModelID;
		Log(ModelID, "Starting Pmod SF3 emulation with SPI mode 0 bus, two interrupt lines, internal clock of 8.0 MHz.", ALWAYS);
		wait;
	end process p_sim_init;

	p_sim_track : process
	begin
        wait for 0 ns;
        WaitForBarrier(BarrierLogStart);
        Log(ModelID, "Entering Pmod SF3 emulation with SPI mode 0 bus.",
            ALWAYS);
        wait;
	end process p_sim_track;

	u_N25Qxxx_wrapper : N25Qxxx_wrapper
		port map(
			S        => ci_csn,
			C        => ci_sck,
			HOLD_DQ3 => cio_hldn,
			DQ0      => cio_copi,
			DQ1      => cio_cipo,
			W_DQ2    => cio_wrpn
		);
end architecture simulation_default;
--------------------------------------------------------------------------------
