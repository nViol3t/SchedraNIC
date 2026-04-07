import itertools
import logging
import os
import random
import sys

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.regression import TestFactory
from cocotb.utils import get_sim_time

from cocotbext.axi import AxiLiteBus, AxiLiteMaster, AxiStreamBus
from cocotbext.axi.stream import define_stream
from cocotbext.eth import EthMac
import heapq

import struct
import socket

try:
    from dma_psdp_ram import ReadPsdpRamMaster,WritePsdpRamMaster,ReadPsdpRamBus,WritePsdpRamBus,PsdpRamWriteBus,PsdpRamReadBus
except ImportError:
    # attempt import from current directory
    sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
    try:
        from dma_psdp_ram import ReadPsdpRamMaster,WritePsdpRamMaster,ReadPsdpRamBus,WritePsdpRamBus,PsdpRamWriteBus,PsdpRamReadBus
    finally:
        del sys.path[0]

RESET  = "\033[0m"
RED    = "\033[91m"
GREEN  = "\033[92m"
YELLOW = "\033[93m"
BLUE   = "\033[94m"
MAGENTA= "\033[95m"
CYAN   = "\033[96m"
WHITE  = "\033[97m"



# DMAReadDesc — DMA读描述符输出
CtrlDMAReadDescBus, CtrlDMAReadDescTransaction, CtrlDMAReadDescSource, CtrlDMAReadDescSink, CtrlDMAReadDescMonitor = define_stream("CtrlDMAReadDesc",
    signals=["dma_addr",  "ram_addr", "len", "tag", "valid"],
    optional_signals=["ready"]
)

#DMAReadDescStatus — DMA读描述符完成状态
CtrlDMAReadDescStatusBus, CtrlDMAReadDescStatusTransaction, CtrlDMAReadDescStatusSource, CtrlDMAReadDescStatusSink, CtrlDMAReadDescStatusMonitor = define_stream("CtrlDMAReadDescStatus",
    signals=["tag", "error", "valid"]
)

DataDMAWriteDescBus, DataDMAWriteDescTransaction, DataDMAWriteDescSource, DataDMAWriteDescSink, DataDMAWriteDescMonitor = define_stream("DataDMAWriteDesc",
    signals=["dma_addr",  "ram_addr",  "len", "tag", "valid"],
    optional_signals=["ready"]
)

DataDMAWriteDescStatusBus, DataDMAWriteDescStatusTransaction, DataDMAWriteDescStatusSource, DataDMAWriteDescStatusSink, DataDMAWriteDescStatusMonitor = define_stream("DataDMAWriteDescStatus",
    signals=["tag", "error", "valid"]
)


# #TxStream — 发送 AXI Stream 数据
# TxStreamBus, TxStreamTransaction, TxStreamSource, TxStreamSink, TxStreamMonitor = define_stream("TxStream",
#     signals=["tdata", "tkeep", "tvalid", "tlast", "tid", "tdest", "tuser"],
#     optional_signals=["tready"]
# )

# #TxCpl — 发送完成状态通知（带时间戳）
# TxCplBus, TxCplTransaction, TxCplSource, TxCplSink, TxCplMonitor = define_stream("TxCpl",
#     signals=["ts", "tag", "valid"],
#     optional_signals=["ready"]
# )


#CplReq — Completion 请求输出
CplReqBus, CplReqTransaction, CplReqSource, CplReqSink, CplReqMonitor = define_stream("CplReq",
    signals=["queue", "tag", "data", "valid"],
    optional_signals=["ready"]
)

#CplReqStatus — Completion 请求返回状态
CplReqStatusBus, CplReqStatusTransaction, CplReqStatusSource, CplReqStatusSink, CplReqStatusMonitor = define_stream("CplReqStatus",
    signals=["tag", "full", "error", "valid"]
)

log_queue_size = 10 # 1024
log_desc_block_size = 2 
desc_block_size = 2**log_desc_block_size # 4
MQNIC_DESC_SIZE = 16


