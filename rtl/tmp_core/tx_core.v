//把DMA_if、mqnic_port和cpl_write暴露为接口
module tx_core #
(
     // PIFO SRAM Parameters
    parameter RANK_WIDTH = 16,
    parameter WQE_WIDTH = 16,

    parameter AXIS_PCIE_DATA_WIDTH = 512,

    parameter TLP_DATA_WIDTH = AXIS_PCIE_DATA_WIDTH,
    parameter TLP_SEG_COUNT = 1,

    parameter RAM_SEG_COUNT = TLP_SEG_COUNT*2,
    parameter RAM_SEG_DATA_WIDTH = TLP_DATA_WIDTH*2/RAM_SEG_COUNT,

    // Structural configuration
    parameter PORTS = 1,
    parameter SCHEDULERS = 1,

    // Clock configuration
    parameter CLK_PERIOD_NS_NUM = 4,
    parameter CLK_PERIOD_NS_DENOM = 1,

    // PTP configuration
    parameter PTP_CLK_PERIOD_NS_NUM = 4,
    parameter PTP_CLK_PERIOD_NS_DENOM = 1,
    parameter PTP_TS_WIDTH = 96,
    parameter PTP_CLOCK_CDC_PIPELINE = 0,
    parameter PTP_PEROUT_ENABLE = 0,
    parameter PTP_PEROUT_COUNT = 1,

    // Queue manager configuration (interface)
    parameter EVENT_QUEUE_OP_TABLE_SIZE = 32,
    parameter TX_QUEUE_OP_TABLE_SIZE = 32,
    parameter RX_QUEUE_OP_TABLE_SIZE = 32,
    parameter CQ_OP_TABLE_SIZE = 32,
    parameter EQN_WIDTH = 5,
    parameter TX_QUEUE_INDEX_WIDTH = 8,
    parameter RX_QUEUE_INDEX_WIDTH = 8,
    parameter CQN_WIDTH = (TX_QUEUE_INDEX_WIDTH > RX_QUEUE_INDEX_WIDTH ? TX_QUEUE_INDEX_WIDTH : RX_QUEUE_INDEX_WIDTH) + 1,
    parameter EQ_PIPELINE = 3,
    parameter TX_QUEUE_PIPELINE = 3+(TX_QUEUE_INDEX_WIDTH > 12 ? TX_QUEUE_INDEX_WIDTH-12 : 0),
    parameter RX_QUEUE_PIPELINE = 3+(RX_QUEUE_INDEX_WIDTH > 12 ? RX_QUEUE_INDEX_WIDTH-12 : 0),
    parameter CQ_PIPELINE = 3+(CQN_WIDTH > 12 ? CQN_WIDTH-12 : 0),
    parameter QUEUE_PTR_WIDTH = 16,
    parameter LOG_QUEUE_SIZE_WIDTH = 4,
    parameter LOG_BLOCK_SIZE_WIDTH = 2,

    // Descriptor management
    parameter TX_MAX_DESC_REQ = 16,
    parameter TX_DESC_FIFO_SIZE = TX_MAX_DESC_REQ*8,
    parameter RX_MAX_DESC_REQ = 16,
    parameter RX_DESC_FIFO_SIZE = RX_MAX_DESC_REQ*8,

    // TX and RX engine configuration
    parameter TX_DESC_TABLE_SIZE = 32,
    parameter RX_DESC_TABLE_SIZE = 32,
    parameter RX_INDIR_TBL_ADDR_WIDTH = RX_QUEUE_INDEX_WIDTH > 8 ? 8 : RX_QUEUE_INDEX_WIDTH,

    // Scheduler configuration
    parameter TX_SCHEDULER_OP_TABLE_SIZE = TX_DESC_TABLE_SIZE,
    parameter TX_SCHEDULER_PIPELINE = TX_QUEUE_PIPELINE,
    parameter TDMA_INDEX_WIDTH = 6,

    // Interface configuration
    parameter PTP_TS_ENABLE = 1,
    parameter TX_CPL_ENABLE = PTP_TS_ENABLE,
    parameter TX_CPL_FIFO_DEPTH = 32,
    parameter TX_TAG_WIDTH = $clog2(TX_DESC_TABLE_SIZE)+1,
    parameter TX_CHECKSUM_ENABLE = 1,
    parameter RX_HASH_ENABLE = 1,
    parameter RX_CHECKSUM_ENABLE = 1,
    parameter PFC_ENABLE = 0,
    parameter LFC_ENABLE = PFC_ENABLE,
    parameter MAC_CTRL_ENABLE = 0,
    parameter TX_FIFO_DEPTH = 32768,
    parameter RX_FIFO_DEPTH = 131072,//32768
    parameter MAX_TX_SIZE = 9214,
    parameter MAX_RX_SIZE = 9214,
    parameter TX_RAM_SIZE = 131072,//32768
    parameter RX_RAM_SIZE = 131072,

    // Application block configuration
    parameter APP_AXIS_DIRECT_ENABLE = 1,
    parameter APP_AXIS_SYNC_ENABLE = 1,
    parameter APP_AXIS_IF_ENABLE = 1,

    // DMA interface configuration
    parameter DMA_ADDR_WIDTH = 64,
    parameter DMA_IMM_ENABLE = 0,
    parameter DMA_IMM_WIDTH = 32,
    parameter DMA_LEN_WIDTH = 16,
    parameter DMA_TAG_WIDTH = 16,
    parameter RAM_SEL_WIDTH = 1,
    parameter RAM_ADDR_WIDTH = $clog2(TX_RAM_SIZE > RX_RAM_SIZE ? TX_RAM_SIZE : RX_RAM_SIZE),
    // parameter RAM_SEG_COUNT = 2,
    // parameter RAM_SEG_DATA_WIDTH = 256*2/RAM_SEG_COUNT,
    parameter RAM_SEG_BE_WIDTH = RAM_SEG_DATA_WIDTH/8,
    parameter RAM_SEG_ADDR_WIDTH = RAM_ADDR_WIDTH-$clog2(RAM_SEG_COUNT*RAM_SEG_BE_WIDTH),
    parameter RAM_PIPELINE = 2,

    // Interrupt configuration
    parameter IRQ_INDEX_WIDTH = 8,

    // AXI lite interface configuration
    parameter AXIL_DATA_WIDTH = 32,
    parameter AXIL_ADDR_WIDTH = 16,
    parameter AXIL_STRB_WIDTH = (AXIL_DATA_WIDTH/8),

    // Streaming interface configuration (direct, async)
    parameter AXIS_DATA_WIDTH = 512,
    parameter AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH/8,
    parameter AXIS_TX_USER_WIDTH = TX_TAG_WIDTH + 1,
    parameter AXIS_RX_USER_WIDTH = (PTP_TS_ENABLE ? PTP_TS_WIDTH : 0) + 1,
    parameter AXIS_RX_USE_READY = 0,
    parameter AXIS_TX_PIPELINE = 0,
    parameter AXIS_TX_FIFO_PIPELINE = 2,
    parameter AXIS_TX_TS_PIPELINE = 0,
    parameter AXIS_RX_PIPELINE = 0,
    parameter AXIS_RX_FIFO_PIPELINE = 2,

    // Streaming interface configuration (direct, sync)
    parameter AXIS_SYNC_DATA_WIDTH = AXIS_DATA_WIDTH,
    parameter AXIS_SYNC_KEEP_WIDTH = AXIS_SYNC_DATA_WIDTH/8,
    parameter AXIS_SYNC_TX_USER_WIDTH = AXIS_TX_USER_WIDTH,
    parameter AXIS_SYNC_RX_USER_WIDTH = AXIS_RX_USER_WIDTH,

    // Streaming interface configuration (interface)
    parameter AXIS_IF_DATA_WIDTH = AXIS_SYNC_DATA_WIDTH*2**$clog2(PORTS),
    parameter AXIS_IF_KEEP_WIDTH = AXIS_IF_DATA_WIDTH/8,
    parameter AXIS_IF_TX_ID_WIDTH = TX_QUEUE_INDEX_WIDTH,
    parameter AXIS_IF_RX_ID_WIDTH = PORTS > 1 ? $clog2(PORTS) : 1,
    parameter AXIS_IF_TX_DEST_WIDTH = $clog2(PORTS)+4,
    parameter AXIS_IF_RX_DEST_WIDTH = RX_QUEUE_INDEX_WIDTH+1,
    parameter AXIS_IF_TX_USER_WIDTH = AXIS_SYNC_TX_USER_WIDTH,
    parameter AXIS_IF_RX_USER_WIDTH = AXIS_SYNC_RX_USER_WIDTH

)
(
    input  wire                     clk,
    input  wire                     rst,

    // AXI-Lite slave interface from axi_lite_master(仿真层) 
    input  wire [AXIL_ADDR_WIDTH-1:0]                   s_axil_awaddr,
    input  wire [2:0]                                   s_axil_awprot,
    input  wire                                         s_axil_awvalid,
    output wire                                         s_axil_awready,
    input  wire [AXIL_DATA_WIDTH-1:0]                   s_axil_wdata,
    input  wire [AXIL_STRB_WIDTH-1:0]                   s_axil_wstrb,
    input  wire                                         s_axil_wvalid,
    output wire                                         s_axil_wready,
    output wire [1:0]                                   s_axil_bresp,
    output wire                                         s_axil_bvalid,
    input  wire                                         s_axil_bready,
    input  wire [AXIL_ADDR_WIDTH-1:0]                   s_axil_araddr,
    input  wire [2:0]                                   s_axil_arprot,
    input  wire                                         s_axil_arvalid,
    output wire                                         s_axil_arready,
    output wire [AXIL_DATA_WIDTH-1:0]                   s_axil_rdata,
    output wire [1:0]                                   s_axil_rresp,
    output wire                                         s_axil_rvalid,
    input  wire                                         s_axil_rready,

    // DMA read descriptor dataoutput to dma_rd(仿真层) 
    output wire [DMA_ADDR_WIDTH-1:0]                    data_dma_read_desc_dma_addr,
    output wire [RAM_ADDR_WIDTH-1:0]                    data_dma_read_desc_ram_addr,
    output wire [DMA_LEN_WIDTH-1:0]                     data_dma_read_desc_len,
    output wire [DMA_TAG_WIDTH-1:0]                     data_dma_read_desc_tag,
    output wire                                         data_dma_read_desc_valid,
    input  wire                                         data_dma_read_desc_ready,

    // DMA read descriptor status input from dma_rd(仿真层) 
    input  wire [DMA_TAG_WIDTH-1:0]                     data_dma_read_desc_status_tag,
    input  wire [3:0]                                   data_dma_read_desc_status_error,
    input  wire                                         data_dma_read_desc_status_valid,

    // DMA RAM interface to dma_wr(仿真层) 
    input  wire [RAM_SEG_COUNT*RAM_SEG_BE_WIDTH-1:0]    data_dma_ram_wr_cmd_be,
    input  wire [RAM_SEG_COUNT*RAM_SEG_ADDR_WIDTH-1:0]  data_dma_ram_wr_cmd_addr,
    input  wire [RAM_SEG_COUNT*RAM_SEG_DATA_WIDTH-1:0]  data_dma_ram_wr_cmd_data,
    input  wire [RAM_SEG_COUNT-1:0]                     data_dma_ram_wr_cmd_valid,
    output wire [RAM_SEG_COUNT-1:0]                     data_dma_ram_wr_cmd_ready,
    output wire [RAM_SEG_COUNT-1:0]                     data_dma_ram_wr_done,

    // DMA read descriptor control output to dma_rd(仿真层) 
    output wire [DMA_ADDR_WIDTH-1:0]                    ctrl_dma_read_desc_dma_addr,
    output wire [RAM_ADDR_WIDTH-1:0]                    ctrl_dma_read_desc_ram_addr,
    output wire [DMA_LEN_WIDTH-1:0]                     ctrl_dma_read_desc_len,
    output wire [DMA_TAG_WIDTH-1:0]                     ctrl_dma_read_desc_tag,
    output wire                                         ctrl_dma_read_desc_valid,
    input  wire                                         ctrl_dma_read_desc_ready,

    // DMA read descriptor status input from dma_rd(仿真层) 
    input  wire [DMA_TAG_WIDTH-1:0]                     ctrl_dma_read_desc_status_tag,
    input  wire [3:0]                                   ctrl_dma_read_desc_status_error,
    input  wire                                         ctrl_dma_read_desc_status_valid,

    // DMA write descriptor control output to dma_wr(仿真层) 
    input  wire [RAM_SEG_COUNT*RAM_SEG_BE_WIDTH-1:0]    ctrl_dma_ram_wr_cmd_be,
    input  wire [RAM_SEG_COUNT*RAM_SEG_ADDR_WIDTH-1:0]  ctrl_dma_ram_wr_cmd_addr,
    input  wire [RAM_SEG_COUNT*RAM_SEG_DATA_WIDTH-1:0]  ctrl_dma_ram_wr_cmd_data,
    input  wire [RAM_SEG_COUNT-1:0]                     ctrl_dma_ram_wr_cmd_valid,
    output wire [RAM_SEG_COUNT-1:0]                     ctrl_dma_ram_wr_cmd_ready,
    output wire [RAM_SEG_COUNT-1:0]                     ctrl_dma_ram_wr_done,

    // Transmit data output to mqnic_port(仿真层) 
    output wire [AXIS_SYNC_DATA_WIDTH-1:0]              m_axis_tx_tdata,
    output wire [AXIS_SYNC_KEEP_WIDTH-1:0]              m_axis_tx_tkeep,
    output wire                                         m_axis_tx_tvalid,
    input  wire                                         m_axis_tx_tready,
    output wire                                         m_axis_tx_tlast,
    output wire [AXIS_IF_TX_ID_WIDTH-1:0]               m_axis_tx_tid,
    output wire [AXIS_IF_TX_DEST_WIDTH-1:0]             m_axis_tx_tdest,
    output wire [AXIS_IF_TX_USER_WIDTH-1:0]             m_axis_tx_tuser,

    // Transmit completion input from mqnic_port(仿真层)
    input  wire [PTP_TS_WIDTH-1:0]                      s_axis_tx_cpl_ts,
    input  wire [TX_TAG_WIDTH-1:0]                      s_axis_tx_cpl_tag,
    input  wire                                         s_axis_tx_cpl_valid,
    output wire                                         s_axis_tx_cpl_ready,

    // Completion request output to cpl_write(仿真层)
    output wire [QUEUE_INDEX_WIDTH-1:0]                 m_axis_cpl_req_queue,
    output wire [CPL_REQ_TAG_WIDTH_INT-1:0]             m_axis_cpl_req_tag,
    output wire [CPL_SIZE-1:0]                          m_axis_cpl_req_data,
    output wire                                         m_axis_cpl_req_valid,
    input  wire                                         m_axis_cpl_req_ready,

    // Completion request status input from cpl_write(仿真层)
    input  wire [CPL_REQ_TAG_WIDTH_INT-1:0]             s_axis_cpl_req_status_tag,
    input  wire                                         s_axis_cpl_req_status_full,
    input  wire                                         s_axis_cpl_req_status_error,
    input  wire                                         s_axis_cpl_req_status_valid
);

