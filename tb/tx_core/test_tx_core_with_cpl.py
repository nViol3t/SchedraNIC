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
    from dma_psdp_ram import PsdpRamMaster,PsdpRamBus,PsdpRamWriteBus
except ImportError:
    # attempt import from current directory
    sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
    try:
        from dma_psdp_ram import PsdpRamMaster,PsdpRamBus,PsdpRamWriteBus
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
    signals=["dma_addr", "ram_addr", "len", "tag", "valid"],
    optional_signals=["ready"]
)

#DMAReadDescStatus — DMA读描述符完成状态
CtrlDMAReadDescStatusBus, CtrlDMAReadDescStatusTransaction, CtrlDMAReadDescStatusSource, CtrlDMAReadDescStatusSink, CtrlDMAReadDescStatusMonitor = define_stream("CtrlDMAReadDescStatus",
    signals=["tag", "error", "valid"]
)

DataDMAReadDescBus, DataDMAReadDescTransaction, DataDMAReadDescSource, DataDMAReadDescSink, DataDMAReadDescMonitor = define_stream("DataDMAReadDesc",
    signals=["dma_addr", "ram_addr", "len", "tag", "valid"],
    optional_signals=["ready"]
)

#DMAReadDescStatus — DMA读描述符完成状态
DataDMAReadDescStatusBus, DataDMAReadDescStatusTransaction, DataDMAReadDescStatusSource, DataDMAReadDescStatusSink, DataDMAReadDescStatusMonitor = define_stream("DataDMAReadDescStatus",
    signals=["tag", "error", "valid"]
)


#TxStream — 发送 AXI Stream 数据
# TxStreamBus, TxStreamTransaction, TxStreamSource, TxStreamSink, TxStreamMonitor = define_stream("TxStream",
#     signals=["tdata", "tkeep", "tvalid", "tlast", "tid", "tdest", "tuser"],
#     optional_signals=["tready"]
# )

# #TxCpl — 发送完成状态通知（带时间戳）
# TxCplBus, TxCplTransaction, TxCplSource, TxCplSink, TxCplMonitor = define_stream("TxCpl",
#     signals=["ts", "tag", "valid"],
#     optional_signals=["ready"]
# )

# Completion path write descriptor request stream
CqDMAWriteDescBus, CqDMAWriteDescTrans, CqDMAWriteDescSource, CqDMAWriteDescSink, CqDMAWriteDescMonitor = define_stream("CqDMAWriteDesc",                                                                                                                          
    signals=["dma_addr", "ram_addr", "len", "tag", "valid"],
    optional_signals=["ready"]
)

# Completion path write descriptor status stream
CqDMAWriteDescStatusBus, CqDMAWriteDescStatusTrans, CqDMAWriteDescStatusSource, CqDMAWriteDescStatusSink, CqDMAWriteDescStatusMonitor = define_stream("CqDMAWriteDescStatus", 
    signals=["tag", "error", "valid"]
)

#event — 请求输出
EventBus, EventTransaction, EventSource, EventSink, EventMonitor = define_stream("Event",
    signals=["queue", "source", "valid"],
    optional_signals=["ready"]
)


class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.enable_debug = False
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        self.axil_master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst)
        self.axil_cqm_master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "axil_cqm"), dut.clk, dut.rst)
        self.axil_ctrl_master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "axil_ctrl"), dut.clk, dut.rst)


        data_dma_ram_bus = PsdpRamBus.from_prefix(dut, "data_dma_ram")
        self.data_dma_ram_master = PsdpRamMaster(data_dma_ram_bus, dut.clk, dut.rst,enable_debug = self.enable_debug)

        ctrl_dma_ram_bus = PsdpRamBus.from_prefix(dut, "ctrl_dma_ram")
        self.ctrl_dma_ram_master = PsdpRamMaster(ctrl_dma_ram_bus, dut.clk, dut.rst,enable_debug = self.enable_debug)


        self.ctrl_dma_read_desc_sink = CtrlDMAReadDescSink(CtrlDMAReadDescBus.from_prefix(dut, "ctrl_dma_read_desc"), dut.clk, dut.rst)
        self.ctrl_dma_read_desc_status_source = CtrlDMAReadDescStatusSource(CtrlDMAReadDescStatusBus.from_prefix(dut, "ctrl_dma_read_desc_status"), dut.clk, dut.rst)

        self.data_dma_read_desc_sink = DataDMAReadDescSink(DataDMAReadDescBus.from_prefix(dut, "data_dma_read_desc"), dut.clk, dut.rst)
        self.data_dma_read_desc_status_source = DataDMAReadDescStatusSource(DataDMAReadDescStatusBus.from_prefix(dut, "data_dma_read_desc_status"), dut.clk, dut.rst)
        

        self.cq_dma_write_desc_sink = CqDMAWriteDescSink(CqDMAWriteDescBus.from_prefix(dut, "cq_dma_write_desc"), dut.clk, dut.rst)
        self.cq_dma_write_desc_status_source = CqDMAWriteDescStatusSource(CqDMAWriteDescStatusBus.from_prefix(dut, "cq_dma_write_desc_status"), dut.clk, dut.rst)

        self.event_req_sink = EventSink(EventBus.from_prefix(dut, "event"), dut.clk, dut.rst)

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

    # async def reset(self):
    #     self.dut.rst.setimmediatevalue(0)
    #     await RisingEdge(self.dut.clk)
    #     await RisingEdge(self.dut.clk)
    #     self.dut.rst.value = 1
    #     await RisingEdge(self.dut.clk)
    #     await RisingEdge(self.dut.clk)
    #     self.dut.rst.value = 0
    #     await RisingEdge(self.dut.clk)
    #     await RisingEdge(self.dut.clk)

    async def send_wqe_data(self, resp, wqe=1, data_len=1024):
        """
        构造每个 WQE 数据，并单独写入 ctrl_dma_ram，记录每个 WQE 的 ptr（DMA地址）
        """
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
    
    async def send_dma_data(self, ram_addr, data_len=1024):
        """
        构造 DMA 数据，并写入 data_dma_ram
        """
        length = data_len
        # 构造包含随机字节的 buffer
        buf = bytearray(random.getrandbits(8) for _ in range(length))

        # 写入DMA RAM
        await self.data_dma_ram_master.write(ram_addr, buf)