class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.enable_debug = False
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        self.axil_ctrl_master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "axil_ctrl"), dut.clk, dut.rst)
        self.axil_rx_qm_master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "axil_rx_qm"), dut.clk, dut.rst)
        self.axil_rx_indir_tbl_master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "axil_rx_indir_tbl"), dut.clk, dut.rst)


        self.ctrl_dma_read_desc_sink = CtrlDMAReadDescSink(CtrlDMAReadDescBus.from_prefix(dut, "ctrl_dma_read_desc"), dut.clk, dut.rst)
        self.ctrl_dma_read_desc_status_source = CtrlDMAReadDescStatusSource(CtrlDMAReadDescStatusBus.from_prefix(dut, "ctrl_dma_read_desc_status"), dut.clk, dut.rst)
        
        ctrl_dma_ram_bus = WritePsdpRamBus.from_prefix(dut, "ctrl_dma_ram")
        self.ctrl_dma_ram_master = WritePsdpRamMaster(ctrl_dma_ram_bus, dut.clk, dut.rst,enable_debug = self.enable_debug)

        
        self.data_dma_write_desc_sink = DataDMAWriteDescSink(DataDMAWriteDescBus.from_prefix(dut, "m_axis_data_dma_write_desc"), dut.clk, dut.rst)
        self.data_dma_write_desc_status_source = DataDMAWriteDescStatusSource(DataDMAWriteDescStatusBus.from_prefix(dut, "s_axis_data_dma_write_desc_status"), dut.clk, dut.rst)
        
        data_dma_ram_bus = ReadPsdpRamBus.from_prefix(dut, "data_dma_ram")
        self.data_dma_ram_master = ReadPsdpRamMaster(data_dma_ram_bus, dut.clk, dut.rst,enable_debug = self.enable_debug)


        self.cpl_req_sink = CplReqSink(CplReqBus.from_prefix(dut, "rx_cpl_req"), dut.clk, dut.rst)
        self.cpl_req_status_source = CplReqStatusSource(CplReqStatusBus.from_prefix(dut, "rx_cpl_req_status"), dut.clk, dut.rst)


        eth_int_if_width = len(dut.m_axis_tx_tdata) / len(dut.m_axis_tx_tvalid)
        eth_clock_period = 6.4
        eth_speed = 10e9

        if eth_int_if_width == 64:
            # 10G
            eth_clock_period = 6.4
            eth_speed = 10e9
        elif eth_int_if_width == 128:
            # 25G
            eth_clock_period = 2.56
            eth_speed = 25e9
        elif eth_int_if_width == 512:
            # 100G
            eth_clock_period = 3.102
            eth_speed = 100e9

        cocotb.start_soon(Clock(dut.port[0].port_inst.tx_clk, eth_clock_period, units="ns").start())
        cocotb.start_soon(Clock(dut.port[0].port_inst.rx_clk, eth_clock_period, units="ns").start())
        
        dut.port[0].port_inst.tx_rst.setimmediatevalue(0)
        dut.port[0].port_inst.rx_rst.setimmediatevalue(0)

        self.port_mac = [] 

        mac = EthMac(
                    tx_clk=dut.port[0].port_inst.tx_clk,
                    tx_rst=dut.port[0].port_inst.tx_rst,
                    tx_bus=AxiStreamBus.from_prefix(dut.port[0].port_inst.port_tx_inst, "m_axis_tx"),
                    tx_ptp_time=0,
                    tx_ptp_ts=dut.port[0].port_inst.s_axis_tx_cpl_ts,
                    tx_ptp_ts_tag=dut.port[0].port_inst.s_axis_tx_cpl_tag,
                    tx_ptp_ts_valid=dut.port[0].port_inst.s_axis_tx_cpl_valid,

                    rx_clk=dut.port[0].port_inst.rx_clk,
                    rx_rst=dut.port[0].port_inst.rx_rst,
                    rx_bus=AxiStreamBus.from_prefix(dut.port[0].port_inst.port_rx_inst, "s_axis_rx"),
                    rx_ptp_time=0,
                    ifg=12, speed=eth_speed
                )
        self.port_mac.append(mac)
     

        dut.tx_status.setimmediatevalue(2**len(dut.m_axis_tx_tvalid)-1)
        dut.tx_fc_quanta_clk_en.setimmediatevalue(2**len(dut.m_axis_tx_tvalid)-1)
        dut.rx_status.setimmediatevalue(2**len(dut.m_axis_tx_tvalid)-1)
        dut.rx_lfc_req.setimmediatevalue(0)
        dut.rx_pfc_req.setimmediatevalue(0)
        dut.rx_fc_quanta_clk_en.setimmediatevalue(2**len(dut.m_axis_tx_tvalid)-1)

    async def init(self):
        
        self.dut.rst.setimmediatevalue(0)
        for mac in self.port_mac:
            mac.rx.reset.setimmediatevalue(0)
            mac.tx.reset.setimmediatevalue(0)

        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

        self.dut.rst.value = 1
        for mac in self.port_mac:
            mac.rx.reset.setimmediatevalue(1)
            mac.tx.reset.setimmediatevalue(1)

        await Timer(100, 'ns')
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

        self.dut.rst.value = 0
        for mac in self.port_mac:
            mac.rx.reset.setimmediatevalue(0)
            mac.tx.reset.setimmediatevalue(0)

        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)



    def set_idle_generator(self, generator=None):
        if generator:
            self.source.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.sink.set_pause_generator(generator())

    async def send_wqe_data(self, resp, wqe=1, data_len=1024):
        wqe_ptr_list = []

        length = data_len
        ram_addr = int(resp.ram_addr)
        csum_cmd = 0

        for i in range(wqe):
            offset = 0
            wqe_base = 0  # 每个buf从0开始填
            current_ptr = random.randint(0x10000000, 0x1FFFFFFF)
            wqe_ptr_list.append(current_ptr)

            buf = bytearray(MQNIC_DESC_SIZE * desc_block_size)

            # 第一个描述符块
            seg = min(length - offset, 42) if desc_block_size > 1 else length - offset
            struct.pack_into("<HHLQ", buf, wqe_base + 0, 0, csum_cmd, seg, current_ptr + offset if seg else 0)
            offset += seg

            # 后续描述符块
            for k in range(1, desc_block_size):
                seg = min(length - offset, 4096) if k < desc_block_size - 1 else length - offset
                struct.pack_into("<4xLQ", buf, k * MQNIC_DESC_SIZE, seg, current_ptr + offset if seg else 0)
                offset += seg

            # 每个 WQE 单独写入
            await self.ctrl_dma_ram_master.write(ram_addr + 2 * i * len(buf), buf)

        return wqe_ptr_list
    
    async def send_port_data(self, data_len=1024):

        length = data_len
        pkt = bytearray(random.getrandbits(8) for _ in range(length))
        await self.port_mac[0].rx.send(pkt)
        return pkt