parameter PTW = RANK_WIDTH;
parameter MTW = QUEUE_INDEX_WIDTH + WQE_WIDTH;
parameter CTW = 15;
parameter LEVEL_TOTAL = 8;
parameter SINGLE_DATA_WITHOUT_COUNTER = PTW + MTW;

parameter DESC_SIZE = 16;
parameter CPL_SIZE = 32;
parameter EVENT_SIZE = 32;

parameter AXIS_DESC_DATA_WIDTH = DESC_SIZE*8;
parameter AXIS_DESC_KEEP_WIDTH = AXIS_DESC_DATA_WIDTH/8;

parameter EVENT_SOURCE_WIDTH = 16;
parameter EVENT_TYPE_WIDTH = 16;

parameter MAX_DESC_TABLE_SIZE = TX_DESC_TABLE_SIZE > RX_DESC_TABLE_SIZE ? TX_DESC_TABLE_SIZE : RX_DESC_TABLE_SIZE;

parameter REQ_TAG_WIDTH_INT = $clog2(MAX_DESC_TABLE_SIZE);
parameter REQ_TAG_WIDTH = REQ_TAG_WIDTH_INT + $clog2(SCHEDULERS);

parameter DESC_REQ_TAG_WIDTH_INT = REQ_TAG_WIDTH;
parameter DESC_REQ_TAG_WIDTH = DESC_REQ_TAG_WIDTH_INT + $clog2(2);

