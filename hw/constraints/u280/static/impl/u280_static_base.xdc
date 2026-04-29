# Power constraint
set_operating_conditions -design_power_budget 160

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design];

# Xilinx supremacy
set_property	PACKAGE_PIN	D32                 [get_ports  fpga_burn]; 
set_property	IOSTANDARD		LVCMOS18	    [get_ports 	fpga_burn];
set_property    PULLDOWN TRUE                   [get_ports  fpga_burn];

# CMAC clocks
create_clock -period 6.206 -name gt0_refclk_p [get_ports gt0_refclk_p];
create_clock -period 6.206 -name gt1_refclk_p [get_ports gt1_refclk_p];

# HBM (100 MHz)
set_property PACKAGE_PIN BJ44 [get_ports {hbm_clk_clk_n[0]}]
set_property PACKAGE_PIN BJ43 [get_ports {hbm_clk_clk_p[0]}]
set_property IOSTANDARD LVDS [get_ports {hbm_clk_clk_n[0]}] ;# Bank 68 VCCO - VCC1V8 - IO_L11N_T1U_N9_GC_68
set_property IOSTANDARD LVDS [get_ports {hbm_clk_clk_p[0]}] ;# Bank 68 VCCO - VCC1V8 - IO_L11P_T1U_N8_GC_68
create_clock -period 10.000 -name hbm_clk_clk_p [get_ports {hbm_clk_clk_p[0]}];
