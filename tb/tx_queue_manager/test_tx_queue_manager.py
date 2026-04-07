#!/usr/bin/env python
# SPDX-License-Identifier: BSD-2-Clause-Views
# Copyright (c) 2020 The Regents of the University of California

import logging
import os
import random

import cocotb_test.simulator

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.regression import TestFactory

from cocotbext.axi import AxiLiteBus, AxiLiteMaster
from cocotbext.axi.stream import define_stream


DequeueReqBus, DequeueReqTransaction, DequeueReqSource, DequeueReqSink, DequeueReqMonitor = define_stream("DequeueReq",
    signals=["queue","wqe", "tag", "valid"],
    optional_signals=["ready"]
)

DequeueRespBus, DequeueRespTransaction, DequeueRespSource, DequeueRespSink, DequeueRespMonitor = define_stream("DequeueResp",
    signals=["queue", "ptr", "phase", "addr", "block_size", "cpl", "tag", "op_tag", "empty", "error", "wqe", "valid"],
    optional_signals=["ready"]
)

DequeueCommitBus, DequeueCommitTransaction, DequeueCommitSource, DequeueCommitSink, DequeueCommitMonitor = define_stream("DequeueCommit",
    signals=["op_tag", "valid"],
    optional_signals=["ready"]
)

DoorbellBus, DoorbellTransaction, DoorbellSource, DoorbellSink, DoorbellMonitor = define_stream("Doorbell",
    signals=["queue","tag","rank", "wqe", "valid"],
    optional_signals=["ready"]
)

PifoCompBus, PifoCompTransaction, PifoCompSource, PifoCompSink, PifoCompMonitor = define_stream("PifoComp",
    signals=["queue", "tag","valid"]
)



class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        self.axil_master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst)

        self.dequeue_req_source = DequeueReqSource(DequeueReqBus.from_prefix(dut, "s_axis_dequeue_req"), dut.clk, dut.rst)
        self.dequeue_resp_sink = DequeueRespSink(DequeueRespBus.from_prefix(dut, "m_axis_dequeue_resp"), dut.clk, dut.rst)
        self.dequeue_commit_source = DequeueCommitSource(DequeueCommitBus.from_prefix(dut, "s_axis_dequeue_commit"), dut.clk, dut.rst)
        self.doorbell_sink = DoorbellSink(DoorbellBus.from_prefix(dut, "m_axis_doorbell"), dut.clk, dut.rst)
        self.pifo_comp_source = PifoCompSource(PifoCompBus.from_prefix(dut, "s_axis_pifo_comp"), dut.clk, dut.rst)


        dut.enable.setimmediatevalue(0)

    def set_idle_generator(self, generator=None):
        if generator:
            self.source.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.sink.set_pause_generator(generator())

    async def reset(self):
        self.dut.rst.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)


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