parameter CPL_REQ_TAG_WIDTH_INT = $clog2(MAX_DESC_TABLE_SIZE);
parameter CPL_REQ_TAG_WIDTH = CPL_REQ_TAG_WIDTH_INT + $clog2(3);

parameter QUEUE_REQ_TAG_WIDTH = DESC_REQ_TAG_WIDTH;
parameter CPL_QUEUE_REQ_TAG_WIDTH = CPL_REQ_TAG_WIDTH;
parameter QUEUE_OP_TAG_WIDTH = 6;

parameter DMA_CLIENT_LEN_WIDTH = DMA_LEN_WIDTH;

parameter QUEUE_INDEX_WIDTH = TX_QUEUE_INDEX_WIDTH > RX_QUEUE_INDEX_WIDTH ? TX_QUEUE_INDEX_WIDTH : RX_QUEUE_INDEX_WIDTH;

parameter AXIL_CSR_ADDR_WIDTH = AXIL_ADDR_WIDTH-5-$clog2((SCHEDULERS+4+7)/8);
parameter AXIL_CTRL_ADDR_WIDTH = AXIL_ADDR_WIDTH-5-$clog2((SCHEDULERS+4+7)/8);
parameter AXIL_RX_INDIR_TBL_ADDR_WIDTH = AXIL_ADDR_WIDTH-5-$clog2((SCHEDULERS+4+7)/8);
parameter AXIL_EQM_ADDR_WIDTH = AXIL_ADDR_WIDTH-5-$clog2((SCHEDULERS+4+7)/8);
parameter AXIL_CQM_ADDR_WIDTH = AXIL_ADDR_WIDTH-3-$clog2((SCHEDULERS+4+7)/8);
parameter AXIL_TX_QM_ADDR_WIDTH = AXIL_ADDR_WIDTH-3-$clog2((SCHEDULERS+4+7)/8);
parameter AXIL_RX_QM_ADDR_WIDTH = AXIL_ADDR_WIDTH-3-$clog2((SCHEDULERS+4+7)/8);
parameter AXIL_SCHED_ADDR_WIDTH = AXIL_ADDR_WIDTH-3-$clog2((SCHEDULERS+4+7)/8);

parameter AXIL_CSR_BASE_ADDR = 0;
parameter AXIL_CTRL_BASE_ADDR = AXIL_CSR_BASE_ADDR + 2**AXIL_CSR_ADDR_WIDTH;
parameter AXIL_RX_INDIR_TBL_BASE_ADDR = AXIL_CTRL_BASE_ADDR + 2**AXIL_CTRL_ADDR_WIDTH;
parameter AXIL_EQM_BASE_ADDR = AXIL_RX_INDIR_TBL_BASE_ADDR + 2**AXIL_RX_INDIR_TBL_ADDR_WIDTH;
parameter AXIL_CQM_BASE_ADDR = AXIL_EQM_BASE_ADDR + 2**AXIL_EQM_ADDR_WIDTH;
parameter AXIL_TX_QM_BASE_ADDR = AXIL_CQM_BASE_ADDR + 2**AXIL_CQM_ADDR_WIDTH;
parameter AXIL_RX_QM_BASE_ADDR = AXIL_TX_QM_BASE_ADDR + 2**AXIL_TX_QM_ADDR_WIDTH;
parameter AXIL_SCHED_BASE_ADDR = AXIL_RX_QM_BASE_ADDR + 2**AXIL_RX_QM_ADDR_WIDTH;

localparam REG_ADDR_WIDTH = AXIL_CTRL_ADDR_WIDTH;
localparam REG_DATA_WIDTH = AXIL_DATA_WIDTH;
localparam REG_STRB_WIDTH = AXIL_STRB_WIDTH;

