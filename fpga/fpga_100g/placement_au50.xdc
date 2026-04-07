# Placement constraints
create_pblock pblock_slr0
add_cells_to_pblock [get_pblocks pblock_slr0] [get_cells -quiet [list core_inst/core_inst/core_pcie_inst/core_inst/dma_if_mux_inst {core_inst/core_inst/core_pcie_inst/core_inst/iface[0].interface_inst/interface_rx_inst} {core_inst/core_inst/core_pcie_inst/core_inst/iface[0].interface_inst/rx_fifo_inst} {core_inst/core_inst/core_pcie_inst/core_inst/iface[0].interface_inst/tx_fifo_inst}]]
resize_pblock [get_pblocks pblock_slr0] -add {SLR0:SLR0}

create_pblock pblock_slr1
resize_pblock [get_pblocks pblock_slr1] -add {SLR1:SLR1}
#add_cells_to_pblock [get_pblocks pblock_slr1] [get_cells -quiet ""]

create_pblock pblock_pcie
add_cells_to_pblock [get_pblocks pblock_pcie] [get_cells -quiet [list core_inst/core_inst/core_pcie_inst/dma_if_pcie_inst core_inst/core_inst/core_pcie_inst/pcie_axil_master_inst core_inst/core_inst/core_pcie_inst/pcie_msix_inst core_inst/core_inst/pcie_if_inst pcie4c_uscale_plus_inst]]
resize_pblock [get_pblocks pblock_pcie] -add {CLOCKREGION_X6Y0:CLOCKREGION_X7Y3}

create_pblock pblock_eth
add_cells_to_pblock [get_pblocks pblock_eth] [get_cells -quiet [list {core_inst/core_inst/core_pcie_inst/core_inst/iface[0].interface_inst/port[0].port_inst/port_rx_inst/rx_async_fifo_inst} {core_inst/core_inst/core_pcie_inst/core_inst/iface[0].interface_inst/port[0].port_inst/port_tx_inst/tx_async_fifo_inst} {core_inst/core_inst/core_pcie_inst/core_inst/iface[0].interface_inst/port[0].port_inst/port_tx_inst/tx_cpl_fifo_inst} qsfp_cmac_inst]]
resize_pblock [get_pblocks pblock_eth] -add {CLOCKREGION_X0Y6:CLOCKREGION_X0Y7}

# CMACs
set_property LOC CMACE4_X0Y4 [get_cells -hierarchical -filter {NAME =~ qsfp_cmac_inst/cmac_inst/inst/i_cmac_usplus_top/* && REF_NAME==CMACE4}]


