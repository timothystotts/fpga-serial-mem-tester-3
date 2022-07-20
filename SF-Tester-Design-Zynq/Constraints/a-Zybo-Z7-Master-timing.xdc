## This file is a synthesis and implementation timing .xdc for the Zybo Z7 Rev. B
## It is compatible with the Zybo Z7-20 and Zybo Z7-10
## To use it in a project:
## - uncomment the lines corresponding to used pins
## - rename the used ports (in each line, after get_ports) according to the top level signal names in the project

##Clock signal
#create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { sysclk }];


##Switches


##Buttons


##LEDs


##RGB LED 5 (Zybo Z7-20 only)

##RGB LED 6


##Audio Codec
 
 
##Additional Ethernet signals


##USB-OTG over-current detect pin


##Fan (Zybo Z7-20 only)


##HDMI RX

##HDMI RX CEC (Zybo Z7-20 only)


##HDMI TX

##HDMI TX CEC 
 

##Pmod Header JA (XADC)
 

##Pmod Header JB (Zybo Z7-20 only)
                                                                                                                                 
                                                                                                                                 
##Pmod Header JC                                                                                                                  
                                                                                                                                 
                                                                                                                                 
##Pmod Header JD                                                                                                                  
                                                                                                                                 
                                                                                                                                 
##Pmod Header JE                                                                                                                  


##Pcam MIPI CSI-2 Connector
#create_clock -period 2.976 -name dphy_hs_clock_clk_p -waveform {0.000 1.488} [get_ports dphy_hs_clock_clk_p]
 
 
##Unloaded Crypto Chip SWI (for future use)
 
 
##Unconnected Pins (Zybo Z7-20 only)