localparam RB_BASE_ADDR = AXIL_CTRL_BASE_ADDR;
localparam RBB = RB_BASE_ADDR & {AXIL_CTRL_ADDR_WIDTH{1'b1}};

localparam RX_RB_BASE_ADDR = RB_BASE_ADDR + 16'h100;

localparam PORT_RB_BASE_ADDR = RB_BASE_ADDR + 16'h1000;
localparam PORT_RB_STRIDE = 16'h1000;

localparam SCHED_RB_BASE_ADDR = (PORT_RB_BASE_ADDR + PORT_RB_STRIDE*PORTS);
localparam SCHED_RB_STRIDE = 16'h1000;

localparam TX_FIFO_DEPTH_WIDTH = $clog2(TX_FIFO_DEPTH)+1;
localparam RX_FIFO_DEPTH_WIDTH = $clog2(RX_FIFO_DEPTH)+1;


// TX request/response wires
wire                                tx_req_valid;
wire                                tx_req_ready;
wire [QUEUE_INDEX_WIDTH-1:0]        tx_resp_queue;
wire [WQE_WIDTH-1:0]                tx_resp_wqe;
wire                                tx_resp_valid;
wire                                tx_resp_ready;

// TX descriptor request wires
wire [0:0]                          tx_desc_req_sel = 1'b0;
wire [QUEUE_INDEX_WIDTH-1:0]        tx_desc_req_queue;
wire [WQE_WIDTH-1:0]                tx_desc_req_wqe;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   tx_desc_req_tag;
wire                                tx_desc_req_valid;
wire                                tx_desc_req_ready;

// TX descriptor request status wires
wire [QUEUE_INDEX_WIDTH-1:0]        tx_desc_req_status_queue;
wire [QUEUE_PTR_WIDTH-1:0]          tx_desc_req_status_ptr;
wire [CQN_WIDTH-1:0]                tx_desc_req_status_cpl;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   tx_desc_req_status_tag;
wire                                tx_desc_req_status_empty;
wire                                tx_desc_req_status_error;
wire                                tx_desc_req_status_valid;

// TX descriptor data wires
wire [AXIS_DESC_DATA_WIDTH-1:0]     tx_desc_tdata;
wire [AXIS_DESC_KEEP_WIDTH-1:0]     tx_desc_tkeep;
wire                                tx_desc_tvalid;
wire                                tx_desc_tready;
wire                                tx_desc_tlast;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   tx_desc_tid;
wire                                tx_desc_tuser;

// RX descriptor request wires
wire [0:0]                          rx_desc_req_sel = 1'b1;
wire [QUEUE_INDEX_WIDTH-1:0]        rx_desc_req_queue;
wire [WQE_WIDTH-1:0]                rx_desc_req_wqe;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   rx_desc_req_tag;
wire                                rx_desc_req_valid = 1'b0;
wire                                rx_desc_req_ready;

// RX descriptor request status wires
wire [QUEUE_INDEX_WIDTH-1:0]        rx_desc_req_status_queue;
wire [QUEUE_PTR_WIDTH-1:0]          rx_desc_req_status_ptr;
wire [CQN_WIDTH-1:0]                rx_desc_req_status_cpl;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   rx_desc_req_status_tag;
wire                                rx_desc_req_status_empty;
wire                                rx_desc_req_status_error;
wire                                rx_desc_req_status_valid = 1'b0;

// RX descriptor data wires
wire [AXIS_DESC_DATA_WIDTH-1:0]     rx_desc_tdata;
wire [AXIS_DESC_KEEP_WIDTH-1:0]     rx_desc_tkeep;
wire                                rx_desc_tvalid = 1'b0;
wire                                rx_desc_tready = 1'b0;
wire                                rx_desc_tlast;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   rx_desc_tid;
wire                                rx_desc_tuser;

// Descriptor operation mux wires
wire [0:0]                          desc_req_sel;//0:tx, 1:rx
wire [QUEUE_INDEX_WIDTH-1:0]        desc_req_queue;
wire [WQE_WIDTH-1:0]                desc_req_wqe;
wire [DESC_REQ_TAG_WIDTH-1:0]       desc_req_tag;
wire                                desc_req_valid;
wire                                desc_req_ready;

wire [QUEUE_INDEX_WIDTH-1:0]        desc_req_status_queue;
wire [QUEUE_PTR_WIDTH-1:0]          desc_req_status_ptr;
wire [CQN_WIDTH-1:0]                desc_req_status_cpl;
wire [DESC_REQ_TAG_WIDTH-1:0]       desc_req_status_tag;
wire                                desc_req_status_empty;
wire                                desc_req_status_error;
wire                                desc_req_status_valid;

wire [AXIS_DESC_DATA_WIDTH-1:0]     axis_desc_tdata;
wire [AXIS_DESC_KEEP_WIDTH-1:0]     axis_desc_tkeep;
wire                                axis_desc_tvalid;
wire                                axis_desc_tready;
wire                                axis_desc_tlast;
wire [DESC_REQ_TAG_WIDTH-1:0]       axis_desc_tid;
wire                                axis_desc_tuser;


wire [QUEUE_INDEX_WIDTH-1:0]        tx_desc_dequeue_req_queue;
wire [WQE_WIDTH-1:0]                tx_desc_dequeue_req_wqe;
wire [QUEUE_REQ_TAG_WIDTH-1:0]      tx_desc_dequeue_req_tag;
wire                                tx_desc_dequeue_req_valid;
wire                                tx_desc_dequeue_req_ready;

wire [QUEUE_INDEX_WIDTH-1:0]        tx_desc_dequeue_resp_queue;
wire [QUEUE_PTR_WIDTH-1:0]          tx_desc_dequeue_resp_ptr;
wire [DMA_ADDR_WIDTH-1:0]           tx_desc_dequeue_resp_addr;
wire [LOG_BLOCK_SIZE_WIDTH-1:0]     tx_desc_dequeue_resp_block_size;
wire [CQN_WIDTH-1:0]                tx_desc_dequeue_resp_cpl;
wire [QUEUE_REQ_TAG_WIDTH-1:0]      tx_desc_dequeue_resp_tag;
wire [QUEUE_OP_TAG_WIDTH-1:0]       tx_desc_dequeue_resp_op_tag;
wire                                tx_desc_dequeue_resp_empty;
wire                                tx_desc_dequeue_resp_error;
wire                                tx_desc_dequeue_resp_valid;
wire                                tx_desc_dequeue_resp_ready;
wire [WQE_WIDTH-1:0]                tx_desc_dequeue_resp_wqe; 

wire [QUEUE_OP_TAG_WIDTH-1:0]       tx_desc_dequeue_commit_op_tag;
wire                                tx_desc_dequeue_commit_valid;
wire                                tx_desc_dequeue_commit_ready;

wire [QUEUE_INDEX_WIDTH-1:0]        tx_doorbell_queue;
wire [RANK_WIDTH-1:0]               tx_doorbell_rank;
wire [WQE_WIDTH-1:0]                tx_doorbell_wqe;
wire                                tx_doorbell_valid;
wire                                tx_doorbell_ready;

wire [QUEUE_INDEX_WIDTH-1:0]        tx_pifo_comp_queue;
wire                                tx_pifo_comp_valid;


wire [QUEUE_INDEX_WIDTH-1:0]        rx_desc_dequeue_req_queue = 0;
wire [WQE_WIDTH-1:0]                rx_desc_dequeue_req_wqe = 0;
wire [QUEUE_REQ_TAG_WIDTH-1:0]      rx_desc_dequeue_req_tag = 0;
wire                                rx_desc_dequeue_req_valid = 1'b0;
wire                                rx_desc_dequeue_req_ready = 1'b0;

wire [QUEUE_INDEX_WIDTH-1:0]        rx_desc_dequeue_resp_queue = 0;
wire [QUEUE_PTR_WIDTH-1:0]          rx_desc_dequeue_resp_ptr = 0;
wire [DMA_ADDR_WIDTH-1:0]           rx_desc_dequeue_resp_addr = 0;
wire [LOG_BLOCK_SIZE_WIDTH-1:0]     rx_desc_dequeue_resp_block_size = 0;
wire [CQN_WIDTH-1:0]                rx_desc_dequeue_resp_cpl = 0;
wire [QUEUE_REQ_TAG_WIDTH-1:0]      rx_desc_dequeue_resp_tag = 0;
wire [QUEUE_OP_TAG_WIDTH-1:0]       rx_desc_dequeue_resp_op_tag = 0;
wire                                rx_desc_dequeue_resp_empty = 1'b0;
wire                                rx_desc_dequeue_resp_error = 1'b0;
wire                                rx_desc_dequeue_resp_valid = 1'b0;
wire                                rx_desc_dequeue_resp_ready = 1'b0;
wire [WQE_WIDTH-1:0]                rx_desc_dequeue_resp_wqe = 1'b0; 

wire [QUEUE_OP_TAG_WIDTH-1:0]       rx_desc_dequeue_commit_op_tag = 0;  
wire                                rx_desc_dequeue_commit_valid = 1'b0;
wire                                rx_desc_dequeue_commit_ready = 1'b0;

reg [DMA_CLIENT_LEN_WIDTH-1:0] tx_mtu_reg = MAX_TX_SIZE;

assign tx_pifo_comp_queue = tx_resp_queue;
assign tx_pifo_comp_valid = tx_resp_valid & tx_resp_ready;//fix
// TX queues
tx_queue_manager #(
    .ADDR_WIDTH(DMA_ADDR_WIDTH),
    .REQ_TAG_WIDTH(QUEUE_REQ_TAG_WIDTH),
    .OP_TABLE_SIZE(TX_QUEUE_OP_TABLE_SIZE),
    .OP_TAG_WIDTH(QUEUE_OP_TAG_WIDTH),
    .QUEUE_INDEX_WIDTH(TX_QUEUE_INDEX_WIDTH),
    .CPL_INDEX_WIDTH(CQN_WIDTH),
    .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
    .DESC_SIZE(DESC_SIZE),
    .LOG_BLOCK_SIZE_WIDTH(LOG_BLOCK_SIZE_WIDTH),
    .PIPELINE(TX_QUEUE_PIPELINE),
    .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
    .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH),
    .AXIL_STRB_WIDTH(AXIL_STRB_WIDTH),
    .RANK_WIDTH(RANK_WIDTH),
    .WQE_WIDTH(WQE_WIDTH)
) 
tx_qm_inst (
    .clk(clk),
    .rst(rst),

    //Dequeue request input
    .s_axis_dequeue_req_queue(tx_desc_dequeue_req_queue),
    .s_axis_dequeue_req_wqe(tx_desc_dequeue_req_wqe),
    .s_axis_dequeue_req_tag(tx_desc_dequeue_req_tag),
    .s_axis_dequeue_req_valid(tx_desc_dequeue_req_valid),
    .s_axis_dequeue_req_ready(tx_desc_dequeue_req_ready),

    //Dequeue response output
    .m_axis_dequeue_resp_queue(tx_desc_dequeue_resp_queue),
    .m_axis_dequeue_resp_ptr(tx_desc_dequeue_resp_ptr),
    .m_axis_dequeue_resp_addr(tx_desc_dequeue_resp_addr),
    .m_axis_dequeue_resp_block_size(tx_desc_dequeue_resp_block_size),
    .m_axis_dequeue_resp_cpl(tx_desc_dequeue_resp_cpl),
    .m_axis_dequeue_resp_tag(tx_desc_dequeue_resp_tag),
    .m_axis_dequeue_resp_op_tag(tx_desc_dequeue_resp_op_tag),
    .m_axis_dequeue_resp_empty(tx_desc_dequeue_resp_empty),
    .m_axis_dequeue_resp_error(tx_desc_dequeue_resp_error),
    .m_axis_dequeue_resp_valid(tx_desc_dequeue_resp_valid),
    .m_axis_dequeue_resp_ready(tx_desc_dequeue_resp_ready),
    .m_axis_dequeue_resp_wqe(tx_desc_dequeue_resp_wqe),
    
    //Dequeue commit input
    .s_axis_dequeue_commit_op_tag(tx_desc_dequeue_commit_op_tag),
    .s_axis_dequeue_commit_valid(tx_desc_dequeue_commit_valid),
    .s_axis_dequeue_commit_ready(tx_desc_dequeue_commit_ready),

    //Doorbell output
    .m_axis_doorbell_queue(tx_doorbell_queue),
    .m_axis_doorbell_rank(tx_doorbell_rank),
    .m_axis_doorbell_wqe(tx_doorbell_wqe),
    .m_axis_doorbell_valid(tx_doorbell_valid),
    .m_axis_doorbell_ready(tx_doorbell_ready),

    //Pifo completion input
    .s_axis_pifo_comp_queue(tx_pifo_comp_queue),
    .s_axis_pifo_comp_valid(tx_pifo_comp_valid),

    //AXI-Lite slave interface
    .s_axil_awaddr(s_axil_awaddr),
    .s_axil_awprot(s_axil_awprot),
    .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata),
    .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid),
    .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp),
    .s_axil_bvalid(s_axil_bvalid),
    .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr),
    .s_axil_arprot(s_axil_arprot),
    .s_axil_arvalid(s_axil_arvalid),
    .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata),
    .s_axil_rresp(s_axil_rresp),
    .s_axil_rvalid(s_axil_rvalid),
    .s_axil_rready(s_axil_rready),

    //Configuration
    .enable(1'b1)
);