MQNIC_QUEUE_BASE_ADDR_VF_REG  = 0x00 #0
MQNIC_QUEUE_CTRL_STATUS_REG   = 0x08 #2
MQNIC_QUEUE_SIZE_CQN_REG      = 0x0C #3

MQNIC_QUEUE_PTR_REG           = 0x10 #4
MQNIC_QUEUE_RANK_WQE          = 0X14 #5

MQNIC_QUEUE_ENABLE_MASK  = 0x00000001
MQNIC_QUEUE_ACTIVE_MASK  = 0x00000008
MQNIC_QUEUE_PTR_MASK     = 0xFFFF

MQNIC_QUEUE_CMD_SET_VF_ID     = 0x80010000
MQNIC_QUEUE_CMD_SET_SIZE      = 0x80020000

MQNIC_QUEUE_CMD_SET_CQN       = 0xC0000000


MQNIC_QUEUE_CMD_SET_PROD_PTR  = 0x80800000
MQNIC_QUEUE_CMD_SET_CONS_PTR  = 0x80900000
MQNIC_QUEUE_CMD_SET_ENABLE    = 0x40000100   

#change
MQNIC_RB_PORT_CTRL_REG_TX_CTRL    = 0x20
MQNIC_RB_PORT_CTRL_REG_RX_CTRL    = 0x24