MQNIC_QUEUE_BASE_ADDR_VF_REG  = 0x00 #0
MQNIC_QUEUE_CTRL_STATUS_REG   = 0x08 #2
MQNIC_QUEUE_SIZE_CQN_REG      = 0x0C #3

MQNIC_QUEUE_PTR_REG           = 0x10 #4
MQNIC_QUEUE_RANK_WQE          = 0X14 #5
MQNIC_QUEUE_DOORBELL_RTX      = 0X14 #5

MQNIC_QUEUE_ENABLE_MASK  = 0x00000001
MQNIC_QUEUE_ACTIVE_MASK  = 0x00000008
MQNIC_QUEUE_PTR_MASK     = 0xFFFF

MQNIC_QUEUE_CMD_SET_VF_ID     = 0x80010000
MQNIC_QUEUE_CMD_SET_SIZE      = 0x80020000

MQNIC_QUEUE_CMD_SET_CQN       = 0xC0000000


MQNIC_QUEUE_CMD_SET_PROD_PTR  = 0x80800000
MQNIC_QUEUE_CMD_SET_CONS_PTR  = 0x80900000
MQNIC_QUEUE_CMD_SET_ENABLE    = 0x40000100   

MQNIC_CQ_BASE_ADDR_VF_REG  = 0x00
MQNIC_CQ_CTRL_STATUS_REG   = 0x08
MQNIC_CQ_PTR_REG           = 0x0C
MQNIC_CQ_PROD_PTR_REG      = 0x0C
MQNIC_CQ_CONS_PTR_REG      = 0x0E

MQNIC_CQ_ENABLE_MASK  = 0x00010000
MQNIC_CQ_ARM_MASK     = 0x00020000
MQNIC_CQ_ACTIVE_MASK  = 0x00080000
MQNIC_CQ_PTR_MASK     = 0xFFFF

MQNIC_CQ_CMD_SET_VF_ID         = 0x80010000
MQNIC_CQ_CMD_SET_SIZE          = 0x80020000
MQNIC_CQ_CMD_SET_EQN           = 0xC0000000
MQNIC_CQ_CMD_SET_PROD_PTR      = 0x80800000
MQNIC_CQ_CMD_SET_CONS_PTR      = 0x80900000
MQNIC_CQ_CMD_SET_CONS_PTR_ARM  = 0x80910000
MQNIC_CQ_CMD_SET_ENABLE        = 0x40000100
MQNIC_CQ_CMD_SET_ARM           = 0x40000200

#change
MQNIC_RB_PORT_CTRL_REG_TX_CTRL    = 0x20
MQNIC_RB_PORT_CTRL_REG_RX_CTRL    = 0x24


log_queue_size = 10 # 1024
log_desc_block_size = 2 
desc_block_size = 2**log_desc_block_size # 4
MQNIC_DESC_SIZE = 16
TX_TAG_WIDTH = 6
tx_tag = 1 << (TX_TAG_WIDTH - 1)
cq_log_size = 10