//Pifo
PIFO_SRAM_Top #(
    .PTW(PTW),
    .MTW(MTW),
    .CTW(CTW),
    .LEVEL_TOTAL(LEVEL_TOTAL),
    .SINGLE_DATA_WITHOUT_COUNTER(SINGLE_DATA_WITHOUT_COUNTER)

) 
pifo_inst (
    .clk(clk),
    .rst(rst),
    
    //Doorbell input
    .Top_Push_valid(tx_doorbell_valid),
    .Top_Push_Data({tx_doorbell_rank,tx_doorbell_queue,tx_doorbell_wqe}),
    .Top_Push_ready(tx_doorbell_ready),
    
    //Pifo pop request input
    .Top_Pop_req_valid(tx_req_valid),
    .Top_Pop_req_DATA(),
    .Top_Pop_req_ready(tx_req_ready),

    //Pifo pop response output
    .Top_Pop_resp_valid(tx_resp_valid),
    .Top_Pop_resp_Data({tx_resp_rank,tx_resp_queue,tx_resp_wqe}),//
    .Top_Pop_resp_ready(tx_resp_ready),
    .Pifo_Empty(Pifo_Empty)
);

//Descriptor request multiplexer
desc_op_mux #(
    .PORTS(2),
    .SELECT_WIDTH(1),
    .QUEUE_INDEX_WIDTH(QUEUE_INDEX_WIDTH),
    .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
    .CPL_QUEUE_INDEX_WIDTH(CQN_WIDTH),
    .S_REQ_TAG_WIDTH(DESC_REQ_TAG_WIDTH_INT),
    .M_REQ_TAG_WIDTH(DESC_REQ_TAG_WIDTH),
    .AXIS_DATA_WIDTH(AXIS_DESC_DATA_WIDTH),
    .AXIS_KEEP_WIDTH(AXIS_DESC_KEEP_WIDTH),
    .ARB_TYPE_ROUND_ROBIN(1),
    .ARB_LSB_HIGH_PRIORITY(1),

    .WQE_WIDTH(WQE_WIDTH)
)
desc_op_mux_inst (
    .clk(clk),
    .rst(rst),

    // Descriptor request input from tx_engine or rx_engine
    .s_axis_req_sel({rx_desc_req_sel, tx_desc_req_sel}),
    .s_axis_req_queue({rx_desc_req_queue, tx_desc_req_queue}),
    .s_axis_req_wqe({rx_desc_req_wqe, tx_desc_req_wqe}),
    .s_axis_req_tag({rx_desc_req_tag, tx_desc_req_tag}),
    .s_axis_req_valid({rx_desc_req_valid, tx_desc_req_valid}),
    .s_axis_req_ready({rx_desc_req_ready, tx_desc_req_ready}),
    // Descriptor request output to desc_fetch
    .m_axis_req_sel(desc_req_sel),
    .m_axis_req_queue(desc_req_queue),
    .m_axis_req_wqe(desc_req_wqe),
    .m_axis_req_tag(desc_req_tag),
    .m_axis_req_valid(desc_req_valid),
    .m_axis_req_ready(desc_req_ready),


    // Descriptor request status input from desc_fetch
    .s_axis_req_status_queue(desc_req_status_queue),
    .s_axis_req_status_ptr(desc_req_status_ptr),
    .s_axis_req_status_cpl(desc_req_status_cpl),
    .s_axis_req_status_tag(desc_req_status_tag),
    .s_axis_req_status_empty(desc_req_status_empty),
    .s_axis_req_status_error(desc_req_status_error),
    .s_axis_req_status_valid(desc_req_status_valid),
    //Descriptor response output to tx/rx_engine
    .m_axis_req_status_queue({rx_desc_req_status_queue, tx_desc_req_status_queue}),
    .m_axis_req_status_ptr({rx_desc_req_status_ptr, tx_desc_req_status_ptr}),
    .m_axis_req_status_cpl({rx_desc_req_status_cpl, tx_desc_req_status_cpl}),
    .m_axis_req_status_tag({rx_desc_req_status_tag, tx_desc_req_status_tag}),
    .m_axis_req_status_empty({rx_desc_req_status_empty, tx_desc_req_status_empty}),
    .m_axis_req_status_error({rx_desc_req_status_error, tx_desc_req_status_error}),
    .m_axis_req_status_valid({rx_desc_req_status_valid, tx_desc_req_status_valid}),


    //Descriptor data input from desc_fetch
    .s_axis_desc_tdata(axis_desc_tdata),
    .s_axis_desc_tkeep(axis_desc_tkeep),
    .s_axis_desc_tvalid(axis_desc_tvalid),
    .s_axis_desc_tready(axis_desc_tready),
    .s_axis_desc_tlast(axis_desc_tlast),
    .s_axis_desc_tid(axis_desc_tid),
    .s_axis_desc_tuser(axis_desc_tuser),
    //Descriptor data output to tx/rx_engine
    .m_axis_desc_tdata({rx_desc_tdata, tx_desc_tdata}),
    .m_axis_desc_tkeep({rx_desc_tkeep, tx_desc_tkeep}),
    .m_axis_desc_tvalid({rx_desc_tvalid, tx_desc_tvalid}),
    .m_axis_desc_tready({rx_desc_tready, tx_desc_tready}),
    .m_axis_desc_tlast({rx_desc_tlast, tx_desc_tlast}),
    .m_axis_desc_tid({rx_desc_tid, tx_desc_tid}),
    .m_axis_desc_tuser({rx_desc_tuser, tx_desc_tuser})
);