async def run_test(dut):

    tb = TB(dut)
    await tb.init()

    await tb.axil_ctrl_master.write_dword(MQNIC_RB_PORT_CTRL_REG_TX_CTRL, 1)
    await tb.axil_ctrl_master.write_dword(MQNIC_RB_PORT_CTRL_REG_RX_CTRL, 1) 

    tb.log.info("single rx queue test")
    await tb.axil_rx_qm_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_ENABLE | 0)
    await tb.axil_rx_qm_master.write_qword(0*32+MQNIC_QUEUE_BASE_ADDR_VF_REG, 0x8877665544332000)
    await tb.axil_rx_qm_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_VF_ID | 0)
    await tb.axil_rx_qm_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_SIZE | (log_desc_block_size << 8) | log_queue_size)
    await tb.axil_rx_qm_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_CQN | 1)
    await tb.axil_rx_qm_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_PROD_PTR | 0)
    await tb.axil_rx_qm_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_CONS_PTR | 0)
    await tb.axil_rx_qm_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_ENABLE | 1)

    assert await tb.axil_rx_qm_master.read_qword(0*32+MQNIC_QUEUE_BASE_ADDR_VF_REG) == 0x8877665544332000
    assert await tb.axil_rx_qm_master.read_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG) == MQNIC_QUEUE_ENABLE_MASK
    assert await tb.axil_rx_qm_master.read_dword(0*32+MQNIC_QUEUE_SIZE_CQN_REG) == 0x2A000001 #0x04000001

    await tb.axil_rx_qm_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_PROD_PTR | 1024)

    for _ in range(100):
        send_data = await tb.send_port_data(1024)

        resp_ctrl = await tb.ctrl_dma_read_desc_sink.recv()
        tb.log.info("%s",resp_ctrl)
        assert resp_ctrl.len == 0x40
        
        await tb.send_wqe_data(resp_ctrl, 1, 1024)
        await tb.ctrl_dma_read_desc_status_source.send(CtrlDMAReadDescStatusTransaction(tag=resp_ctrl.tag, error=0))

        #1024
        resp_data_first = await tb.data_dma_write_desc_sink.recv()
        tb.log.info("%s",resp_data_first)
        resp_data_second = await tb.data_dma_write_desc_sink.recv()
        tb.log.info("%s",resp_data_second)

        addr = int(resp_data_first.ram_addr)
        length = resp_data_first.len + resp_data_second.len
        recive_data = await tb.data_dma_ram_master.read(addr, length)
        assert send_data == recive_data.data

        await tb.data_dma_write_desc_status_source.send(DataDMAWriteDescStatusTransaction(tag=resp_data_first.tag, error=0))

        resp_cpl = await tb.cpl_req_sink.recv()
        await tb.cpl_req_status_source.send(CplReqStatusTransaction(tag=resp_cpl.tag, error=0, full=0))




    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)



if cocotb.SIM_NAME:

    factory = TestFactory(run_test)
    factory.generate_tests()


 # cocotb-test


tests_dir = os.path.dirname(__file__)
rtl_dir = os.path.abspath(os.path.join(tests_dir, '..', '..', 'rtl'))
lib_dir = os.path.abspath(os.path.join(rtl_dir, '..', 'lib'))
memory_rtl_dir              = os.path.abspath(os.path.join(lib_dir  ,'memory'))

axi_rtl_dir = os.path.abspath(os.path.join(lib_dir, 'axi', 'rtl'))
axis_rtl_dir = os.path.abspath(os.path.join(lib_dir, 'axis', 'rtl'))
eth_rtl_dir = os.path.abspath(os.path.join(lib_dir, 'eth', 'rtl'))
pcie_rtl_dir = os.path.abspath(os.path.join(lib_dir, 'pcie', 'rtl'))
synchronous_Logic_rtl_dir   = os.path.abspath(os.path.join(lib_dir  ,'Synchronous_Logic'))
boolean_logic_rtl_dir       = os.path.abspath(os.path.join(lib_dir  ,'Boolean_Logic'))

