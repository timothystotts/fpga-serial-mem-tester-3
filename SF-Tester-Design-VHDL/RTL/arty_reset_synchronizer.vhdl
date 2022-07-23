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
-- \file arty_reset_synchronizer.vhdl
--
-- \brief A simple non-generic reset synchronizer for the Arty A7 board.
-- Credit is due to a non-copied examination of VHDL EXTRAS repo on GitHub, VHDL
-- reset_synchronizer.vhdl source at:
-- https://github.com/kevinpt/vhdl-extras/blob/master/rtl/extras/synchronizing.vhdl
-- The reference is MIT License Copyright 2010 Kevin Thibedeau
--
-- Note that this module does not track the clock locking of the MMCM.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--------------------------------------------------------------------------------
entity arty_reset_synchronizer is
	port(
		i_clk_mhz     : in  std_logic;
		i_rstn_global : in  std_logic;
		o_rst_mhz     : out std_logic
	);
end entity arty_reset_synchronizer;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
architecture rtl of arty_reset_synchronizer is
	constant c_RESET_STAGES : natural := 14;

	signal s_rst_shift : std_logic_vector((c_RESET_STAGES - 1) downto 0);
begin
	p_sync_reset_shift : process(i_clk_mhz, i_rstn_global)
	begin
		if (i_rstn_global = '0') then
			s_rst_shift <= (others => '1');
		elsif rising_edge(i_clk_mhz) then
			s_rst_shift <= s_rst_shift((c_RESET_STAGES - 2) downto 0) & '0';
		end if;
	end process p_sync_reset_shift;

	o_rst_mhz <= s_rst_shift(c_RESET_STAGES - 1);
end architecture rtl;
--------------------------------------------------------------------------------
