# SF-Tester-Design-SV

## Verification on 2023-03-03

Manually tested on Arty A7-100 hardware on 2023-??-??, #1.
Checked on hardware:
- Button press to GO for Buttons 3,2,1,0
- Switch select to GO for Switch 3,2,1,0
- Displaying step indication on RGB LEDs 3,2,1,0
- Displaying done and pass on Basic LEDs 5,4
- Displaying "SF3 PA/PB/PC/PD address GO/ERS/PRO/TST/END errcount" on LCD and UART.
- Halting at the end of 1 full address range test after iteration address h01F00000.
- sf_tester_fsm.sv: c_force_fake_errors 1'b1 or 1'b0 to show a non-zero error count.

Manually tested on Arty S7-25 hardware on 2023-03-03, #1.
Checked on hardware:
- Button press to GO for Buttons 3,2,1,0
- Switch select to GO for Switch 3,2,1,0
- Displaying step indication on RGB LEDs 1,0
- Displaying done and pass on Basic LEDs 3,2
- Displaying "SF3 PA/PB/PC/PD address GO/ERS/PRO/TST/END errcount" on LCD and UART.
- Halting at the end of 1 full address range test after iteration address h01F00000.
- sf_tester_fsm.sv: c_force_fake_errors 1'b1 or 1'b0 to show a non-zero error count.

NO WARRANTY
MIT LICENSE
Copyright (c) 2020-2023 Timothy Stotts
