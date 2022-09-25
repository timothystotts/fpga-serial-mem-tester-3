## This file is a general .xdc for the Arty S7-25 Rev. E

create_clock -period 83.333 -name sys_clk_pin -waveform {0.000 41.666} -add [get_ports CLK12MHZ]

# The following are generated clocks as implemented by clock divider components.
# The syntax of the TCL command requires specification of either a port or a pin
# for both the source clock output register and the clock divider output register.
# It appears that the MMCM cannot have one of its ports referenced with [get_ports {}] ,
# but instead requires to have one of its pins referenced wtih [get_pins {}] .
# This causes a synthesis warning of the internal synthesized pin not yet existing;
# but synthesis and implementation still succeed in the end and still create the
# generated clock and still constrain related logic according to the generated
# clock.
create_generated_clock -name genclk5mhz -source [get_pins MMCME2_BASE_inst/CLKOUT0] -divide_by 8 [get_pins u_pmod_sf3_custom_driver/u_pmod_generic_qspi_solo/u_spi_1x_clock_divider/s_clk_out_reg/Q]
create_generated_clock -name genclk50khz -source [get_pins MMCME2_BASE_inst/CLKOUT0] -divide_by 800 [get_pins u_pmod_cls_custom_driver/u_pmod_generic_spi_solo/u_spi_1x_clock_divider/s_clk_out_reg/Q]

# The following are input and output virtual clocks for constaining the estimated input
# and output delays of the top ports of the FPGA design. By constraining with virtual
# clocks that match the waveform of the internal clock that opperates that port, the
# implementation (and synthesis?) are given the liberty to more accurately calculate
# the uncertainty timings at ports that talk with peripheral devices.
# create_clock -period 12.500 -name wiz_80mhz_virt_in -waveform {0.000 6.250}
# create_clock -period 12.500 -name wiz_80mhz_virt_out -waveform {0.000 6.250}
create_clock -period 25.000 -name wiz_40mhz_virt_in -waveform {0.000 12.500}
create_clock -period 25.000 -name wiz_40mhz_virt_out -waveform {0.000 12.500}
# create_clock -period 50.000 -name wiz_20mhz_virt_in -waveform {0.000 25.000}
# create_clock -period 50.000 -name wiz_20mhz_virt_out -waveform {0.000 25.000}
create_clock -period 135.947 -name wiz_7_373mhz_virt_in -waveform {0.000 67.974}
create_clock -period 135.947 -name wiz_7_373mhz_virt_out -waveform {0.000 67.974}

# The following are scaled input and output delays of the top-level ports of the design.
# The waveform that was calculated for determining the input and output delays as
# estimated values (rather than datasheet calculations) is taken from the Vivdado
# Quick Take video on constrainting inputs and outputs. To determine more precise
# delay contraints requires collaboration between the board designer and the
# FPGA designer.

## Switches
## The input of two-position switches is synchronized into the design at the MMCM
## 40 MHz clock. A virtual clock is used to allow the tool to automatically compute
## jitter and other metrics.
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay 10.000 [get_ports ei_sw0]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 15.000 [get_ports ei_sw0]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay 10.000 [get_ports ei_sw1]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 15.000 [get_ports ei_sw1]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay 10.000 [get_ports ei_sw2]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 15.000 [get_ports ei_sw2]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay 10.000 [get_ports ei_sw3]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 15.000 [get_ports ei_sw3]

## RGB LEDs
## The output of RGB LEDs is synchronized out of the design at the MMCM 40 MHz clock.
## A virtual clock is used to allow the tool to automatically compute jitter and other metrics.
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led0_b]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led0_b]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led0_g]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led0_g]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led0_r]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led0_r]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led1_b]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led1_b]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led1_g]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led1_g]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led1_r]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led1_r]

## LEDs
## The output of LEDs is synchronized out of the design at the MMCM 40 MHz clock.
## A virtual clock is used to allow the tool to automatically compute jitter and other metrics.
## The external device is asynchronous; thus a virtual clock and estimated delay are used.
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led2]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led2]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led3]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led3]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led4]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led4]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led5]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led5]

## Buttons
## The input of two-position buttons is synchronized into the design at the MMCM
## 40 MHz clock. A virtual clock is used to allow the tool to automatically compute
## jitter and other metrics.
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay 10.000 [get_ports ei_bt0]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 15.000 [get_ports ei_bt0]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay 10.000 [get_ports ei_bt1]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 15.000 [get_ports ei_bt1]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay 10.000 [get_ports ei_bt2]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 15.000 [get_ports ei_bt2]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay 10.000 [get_ports ei_bt3]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 15.000 [get_ports ei_bt3]

## Pmod Header JA
## The input of full duplex SPI bus with the PMOD CLS peripheral is synchronized into
## the design at the MMCM 40 MHz clock. A virtual clock is used to allow the tool to
## automatically compute jitter and other metrics.
#set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay 10.000 [get_ports ei_pmod_cls_dq1]
#set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 15.000 [get_ports ei_pmod_cls_dq1]