async def run_test(dut):

    tb = TB(dut)
    await tb.init()

    await tb.axil_ctrl_master.write_dword(MQNIC_RB_PORT_CTRL_REG_TX_CTRL, 1)
    await tb.axil_ctrl_master.write_dword(MQNIC_RB_PORT_CTRL_REG_RX_CTRL, 1) 

    # tb.log.info("single queue test")
    # # tx_manager
    # await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_ENABLE | 0)
    # await tb.axil_master.write_qword(0*32+MQNIC_QUEUE_BASE_ADDR_VF_REG, 0x8877665544332000)
    # await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_VF_ID | 0)


    # await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_SIZE | (log_desc_block_size << 8) | log_queue_size)
    # await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_CQN | 1)#cpl queue
    # await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_PROD_PTR | 0)
    # await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_CONS_PTR | 0)
    # await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_ENABLE | 1)

    # assert await tb.axil_master.read_qword(0*32+MQNIC_QUEUE_BASE_ADDR_VF_REG) == 0x8877665544332000
    # assert await tb.axil_master.read_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG) == MQNIC_QUEUE_ENABLE_MASK
    # assert await tb.axil_master.read_dword(0*32+MQNIC_QUEUE_SIZE_CQN_REG) == 0x2A000001 #0x04000001
  
    # #cpl_manager
    # await tb.axil_cqm_master.write_dword(1*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_ENABLE | 0)
    # await tb.axil_cqm_master.write_qword(1*16+MQNIC_CQ_BASE_ADDR_VF_REG, 0x8877665544332000)
    # await tb.axil_cqm_master.write_dword(1*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_VF_ID | 0)
    # await tb.axil_cqm_master.write_dword(1*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_SIZE | cq_log_size)
    # await tb.axil_cqm_master.write_dword(1*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_EQN | 1)
    # await tb.axil_cqm_master.write_dword(1*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_PROD_PTR | 0)
    # await tb.axil_cqm_master.write_dword(1*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_CONS_PTR_ARM | 0)
    # await tb.axil_cqm_master.write_dword(1*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_ENABLE | 1)

    # assert await tb.axil_cqm_master.read_qword(1*16+MQNIC_CQ_BASE_ADDR_VF_REG) == 0x8877665544332000
    # assert await tb.axil_cqm_master.read_dword(1*16+MQNIC_CQ_CTRL_STATUS_REG) == ((cq_log_size << 28) | MQNIC_CQ_ENABLE_MASK | MQNIC_CQ_ARM_MASK | 1)


    # #first doorbell
    # tx_prod_ptr = (await tb.axil_master.read_dword(0*32+MQNIC_QUEUE_PTR_REG)) & MQNIC_QUEUE_PTR_MASK
    # tb.log.info("tx Producer pointer: %d", tx_prod_ptr)

    # cpl_prod_ptr = (await tb.axil_cqm_master.read_dword(1*16+MQNIC_CQ_PTR_REG)) >> 16
    # tb.log.info("cpl Producer pointer: %d", cpl_prod_ptr)

    # rank = 0x1000
    # wqe = 4 #range(1, 4)
    # tx_prod_ptr += wqe
    # tb.log.info("[IN] Queue %2d → Rank 0x%04X, WQE %d", 0, rank, wqe)
    # await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_RANK_WQE, rank << 3 | wqe )
    # await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_PROD_PTR | tx_prod_ptr)


    # resp_ctrl = await tb.ctrl_dma_read_desc_sink.recv()
    # assert resp_ctrl.dma_addr == 0x8877665544332000
    # assert resp_ctrl.len == 0x100
    # wqe_ptr_list = await tb.send_wqe_data(resp_ctrl, wqe, 1024)

    # await tb.ctrl_dma_read_desc_status_source.send(CtrlDMAReadDescStatusTransaction(tag=resp_ctrl.tag, error=0))

    # for i in range(wqe):
    #     resp_data_first = await tb.data_dma_read_desc_sink.recv()
    #     assert int(resp_data_first.dma_addr) == wqe_ptr_list[i]
    #     # tb.log.info("%s",resp_data_first)
    #     await tb.data_dma_read_desc_status_source.send(DataDMAReadDescStatusTransaction(tag=resp_data_first.tag, error=0))
    #     resp_data_two = await tb.data_dma_read_desc_sink.recv()
    #     # tb.log.info("%s",resp_data_two)
    #     await tb.data_dma_read_desc_status_source.send(DataDMAReadDescStatusTransaction(tag=resp_data_two.tag, error=0))
    #     data_len = resp_data_first.len + resp_data_two.len

    #     ram_addr = int(resp_data_first.ram_addr)
    #     await tb.send_dma_data(ram_addr,data_len)

    #     pkt = await tb.port_mac[0].tx.recv()
    #     tb.log.info("Packet: %s", pkt)

    #     tb.log.info(f"{GREEN}[CQ STATGE]{RESET}")
    #     resp_cq = await tb.cq_dma_write_desc_sink.recv()
    #     # tb.log.info("%s",resp_cq)
    #     #send ctrl
    #     #recive data
    #     await tb.cq_dma_write_desc_status_source.send(CqDMAWriteDescStatusTrans(tag=resp_cq.tag, error=0)) 
    #     resp_event = await tb.event_req_sink.recv()
    #     # tb.log.info("%s",resp_event)

    #     new_cpl_prod_ptr = (await tb.axil_cqm_master.read_dword(1*16+MQNIC_CQ_PTR_REG)) & MQNIC_CQ_PTR_MASK
    #     tb.log.info("cpl Producer pointer: %d", new_cpl_prod_ptr)

    #     assert new_cpl_prod_ptr - cpl_prod_ptr == 1
    #     cpl_prod_ptr = new_cpl_prod_ptr
    #     # increment consumer pointer
    #     cpl_cons_ptr = (await tb.axil_cqm_master.read_dword(1*16+MQNIC_CQ_PTR_REG)) >> 16
    #     cpl_cons_ptr += 1
    #     tb.log.info("cpl Consumer pointer: %d", cpl_cons_ptr)
    #     await tb.axil_cqm_master.write_dword(1*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_CONS_PTR_ARM | cpl_cons_ptr)
        
    #     tb.log.info(f"{GREEN}[END CQ STATGE]{RESET}")
    # assert cpl_cons_ptr == tx_prod_ptr
    # await Timer(200, units='ns')


    tb.log.info("multiple queue test")

    num_queues = 32
    cpl_num_queues = 4
    queue_base_addr = 0x5555555555000000
    # init
    for q in range(num_queues):
        base = q * 32
        cqn = q // 8
        await tb.axil_master.write_dword(base + MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_ENABLE | 0)
        await tb.axil_master.write_qword(base + MQNIC_QUEUE_BASE_ADDR_VF_REG,queue_base_addr + 0x10000*q)
        await tb.axil_master.write_dword(base + MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_VF_ID | 0)
        await tb.axil_master.write_dword(base + MQNIC_QUEUE_CTRL_STATUS_REG,MQNIC_QUEUE_CMD_SET_SIZE | (log_desc_block_size << 8) | log_queue_size)
        await tb.axil_master.write_dword(base + MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_CQN | cqn)
        await tb.axil_master.write_dword(base + MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_PROD_PTR | 0)
        await tb.axil_master.write_dword(base + MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_CONS_PTR | 0)
        await tb.axil_master.write_dword(base + MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_ENABLE | 1)
        tb.log.info(f"init Queue {q},CQN {cqn}")

    for k in range(cpl_num_queues):
        await tb.axil_cqm_master.write_dword(k*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_ENABLE | 0)
        await tb.axil_cqm_master.write_qword(k*16+MQNIC_CQ_BASE_ADDR_VF_REG, 0x5555555555000000 + 0x10000*k)
        await tb.axil_cqm_master.write_dword(k*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_VF_ID | 0)
        await tb.axil_cqm_master.write_dword(k*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_SIZE | cq_log_size)
        await tb.axil_cqm_master.write_dword(k*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_EQN | k)
        await tb.axil_cqm_master.write_dword(k*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_PROD_PTR | 0)
        await tb.axil_cqm_master.write_dword(k*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_CONS_PTR_ARM | 0)
        await tb.axil_cqm_master.write_dword(k*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_ENABLE | 1)

    tx_queue_prod_ptr = [0]*num_queues
    tx_queue_cons_ptr = [0]*num_queues

    cpl_queue_prod_ptr = [0]*cpl_num_queues
    cpl_queue_cons_ptr = [0]*cpl_num_queues

    doorbell_ram_prod_rtx = [0]*num_queues
    doorbell_ram_cons_rtx = [0]*num_queues
    # for qid in range(num_queues):

    #     tb.log.info(f"Sending WQE on queue {qid}")
    #     base = qid * 32
    #     tx_queue_prod_ptr[qid] = (await tb.axil_master.read_dword(base + MQNIC_QUEUE_PTR_REG)) & MQNIC_QUEUE_PTR_MASK
    #     tb.log.info("TX Producer pointer: %d", tx_queue_prod_ptr[qid])

    #     rank = 0x1000 + qid
    #     wqe = 2
    #     tx_queue_prod_ptr[qid] += wqe
    #     tb.log.info("[IN] Queue %2d → Rank 0x%04X, WQE %d", qid, rank, wqe)
    #     await tb.axil_master.write_dword(base + MQNIC_QUEUE_RANK_WQE, (rank << 3) | wqe)
    #     await tb.axil_master.write_dword(base + MQNIC_QUEUE_CTRL_STATUS_REG,MQNIC_QUEUE_CMD_SET_PROD_PTR | tx_queue_prod_ptr[qid])

    #     # 接收 ctrl 描述符
    #     resp_ctrl = await tb.ctrl_dma_read_desc_sink.recv()
    #     assert resp_ctrl.dma_addr == queue_base_addr + qid * 0x10000
    #     assert resp_ctrl.len == 0x80

    #     wqe_ptr_list = await tb.send_wqe_data(resp_ctrl, wqe, 1024)
    #     await tb.ctrl_dma_read_desc_status_source.send(CtrlDMAReadDescStatusTransaction(tag=resp_ctrl.tag, error=0))

    #     for i in range(wqe):
    #         resp_data_first = await tb.data_dma_read_desc_sink.recv()
    #         assert int(resp_data_first.dma_addr) == wqe_ptr_list[i]
    #         await tb.data_dma_read_desc_status_source.send(DataDMAReadDescStatusTransaction(tag=resp_data_first.tag, error=0))

    #         resp_data_two = await tb.data_dma_read_desc_sink.recv()
    #         await tb.data_dma_read_desc_status_source.send(DataDMAReadDescStatusTransaction(tag=resp_data_two.tag, error=0))

    #         data_len = resp_data_first.len + resp_data_two.len
    #         ram_addr = int(resp_data_first.ram_addr)
    #         await tb.send_dma_data(ram_addr, data_len)

    #         # TX Stream 输出
    #         pkt = await tb.port_mac[0].tx.recv()
    #         tb.log.info("Packet: %s", pkt)
            
    #         tb.log.info(f"{GREEN}[CQ STATGE]{RESET}")
    #         resp_cq = await tb.cq_dma_write_desc_sink.recv()
    #         # tb.log.info("%s",resp_cq)
            
    #         '''
    #             process1: send ctrl
    #             process2: recive data
    #         '''

    #         await tb.cq_dma_write_desc_status_source.send(CqDMAWriteDescStatusTrans(tag=resp_cq.tag, error=0)) 
    #         resp_event = await tb.event_req_sink.recv()
    #         # tb.log.info("%s",resp_event)

    #         cpl_queue = resp_event.queue
    #         new_cpl_prod_ptr = (await tb.axil_cqm_master.read_dword(cpl_queue*16+MQNIC_CQ_PTR_REG)) & MQNIC_CQ_PTR_MASK
    #         assert new_cpl_prod_ptr - cpl_queue_prod_ptr[cpl_queue] == 1
    #         cpl_queue_prod_ptr[cpl_queue] = new_cpl_prod_ptr
    #         tb.log.info("cpl Producer pointer: %d", cpl_queue_prod_ptr[cpl_queue])
            
    #         # increment consumer pointer
    #         cpl_queue_cons_ptr[cpl_queue] = (await tb.axil_cqm_master.read_dword(cpl_queue*16+MQNIC_CQ_PTR_REG)) >> 16
    #         cpl_queue_cons_ptr[cpl_queue] += 1
    #         tb.log.info("cpl Consumer pointer: %d", cpl_queue_cons_ptr[cpl_queue])
    #         await tb.axil_cqm_master.write_dword(cpl_queue*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_CONS_PTR_ARM | cpl_queue_cons_ptr[cpl_queue])
            
    #         tb.log.info(f"{GREEN}[END CQ STATGE]{RESET}")
    

    # tb.log.info("[double] multiple queue test")

    # for qid in range(num_queues):
    #     base = qid * 32

    #     for enqueue_index in range(2):  # 每个 queue 发 2 次 WQE
    #         rank = 0x1000 + qid + (enqueue_index << 8)
    #         wqe = 2 * (enqueue_index + 1)

    #         tx_queue_prod_ptr[qid] = (await tb.axil_master.read_dword(base + MQNIC_QUEUE_PTR_REG)) & MQNIC_QUEUE_PTR_MASK
    #         tx_queue_prod_ptr[qid] += wqe

    #         tb.log.info("[IN %s] Queue %2d → Rank 0x%04X, WQE %d", "FIRST" if enqueue_index == 0 else "SECOND", qid, rank, wqe)

    #         await tb.axil_master.write_dword(base + MQNIC_QUEUE_RANK_WQE, (rank << 3) | wqe)
    #         await tb.axil_master.write_dword(base + MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_PROD_PTR | tx_queue_prod_ptr[qid])

    #         # 接收 ctrl 描述符
    #         resp_ctrl = await tb.ctrl_dma_read_desc_sink.recv()

    #         tb.log.info(f"{YELLOW}[CTRL OUT] Queue %2d (%s, Rank 0x%04X, WQE %d, DMA addr: 0x%X){RESET}", qid, "FIRST" if enqueue_index == 0 else "SECOND", rank, wqe, int(resp_ctrl.dma_addr))

    #         wqe_ptr_list = await tb.send_wqe_data(resp_ctrl, wqe, 1024)
    #         await tb.ctrl_dma_read_desc_status_source.send(CtrlDMAReadDescStatusTransaction(tag=resp_ctrl.tag, error=0))

    #         for i in range(wqe):
    #             resp_data_first = await tb.data_dma_read_desc_sink.recv()
    #             assert int(resp_data_first.dma_addr) == wqe_ptr_list[i]
    #             await tb.data_dma_read_desc_status_source.send(DataDMAReadDescStatusTransaction(tag=resp_data_first.tag, error=0))

    #             resp_data_two = await tb.data_dma_read_desc_sink.recv()
    #             await tb.data_dma_read_desc_status_source.send(DataDMAReadDescStatusTransaction(tag=resp_data_two.tag, error=0))

    #             data_len = resp_data_first.len + resp_data_two.len
    #             ram_addr = int(resp_data_first.ram_addr)
    #             await tb.send_dma_data(ram_addr, data_len)

    #             pkt = await tb.port_mac[0].tx.recv()
    #             tb.log.info("Packet: %s", pkt)

    #             tb.log.info(f"{GREEN}[CQ STAGE]{RESET}")
    #             resp_cq = await tb.cq_dma_write_desc_sink.recv()
    #             # tb.log.info("%s", resp_cq)
    #             await tb.cq_dma_write_desc_status_source.send(CqDMAWriteDescStatusTrans(tag=resp_cq.tag, error=0)) 

    #             resp_event = await tb.event_req_sink.recv()
    #             # tb.log.info("%s", resp_event)

    #             cpl_queue = resp_event.queue
    #             new_cpl_prod_ptr = (await tb.axil_cqm_master.read_dword(cpl_queue*16+MQNIC_CQ_PTR_REG)) & MQNIC_CQ_PTR_MASK
    #             assert new_cpl_prod_ptr - cpl_queue_prod_ptr[cpl_queue] == 1
    #             cpl_queue_prod_ptr[cpl_queue] = new_cpl_prod_ptr
    #             tb.log.info("cpl Producer pointer: %d", cpl_queue_prod_ptr[cpl_queue])

    #             cpl_queue_cons_ptr[cpl_queue] = (await tb.axil_cqm_master.read_dword(cpl_queue*16+MQNIC_CQ_PTR_REG)) >> 16
    #             cpl_queue_cons_ptr[cpl_queue] += 1
    #             tb.log.info("cpl Consumer pointer: %d", cpl_queue_cons_ptr[cpl_queue])
    #             await tb.axil_cqm_master.write_dword(cpl_queue*16+MQNIC_CQ_CTRL_STATUS_REG, MQNIC_CQ_CMD_SET_CONS_PTR_ARM | cpl_queue_cons_ptr[cpl_queue])

    #             tb.log.info(f"{GREEN}[END CQ STAGE]{RESET}")


    # tb.log.info("[full] multiple queue test")

    # wqe_per_queue = [random.randint(1, 4) for _ in range(num_queues)]
    # ranks = [random.randint(0x100, 0x900) for _ in range(num_queues)]

    # # doorbell 发起
    # for q in range(num_queues):
    #     base = q * 32
    #     tx_queue_prod_ptr[q] = (await tb.axil_master.read_dword(base + MQNIC_QUEUE_PTR_REG)) & MQNIC_QUEUE_PTR_MASK

    #     rank = ranks[q]
    #     wqe = wqe_per_queue[q]
    #     tx_queue_prod_ptr[q] += wqe

    #     tb.log.info("[FULL IN] Queue %2d → Rank 0x%04X, WQE %d", q, rank, wqe)


    #     doorbell_ram_prod_rtx[q] += 1
    #     await tb.axil_master.write_dword(base + MQNIC_QUEUE_RANK_WQE, (rank << 3) | wqe)
    #     await tb.axil_master.write_dword(base + MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_PROD_PTR | tx_queue_prod_ptr[q])

    # # 出队处理（DMA ctrl -> data -> TX -> cpl -> CQ）
    # pending = set(range(num_queues))
    # rank_order = []

    # while pending:
    #     resp_ctrl = await tb.ctrl_dma_read_desc_sink.recv()
    #     qid = (resp_ctrl.dma_addr - queue_base_addr) >> 16
    #     if qid > num_queues :
    #         tb.log.error("[Unknown] DMA addr: 0x%X qid: %d", int(resp_ctrl.dma_addr),qid)
    #         continue

    #     base = qid * 32
    #     wqe = wqe_per_queue[qid]
    #     rank = ranks[qid]

    #     tb.log.info(f"{YELLOW}[CTRL OUT] Queue %2d (Rank 0x%04X, WQE %d, DMA addr: 0x%X){RESET}", qid, rank, wqe, int(resp_ctrl.dma_addr))

    #     wqe_ptr_list = await tb.send_wqe_data(resp_ctrl, wqe, 1024)
    #     await tb.ctrl_dma_read_desc_status_source.send(CtrlDMAReadDescStatusTransaction(tag=resp_ctrl.tag, error=0))

    #     for i in range(wqe):
    #         # Data fetch
    #         resp_data_first = await tb.data_dma_read_desc_sink.recv()
    #         assert int(resp_data_first.dma_addr) == wqe_ptr_list[i]
    #         await tb.data_dma_read_desc_status_source.send(DataDMAReadDescStatusTransaction(tag=resp_data_first.tag, error=0))

    #         resp_data_two = await tb.data_dma_read_desc_sink.recv()
    #         await tb.data_dma_read_desc_status_source.send(DataDMAReadDescStatusTransaction(tag=resp_data_two.tag, error=0))

    #         data_len = resp_data_first.len + resp_data_two.len
    #         ram_addr = int(resp_data_first.ram_addr)
    #         await tb.send_dma_data(ram_addr, data_len)

    #         # TX Stream 输出
    #         pkt = await tb.port_mac[0].tx.recv()
    #         tb.log.info("Packet: %s", pkt)

    #         # CQ 处理阶段
    #         tb.log.info(f"{GREEN}[CQ STAGE]{RESET}")
    #         resp_cq = await tb.cq_dma_write_desc_sink.recv()
    #         # tb.log.info("%s", resp_cq)
    #         await tb.cq_dma_write_desc_status_source.send(CqDMAWriteDescStatusTrans(tag=resp_cq.tag, error=0))

    #         resp_event = await tb.event_req_sink.recv()
    #         # tb.log.info("%s", resp_event)

    #         cpl_queue = resp_event.queue
    #         new_cpl_prod_ptr = (await tb.axil_cqm_master.read_dword(cpl_queue*16 + MQNIC_CQ_PTR_REG)) & MQNIC_CQ_PTR_MASK
    #         assert new_cpl_prod_ptr - cpl_queue_prod_ptr[cpl_queue] == 1
    #         cpl_queue_prod_ptr[cpl_queue] = new_cpl_prod_ptr
    #         tb.log.info("cpl Producer pointer: %d", cpl_queue_prod_ptr[cpl_queue])

    #         cpl_queue_cons_ptr[cpl_queue] = (await tb.axil_cqm_master.read_dword(cpl_queue*16 + MQNIC_CQ_PTR_REG)) >> 16
    #         cpl_queue_cons_ptr[cpl_queue] += 1
    #         tb.log.info("cpl Consumer pointer: %d", cpl_queue_cons_ptr[cpl_queue])

    #         await tb.axil_cqm_master.write_dword(cpl_queue*16 + MQNIC_CQ_CTRL_STATUS_REG,
    #                                             MQNIC_CQ_CMD_SET_CONS_PTR_ARM | cpl_queue_cons_ptr[cpl_queue])
    #         tb.log.info(f"{GREEN}[END CQ STAGE]{RESET}")

    #     pending.remove(qid)
    #     rank_order.append((rank, qid))


    # # 检查顺序
    # sorted_rank_order = sorted(rank_order)
    # tb.log.info(f"{CYAN}--- Completion Order Check ---{RESET}")
    # for rank_actual, q_actual in sorted_rank_order:
    #     tb.log.info(f"{GREEN}Got Rank 0x%04X WQE %d (Queue %d){RESET}", rank_actual, wqe_per_queue[q_actual], q_actual)


    # await Timer(200, units='ns')



    tb.log.info("[random] multiple queue test")

    MAX_WQE = 16

    queue_prod_ptr = [0] * num_queues
    queue_cons_ptr = [0] * num_queues
    queue_inflight = [0] * num_queues
    queue_depth = [0] * num_queues

    all_wqe_num = 0

    wqe_per_queue = [random.randint(1, 4) for _ in range(num_queues)]
    ranks = [random.randint(0x001, 0xfff) for _ in range(num_queues)]

    for q in range(num_queues):
        ptr = await tb.axil_master.read_dword(q*32+MQNIC_QUEUE_PTR_REG)
        queue_prod_ptr[q] = ptr & MQNIC_QUEUE_PTR_MASK
        queue_cons_ptr[q] = ptr >> 16
        assert queue_prod_ptr[q] == queue_cons_ptr[q]

    for _ in range(100):
        # ------------------ 随机入队阶段 ------------------
        for _ in range(random.randrange(8)):
            q = random.randrange(num_queues)
            if queue_depth[q] >= MAX_WQE:
                continue

            rank = ranks[q]
            wqe = wqe_per_queue[q]
            base = q * 32

            queue_depth[q] += wqe
            queue_inflight[q] += 1
            queue_prod_ptr[q] = (queue_prod_ptr[q] + wqe) & MQNIC_QUEUE_PTR_MASK
            all_wqe_num += wqe

            tb.log.info(f"{GREEN}[RANDOM IN]{RESET} Queue %2d → Rank 0x%04X, WQE %d", q, rank, wqe)
            doorbell_ram_prod_rtx[q] += 1
            await tb.axil_master.write_dword(base + MQNIC_QUEUE_RANK_WQE, (rank << 3) | wqe)
            await tb.axil_master.write_dword(base + MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_PROD_PTR | queue_prod_ptr[q])

        # ------------------ 随机提交阶段 ------------------
        for _ in range(random.randrange(8)):
            if not any(queue_depth):
                continue

            resp_ctrl = await tb.ctrl_dma_read_desc_sink.recv()
            qid = (resp_ctrl.dma_addr - queue_base_addr) >> 16
            if qid >= num_queues:
                tb.log.error("Invalid qid: %d from addr: 0x%X", qid, int(resp_ctrl.dma_addr))
                continue

            wqe = wqe_per_queue[qid]
            rank = ranks[qid]

            if queue_inflight[qid] > 0:
                queue_inflight[qid] -= 1
            else:
                tb.log.error("[ERROR] qid %d inflight mismatch", qid)

            queue_depth[qid] -= wqe
            queue_cons_ptr[qid] += wqe
            all_wqe_num -= wqe

            tb.log.info(f"{YELLOW}[CTRL OUT]{RESET} Queue %2d → Rank 0x%04X, WQE %d", qid, rank, wqe)
            wqe_ptr_list = await tb.send_wqe_data(resp_ctrl, wqe, 1024)
            await tb.ctrl_dma_read_desc_status_source.send(CtrlDMAReadDescStatusTransaction(tag=resp_ctrl.tag, error=0))

            for i in range(wqe):
                # Data fetch
                resp_data_first = await tb.data_dma_read_desc_sink.recv()
                assert int(resp_data_first.dma_addr) == wqe_ptr_list[i]
                await tb.data_dma_read_desc_status_source.send(DataDMAReadDescStatusTransaction(tag=resp_data_first.tag, error=0))

                resp_data_two = await tb.data_dma_read_desc_sink.recv()
                await tb.data_dma_read_desc_status_source.send(DataDMAReadDescStatusTransaction(tag=resp_data_two.tag, error=0))

                data_len = resp_data_first.len + resp_data_two.len
                ram_addr = int(resp_data_first.ram_addr)
                await tb.send_dma_data(ram_addr, data_len)

                # TX Stream 输出
                pkt = await tb.port_mac[0].tx.recv()
                tb.log.info("Packet: %s", pkt)

                # CQ 处理阶段
                tb.log.info(f"{GREEN}[CQ STAGE]{RESET}")
                resp_cq = await tb.cq_dma_write_desc_sink.recv()
                # tb.log.info("%s", resp_cq)
                await tb.cq_dma_write_desc_status_source.send(CqDMAWriteDescStatusTrans(tag=resp_cq.tag, error=0))

                resp_event = await tb.event_req_sink.recv()
                # tb.log.info("%s", resp_event)

                cpl_queue = resp_event.queue
                new_cpl_prod_ptr = (await tb.axil_cqm_master.read_dword(cpl_queue*16 + MQNIC_CQ_PTR_REG)) & MQNIC_CQ_PTR_MASK
                assert new_cpl_prod_ptr - cpl_queue_prod_ptr[cpl_queue] == 1
                cpl_queue_prod_ptr[cpl_queue] = new_cpl_prod_ptr
                tb.log.info("cpl Producer pointer: %d", cpl_queue_prod_ptr[cpl_queue])

                cpl_queue_cons_ptr[cpl_queue] = (await tb.axil_cqm_master.read_dword(cpl_queue*16 + MQNIC_CQ_PTR_REG)) >> 16
                cpl_queue_cons_ptr[cpl_queue] += 1
                tb.log.info("cpl Consumer pointer: %d", cpl_queue_cons_ptr[cpl_queue])

                await tb.axil_cqm_master.write_dword(cpl_queue*16 + MQNIC_CQ_CTRL_STATUS_REG,
                                                    MQNIC_CQ_CMD_SET_CONS_PTR_ARM | cpl_queue_cons_ptr[cpl_queue])
                tb.log.info(f"{GREEN}[END CQ STAGE]{RESET}")

    # ------------------ 完成剩余 WQE 队列 ------------------

    while any(queue_depth):
        tb.log.info(f"{GREEN}[FINISH LEFT]{RESET} all_wqe_num: %d", all_wqe_num)
        resp_ctrl = await tb.ctrl_dma_read_desc_sink.recv()
        qid = (resp_ctrl.dma_addr - queue_base_addr) >> 16
        if qid >= num_queues:
            continue

        wqe = wqe_per_queue[qid]
        queue_inflight[qid] -= 1
        queue_depth[qid] -= wqe
        queue_cons_ptr[qid] += wqe

        wqe_ptr_list = await tb.send_wqe_data(resp_ctrl, wqe, 1024)
        await tb.ctrl_dma_read_desc_status_source.send(CtrlDMAReadDescStatusTransaction(tag=resp_ctrl.tag, error=0))

        for i in range(wqe):
            # Data fetch
            resp_data_first = await tb.data_dma_read_desc_sink.recv()
            assert int(resp_data_first.dma_addr) == wqe_ptr_list[i]
            await tb.data_dma_read_desc_status_source.send(DataDMAReadDescStatusTransaction(tag=resp_data_first.tag, error=0))

            resp_data_two = await tb.data_dma_read_desc_sink.recv()
            await tb.data_dma_read_desc_status_source.send(DataDMAReadDescStatusTransaction(tag=resp_data_two.tag, error=0))

            data_len = resp_data_first.len + resp_data_two.len
            ram_addr = int(resp_data_first.ram_addr)
            await tb.send_dma_data(ram_addr, data_len)

            # TX Stream 输出
            pkt = await tb.port_mac[0].tx.recv()
            tb.log.info("Packet: %s", pkt)

            # CQ 处理阶段
            tb.log.info(f"{GREEN}[CQ STAGE]{RESET}")
            resp_cq = await tb.cq_dma_write_desc_sink.recv()
            # tb.log.info("%s", resp_cq)
            await tb.cq_dma_write_desc_status_source.send(CqDMAWriteDescStatusTrans(tag=resp_cq.tag, error=0))

            resp_event = await tb.event_req_sink.recv()
            # tb.log.info("%s", resp_event)

            cpl_queue = resp_event.queue
            new_cpl_prod_ptr = (await tb.axil_cqm_master.read_dword(cpl_queue*16 + MQNIC_CQ_PTR_REG)) & MQNIC_CQ_PTR_MASK
            assert new_cpl_prod_ptr - cpl_queue_prod_ptr[cpl_queue] == 1
            cpl_queue_prod_ptr[cpl_queue] = new_cpl_prod_ptr
            tb.log.info("cpl Producer pointer: %d", cpl_queue_prod_ptr[cpl_queue])

            cpl_queue_cons_ptr[cpl_queue] = (await tb.axil_cqm_master.read_dword(cpl_queue*16 + MQNIC_CQ_PTR_REG)) >> 16
            cpl_queue_cons_ptr[cpl_queue] += 1
            tb.log.info("cpl Consumer pointer: %d", cpl_queue_cons_ptr[cpl_queue])

            await tb.axil_cqm_master.write_dword(cpl_queue*16 + MQNIC_CQ_CTRL_STATUS_REG,
                                                MQNIC_CQ_CMD_SET_CONS_PTR_ARM | cpl_queue_cons_ptr[cpl_queue])
            tb.log.info(f"{GREEN}[END CQ STAGE]{RESET}")

    # for q in range(num_queues):
    #     base = q * 32
    #     doorbell_ram_cons_rtx[q] = ((await tb.axil_master.read_dword(base + MQNIC_QUEUE_DOORBELL_RTX)) >> 4 ) & 0xF
    #     assert doorbell_ram_cons_rtx[q] == (doorbell_ram_prod_rtx[q] & 0xF) 

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

def test_tx_core(request):
    dut = "tx_core"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.v"),
        os.path.join(rtl_dir, "tx_queue_manager_change.v"),
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