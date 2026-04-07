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
import heapq
PTW = 16 
MTW = 24 #32
CTW = 15
LEVEL_TOTAL = 6

Top_PushReqBus, Top_PushReqTransaction, Top_PushReqSource, Top_PushReqSink, Top_PushReqMonitor = define_stream("Top_PushReq",
    signals         =["Data", "valid"],
    optional_signals=["ready"]
)

Top_PopReqBus, Top_PopReqTransaction, Top_PopReqSource, Top_PopReqSink, Top_PopReqMonitor = define_stream("Top_PopReq",
    signals             =["valid"],
    optional_signals    =["ready"]
)
Top_PopRespBus, Top_PopRespTransaction, Top_PopRespSource, Top_PopRespSink, Top_PopRespMonitor = define_stream("Top_PopResp",
    signals=["Data", "valid"],
    optional_signals=["ready"]
)



class RankMetaStructure:
    def __init__(self):
        self.Data = []  # 小顶堆存储 (rank, meta)
    def insert(self, rank, meta):
        """插入数据"""
        heapq.heappush(self.Data, (rank, meta))

    def check_and_remove_min(self, input_rank,meta):
        """校验输入数据并删除最小值（如果是的话）"""
        if not self.Data:
            raise ValueError("Structure is empty!")    
        min_rank, min_meta = self.Data[0]  # 查看最小值（不弹出）        
        if input_rank == min_rank:
            return heapq.heappop(self.Data)[1]  # 弹出并返回 meta
        else:
            raise ValueError(f"pop rank 0x{input_rank:X} not minimum rank: 0x{min_rank:X}")
    

class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.test_struct_lock = cocotb.triggers.Lock()#dyc add
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)        
        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
        self.Top_push_req_source        = Top_PushReqSource(Top_PushReqBus.from_prefix(dut, "Top_Push"),dut.clk, dut.rst)
        self.Top_pop_req_source         = Top_PopReqSource (Top_PopReqBus.from_prefix(dut, "Top_Pop_req"),dut.clk, dut.rst)
        self.Top_pop_resp_sink          = Top_PopRespSink(Top_PopRespBus.from_prefix(dut, "Top_Pop_resp"),dut.clk, dut.rst)
        self.test_struct                = RankMetaStructure()

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

    async def pow_add(self,num):
        sum = 0 
        for i in range(num) :
            sum = 4 ** (i+1) + sum 
        self.log.info(f"queue sum = {sum}")
        return sum 

    async def pop(self): 
        async with self.test_struct_lock:
            await self.Top_pop_req_source.send(Top_PopReqTransaction())
            await RisingEdge(self.dut.clk)
            return await self.Top_pop_resp_sink.recv()
    
    async def push(self,rank_Data,meta_Data): 
        await self.Top_push_req_source.send(Top_PushReqTransaction(Data=(rank_Data << MTW) | meta_Data))
        async with self.test_struct_lock:
            self.test_struct.insert(rank_Data, meta_Data)
          

    async def push_all_pop_all(self,num):
        for i in range(num):
            meta_Data = (i+1) & ((1 << MTW) - 1) 
            rank_Data = cocotb.random.getrandbits(PTW) & ((1 << PTW) - 1)            
            await self.push(rank_Data,meta_Data)
            self.log.debug(f"[PUSH] i = {i},meta = 0x{meta_Data:x}, rank = 0x{rank_Data:x}")


        for _ in range(5*num):  # 根据设计调整等待周期
            await RisingEdge(self.dut.clk)

        for i in range(num):  
            resp = await self.pop()
            rev_rank  = (resp.Data.integer >> MTW) & ((1 << PTW) - 1)
            rev_meta  = resp.Data.integer & ((1 << MTW) - 1)
            self.test_struct.check_and_remove_min(rev_rank,rev_meta)
            self.log.debug(f"[POP] i = {i},rev_meta= 0x{rev_meta:x}, rev_rank = 0x{rev_rank:x}")



    async def producer(self, num):
        for i in range(num):
            meta_Data = (i+1) & ((1 << MTW) - 1)
            rank_Data = cocotb.random.getrandbits(PTW) & ((1 << PTW) - 1)
            await self.push(rank_Data,meta_Data)
            self.log.debug(f"[PUSH] i = {i}, meta = 0x{meta_Data:x}, rank = 0x{rank_Data:x}")
            await RisingEdge(self.dut.clk) 

    async def consumer(self, num):
        for i in range(num):
            resp = await self.pop()
            rev_rank = (resp.Data.integer >> MTW) & ((1 << PTW) - 1)
            rev_meta = resp.Data.integer & ((1 << MTW) - 1)
            self.log.debug(f"[POP] i = {i},rev_meta = 0x{rev_meta:x}, rev_rank = 0x{rev_rank:x}")
            self.test_struct.check_and_remove_min(rev_rank,rev_meta)
            await RisingEdge(self.dut.clk)


    async def push_and_pop_concurrent(self, num):
        await self.producer(1)
        for i in range(num - 1):
            await self.consumer(1)
            await self.producer(1)
        await self.consumer(1)

async def run_test(dut):
    tb = TB(dut)
    await tb.reset()
    num = await tb.pow_add(LEVEL_TOTAL)
    tb.log.info("Test simple push and pop ")
    await tb.push_all_pop_all(num)

    tb.log.info("Test concurrent push and pop ")
    await tb.push_and_pop_concurrent(num)  


    tb.log.info("Test over ")
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
if cocotb.SIM_NAME:
    factory = TestFactory(run_test)
    factory.generate_tests()

tests_dir                   = os.path.dirname(__file__)
rtl_dir                     = os.path.abspath(os.path.join(tests_dir,'..','..','rtl' ))
pifo_sram_dir               = os.path.abspath(os.path.join(rtl_dir  ,'Pifo_Sram'))
lib_dir                     = os.path.abspath(os.path.join(tests_dir,'..','lib' ))
boolean_logic_rtl_dir       = os.path.abspath(os.path.join(lib_dir  ,'Boolean_Logic'))
memory_rtl_dir              = os.path.abspath(os.path.join(lib_dir  ,'memory'))
synchronous_Logic_rtl_dir   = os.path.abspath(os.path.join(lib_dir  ,'Synchronous_Logic'))


def test_PIFO_SRAM_Top(request):
    dut         = "PIFO_SRAM_Top"#PIFO_SRAM_Top
    module      = os.path.splitext(os.path.basename(__file__))[0]
    toplevel    = dut    
    verilog_sources = [
        os.path.join(pifo_sram_dir, f"{dut}.sv"),
        os.path.join(pifo_sram_dir, "PIFO_SRAM_Level_1.sv"),
        os.path.join(pifo_sram_dir, "PIFO_SRAM_Level_other.sv"),        
        os.path.join(boolean_logic_rtl_dir, "Multiplexer_Binary_Behavioural.v"),      
        os.path.join(memory_rtl_dir, "RAM_Simple_Dual_Port.v"),
        os.path.join(synchronous_Logic_rtl_dir, "Register_Pipeline.v"),           
        os.path.join(synchronous_Logic_rtl_dir, "Register.v")
    ]
    parameters = {}
    parameters["PTW"] = PTW
    parameters["MTW"] = MTW
    parameters["CTW"] = CTW
    parameters["LEVEL_TOTAL"] = LEVEL_TOTAL
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