## The output of PMOD CLS at SPI is synchronized into the design at the MMCM 40 MHz clock.
## A virtual clock is used to allow the tool to automatically compute jitter and other metrics.
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_pmod_cls_dq0]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_pmod_cls_dq0]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_pmod_cls_sck]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_pmod_cls_sck]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_pmod_cls_csn]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_pmod_cls_csn]

## Pmod Header JB
## The inputs of PMOD SF3 are all synchronized into the design at the MMCM 40 MHz clock.
## A virtual clock is used to allow the tool to automatically compute jitter and other metrics.
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay 10.000 [get_ports eio_pmod_sf3_hldn_dq3]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 15.000 [get_ports eio_pmod_sf3_hldn_dq3]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay 10.000 [get_ports eio_pmod_sf3_cipo_dq1]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 15.000 [get_ports eio_pmod_sf3_cipo_dq1]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay 10.000 [get_ports eio_pmod_sf3_copi_dq0]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 15.000 [get_ports eio_pmod_sf3_copi_dq0]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay 10.000 [get_ports eio_pmod_sf3_wrpn_dq2]
set_input_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 15.000 [get_ports eio_pmod_sf3_wrpn_dq2]

## The output of PMOD SF3 at SPI is synchronized out of the design at the MMCM 40 MHz clock.
## A virtual clock is used to allow the tool to automatically compute jitter and other metrics.
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eio_pmod_sf3_hldn_dq3]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eio_pmod_sf3_hldn_dq3]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eio_pmod_sf3_cipo_dq1]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eio_pmod_sf3_cipo_dq1]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eio_pmod_sf3_copi_dq0]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eio_pmod_sf3_copi_dq0]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eio_pmod_sf3_wrpn_dq2]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eio_pmod_sf3_wrpn_dq2]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_pmod_sf3_sck]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_pmod_sf3_sck]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_pmod_sf3_csn]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_pmod_sf3_csn]

## Pmod Header JC

## Pmod Header JD

## USB-UART Interface
## The input of UART is disconnected, but would be sampled at
## division of the 7.373 MHz MMCM clock.
## A virtual clock is used to allow the tool to automatically compute jitter and other metrics.
# no delays are computed for unused port ei_uart_rx

## The output of TX ONLY is synchronized out of the design at the MMCM 7.373 MHz clock.
## A virtual clock is used to allow the tool to automatically compute jitter and other metrics.
set_output_delay -clock [get_clocks wiz_7_373mhz_virt_out] -min -add_delay -2.400 [get_ports eo_uart_tx]
set_output_delay -clock [get_clocks wiz_7_373mhz_virt_out] -max -add_delay 14.500 [get_ports eo_uart_tx]

## ChipKit Outer Digital Header

## ChipKit SPI Header
## NOTE: The ChipKit SPI header ports can also be used as digital I/O and share FPGA pins with ck_io10-13. Do not use both at the same time.

## ChipKit Inner Digital Header
## NOTE: these pins are shared with PMOD Headers JC and JD and cannot be used at the same time as the applicable PMOD interface(s)

## Dedicated Analog Inputs

## ChipKit Outer Analog Header - as Single-Ended Analog Inputs
## NOTE: These ports can be used as single-ended analog inputs with voltages from 0-3.3V (ChipKit analog pins A0-A5) or as digital I/O.
## WARNING: Do not use both sets of constraints at the same time!
## NOTE: The following constraints should be used with the XADC IP core when using these ports as analog inputs.

## ChipKit Outer Analog Header - as Digital I/O
## NOTE: The following constraints should be used when using these ports as digital I/O.

## ChipKit Inner Analog Header - as Differential Analog Inputs
## NOTE: These ports can be used as differential analog inputs with voltages from 0-1.0V (ChipKit analog pins A6-A11) or as digital I/O.
## WARNING: Do not use both sets of constraints at the same time!
## NOTE: The following constraints should be used with the XADC core when using these ports as analog inputs.

## ChipKit Inner Analog Header - as Digital I/O
## NOTE: The following constraints should be used when using the inner analog header ports as digital I/O.

## ChipKit I2C

## Misc. ChipKit Ports
set_input_delay -clock [get_clocks sys_clk_pin] -min -add_delay 33.333 [get_ports i_resetn]
set_input_delay -clock [get_clocks sys_clk_pin] -max -add_delay 50.000 [get_ports i_resetn]
set_false_path -from [get_ports i_resetn] -to [all_registers]

## Quad SPI Flash
## Note: the SCK clock signal can be driven using the STARTUPE2 primitive

## Configuration options, can be used for all designs

## SW3 is assigned to a pin M5 in the 1.35v bank. This pin can also be used as
## the VREF for BANK 34. To ensure that SW3 does not define the reference voltage
## and to be able to use this pin as an ordinary I/O the following property must
## be set to enable an internal VREF for BANK 34. Since a 1.35v supply is being
## used the internal reference is set to half that value (i.e. 0.675v). Note that
## this property must be set even if SW3 is not used in the design.

## Internal asynchronous items requiring false_path
set_false_path -to [get_pins u_uart_tx_only/u_fifo_uart_tx_0/genblk5_0.fifo_18_bl.fifo_18_bl/RST]
