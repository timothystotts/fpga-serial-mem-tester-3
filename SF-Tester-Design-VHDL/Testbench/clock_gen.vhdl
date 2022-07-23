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
-- \file clock_gen.vhdl
--
-- \brief OSVVM testbench component: External Clock and Reset Generator
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

library work;
--------------------------------------------------------------------------------
entity tbc_clock_gen is
	generic(
        parm_main_clock_period : time := 10 ns;
        parm_reset_cycle_count : positive := 100
    );
    port(
        TBID : in  AlertLogIDType;
        BarrierTestStart : inout std_logic;
        BarrierLogStart : inout std_logic;
        co_main_clock : out std_logic;
        con_main_reset : out std_logic
    );
end entity tbc_clock_gen;
--------------------------------------------------------------------------------
architecture simulation_default of tbc_clock_gen is
    -- Simulation logging ID for this architecture.
    signal ModelID : AlertLogIDType;

    -- Internal clock signal.
    signal so_main_clock : std_logic;
begin
    -- Simulation initialization for the tbc_clock_gen component.
    p_sim_init : process
        variable ID : AlertLogIDType;
    begin
        wait for 0 ns;
        WaitForBarrier(BarrierTestStart);
        ID := GetAlertLogID(PathTail(tbc_clock_gen'path_name), TBID);
        ModelID <= ID;

        wait on ModelID;
        Log(ModelID, "Starting system clock emulation with period " &
            to_string(parm_main_clock_period) & ".", ALWAYS);
        wait;
    end process p_sim_init;

    -- Output main clock
    co_main_clock <= so_main_clock;

    -- Generate main clock
    p_gen_main_clock : process
    begin
        wait for 0 ns;
        WaitForBarrier(BarrierLogStart);
        Log(ModelID, "Entering external clock running with period " &
            to_string(parm_main_clock_period) & " and 50% duty cycle.", ALWAYS);

        -- Generate the main clock. This procedure does not exit.
        CreateClock(
            Clk => so_main_clock,
            Period => parm_main_clock_period,
            DutyCycle => 0.5
        );
        wait;
    end process p_gen_main_clock;

    -- Generate and output main reset
    p_gen_main_reset : process
        -- The reset line is active-low.
        constant c_reset_active : std_logic := '0';

        -- Calculation of time duration to wait before holding reset signal.
        constant c_reset_wait_time : time :=
            parm_reset_cycle_count * parm_main_clock_period;

        -- Calculation of time duration to hold reset signal.
        constant c_reset_period : time :=
            parm_reset_cycle_count * parm_main_clock_period;

        -- The time offset for asserting and deasserting the RESET ACTIVE signal
        -- to the con_main_reset active-low reset output.
        constant c_tpd : time := 2 ns;
    begin
        wait for 0 ns;
        WaitForBarrier(BarrierLogStart);

        -- Test-bench is running. Do not assert reset yet.
        con_main_reset <= not c_reset_active;
        Log(ModelID, "Delaying external reset running with delay " &
            to_string(c_reset_wait_time) & ".", ALWAYS);
        wait for c_reset_wait_time;

        -- Testbench has run a while. Now assert reset just once, with time
        -- duration \ref c_reset_period , with adjustment 2 ns .
        Log(ModelID, "Entering external reset running low with period " &
            to_string(c_reset_period) & ".", ALWAYS);

        -- Generate the main FPGA reset line. This procedure does not exit, even
        -- after the signal has asserted de-active.
        CreateReset(
            Reset => con_main_reset,
            ResetActive => c_reset_active,
            Clk => so_main_clock,
            Period => c_reset_period,
            tpd => c_tpd
        );
        wait;
    end process p_gen_main_reset;
end architecture simulation_default;
--------------------------------------------------------------------------------
