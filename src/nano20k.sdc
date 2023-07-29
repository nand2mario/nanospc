//Copyright (C)2014-2023 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: 1.9.8.11 Education
//Created Time: 2023-06-23 16:56:38
create_clock -name sys_clk -period 37.04 -waveform {0 18.52} [get_ports {sys_clk}]
//create_clock -name fclk -period 15.59 -waveform {0 7.715} [get_nets {fclk}]
//create_generated_clock -name fclk_p -source [get_nets {fclk}] -master_clock fclk -phase 180 [get_nets {fclk_p}]

create_clock -name hclk5 -period 2.694 -waveform {0 1.347} [get_nets {hclk5}]
create_generated_clock -name hclk -source [get_nets {hclk5}] -master_clock hclk5 -divide_by 5 [get_nets {hclk}]

create_clock -name dclk -period 40.868 -waveform {0 20.434} [get_nets {dclk}]

//create_generated_clock -name wclk -source [get_nets {mclk}] -master_clock mclk -divide_by 2 [get_nets {wclk}]

