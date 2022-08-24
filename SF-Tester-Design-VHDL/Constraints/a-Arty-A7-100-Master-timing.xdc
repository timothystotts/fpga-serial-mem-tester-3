## This file is a synthesis and implementation .xdc for the Arty A7-100 Rev. D, specific to the SF Tester clocking.

create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports CLK100MHZ]

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
create_clock -period 135.632 -name wiz_7_373mhz_virt_in -waveform {0.000 67.816}
create_clock -period 135.632 -name wiz_7_373mhz_virt_out -waveform {0.000 67.816}

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
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led2_b]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led2_b]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led2_g]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led2_g]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led2_r]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led2_r]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led3_b]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led3_b]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led3_g]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led3_g]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led3_r]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led3_r]

## LEDs
## The output of LEDs is synchronized out of the design at the MMCM 40 MHz clock.
## A virtual clock is used to allow the tool to automatically compute jitter and other metrics.
## The external device is asynchronous; thus a virtual clock and estimated delay are used.
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led4]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led4]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led5]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led5]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led6]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led6]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -min -add_delay -0.200 [get_ports eo_led7]
set_output_delay -clock [get_clocks wiz_40mhz_virt_in] -max -add_delay 3.500 [get_ports eo_led7]

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

## Pmod Header JB
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

## Pmod Header JC
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

## ChipKit Inner Digital Header

## ChipKit SPI

## ChipKit I2C

## Misc. ChipKit Ports
set_input_delay -clock [get_clocks sys_clk_pin] -min -add_delay 4.000 [get_ports i_resetn]
set_input_delay -clock [get_clocks sys_clk_pin] -max -add_delay 6.000 [get_ports i_resetn]
set_false_path -from [get_ports i_resetn] -to [all_registers]

## SMSC Ethernet PHY

## Quad SPI Flash

## Power Measurements

## Internal asynchronous items requiring false_path
set_false_path -to [get_pins u_uart_tx_only/u_fifo_uart_tx_0/bl.fifo_18_inst_bl.fifo_18_bl/RST]