def test_rx_core(request):
    dut = "rx_core"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.v"),
        os.path.join(rtl_dir, "queue_manager.v"),
        os.path.join(rtl_dir, "axis_arb_mux.v"),
        os.path.join(rtl_dir, "arbiter.v"),         
        os.path.join(rtl_dir, "priority_encoder.v"),      
        os.path.join(memory_rtl_dir, "RAM_Simple_Dual_Port.v"),
        os.path.join(memory_rtl_dir, "RAM_Simple_Dual_Port_byte.v"),
        os.path.join(memory_rtl_dir, "axis_fifo.v"),

        os.path.join(rtl_dir, "Pifo_Sram/PIFO_SRAM_Top.sv"),
        os.path.join(rtl_dir, "Pifo_Sram/PIFO_SRAM_Level_1.sv"),
        os.path.join(rtl_dir, "Pifo_Sram/PIFO_SRAM_Level_other.sv"),

        os.path.join(synchronous_Logic_rtl_dir, "Register.v"),
        os.path.join(synchronous_Logic_rtl_dir, "Register_Pipeline.v"),
        os.path.join(synchronous_Logic_rtl_dir, "Register_Pipeline_Simple.v"),
        os.path.join(boolean_logic_rtl_dir, "Multiplexer_Binary_Behavioural.v"),

        os.path.join(rtl_dir, "desc_fetch.v"),
        os.path.join(rtl_dir, "desc_op_mux.v"),
       
        os.path.join(rtl_dir, "tx_engine.v"),
        os.path.join(rtl_dir, "tx_checksum.v"),
        
        os.path.join(pcie_rtl_dir, "dma_if_mux.v"),
        os.path.join(pcie_rtl_dir, "dma_if_mux_rd.v"),
        os.path.join(pcie_rtl_dir, "dma_if_mux_wr.v"),
        os.path.join(pcie_rtl_dir, "dma_if_desc_mux.v"),
        os.path.join(pcie_rtl_dir, "dma_ram_demux_rd.v"),
        os.path.join(pcie_rtl_dir, "dma_ram_demux_wr.v"),
        os.path.join(pcie_rtl_dir, "dma_psdpram.v"),
        os.path.join(pcie_rtl_dir, "dma_client_axis_source.v"),
   
    ]

    parameters = {}
    parameters['AXIS_PCIE_DATA_WIDTH'] = 512
    # parameters['ADDR_WIDTH'] = 64
    # parameters['REQ_TAG_WIDTH'] = 8
    # parameters['OP_TABLE_SIZE'] = 16
    # parameters['OP_TAG_WIDTH'] = 8
    # parameters['QUEUE_INDEX_WIDTH'] = 8
    # parameters['CPL_INDEX_WIDTH'] = 8
    # parameters['QUEUE_PTR_WIDTH'] = 16
    # parameters['LOG_QUEUE_SIZE_WIDTH'] = 4
    # parameters['DESC_SIZE'] = 16
    # parameters['LOG_BLOCK_SIZE_WIDTH'] = 2
    # parameters['PIPELINE'] = 2
    # parameters['AXIL_DATA_WIDTH'] = 32
    # parameters['AXIL_ADDR_WIDTH'] = parameters['QUEUE_INDEX_WIDTH'] + 5
    # parameters['AXIL_STRB_WIDTH'] = parameters['AXIL_DATA_WIDTH'] // 8

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}

    sim_build = os.path.join(tests_dir, "sim_build",
        request.node.name.replace('[', '-').replace(']', ''))

    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        toplevel=toplevel,
        module=module,
        parameters=parameters,
        sim_build=sim_build,
        extra_env=extra_env,
    )