//Descriptor fetch
desc_fetch #(
    .PORTS(2),
    .SELECT_WIDTH(1),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
    .SEG_COUNT(RAM_SEG_COUNT),
    .SEG_DATA_WIDTH(RAM_SEG_DATA_WIDTH),
    .SEG_BE_WIDTH(RAM_SEG_BE_WIDTH),
    .SEG_ADDR_WIDTH(RAM_SEG_ADDR_WIDTH),
    .RAM_PIPELINE(RAM_PIPELINE),
    .AXIS_DATA_WIDTH(AXIS_DESC_DATA_WIDTH),
    .AXIS_KEEP_WIDTH(AXIS_DESC_KEEP_WIDTH),
    .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .REQ_TAG_WIDTH(DESC_REQ_TAG_WIDTH),
    .QUEUE_REQ_TAG_WIDTH(QUEUE_REQ_TAG_WIDTH),
    .QUEUE_OP_TAG_WIDTH(QUEUE_OP_TAG_WIDTH),
    .QUEUE_INDEX_WIDTH(QUEUE_INDEX_WIDTH),
    .CPL_QUEUE_INDEX_WIDTH(CQN_WIDTH),
    .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
    .DESC_SIZE(DESC_SIZE),
    .LOG_BLOCK_SIZE_WIDTH(LOG_BLOCK_SIZE_WIDTH),
    .DESC_TABLE_SIZE(32),

    .WQE_WIDTH(WQE_WIDTH)
)
desc_fetch_inst (
    .clk(clk),
    .rst(rst),


    //Descriptor read request input from tx/rx_engine through desc_op_mux
    .s_axis_req_sel(desc_req_sel),
    .s_axis_req_queue(desc_req_queue),
    .s_axis_req_wqe(desc_req_wqe),
    .s_axis_req_tag(desc_req_tag),
    .s_axis_req_valid(desc_req_valid),
    .s_axis_req_ready(desc_req_ready),
    //Descriptor read request status output to tx/rx_engine through desc_op_mux
    .m_axis_req_status_queue(desc_req_status_queue),
    .m_axis_req_status_ptr(desc_req_status_ptr),
    .m_axis_req_status_cpl(desc_req_status_cpl),
    .m_axis_req_status_tag(desc_req_status_tag),
    .m_axis_req_status_empty(desc_req_status_empty),
    .m_axis_req_status_error(desc_req_status_error),
    .m_axis_req_status_valid(desc_req_status_valid),


    //Descriptor dequeue request output
    .m_axis_desc_dequeue_req_queue({rx_desc_dequeue_req_queue, tx_desc_dequeue_req_queue}),
    .m_axis_desc_dequeue_req_wqe({rx_desc_dequeue_req_wqe, tx_desc_dequeue_req_wqe}),
    .m_axis_desc_dequeue_req_tag({rx_desc_dequeue_req_tag, tx_desc_dequeue_req_tag}),
    .m_axis_desc_dequeue_req_valid({rx_desc_dequeue_req_valid, tx_desc_dequeue_req_valid}),
    .m_axis_desc_dequeue_req_ready({rx_desc_dequeue_req_ready, tx_desc_dequeue_req_ready}),
    //Descriptor dequeue response input
    .s_axis_desc_dequeue_resp_queue({rx_desc_dequeue_resp_queue, tx_desc_dequeue_resp_queue}),
    .s_axis_desc_dequeue_resp_ptr({rx_desc_dequeue_resp_ptr, tx_desc_dequeue_resp_ptr}),
    .s_axis_desc_dequeue_resp_addr({rx_desc_dequeue_resp_addr, tx_desc_dequeue_resp_addr}),
    .s_axis_desc_dequeue_resp_block_size({rx_desc_dequeue_resp_block_size, tx_desc_dequeue_resp_block_size}),
    .s_axis_desc_dequeue_resp_cpl({rx_desc_dequeue_resp_cpl, tx_desc_dequeue_resp_cpl}),
    .s_axis_desc_dequeue_resp_tag({rx_desc_dequeue_resp_tag, tx_desc_dequeue_resp_tag}),
    .s_axis_desc_dequeue_resp_op_tag({rx_desc_dequeue_resp_op_tag, tx_desc_dequeue_resp_op_tag}),
    .s_axis_desc_dequeue_resp_empty({rx_desc_dequeue_resp_empty, tx_desc_dequeue_resp_empty}),
    .s_axis_desc_dequeue_resp_error({rx_desc_dequeue_resp_error, tx_desc_dequeue_resp_error}),
    .s_axis_desc_dequeue_resp_valid({rx_desc_dequeue_resp_valid, tx_desc_dequeue_resp_valid}),
    .s_axis_desc_dequeue_resp_ready({rx_desc_dequeue_resp_ready, tx_desc_dequeue_resp_ready}),
    .s_axis_desc_dequeue_resp_wqe({rx_desc_dequeue_resp_wqe, tx_desc_dequeue_resp_wqe}),

    //Descriptor dequeue commit output
    .m_axis_desc_dequeue_commit_op_tag({rx_desc_dequeue_commit_op_tag, tx_desc_dequeue_commit_op_tag}),
    .m_axis_desc_dequeue_commit_valid({rx_desc_dequeue_commit_valid, tx_desc_dequeue_commit_valid}),
    .m_axis_desc_dequeue_commit_ready({rx_desc_dequeue_commit_ready, tx_desc_dequeue_commit_ready}),


    //DMA read descriptor output to DMA_interface
    .m_axis_dma_read_desc_dma_addr(ctrl_dma_read_desc_dma_addr),
    .m_axis_dma_read_desc_ram_addr(ctrl_dma_read_desc_ram_addr),
    .m_axis_dma_read_desc_len(ctrl_dma_read_desc_len),
    .m_axis_dma_read_desc_tag(ctrl_dma_read_desc_tag),
    .m_axis_dma_read_desc_valid(ctrl_dma_read_desc_valid),
    .m_axis_dma_read_desc_ready(ctrl_dma_read_desc_ready),
    //DMA read descriptor status input for DMA_interface
    .s_axis_dma_read_desc_status_tag(ctrl_dma_read_desc_status_tag),
    .s_axis_dma_read_desc_status_error(ctrl_dma_read_desc_status_error),
    .s_axis_dma_read_desc_status_valid(ctrl_dma_read_desc_status_valid),
    //RAM interface for DMA Write from DMA_interface
    .dma_ram_wr_cmd_be(ctrl_dma_ram_wr_cmd_be),
    .dma_ram_wr_cmd_addr(ctrl_dma_ram_wr_cmd_addr),
    .dma_ram_wr_cmd_data(ctrl_dma_ram_wr_cmd_data),
    .dma_ram_wr_cmd_valid(ctrl_dma_ram_wr_cmd_valid),
    .dma_ram_wr_cmd_ready(ctrl_dma_ram_wr_cmd_ready),
    .dma_ram_wr_done(ctrl_dma_ram_wr_done),
    //Descriptor data output to tx/rx_engine through desc_op_mux
    .m_axis_desc_tdata(axis_desc_tdata),
    .m_axis_desc_tkeep(axis_desc_tkeep),
    .m_axis_desc_tvalid(axis_desc_tvalid),
    .m_axis_desc_tready(axis_desc_tready),
    .m_axis_desc_tlast(axis_desc_tlast),
    .m_axis_desc_tid(axis_desc_tid),
    .m_axis_desc_tuser(axis_desc_tuser),
    

    //Configuration
    .enable(1'b1)
);

mqnic_interface_tx #(
    // Structural configuration
    .PORTS(1),

    // PTP configuration
    .PTP_TS_WIDTH(PTP_TS_WIDTH),

    // Queue manager configuration
    .TX_QUEUE_INDEX_WIDTH(QUEUE_INDEX_WIDTH),
    .QUEUE_INDEX_WIDTH(QUEUE_INDEX_WIDTH),
    .CQN_WIDTH(CQN_WIDTH),
    .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
    .LOG_QUEUE_SIZE_WIDTH(LOG_QUEUE_SIZE_WIDTH),
    .LOG_BLOCK_SIZE_WIDTH(LOG_BLOCK_SIZE_WIDTH),

    // Descriptor management
    .TX_MAX_DESC_REQ(TX_MAX_DESC_REQ),
    .TX_DESC_FIFO_SIZE(TX_DESC_FIFO_SIZE),
    .DESC_SIZE(DESC_SIZE),
    .CPL_SIZE(CPL_SIZE),
    .AXIS_DESC_DATA_WIDTH(AXIS_DESC_DATA_WIDTH),
    .AXIS_DESC_KEEP_WIDTH(AXIS_DESC_KEEP_WIDTH),
    .REQ_TAG_WIDTH(REQ_TAG_WIDTH),
    .DESC_REQ_TAG_WIDTH(DESC_REQ_TAG_WIDTH_INT),
    .CPL_REQ_TAG_WIDTH(CPL_REQ_TAG_WIDTH_INT),

    // TX engine configuration
    .TX_DESC_TABLE_SIZE(TX_DESC_TABLE_SIZE),
    .DESC_TABLE_DMA_OP_COUNT_WIDTH(((2**LOG_BLOCK_SIZE_WIDTH)-1)+1),

    // Interface configuration
    .PTP_TS_ENABLE(PTP_TS_ENABLE),
    .TX_TAG_WIDTH(TX_TAG_WIDTH),
    .TX_CHECKSUM_ENABLE(TX_CHECKSUM_ENABLE),
    .MAX_TX_SIZE(MAX_TX_SIZE),
    .TX_RAM_SIZE(TX_RAM_SIZE),

    // DMA interface configuration
    .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
    .RAM_SEG_COUNT(RAM_SEG_COUNT),
    .RAM_SEG_DATA_WIDTH(RAM_SEG_DATA_WIDTH),
    .RAM_SEG_BE_WIDTH(RAM_SEG_BE_WIDTH),
    .RAM_SEG_ADDR_WIDTH(RAM_SEG_ADDR_WIDTH),
    .RAM_PIPELINE(RAM_PIPELINE),

    // Streaming interface configuration
    .AXIS_DATA_WIDTH(AXIS_IF_DATA_WIDTH),
    .AXIS_KEEP_WIDTH(AXIS_IF_KEEP_WIDTH),
    .AXIS_TX_ID_WIDTH(AXIS_IF_TX_ID_WIDTH),
    .AXIS_TX_DEST_WIDTH(AXIS_IF_TX_DEST_WIDTH),
    .AXIS_TX_USER_WIDTH(AXIS_IF_TX_USER_WIDTH),

    .WQE_WIDTH(WQE_WIDTH)

)
interface_tx_inst (
    .clk(clk),
    .rst(rst),

    // Transmit request output
    .m_axis_tx_req_valid(tx_req_valid),
    .m_axis_tx_req_ready(tx_req_ready),
    //Transmit request input from scheduler
    .s_axis_tx_resp_queue(tx_resp_queue),
    .s_axis_tx_resp_wqe(tx_resp_wqe),
    .s_axis_tx_resp_dest(0),//取决于port数目，但是port是什么意思？
    .s_axis_tx_resp_valid(tx_resp_valid),
    .s_axis_tx_resp_ready(tx_resp_ready),


    //Descriptor request output to desc_fetch through desc_op_mux
    .m_axis_desc_req_queue(tx_desc_req_queue),
    .m_axis_desc_req_wqe(tx_desc_req_wqe),
    .m_axis_desc_req_tag(tx_desc_req_tag),
    .m_axis_desc_req_valid(tx_desc_req_valid),
    .m_axis_desc_req_ready(tx_desc_req_ready),
    // Descriptor request status input from desc_fetch through desc_op_mux
    .s_axis_desc_req_status_queue(tx_desc_req_status_queue),
    .s_axis_desc_req_status_ptr(tx_desc_req_status_ptr),
    .s_axis_desc_req_status_cpl(tx_desc_req_status_cpl),
    .s_axis_desc_req_status_tag(tx_desc_req_status_tag),
    .s_axis_desc_req_status_empty(tx_desc_req_status_empty),
    .s_axis_desc_req_status_error(tx_desc_req_status_error),
    .s_axis_desc_req_status_valid(tx_desc_req_status_valid),
    // Descriptor data input to desc_fetch through desc_op_mux
    .s_axis_desc_tdata(tx_desc_tdata),
    .s_axis_desc_tkeep(tx_desc_tkeep),
    .s_axis_desc_tvalid(tx_desc_tvalid),
    .s_axis_desc_tready(tx_desc_tready),
    .s_axis_desc_tlast(tx_desc_tlast),
    .s_axis_desc_tid(tx_desc_tid),
    .s_axis_desc_tuser(tx_desc_tuser),


    // DMA read descriptor output (data)
    .m_axis_dma_read_desc_dma_addr(data_dma_read_desc_dma_addr),
    .m_axis_dma_read_desc_ram_addr(data_dma_read_desc_ram_addr),
    .m_axis_dma_read_desc_len(data_dma_read_desc_len),
    .m_axis_dma_read_desc_tag(data_dma_read_desc_tag),
    .m_axis_dma_read_desc_valid(data_dma_read_desc_valid),
    .m_axis_dma_read_desc_ready(data_dma_read_desc_ready),
    // DMA read descriptor status input (data)
    .s_axis_dma_read_desc_status_tag(data_dma_read_desc_status_tag),
    .s_axis_dma_read_desc_status_error(data_dma_read_desc_status_error),
    .s_axis_dma_read_desc_status_valid(data_dma_read_desc_status_valid),
    // RAM interface (data)
    .dma_ram_wr_cmd_be(data_dma_ram_wr_cmd_be),
    .dma_ram_wr_cmd_addr(data_dma_ram_wr_cmd_addr),
    .dma_ram_wr_cmd_data(data_dma_ram_wr_cmd_data),
    .dma_ram_wr_cmd_valid(data_dma_ram_wr_cmd_valid),
    .dma_ram_wr_cmd_ready(data_dma_ram_wr_cmd_ready),
    .dma_ram_wr_done(data_dma_ram_wr_done),

    // Transmit data output to mqnic_port(仿真层) 
    .m_axis_tx_tdata(m_axis_tx_tdata),
    .m_axis_tx_tkeep(m_axis_tx_tkeep),
    .m_axis_tx_tvalid(m_axis_tx_tvalid),
    .m_axis_tx_tready(m_axis_tx_tready),
    .m_axis_tx_tlast(m_axis_tx_tlast),
    .m_axis_tx_tid(m_axis_tx_tid),
    .m_axis_tx_tdest(m_axis_tx_tdest),
    .m_axis_tx_tuser(m_axis_tx_tuser),

    // Completion request output to cpl_write(仿真层)
    .m_axis_cpl_req_queue(m_axis_cpl_req_queue),
    .m_axis_cpl_req_tag(m_axis_cpl_req_tag),
    .m_axis_cpl_req_data(m_axis_cpl_req_data),
    .m_axis_cpl_req_valid(m_axis_cpl_req_valid),
    .m_axis_cpl_req_ready(m_axis_cpl_req_ready),

    // Completion request status input from cpl_write(仿真层)
    .s_axis_cpl_req_status_tag(s_axis_cpl_req_status_tag),
    .s_axis_cpl_req_status_full(s_axis_cpl_req_status_full),
    .s_axis_cpl_req_status_error(s_axis_cpl_req_status_error),
    .s_axis_cpl_req_status_valid(s_axis_cpl_req_status_valid),

    // Transmit completion input from cpl_write(仿真层)
    .s_axis_tx_cpl_ts(s_axis_tx_cpl_ts),
    .s_axis_tx_cpl_tag(s_axis_tx_cpl_tag),
    .s_axis_tx_cpl_valid(s_axis_tx_cpl_valid),
    .s_axis_tx_cpl_ready(s_axis_tx_cpl_ready),

    // Configuration
    .mtu(tx_mtu_reg)
);


endmodule