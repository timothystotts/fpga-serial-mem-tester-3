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
-- \file fpga_serial_acl_tester_testbench.vhdl
--
-- \brief Accelerometer control and reading, testbench.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

library work;
use work.all;
--------------------------------------------------------------------------------
configuration test_default_fpga_regression of fpga_serial_mem_tester_testharness is
    for simulation
        for u_fpga_serial_mem_tester_testbench : fpga_serial_mem_tester_testbench
            use entity work.fpga_serial_mem_tester_testbench(simulation)
            generic map(
                -- Total execution time of approximately less than 8 iterations
                -- of 1/32 flash size testing if timing characteristics are
                -- sped-up by documented factor. Number of iterations were
                -- determined empirically with simulator.
                parm_simulation_duration => 30000 ms, 
                parm_log_file_name => "log_test_default_fpga_regression.txt"
            );

            for simulation
                for uut_fpga_serial_mem_tester : fpga_serial_mem_tester
                    use entity work.fpga_serial_mem_tester(rtl);
                end for;

                -- select
                for u_tbc_clock_gen : tbc_clock_gen
                    -- specify the component architecture to generate
                    -- the clock and reset
                    use entity work.tbc_clock_gen(simulation_default);
                end for;

                for u_tbc_board_ui : tbc_board_ui
                    -- specify the component architecture to emulate/
                    -- monitor/check the user interface board components
                    use entity work.tbc_board_ui(simulation_default);
                end for;

                for u_tbc_pmod_sf3 : tbc_pmod_sf3
                    -- specify the component architecture to emulate/
                    -- monitor/check the serial flash memory peripheral
                    use entity work.tbc_pmod_sf3(simulation_default);
                end for;

                for u_tbc_pmod_cls : tbc_pmod_cls
                    -- specify the component architecture to emulate/
                    -- monitor/check the 16x2 LCD peripheral
                    use entity work.tbc_pmod_cls(simulation_default);
                end for;

                for u_tbc_board_uart : tbc_board_uart
                    -- specify the component architecture to emulate/
                    -- monitor/check the UART terminal
                    use entity work.tbc_board_uart(simulation_default);
                end for;
            end for;
        end for;
    end for;
end configuration test_default_fpga_regression;
--------------------------------------------------------------------------------
