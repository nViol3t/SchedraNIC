# SPDX-License-Identifier: BSD-2-Clause-Views
# Copyright (c) 2020-2023 The Regents of the University of California

TOPLEVEL_LANG = verilog

SIM ?= icarus
WAVES ?= 1

KEY ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

ifeq ($(KEY),1)
    DUT = PIFO_SRAM_Level_1#PIFO_SRAM_Level_other
else
    DUT = PIFO_SRAM_Top
endif

TOPLEVEL = $(DUT)
MODULE   = test_$(DUT)
VERILOG_SOURCES += ../../rtl/Pifo_Sram/PIFO_SRAM_Top.sv
VERILOG_SOURCES += ../../rtl/Pifo_Sram/PIFO_SRAM_Level_1.sv
VERILOG_SOURCES += ../../rtl/Pifo_Sram/PIFO_SRAM_Level_other.sv


VERILOG_SOURCES	+= ../../lib/memory/RAM_Simple_Dual_Port.v
VERILOG_SOURCES	+= ../../lib/Synchronous_Logic/Register.v
VERILOG_SOURCES += ../../lib/Synchronous_Logic/Register_Pipeline.v
VERILOG_SOURCES	+= ../../lib/Synchronous_Logic/Register_Pipeline_Simple.v
VERILOG_SOURCES	+= ../../lib/Boolean_Logic/Multiplexer_Binary_Behavioural.v
VERILOG_SOURCES	+= ../../lib/Boolean_Logic/Multiplexer_Binary_Behavioural_clock.v


# VERILOG_SOURCES_DIR += ../../rtl/include
# VERILOG_SOURCES_DIR	+= ../../rtl/include/Useful_Functions

# INCLUDE_FLAGS = $(addprefix +incdir+,$(VERILOG_SOURCES_DIR))

# module parameters

export PARAM_PTW 			:= 16 
export PARAM_MTW 			:= 24
export PARAM_CTW 			:= 15
export PARAM_LEVEL_TOTAL 	:= 8 
#export PARAM_LEVEL  := 2


ifeq ($(SIM), icarus)
	PLUSARGS += -fst

	COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-P $(TOPLEVEL).$(subst PARAM_,,$(v))=$($(v)))
	COMPILE_ARGS += $(INCLUDE_FLAGS)
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

.PHONY: iverilog_dump.v

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
