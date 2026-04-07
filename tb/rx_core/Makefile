# SPDX-License-Identifier: BSD-2-Clause-Views
# Copyright (c) 2020-2023 The Regents of the University of California

TOPLEVEL_LANG = verilog

SIM ?= icarus
WAVES ?= 1

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

DUT      = rx_core
TOPLEVEL = $(DUT)
MODULE   = test_$(DUT)
VERILOG_SOURCES += ../../rtl/tmp_core/$(DUT).v
VERILOG_SOURCES += ../../rtl/tx_queue_manager.v
VERILOG_SOURCES += ../../rtl/rx_queue_manager.v
VERILOG_SOURCES += ../../rtl/desc_fetch.v
VERILOG_SOURCES += ../../rtl/desc_op_mux.v
VERILOG_SOURCES += ../../rtl/mqnic_egress.v
VERILOG_SOURCES += ../../rtl/mqnic_interface_tx.v
VERILOG_SOURCES += ../../rtl/tx_engine.v
VERILOG_SOURCES += ../../rtl/tx_checksum.v
VERILOG_SOURCES += ../../rtl/mqnic_interface_rx.v
VERILOG_SOURCES += ../../rtl/rx_engine.v
VERILOG_SOURCES += ../../rtl/rx_checksum.v
VERILOG_SOURCES += ../../rtl/cpl_write.v
VERILOG_SOURCES += ../../rtl/cpl_op_mux.v
VERILOG_SOURCES += ../../rtl/cpl_queue_manager.v
VERILOG_SOURCES += ../../rtl/tx_fifo.v
VERILOG_SOURCES += ../../rtl/rx_fifo.v
VERILOG_SOURCES += ../../rtl/mqnic_port.v
VERILOG_SOURCES += ../../rtl/mqnic_port_tx.v
VERILOG_SOURCES += ../../rtl/mqnic_port_rx.v
VERILOG_SOURCES += ../../rtl/mqnic_l2_egress.v
VERILOG_SOURCES += ../../rtl/mqnic_l2_ingress.v
VERILOG_SOURCES += ../../rtl/mqnic_ingress.v
VERILOG_SOURCES += ../../rtl/mqnic_rx_queue_map.v
VERILOG_SOURCES += ../../rtl/rx_hash.v

VERILOG_SOURCES += ../../rtl/Pifo_Sram/PIFO_SRAM_Top.sv
VERILOG_SOURCES += ../../rtl/Pifo_Sram/PIFO_SRAM_Level_1.sv
VERILOG_SOURCES += ../../rtl/Pifo_Sram/PIFO_SRAM_Level_other.sv

VERILOG_SOURCES += ../../lib/memory/RAM_Simple_Dual_Port_byte.v
VERILOG_SOURCES += ../../lib/memory/RAM_Simple_Dual_Port.v

VERILOG_SOURCES	+= ../../lib/Synchronous_Logic/Register.v
VERILOG_SOURCES += ../../lib/Synchronous_Logic/Register_Pipeline.v
VERILOG_SOURCES	+= ../../lib/Synchronous_Logic/Register_Pipeline_Simple.v
VERILOG_SOURCES	+= ../../lib/Boolean_Logic/Multiplexer_Binary_Behavioural.v

VERILOG_SOURCES += ../../lib/axis/rtl/axis_fifo.v
VERILOG_SOURCES += ../../lib/axis/rtl/axis_arb_mux.v
VERILOG_SOURCES += ../../lib/axis/rtl/axis_fifo_adapter.v
VERILOG_SOURCES += ../../lib/axis/rtl/axis_async_fifo.v
VERILOG_SOURCES += ../../lib/axis/rtl/axis_async_fifo_adapter.v
VERILOG_SOURCES += ../../lib/axis/rtl/axis_pipeline_fifo.v

VERILOG_SOURCES += ../../lib/axi/rtl/arbiter.v
VERILOG_SOURCES += ../../lib/axi/rtl/priority_encoder.v
VERILOG_SOURCES += ../../lib/axi/rtl/axil_reg_if.v
VERILOG_SOURCES += ../../lib/axi/rtl/axil_reg_if_wr.v
VERILOG_SOURCES += ../../lib/axi/rtl/axil_reg_if_rd.v



VERILOG_SOURCES += ../../lib/pcie/rtl/dma_if_mux.v
VERILOG_SOURCES += ../../lib/pcie/rtl/dma_if_mux_rd.v
VERILOG_SOURCES += ../../lib/pcie/rtl/dma_if_mux_wr.v
VERILOG_SOURCES += ../../lib/pcie/rtl/dma_if_desc_mux.v
VERILOG_SOURCES += ../../lib/pcie/rtl/dma_ram_demux_wr.v
VERILOG_SOURCES += ../../lib/pcie/rtl/dma_ram_demux_rd.v
VERILOG_SOURCES += ../../lib/pcie/rtl/dma_psdpram.v
VERILOG_SOURCES += ../../lib/pcie/rtl/dma_client_axis_source.v


VERILOG_SOURCES += ../../lib/pcie/rtl/dma_client_axis_sink.v


# module parameters
# todo: add module parameters


ifeq ($(SIM), icarus)
	PLUSARGS += -fst

	COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-P $(TOPLEVEL).$(subst PARAM_,,$(v))=$($(v)))

	ifeq ($(WAVES), 1)
		VERILOG_SOURCES += iverilog_dump.v
		COMPILE_ARGS += -s iverilog_dump
	endif
else ifeq ($(SIM), verilator)
	COMPILE_ARGS += -Wno-SELRANGE -Wno-WIDTH

	COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-G$(subst PARAM_,,$(v))=$($(v)))

	ifeq ($(WAVES), 1)
		COMPILE_ARGS += --trace-fst
	endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

iverilog_dump.v:
	echo 'module iverilog_dump();' > $@
	echo 'initial begin' >> $@
	echo '    $$dumpfile("$(TOPLEVEL).fst");' >> $@
	echo '    $$dumpvars(0, $(TOPLEVEL));' >> $@
	echo 'end' >> $@
	echo 'endmodule' >> $@

clean::
	@rm -rf iverilog_dump.v
	@rm -rf dump.fst $(TOPLEVEL).fst