async def run_test(dut):

    OP_TABLE_SIZE = int(os.getenv("PARAM_OP_TABLE_SIZE"))

    tb = TB(dut)

    await tb.reset()

    dut.enable.value = 1

    tb.log.info("Test read and write queue configuration registers")

    await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_ENABLE | 0)
    await tb.axil_master.write_qword(0*32+MQNIC_QUEUE_BASE_ADDR_VF_REG, 0x8877665544332000)
    await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_VF_ID | 0)


    await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_SIZE | 4)
    await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_CQN | 1)
    await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_PROD_PTR | 0)
    await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_CONS_PTR | 0)
    await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_ENABLE | 1)

    assert await tb.axil_master.read_qword(0*32+MQNIC_QUEUE_BASE_ADDR_VF_REG) == 0x8877665544332000
    assert await tb.axil_master.read_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG) == MQNIC_QUEUE_ENABLE_MASK
    assert await tb.axil_master.read_dword(0*32+MQNIC_QUEUE_SIZE_CQN_REG) == 0x04000001

    tb.log.info("Test enqueue and dequeue")

    # data1 increment producer pointer
    prod_ptr = (await tb.axil_master.read_dword(0*32+MQNIC_QUEUE_PTR_REG)) & MQNIC_QUEUE_PTR_MASK
    prod_ptr += 1
    tb.log.info("Producer pointer: %d", prod_ptr)
    rank = 0b0_0000_0000_0001 #13bit
    wqe = 1
    await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_RANK_WQE, rank << 3 | wqe )
    await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_PROD_PTR | prod_ptr)

    # data1 check for doorbell
    db = await tb.doorbell_sink.recv()
    tb.log.info("Doorbell: %s", db)

    assert db.queue == 0
    assert db.rank == rank
    assert db.wqe == wqe

    # read consumer pointer
    cons_ptr = (await tb.axil_master.read_dword(0*32+MQNIC_QUEUE_PTR_REG)) >> 16
    tb.log.info("Consumer pointer: %d", cons_ptr)

    # data2 increment producer pointer
    prod_ptr += 1
    tb.log.info("Producer pointer: %d", prod_ptr)
    rank = 0b0_0000_0000_0010
    wqe = 4
    await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_RANK_WQE, rank << 3 | wqe )
    await tb.axil_master.write_dword(0*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_PROD_PTR | prod_ptr)

    # data1 pifocomb 
    await tb.pifo_comp_source.send(PifoCompTransaction(queue=0))

    # data2 check for doorbell
    db = await tb.doorbell_sink.recv()
    tb.log.info("Doorbell: %s", db)
    assert db.queue == 0
    assert db.rank == rank
    assert db.wqe == wqe

    # data2 pifocomb 
    await tb.pifo_comp_source.send(PifoCompTransaction(queue=db.queue,tag=db.tag))

    # data1 dequeue request
    await tb.dequeue_req_source.send(DequeueReqTransaction(queue=0,wqe=wqe,tag=1))
    resp = await tb.dequeue_resp_sink.recv()
    tb.log.info("Dequeue response: %s", resp)

    assert resp.queue == 0
    assert resp.ptr == cons_ptr

    base_addr = 0x8877665544332000
    entry_size = 16 #和DESC_SIZE有关，rtl422行
    expected_addr = base_addr + (resp.ptr & 0xF) * entry_size

    assert resp.phase == ~(resp.ptr >> 4) & 1
    assert resp.addr == expected_addr
    assert resp.block_size == 0
    assert resp.cpl == 1
    assert resp.tag == 1
    assert resp.wqe == wqe
    assert not resp.empty
    assert not resp.error

    # data1 dequeue commit
    await tb.dequeue_commit_source.send(DequeueCommitTransaction(op_tag=resp.op_tag))

    await Timer(100, 'ns')

    # data1 read consumer pointer
    new_cons_ptr = (await tb.axil_master.read_dword(0*32+MQNIC_QUEUE_PTR_REG)) >> 16
    tb.log.info("Consumer pointer: %d", new_cons_ptr)
    assert new_cons_ptr - cons_ptr == wqe

    cons_ptr = new_cons_ptr

    # data2 dequeue request
    await tb.dequeue_req_source.send(DequeueReqTransaction(queue=0,wqe=wqe, tag=1))
    resp = await tb.dequeue_resp_sink.recv()
    tb.log.info("Dequeue response: %s", resp)

    assert resp.queue == 0
    assert resp.ptr == cons_ptr
    assert resp.wqe == wqe

    base_addr = 0x8877665544332000
    entry_size = 16 
    expected_addr = base_addr + (resp.ptr & 0xF) * entry_size

    assert resp.phase == ~(resp.ptr >> 4) & 1
    assert resp.addr == expected_addr
    assert resp.block_size == 0
    assert resp.cpl == 1
    assert resp.tag == 1
    assert not resp.empty
    assert not resp.error

    #data2 dequeue commit
    await tb.dequeue_commit_source.send(DequeueCommitTransaction(op_tag=resp.op_tag))

    await Timer(100, 'ns')

    #data2 read consumer pointer
    new_cons_ptr = (await tb.axil_master.read_dword(0*32+MQNIC_QUEUE_PTR_REG)) >> 16
    tb.log.info("Consumer pointer: %d", new_cons_ptr)

    assert new_cons_ptr - cons_ptr == wqe

    tb.log.info("Test multiple enqueue pifocomb and dequeue")

    NUM_QUEUES = 16 # need change if queue big then 16
    OP_TABLE_SIZE = 32  
    MAX_INFLIGHT = 16    # 每个队列最多缓冲 16 个未完成项
    PTW = 13
    WQE_WITHE = 3
    # 初始化队列
    for k in range(NUM_QUEUES):
        await tb.axil_master.write_dword(k*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_ENABLE | 0)
        await tb.axil_master.write_qword(k*32+MQNIC_QUEUE_BASE_ADDR_VF_REG, 0x5555555555000000 + 0x10000*k)
        await tb.axil_master.write_dword(k*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_VF_ID | 0)
        await tb.axil_master.write_dword(k*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_SIZE | 4)
        await tb.axil_master.write_dword(k*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_CQN | k)
        await tb.axil_master.write_dword(k*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_PROD_PTR | 0xfff0)
        await tb.axil_master.write_dword(k*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_CONS_PTR | 0xfff0)
        await tb.axil_master.write_dword(k*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_ENABLE | 1)

    # 状态追踪变量
    queue_prod_ptr = [0xfff0]*NUM_QUEUES
    queue_cons_ptr = [0xfff0]*NUM_QUEUES
    queue_depth = [0]*NUM_QUEUES
    queue_uncommit_depth = [0]*NUM_QUEUES
    queue_inflight = [0]*NUM_QUEUES
    op = 0

    # commit 列表和 metadata
    commit_list = []  # [(q, tag, rank, wqe)]
    random.seed(123456)
    current_tag = 1

    for i in range(200):
        # ------------------ 入队阶段 ------------------
        for _ in range(random.randrange(8)):
            q = random.randrange(NUM_QUEUES)

            if queue_inflight[q] >= MAX_INFLIGHT:
                continue

            if queue_depth[q] < 16:
                tb.log.info("Enqueue into queue %d", q)

                # 校验指针
                prod_ptr = (await tb.axil_master.read_dword(q*32+MQNIC_QUEUE_PTR_REG)) & MQNIC_QUEUE_PTR_MASK
                assert prod_ptr == queue_prod_ptr[q]

                # 生成元数据
                rank = cocotb.random.getrandbits(PTW) & ((1 << PTW) - 1)
                #wqe = (i+1) & ((1 << WQE_WITHE) - 1)
                wqe = 4
                await tb.axil_master.write_dword(q*32+MQNIC_QUEUE_RANK_WQE, rank << 3 | wqe )

                # 入队
                prod_ptr = (prod_ptr + wqe) & MQNIC_QUEUE_PTR_MASK
                queue_prod_ptr[q] = prod_ptr
                queue_depth[q] += 1
                queue_uncommit_depth[q] += 1
                queue_inflight[q] += 1

                await tb.axil_master.write_dword(q*32+MQNIC_QUEUE_CTRL_STATUS_REG, MQNIC_QUEUE_CMD_SET_PROD_PTR | prod_ptr)

                # 接收 doorbell
                db1 = await tb.doorbell_sink.recv()
                tb.log.info("Doorbell: %s", db1)
                assert db1.queue == q
                assert db1.rank == rank
                assert db1.wqe == wqe

                # 发送 PIFO 完成信号
                await tb.pifo_comp_source.send(PifoCompTransaction(queue=db1.queue,tag=db1.tag))


        # ------------------ 出队阶段 ------------------
        for _ in range(random.randrange(8)):
            op = op + 1
            if op >= MAX_INFLIGHT:
                continue

            q = random.randrange(NUM_QUEUES)

            if len(commit_list) < OP_TABLE_SIZE and queue_uncommit_depth[q] > 0:
                tb.log.info("try dequeue from queue %d", q)

                await tb.dequeue_req_source.send(DequeueReqTransaction(queue=q, wqe=wqe,tag=current_tag))
                resp = await tb.dequeue_resp_sink.recv()

                tb.log.info("Dequeue response: %s", resp)

                # 检查响应内容
                assert resp.queue == q
                assert resp.ptr == queue_cons_ptr[q]
                assert resp.phase == ~(resp.ptr >> 4) & 1
                assert (resp.addr >> 16) & 0xf == q
                assert (resp.addr >> 4) & 0xf == queue_cons_ptr[q] & 0xf
                assert not resp.error
                assert resp.tag == current_tag
                assert resp.wqe == wqe

                if not resp.empty:
                    # 模拟同样的 metadata
                    rank = random.randint(0, 15)
                    wqe = 4
                    commit_list.append((q, resp.op_tag, rank, wqe))
                    queue_cons_ptr[q] = (queue_cons_ptr[q] + wqe) & MQNIC_QUEUE_PTR_MASK
                    queue_uncommit_depth[q] -= 1
                else:
                    tb.log.info("Queue was empty")
                    assert resp.empty

                current_tag = (current_tag + 1) % 256

        # ------------------ 提交阶段 ------------------
        for _ in range(random.randrange(8)):
            if commit_list:
                op = op - 1
                q, op_tag, rank, wqe = commit_list.pop(0)

                tb.log.info("Commit dequeue from queue %d", q)
                await tb.dequeue_commit_source.send(DequeueCommitTransaction(op_tag=op_tag))
                queue_depth[q] -= 1
                queue_inflight[q] -= 1


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


