import logging
import os
import random

import cocotb_test.simulator

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.regression import TestFactory

from cocotb_bus.bus import Bus

from cocotbext.axi import AxiLiteBus, AxiLiteMaster
from cocotbext.axi.stream import define_stream
import heapq
PTW = 16 
MTW = 24 #32
CTW = 10

Top_PushReqBus, Top_PushReqTransaction, Top_PushReqSource, Top_PushReqSink, Top_PushReqMonitor = define_stream("Top_PushReq",
    signals         =["Data", "valid"],
    optional_signals=["ready"]
)
Top_PopReqBus, Top_PopReqTransaction, Top_PopReqSource, Top_PopReqSink, Top_PopReqMonitor = define_stream("Top_PopReq",
    signals             =["valid"],
    optional_signals    =["ready"]
)

Top_PopRespBus, Top_PopRespTransaction, Top_PopRespSource, Top_PopRespSink, Top_PopRespMonitor = define_stream("Top_PopResp",
    signals=["data", "valid"],
    optional_signals=["ready"]
)

Parents_PushReqBus, Parents_PushReqTransaction, Parents_PushReqSource, Parents_PushReqSink, Parents_PushReqMonitor = define_stream("Parents_PushReq",
    signals             =["valid","Data"],
    optional_signals    =["ready"]
)

Parents_PopReqBus, Parents_PopReqTransaction, Parents_PopReqSource, Parents_PopReqSink, Parents_PopReqMonitor = define_stream("Parents_PopReq",
    signals             =["valid"],
    optional_signals    =["ready"]
)



class RankMetaStructure:
    def __init__(self):
        self.data = []  # 小顶堆存储 (rank, meta)
    def insert(self, rank, meta):
        """插入数据"""
        heapq.heappush(self.data, (rank, meta))
    def check_and_remove_min(self, input_rank,meta):
        """校验输入数据并删除最小值（如果是的话）"""
        if not self.data:
            raise ValueError("Structure is empty!")    
        min_rank, min_meta = self.data[0]  # 查看最小值（不弹出）        
        if input_rank == min_rank:
            return heapq.heappop(self.data)[1]  # 弹出并返回 meta
        else:
            raise ValueError(f"Input rank {input_rank} is not the minimum (current min: {min_rank})")
        
class TB(object):
    def __init__(self, dut):
        self.dut = dut
        
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)        
        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
        self.Top_push_req_source        = Top_PushReqSource(Top_PushReqBus.from_prefix(dut, "Top_Push"),dut.clk, dut.rst)
        self.Top_pop_req_source         = Top_PopReqSource (Top_PopReqBus.from_prefix(dut, "Top_Pop_req"),dut.clk, dut.rst)
        self.Top_pop_resp_sink          = Top_PopRespSink(Top_PopRespBus.from_prefix(dut, "Top_Pop_resp"),dut.clk, dut.rst)
        self.Parents_pushreq_sink       = Parents_PushReqSink(Parents_PushReqBus.from_prefix(dut,"Parents_Push"),dut.clk, dut.rst)

        self.Parents_pop_req_sink       = Parents_PopReqSource(Parents_PopReqBus.from_prefix(dut, "Parents_Pop_req"),dut.clk, dut.rst)
        # self.Parents_pop_resp_source    = Parents_PopRespSource(Parents_PopRespBus.from_prefix(dut,"Parents_Pop_resp"),dut.clk, dut.rst)
        self.Parents_PopRespBus = Bus(dut, "Parents_Pop_resp", ["data"])

        self.test_struct                = RankMetaStructure()
    async def reset(self):
        self.dut.Top_My_addr.setimmediatevalue(0)
        #self.dut.Top_Pop_req_valid.setimmediatevalue(0) 
        meta_data = 6 & ((1 << MTW) - 1) #cocotb.random.getrandbits(MTW) & ((1 << MTW) - 1)
        rank_data = cocotb.random.getrandbits(PTW) & ((1 << PTW) - 1)
        self.dut.rst.setimmediatevalue(0)
        self.dut.Parents_Pop_resp_data.setimmediatevalue(((rank_data << MTW) | meta_data))
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)      
    async def push(self,DATA_IN): 
        await self.Top_push_req_source.send(Top_PushReqTransaction(Data=DATA_IN))
    async def pop(self): 
        await self.Top_pop_req_source.send(Top_PopReqTransaction())
        await RisingEdge(self.dut.clk)
        resp = await self.Top_pop_resp_sink.recv() 
        return resp 
    async def push_all_pop_all(self,num):
        for i in range(1):
            meta_data = (i+1) & ((1 << MTW) - 1) #cocotb.random.getrandbits(MTW) & ((1 << MTW) - 1)
            rank_data = cocotb.random.getrandbits(PTW) & ((1 << PTW) - 1)            
            self.test_struct.insert(rank_data,meta_data)
            await self.push(((rank_data << MTW) | meta_data))
            print(f"i = {i},meta_data = 0x{meta_data:x}, rank_data = 0x{rank_data:x}")
            await RisingEdge(self.dut.clk)
        for i in range(1):  
            resp = await self.pop()
            rev_rank        = (resp.data.integer >> MTW) & ((1 << PTW) - 1)
            rev_meta_Data   = resp.data.integer & ((1 << MTW) - 1)
            self.test_struct.check_and_remove_min(rev_rank,rev_meta_Data)
            print(f"i = {i},rev_meta_Data = 0x{rev_meta_Data:x}, rev_rank = 0x{rev_rank:x}")
            await RisingEdge(self.dut.clk)            
        for i in range(1):
            meta_data = (i+1) & ((1 << MTW) - 1) #cocotb.random.getrandbits(MTW) & ((1 << MTW) - 1)
            rank_data = cocotb.random.getrandbits(PTW) & ((1 << PTW) - 1)            
            self.test_struct.insert(rank_data,meta_data)
            await self.push(((rank_data << MTW) | meta_data))
            print(f"i = {i},meta_data = 0x{meta_data:x}, rank_data = 0x{rank_data:x}")
            await RisingEdge(self.dut.clk)
        for i in range(1):  
            resp            = await self.pop()
            rev_rank        = (resp.data.integer >> MTW) & ((1 << PTW) - 1)
            rev_meta_Data   = resp.data.integer & ((1 << MTW) - 1)
            self.test_struct.check_and_remove_min(rev_rank,rev_meta_Data)
            print(f"i = {i},rev_meta_Data = 0x{rev_meta_Data:x}, rev_rank = 0x{rev_rank:x}")
            await RisingEdge(self.dut.clk)  
