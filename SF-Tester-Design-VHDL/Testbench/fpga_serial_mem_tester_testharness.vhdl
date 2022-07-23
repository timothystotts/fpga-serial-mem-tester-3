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
-- \file fpga_serial_mem_tester_testharness.vhdl
--
-- \brief SPI NOR Flash Memory testing, testharness.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--------------------------------------------------------------------------------
entity fpga_serial_mem_tester_testharness is
end entity fpga_serial_mem_tester_testharness;
--------------------------------------------------------------------------------
architecture simulation of fpga_serial_mem_tester_testharness is
    component fpga_serial_mem_tester_testbench is
        generic(
            parm_simulation_duration : time := 7 ms;
            parm_fast_simulation : integer := 1;
            parm_log_file_name : string := "log_fpga_serial_mem_tester_no_test.txt"
        );
    end component fpga_serial_mem_tester_testbench;
begin

    u_fpga_serial_mem_tester_testbench : fpga_serial_mem_tester_testbench
        generic map(
            parm_simulation_duration => 7 ms,
            parm_fast_simulation => 1,
            parm_log_file_name => "log_fpga_serial_mem_tester_no_test.txt"
            );

end architecture simulation;
--------------------------------------------------------------------------------