def test_queue_manager(request):
    dut = "queue_manager"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.v"),
        os.path.join(rtl_dir, "axis_arb_mux.v"),
        os.path.join(rtl_dir, "arbiter.v"),         
        os.path.join(rtl_dir, "priority_encoder.v"),      
        os.path.join(memory_rtl_dir, "RAM_Simple_Dual_Port.v"),
        os.path.join(memory_rtl_dir, "RAM_Simple_Dual_Port_byte.v"),
        os.path.join(memory_rtl_dir, "axis_fifo.v"),
    ]

    parameters = {}

    parameters['ADDR_WIDTH'] = 64
    parameters['REQ_TAG_WIDTH'] = 8
    parameters['OP_TABLE_SIZE'] = 16
    parameters['OP_TAG_WIDTH'] = 8
    parameters['QUEUE_INDEX_WIDTH'] = 8
    parameters['CPL_INDEX_WIDTH'] = 8
    parameters['QUEUE_PTR_WIDTH'] = 16
    parameters['LOG_QUEUE_SIZE_WIDTH'] = 4
    parameters['DESC_SIZE'] = 16
    parameters['LOG_BLOCK_SIZE_WIDTH'] = 2
    parameters['PIPELINE'] = 2
    parameters['AXIL_DATA_WIDTH'] = 32
    parameters['AXIL_ADDR_WIDTH'] = parameters['QUEUE_INDEX_WIDTH'] + 5
    parameters['AXIL_STRB_WIDTH'] = parameters['AXIL_DATA_WIDTH'] // 8

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