async def run_test(dut):
    tb = TB(dut)
    await tb.reset()
    tb.log.info("Test simple push and pop ")
    await tb.push_all_pop_all(4)
    tb.log.info("Test over ")
    #for i in range(4):
    #    meta_data = (i+1) & ((1 << MTW) - 1) #cocotb.random.getrandbits(MTW) & ((1 << MTW) - 1)
    #    rank_data = cocotb.random.getrandbits(PTW) & ((1 << PTW) - 1)
    #    tb.test_struct.insert(rank_data,meta_data)
    #    await tb.Top_push_req_source.send(Top_PushReqTransaction(Data=((rank_data << MTW) | meta_data)))
    #    print(f"i = {i},meta_data = 0x{meta_data:x}, rank_data = 0x{rank_data:x}")
    #    await RisingEdge(tb.dut.clk)
    #    #await tb.Top_push_req_source.send(Top_PushReqTransaction(Data=((rank_data << MTW) | meta_data)))
    #    #await RisingEdge(tb.dut.clk)
    #    ##await tb.Top_push_req_source.send(Top_PushReqTransaction(Data=((rank_data << MTW) | meta_data)))
    #    ##await tb.Top_push_req_source.send(Top_PushReqTransaction(Data=((rank_data << MTW) | meta_data)))
    #    #await RisingEdge(tb.dut.clk)
    #    #await RisingEdge(tb.dut.clk)
    #    #await RisingEdge(tb.dut.clk)
    #    #await RisingEdge(tb.dut.clk)
    #    #await RisingEdge(tb.dut.clk)
    #    #await RisingEdge(tb.dut.clk)
    #    #await RisingEdge(tb.dut.clk)
    #    #await RisingEdge(tb.dut.clk)
    #    #await RisingEdge(tb.dut.clk)
    #    #tb.log.info("Test simple pop")
    ##meta_data = (5) & ((1 << MTW) - 1) #cocotb.random.getrandbits(MTW) & ((1 << MTW) - 1)
    ##rank_data = cocotb.random.getrandbits(PTW) & ((1 << PTW) - 1)
    ##await tb.Top_push_req_source.send(Top_PushReqTransaction(Data=((rank_data << MTW) | meta_data)))
    #for i in range(4):
    #    await tb.Top_pop_req_source.send(Top_PopReqTransaction())
    #    await RisingEdge(tb.dut.clk)
    #    resp = await tb.Top_pop_resp_sink.recv()
    #    rev_rank        = (resp.data.integer >> MTW) & ((1 << PTW) - 1)
    #    rev_meta_Data   = resp.data.integer & ((1 << MTW) - 1)
    #    tb.test_struct.check_and_remove_min(rev_rank,rev_meta_Data)
    #    print(f"i = {i},rev_meta_Data = 0x{rev_meta_Data:x}, rev_rank = 0x{rev_rank:x}")
    #    await RisingEdge(tb.dut.clk)
    #await tb.Top_pop_req_source.send(Top_PopReqTransaction())
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
rtl_dir                     = os.path.abspath(os.path.join(tests_dir,'..','rtl' ))
pifo_sram_dir               = os.path.abspath(os.path.join(rtl_dir  ,'Pifo_Sram'))
lib_dir                     = os.path.abspath(os.path.join(tests_dir,'..','lib' ))
boolean_logic_rtl_dir       = os.path.abspath(os.path.join(lib_dir  ,'Boolean_Logic'))
memory_rtl_dir              = os.path.abspath(os.path.join(lib_dir  ,'memory'))
synchronous_Logic_rtl_dir   = os.path.abspath(os.path.join(lib_dir  ,'Synchronous_Logic'))


def test_PIFO_SRAM_Level_1(request):
    dut         = "PIFO_SRAM_Level_1"
    module      = os.path.splitext(os.path.basename(__file__))[0]
    toplevel    = dut    
    verilog_sources = [
        os.path.join(pifo_sram_dir, f"{dut}.sv"),
        os.path.join(boolean_logic_rtl_dir, "Multiplexer_Binary_Behavioural.v"),      
        os.path.join(memory_rtl_dir, "RAM_Simple_Dual_Port.v"),
        os.path.join(synchronous_Logic_rtl_dir, "Register_Pipeline.v"),           
        os.path.join(synchronous_Logic_rtl_dir, "Register.v")
    ]
    parameters = {}
    parameters["PTW"] = 16
    parameters["MTW"] = 24#32
    parameters["CTW"] = 10
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