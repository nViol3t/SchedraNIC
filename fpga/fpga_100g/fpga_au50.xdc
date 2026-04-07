# XDC constraints for the Xilinx Alveo U50 board
# part: xcu50-fsvh2104-2-e

# General configuration
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.CONFIG.CONFIGFALLBACK ENABLE [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 85.0 [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN DISABLE [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN Enable [current_design]

set_operating_conditions -design_power_budget 63

# System clocks
# 100 MHz
#set_property -dict {LOC G17 IOSTANDARD LVDS} [get_ports clk_100mhz_0_p]
#set_property -dict {LOC G16 IOSTANDARD LVDS} [get_ports clk_100mhz_0_n]
#create_clock -period 10 -name clk_100mhz_0 [get_ports clk_100mhz_0_p]

# 100 MHz
set_property -dict {LOC BB18 IOSTANDARD LVDS} [get_ports clk_100mhz_1_p]
set_property -dict {LOC BC18 IOSTANDARD LVDS} [get_ports clk_100mhz_1_n]
create_clock -period 10.000 -name clk_100mhz_1 [get_ports clk_100mhz_1_p]

# LEDs
set_property -dict {LOC E18 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports qsfp_led_act]
set_property -dict {LOC E16 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports qsfp_led_stat_g]
set_property -dict {LOC F17 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports qsfp_led_stat_y]

set_false_path -to [get_ports {qsfp_led_act qsfp_led_stat_g qsfp_led_stat_y}]
set_output_delay 0.000 [get_ports {qsfp_led_act qsfp_led_stat_g qsfp_led_stat_y}]

# UART
#set_property -dict {LOC BE26 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports usb_uart0_txd]
#set_property -dict {LOC BF26 IOSTANDARD LVCMOS18} [get_ports usb_uart0_rxd]
#set_property -dict {LOC A17  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports usb_uart1_txd]
#set_property -dict {LOC B15  IOSTANDARD LVCMOS18} [get_ports usb_uart1_rxd]
#set_property -dict {LOC A19  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports usb_uart2_txd]
#set_property -dict {LOC A18  IOSTANDARD LVCMOS18} [get_ports usb_uart2_rxd]

#set_false_path -to [get_ports {usb_uart0_txd usb_uart1_txd usb_uart2_txd}]
#set_output_delay 0 [get_ports {usb_uart0_txd usb_uart1_txd usb_uart2_txd}]
#set_false_path -from [get_ports {usb_uart0_rxd usb_uart1_rxd usb_uart2_rxd}]
#set_input_delay 0 [get_ports {usb_uart0_rxd usb_uart1_rxd usb_uart2_rxd}]

# BMC
set_property PACKAGE_PIN C16 [get_ports {msp_gpio[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {msp_gpio[0]}]
set_property PACKAGE_PIN C17 [get_ports {msp_gpio[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {msp_gpio[1]}]
set_property -dict {LOC BB25 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 4} [get_ports msp_uart_txd]
set_property -dict {LOC BB26 IOSTANDARD LVCMOS18} [get_ports msp_uart_rxd]

set_false_path -to [get_ports msp_uart_txd]
set_output_delay 0.000 [get_ports msp_uart_txd]
set_false_path -from [get_ports {{msp_gpio[*]} msp_uart_rxd}]
set_input_delay 0.000 [get_ports {{msp_gpio[*]} msp_uart_rxd}]

# HBM overtemp
set_property -dict {LOC J18 IOSTANDARD LVCMOS18} [get_ports hbm_cattrip]

set_false_path -to [get_ports hbm_cattrip]
set_output_delay 0.000 [get_ports hbm_cattrip]

# SI5394 (SI5394B-A10605-GM)
# I2C address 0x68
# IN0: 161.1328125 MHz from qsfp_recclk
# OUT0: 161.1328125 MHz to qsfp_mgt_refclk_0
# OUT2: 322.265625 MHz to qsfp_mgt_refclk_1
# OUT3: 100 MHz to clk_100mhz_0, clk_100mhz_1, pcie_refclk_2, pcie_refclk_3
#set_property -dict {LOC F20 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports si5394_rst_b]
#set_property -dict {LOC H18 IOSTANDARD LVCMOS18 PULLUP true} [get_ports si5394_int_b]
#set_property -dict {LOC G19 IOSTANDARD LVCMOS18 PULLUP true} [get_ports si5394_lol_b]
#set_property -dict {LOC H19 IOSTANDARD LVCMOS18 PULLUP true} [get_ports si5394_los_b]
#set_property -dict {LOC J16 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8 PULLUP true} [get_ports si5394_i2c_sda]
#set_property -dict {LOC L19 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8 PULLUP true} [get_ports si5394_i2c_scl]

#set_false_path -to [get_ports {si5394_rst_b}]
#set_output_delay 0 [get_ports {si5394_rst_b}]
#set_false_path -from [get_ports {si5394_int_b si5394_lol_b si5394_los_b}]
#set_input_delay 0 [get_ports {si5394_int_b si5394_lol_b si5394_los_b}]

#set_false_path -to [get_ports {si5394_i2c_sda si5394_i2c_scl}]
#set_output_delay 0 [get_ports {si5394_i2c_sda si5394_i2c_scl}]
#set_false_path -from [get_ports {si5394_i2c_sda si5394_i2c_scl}]
#set_input_delay 0 [get_ports {si5394_i2c_sda si5394_i2c_scl}]

# QSFP28 Interfaces
set_property -dict {LOC J45} [get_ports {qsfp_rx_p[0]}]
set_property -dict {LOC J46} [get_ports {qsfp_rx_n[0]}]
set_property -dict {LOC D42} [get_ports {qsfp_tx_p[0]}]
set_property -dict {LOC D43} [get_ports {qsfp_tx_n[0]}]
set_property -dict {LOC G45} [get_ports {qsfp_rx_p[1]}]
set_property -dict {LOC G46} [get_ports {qsfp_rx_n[1]}]
set_property -dict {LOC C40} [get_ports {qsfp_tx_p[1]}]
set_property -dict {LOC C41} [get_ports {qsfp_tx_n[1]}]
set_property -dict {LOC F43} [get_ports {qsfp_rx_p[2]}]
set_property -dict {LOC F44} [get_ports {qsfp_rx_n[2]}]
set_property -dict {LOC B42} [get_ports {qsfp_tx_p[2]}]
set_property -dict {LOC B43} [get_ports {qsfp_tx_n[2]}]
set_property -dict {LOC E45} [get_ports {qsfp_rx_p[3]}]
set_property -dict {LOC E46} [get_ports {qsfp_rx_n[3]}]
set_property -dict {LOC A40} [get_ports {qsfp_tx_p[3]}]
set_property -dict {LOC A41} [get_ports {qsfp_tx_n[3]}]
set_property -dict {LOC N36} [get_ports qsfp_mgt_refclk_0_p]
set_property -dict {LOC N37} [get_ports qsfp_mgt_refclk_0_n]
#set_property -dict {LOC M38 } [get_ports qsfp_mgt_refclk_1_p] ;# MGTREFCLK1P_131 from SI5394 OUT2
#set_property -dict {LOC M39 } [get_ports qsfp_mgt_refclk_1_n] ;# MGTREFCLK1N_131 from SI5394 OUT2
#set_property -dict {LOC F19 IOSTANDARD LVDS} [get_ports qsfp_recclk_p] ;# to SI5394 IN0
#set_property -dict {LOC F18 IOSTANDARD LVDS} [get_ports qsfp_recclk_n] ;# to SI5394 IN0

# 161.1328125 MHz MGT reference clock (SI5394 OUT0)
create_clock -period 6.206 -name qsfp_mgt_refclk_0 [get_ports qsfp_mgt_refclk_0_p]

# 322.265625 MHz MGT reference clock (SI5394 OUT2)
#create_clock -period 3.103 -name qsfp_mgt_refclk_1 [get_ports qsfp_mgt_refclk_1_p]

# PCIe Interface
set_property -dict {LOC AL2} [get_ports {pcie_rx_p[0]}]
set_property -dict {LOC AL1} [get_ports {pcie_rx_n[0]}]
set_property -dict {LOC Y5} [get_ports {pcie_tx_p[0]}]
set_property LOC GTYE4_CHANNEL_X1Y15 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[27].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[3].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC Y4} [get_ports {pcie_tx_n[0]}]
set_property -dict {LOC AM4} [get_ports {pcie_rx_p[1]}]
set_property -dict {LOC AM3} [get_ports {pcie_rx_n[1]}]
set_property -dict {LOC AA7} [get_ports {pcie_tx_p[1]}]
set_property LOC GTYE4_CHANNEL_X1Y14 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[27].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[2].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AA6} [get_ports {pcie_tx_n[1]}]
set_property -dict {LOC AK4} [get_ports {pcie_rx_p[2]}]
set_property -dict {LOC AK3} [get_ports {pcie_rx_n[2]}]
set_property -dict {LOC AB5} [get_ports {pcie_tx_p[2]}]
set_property LOC GTYE4_CHANNEL_X1Y13 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[27].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[1].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AB4} [get_ports {pcie_tx_n[2]}]
set_property -dict {LOC AN2} [get_ports {pcie_rx_p[3]}]
set_property -dict {LOC AN1} [get_ports {pcie_rx_n[3]}]
set_property -dict {LOC AC7} [get_ports {pcie_tx_p[3]}]
set_property LOC GTYE4_CHANNEL_X1Y12 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[27].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[0].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AC6} [get_ports {pcie_tx_n[3]}]
set_property -dict {LOC AP4} [get_ports {pcie_rx_p[4]}]
set_property -dict {LOC AP3} [get_ports {pcie_rx_n[4]}]
set_property -dict {LOC AD5} [get_ports {pcie_tx_p[4]}]
set_property LOC GTYE4_CHANNEL_X1Y11 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[26].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[3].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AD4} [get_ports {pcie_tx_n[4]}]
set_property -dict {LOC AR2} [get_ports {pcie_rx_p[5]}]
set_property -dict {LOC AR1} [get_ports {pcie_rx_n[5]}]
set_property -dict {LOC AF5} [get_ports {pcie_tx_p[5]}]
set_property LOC GTYE4_CHANNEL_X1Y10 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[26].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[2].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AF4} [get_ports {pcie_tx_n[5]}]
set_property -dict {LOC AT4} [get_ports {pcie_rx_p[6]}]
set_property -dict {LOC AT3} [get_ports {pcie_rx_n[6]}]
set_property -dict {LOC AE7} [get_ports {pcie_tx_p[6]}]
set_property LOC GTYE4_CHANNEL_X1Y9 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[26].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[1].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AE6} [get_ports {pcie_tx_n[6]}]
set_property -dict {LOC AU2} [get_ports {pcie_rx_p[7]}]
set_property -dict {LOC AU1} [get_ports {pcie_rx_n[7]}]
set_property -dict {LOC AH5} [get_ports {pcie_tx_p[7]}]
set_property LOC GTYE4_CHANNEL_X1Y8 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[26].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[0].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AH4} [get_ports {pcie_tx_n[7]}]
set_property -dict {LOC AV4} [get_ports {pcie_rx_p[8]}]
set_property -dict {LOC AV3} [get_ports {pcie_rx_n[8]}]
set_property -dict {LOC AG7} [get_ports {pcie_tx_p[8]}]
set_property LOC GTYE4_CHANNEL_X1Y7 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[25].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[3].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AG6} [get_ports {pcie_tx_n[8]}]
set_property -dict {LOC AW2} [get_ports {pcie_rx_p[9]}]
set_property -dict {LOC AW1} [get_ports {pcie_rx_n[9]}]
set_property -dict {LOC AJ7} [get_ports {pcie_tx_p[9]}]
set_property LOC GTYE4_CHANNEL_X1Y6 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[25].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[2].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AJ6} [get_ports {pcie_tx_n[9]}]
set_property -dict {LOC BA2} [get_ports {pcie_rx_p[10]}]
set_property -dict {LOC BA1} [get_ports {pcie_rx_n[10]}]
set_property -dict {LOC AL7} [get_ports {pcie_tx_p[10]}]
set_property LOC GTYE4_CHANNEL_X1Y5 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[25].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[1].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AL6} [get_ports {pcie_tx_n[10]}]
set_property -dict {LOC BC2} [get_ports {pcie_rx_p[11]}]
set_property -dict {LOC BC1} [get_ports {pcie_rx_n[11]}]
set_property -dict {LOC AM9} [get_ports {pcie_tx_p[11]}]
set_property LOC GTYE4_CHANNEL_X1Y4 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[25].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[0].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AM8} [get_ports {pcie_tx_n[11]}]
set_property -dict {LOC AY4} [get_ports {pcie_rx_p[12]}]
set_property -dict {LOC AY3} [get_ports {pcie_rx_n[12]}]
set_property -dict {LOC AN7} [get_ports {pcie_tx_p[12]}]
set_property LOC GTYE4_CHANNEL_X1Y3 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[24].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[3].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AN6} [get_ports {pcie_tx_n[12]}]
set_property -dict {LOC BB4} [get_ports {pcie_rx_p[13]}]
set_property -dict {LOC BB3} [get_ports {pcie_rx_n[13]}]
set_property -dict {LOC AP9} [get_ports {pcie_tx_p[13]}]
set_property LOC GTYE4_CHANNEL_X1Y2 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[24].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[2].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AP8} [get_ports {pcie_tx_n[13]}]
set_property -dict {LOC BD4} [get_ports {pcie_rx_p[14]}]
set_property -dict {LOC BD3} [get_ports {pcie_rx_n[14]}]
set_property -dict {LOC AR7} [get_ports {pcie_tx_p[14]}]
set_property LOC GTYE4_CHANNEL_X1Y1 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[24].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[1].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AR6} [get_ports {pcie_tx_n[14]}]
set_property -dict {LOC BE6} [get_ports {pcie_rx_p[15]}]
set_property -dict {LOC BE5} [get_ports {pcie_rx_n[15]}]
set_property -dict {LOC AT9} [get_ports {pcie_tx_p[15]}]
set_property LOC GTYE4_CHANNEL_X1Y0 [get_cells {pcie4c_uscale_plus_inst/inst/pcie4c_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/gt_wizard.gtwizard_top_i/pcie4c_uscale_plus_0_gt_i/inst/gen_gtwizard_gtye4_top.pcie4c_uscale_plus_0_gt_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[24].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[0].GTYE4_CHANNEL_PRIM_INST}]
set_property -dict {LOC AT8} [get_ports {pcie_tx_n[15]}]
#set_property -dict {LOC AB9 } [get_ports pcie_refclk_0_p] ;# MGTREFCLK0P_227 (for x8 bifurcated lanes 0-7)
#set_property -dict {LOC AB8 } [get_ports pcie_refclk_0_n] ;# MGTREFCLK0N_227 (for x8 bifurcated lanes 0-7)
#set_property -dict {LOC AA11} [get_ports pcie_refclk_2_p] ;# MGTREFCLK1P_227 (for async x8 bifurcated lanes 0-7)
#set_property -dict {LOC AA10} [get_ports pcie_refclk_2_n] ;# MGTREFCLK1N_227 (for async x8 bifurcated lanes 0-7)
set_property -dict {LOC AF9} [get_ports pcie_refclk_1_p]
set_property -dict {LOC AF8} [get_ports pcie_refclk_1_n]
#set_property -dict {LOC AE11} [get_ports pcie_refclk_3_p] ;# MGTREFCLK1P_225 (for async x16 or x8 bifurcated lanes 8-16)
#set_property -dict {LOC AE10} [get_ports pcie_refclk_3_n] ;# MGTREFCLK1N_225 (for async x16 or x8 bifurcated lanes 8-16)
set_property PACKAGE_PIN AW27 [get_ports pcie_reset_n]
set_property IOSTANDARD LVCMOS18 [get_ports pcie_reset_n]
set_property PULLTYPE PULLUP [get_ports pcie_reset_n]

# 100 MHz MGT reference clock
#create_clock -period 10 -name pcie_mgt_refclk_0 [get_ports pcie_refclk_0_p]
create_clock -period 10.000 -name pcie_mgt_refclk_1 [get_ports pcie_refclk_1_p]
#create_clock -period 10 -name pcie_mgt_refclk_2 [get_ports pcie_refclk_2_p]
#create_clock -period 10 -name pcie_mgt_refclk_3 [get_ports pcie_refclk_3_p]

set_false_path -from [get_ports pcie_reset_n]
set_input_delay 0.000 [get_ports pcie_reset_n]

