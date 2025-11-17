
module rx_core #
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
    parameter PTP_TS_ENABLE = 0,
    parameter TX_CPL_ENABLE = PTP_TS_ENABLE,
    parameter TX_CPL_FIFO_DEPTH = 32,
    parameter TX_TAG_WIDTH = $clog2(TX_DESC_TABLE_SIZE)+1,
    parameter TX_CHECKSUM_ENABLE = 0,
    parameter RX_HASH_ENABLE = 1,
    parameter RX_CHECKSUM_ENABLE = 0,
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

    // AXI-Lite slave interface from axi_lite_master(仿真层) axil_rx_qm_awaddr
    input  wire [AXIL_ADDR_WIDTH-1:0]                   axil_ctrl_awaddr,
    input  wire [2:0]                                   axil_ctrl_awprot,
    input  wire                                         axil_ctrl_awvalid,
    output wire                                         axil_ctrl_awready,
    input  wire [AXIL_DATA_WIDTH-1:0]                   axil_ctrl_wdata,
    input  wire [AXIL_STRB_WIDTH-1:0]                   axil_ctrl_wstrb,
    input  wire                                         axil_ctrl_wvalid,
    output wire                                         axil_ctrl_wready,
    output wire [1:0]                                   axil_ctrl_bresp,
    output wire                                         axil_ctrl_bvalid,
    input  wire                                         axil_ctrl_bready,
    input  wire [AXIL_ADDR_WIDTH-1:0]                   axil_ctrl_araddr,
    input  wire [2:0]                                   axil_ctrl_arprot,
    input  wire                                         axil_ctrl_arvalid,
    output wire                                         axil_ctrl_arready,
    output wire [AXIL_DATA_WIDTH-1:0]                   axil_ctrl_rdata,
    output wire [1:0]                                   axil_ctrl_rresp,
    output wire                                         axil_ctrl_rvalid,
    input  wire                                         axil_ctrl_rready,

    input  wire [AXIL_ADDR_WIDTH-1:0]                   axil_rx_qm_awaddr,
    input  wire [2:0]                                   axil_rx_qm_awprot,
    input  wire                                         axil_rx_qm_awvalid,
    output wire                                         axil_rx_qm_awready,
    input  wire [AXIL_DATA_WIDTH-1:0]                   axil_rx_qm_wdata,
    input  wire [AXIL_STRB_WIDTH-1:0]                   axil_rx_qm_wstrb,
    input  wire                                         axil_rx_qm_wvalid,
    output wire                                         axil_rx_qm_wready,
    output wire [1:0]                                   axil_rx_qm_bresp,
    output wire                                         axil_rx_qm_bvalid,
    input  wire                                         axil_rx_qm_bready,
    input  wire [AXIL_ADDR_WIDTH-1:0]                   axil_rx_qm_araddr,
    input  wire [2:0]                                   axil_rx_qm_arprot,
    input  wire                                         axil_rx_qm_arvalid,
    output wire                                         axil_rx_qm_arready,
    output wire [AXIL_DATA_WIDTH-1:0]                   axil_rx_qm_rdata,
    output wire [1:0]                                   axil_rx_qm_rresp,
    output wire                                         axil_rx_qm_rvalid,
    input  wire                                         axil_rx_qm_rready,


    input  wire [AXIL_ADDR_WIDTH-1:0]                   axil_rx_indir_tbl_awaddr,
    input  wire [2:0]                                   axil_rx_indir_tbl_awprot,
    input  wire                                         axil_rx_indir_tbl_awvalid,
    output wire                                         axil_rx_indir_tbl_awready,
    input  wire [AXIL_DATA_WIDTH-1:0]                   axil_rx_indir_tbl_wdata,
    input  wire [AXIL_STRB_WIDTH-1:0]                   axil_rx_indir_tbl_wstrb,
    input  wire                                         axil_rx_indir_tbl_wvalid,
    output wire                                         axil_rx_indir_tbl_wready,
    output wire [1:0]                                   axil_rx_indir_tbl_bresp,
    output wire                                         axil_rx_indir_tbl_bvalid,
    input  wire                                         axil_rx_indir_tbl_bready,
    input  wire [AXIL_ADDR_WIDTH-1:0]                   axil_rx_indir_tbl_araddr,
    input  wire [2:0]                                   axil_rx_indir_tbl_arprot,
    input  wire                                         axil_rx_indir_tbl_arvalid,
    output wire                                         axil_rx_indir_tbl_arready,
    output wire [AXIL_DATA_WIDTH-1:0]                   axil_rx_indir_tbl_rdata,
    output wire [1:0]                                   axil_rx_indir_tbl_rresp,
    output wire                                         axil_rx_indir_tbl_rvalid,
    input  wire                                         axil_rx_indir_tbl_rready,


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



    input  wire [RAM_SEG_COUNT*RAM_SEG_ADDR_WIDTH-1:0]  data_dma_ram_rd_cmd_addr,
    input  wire [RAM_SEG_COUNT-1:0]                     data_dma_ram_rd_cmd_valid,
    output wire [RAM_SEG_COUNT-1:0]                     data_dma_ram_rd_cmd_ready,
    output wire [RAM_SEG_COUNT*RAM_SEG_DATA_WIDTH-1:0]  data_dma_ram_rd_resp_data,
    output wire [RAM_SEG_COUNT-1:0]                     data_dma_ram_rd_resp_valid,
    input  wire [RAM_SEG_COUNT-1:0]                     data_dma_ram_rd_resp_ready,

    /*
     * DMA write descriptor output (data)
     */
    output wire [DMA_ADDR_WIDTH-1:0]                    m_axis_data_dma_write_desc_dma_addr,
    // output wire [RAM_SEL_WIDTH-1:0]                     m_axis_data_dma_write_desc_ram_sel,
    output wire [RAM_ADDR_WIDTH-1:0]                    m_axis_data_dma_write_desc_ram_addr,
    // output wire [DMA_IMM_WIDTH-1:0]                     m_axis_data_dma_write_desc_imm,
    // output wire                                         m_axis_data_dma_write_desc_imm_en,
    output wire [DMA_LEN_WIDTH-1:0]                     m_axis_data_dma_write_desc_len,
    output wire [DMA_TAG_WIDTH-1:0]                     m_axis_data_dma_write_desc_tag,
    output wire                                         m_axis_data_dma_write_desc_valid,
    input  wire                                         m_axis_data_dma_write_desc_ready,

    /*
     * DMA write descriptor status input (data)
     */
    input  wire [DMA_TAG_WIDTH-1:0]                     s_axis_data_dma_write_desc_status_tag,
    input  wire [3:0]                                   s_axis_data_dma_write_desc_status_error,
    input  wire                                         s_axis_data_dma_write_desc_status_valid,

    // Transmit data output  
    input  wire [PORTS-1:0]                             tx_clk,
    input  wire [PORTS-1:0]                             tx_rst,

    output wire [PORTS*AXIS_DATA_WIDTH-1:0]             m_axis_tx_tdata,
    output wire [PORTS*AXIS_KEEP_WIDTH-1:0]             m_axis_tx_tkeep,
    output wire [PORTS-1:0]                             m_axis_tx_tvalid,
    input  wire [PORTS-1:0]                             m_axis_tx_tready,
    output wire [PORTS-1:0]                             m_axis_tx_tlast,
    output wire [PORTS*AXIS_TX_USER_WIDTH-1:0]          m_axis_tx_tuser,

    input  wire [PORTS*PTP_TS_WIDTH-1:0]                s_axis_tx_cpl_ts,
    input  wire [PORTS*TX_TAG_WIDTH-1:0]                s_axis_tx_cpl_tag,
    input  wire [PORTS-1:0]                             s_axis_tx_cpl_valid,
    output wire [PORTS-1:0]                             s_axis_tx_cpl_ready,

    output wire [PORTS-1:0]                             tx_enable,
    input  wire [PORTS-1:0]                             tx_status,
    output wire [PORTS-1:0]                             tx_lfc_en,
    output wire [PORTS-1:0]                             tx_lfc_req,
    output wire [PORTS*8-1:0]                           tx_pfc_en,
    output wire [PORTS*8-1:0]                           tx_pfc_req,
    input  wire [PORTS-1:0]                             tx_fc_quanta_clk_en,

    // Receive data input 
    input  wire [PORTS-1:0]                             rx_clk,
    input  wire [PORTS-1:0]                             rx_rst,

    input  wire [PORTS*AXIS_DATA_WIDTH-1:0]             s_axis_rx_tdata,
    input  wire [PORTS*AXIS_KEEP_WIDTH-1:0]             s_axis_rx_tkeep,
    input  wire [PORTS-1:0]                             s_axis_rx_tvalid,
    output wire [PORTS-1:0]                             s_axis_rx_tready,
    input  wire [PORTS-1:0]                             s_axis_rx_tlast,
    input  wire [PORTS*AXIS_RX_USER_WIDTH-1:0]          s_axis_rx_tuser,

    output wire [PORTS-1:0]                             rx_enable,
    input  wire [PORTS-1:0]                             rx_status,
    output wire [PORTS-1:0]                             rx_lfc_en,
    input  wire [PORTS-1:0]                             rx_lfc_req,
    output wire [PORTS-1:0]                             rx_lfc_ack,
    output wire [PORTS*8-1:0]                           rx_pfc_en,
    input  wire [PORTS*8-1:0]                           rx_pfc_req,
    output wire [PORTS*8-1:0]                           rx_pfc_ack,
    input  wire [PORTS-1:0]                             rx_fc_quanta_clk_en,


    // Completion request output to cpl_write(仿真层)
    output wire [QUEUE_INDEX_WIDTH-1:0]                 rx_cpl_req_queue,
    output wire [CPL_REQ_TAG_WIDTH_INT-1:0]             rx_cpl_req_tag,
    output wire [CPL_SIZE-1:0]                          rx_cpl_req_data,
    output wire                                         rx_cpl_req_valid,
    input  wire                                         rx_cpl_req_ready,

    // Completion request status input from cpl_write(仿真层)
    input  wire [CPL_REQ_TAG_WIDTH_INT-1:0]             rx_cpl_req_status_tag,
    input  wire                                         rx_cpl_req_status_full,
    input  wire                                         rx_cpl_req_status_error,
    input  wire                                         rx_cpl_req_status_valid

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
wire                                tx_req_valid = 1'b0;
wire                                tx_req_ready = 1'b0;
wire [QUEUE_INDEX_WIDTH-1:0]        tx_resp_queue = 0;
wire [WQE_WIDTH-1:0]                tx_resp_wqe = 0;
wire                                tx_resp_valid = 1'b0;
wire                                tx_resp_ready = 1'b0;

// TX descriptor request wires
wire [0:0]                          tx_desc_req_sel = 1'b0;
wire [QUEUE_INDEX_WIDTH-1:0]        tx_desc_req_queue = 0;
wire [WQE_WIDTH-1:0]                tx_desc_req_wqe = 0;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   tx_desc_req_tag = 0;
wire                                tx_desc_req_valid = 1'b0;
wire                                tx_desc_req_ready= 1'b0;

// TX descriptor request status wires
wire [QUEUE_INDEX_WIDTH-1:0]        tx_desc_req_status_queue = 0;
wire [QUEUE_PTR_WIDTH-1:0]          tx_desc_req_status_ptr = 0;
wire [CQN_WIDTH-1:0]                tx_desc_req_status_cpl = 0;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   tx_desc_req_status_tag = 0;
wire                                tx_desc_req_status_empty= 1'b0;
wire                                tx_desc_req_status_error= 1'b0;
wire                                tx_desc_req_status_valid = 1'b0;

// TX descriptor data wires
wire [AXIS_DESC_DATA_WIDTH-1:0]     tx_desc_tdata = 0;
wire [AXIS_DESC_KEEP_WIDTH-1:0]     tx_desc_tkeep = 0;
wire                                tx_desc_tvalid = 1'b0;
wire                                tx_desc_tready = 1'b0;
wire                                tx_desc_tlast = 1'b0;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   tx_desc_tid = 0;
wire                                tx_desc_tuser = 1'b0;

// RX descriptor request wires
wire [0:0]                          rx_desc_req_sel = 1'b1;
wire [QUEUE_INDEX_WIDTH-1:0]        rx_desc_req_queue;
wire [WQE_WIDTH-1:0]                rx_desc_req_wqe = 1'b1;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   rx_desc_req_tag;
wire                                rx_desc_req_valid;
wire                                rx_desc_req_ready;

// RX descriptor request status wires
wire [QUEUE_INDEX_WIDTH-1:0]        rx_desc_req_status_queue;
wire [QUEUE_PTR_WIDTH-1:0]          rx_desc_req_status_ptr;
wire [CQN_WIDTH-1:0]                rx_desc_req_status_cpl;
wire [DESC_REQ_TAG_WIDTH_INT-1:0]   rx_desc_req_status_tag;
wire                                rx_desc_req_status_empty;
wire                                rx_desc_req_status_error;
wire                                rx_desc_req_status_valid;

// RX descriptor data wires
wire [AXIS_DESC_DATA_WIDTH-1:0]     rx_desc_tdata;
wire [AXIS_DESC_KEEP_WIDTH-1:0]     rx_desc_tkeep;
wire                                rx_desc_tvalid;
wire                                rx_desc_tready;
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

wire [QUEUE_INDEX_WIDTH-1:0]        tx_desc_dequeue_req_queue = 0;
wire [WQE_WIDTH-1:0]                tx_desc_dequeue_req_wqe = 0;
wire [QUEUE_REQ_TAG_WIDTH-1:0]      tx_desc_dequeue_req_tag = 0;
wire                                tx_desc_dequeue_req_valid = 1'b0;
wire                                tx_desc_dequeue_req_ready = 1'b0;

wire [QUEUE_INDEX_WIDTH-1:0]        tx_desc_dequeue_resp_queue = 0;
wire [QUEUE_PTR_WIDTH-1:0]          tx_desc_dequeue_resp_ptr = 0;
wire [DMA_ADDR_WIDTH-1:0]           tx_desc_dequeue_resp_addr = 0;
wire [LOG_BLOCK_SIZE_WIDTH-1:0]     tx_desc_dequeue_resp_block_size = 0;
wire [CQN_WIDTH-1:0]                tx_desc_dequeue_resp_cpl = 0;
wire [QUEUE_REQ_TAG_WIDTH-1:0]      tx_desc_dequeue_resp_tag = 0;
wire [QUEUE_OP_TAG_WIDTH-1:0]       tx_desc_dequeue_resp_op_tag = 0;
wire                                tx_desc_dequeue_resp_empty = 1'b0;
wire                                tx_desc_dequeue_resp_error = 1'b0;
wire                                tx_desc_dequeue_resp_valid = 1'b0;
wire                                tx_desc_dequeue_resp_ready = 1'b0;
wire [WQE_WIDTH-1:0]                tx_desc_dequeue_resp_wqe = 0; 

wire [QUEUE_OP_TAG_WIDTH-1:0]       tx_desc_dequeue_commit_op_tag = 0;  
wire                                tx_desc_dequeue_commit_valid = 1'b0;
wire                                tx_desc_dequeue_commit_ready = 1'b0;

wire [QUEUE_INDEX_WIDTH-1:0]        tx_doorbell_queue = 0;
wire [RANK_WIDTH-1:0]               tx_doorbell_rank = 0;
wire [WQE_WIDTH-1:0]                tx_doorbell_wqe = 0;
wire                                tx_doorbell_valid = 1'b0;
wire                                tx_doorbell_ready = 1'b0;

wire [QUEUE_INDEX_WIDTH-1:0]        tx_pifo_comp_queue = 0;
wire                                tx_pifo_comp_valid = 1'b0;


wire [QUEUE_INDEX_WIDTH-1:0]        rx_desc_dequeue_req_queue;
wire [WQE_WIDTH-1:0]                rx_desc_dequeue_req_wqe;
wire [QUEUE_REQ_TAG_WIDTH-1:0]      rx_desc_dequeue_req_tag;
wire                                rx_desc_dequeue_req_valid;
wire                                rx_desc_dequeue_req_ready;

wire [QUEUE_INDEX_WIDTH-1:0]        rx_desc_dequeue_resp_queue;
wire [QUEUE_PTR_WIDTH-1:0]          rx_desc_dequeue_resp_ptr;
wire [DMA_ADDR_WIDTH-1:0]           rx_desc_dequeue_resp_addr;
wire [LOG_BLOCK_SIZE_WIDTH-1:0]     rx_desc_dequeue_resp_block_size;
wire [CQN_WIDTH-1:0]                rx_desc_dequeue_resp_cpl;
wire [QUEUE_REQ_TAG_WIDTH-1:0]      rx_desc_dequeue_resp_tag;
wire [QUEUE_OP_TAG_WIDTH-1:0]       rx_desc_dequeue_resp_op_tag;
wire                                rx_desc_dequeue_resp_empty;
wire                                rx_desc_dequeue_resp_error;
wire                                rx_desc_dequeue_resp_valid;
wire                                rx_desc_dequeue_resp_ready;
wire [WQE_WIDTH-1:0]                rx_desc_dequeue_resp_wqe = 1'b1; 


wire [QUEUE_OP_TAG_WIDTH-1:0]       rx_desc_dequeue_commit_op_tag;  
wire                                rx_desc_dequeue_commit_valid;
wire                                rx_desc_dequeue_commit_ready;


// RX queues
rx_queue_manager #(
    .ADDR_WIDTH(DMA_ADDR_WIDTH),
    .REQ_TAG_WIDTH(QUEUE_REQ_TAG_WIDTH),
    .OP_TABLE_SIZE(RX_QUEUE_OP_TABLE_SIZE),
    .OP_TAG_WIDTH(QUEUE_OP_TAG_WIDTH),
    .QUEUE_INDEX_WIDTH(RX_QUEUE_INDEX_WIDTH),
    .CPL_INDEX_WIDTH(CQN_WIDTH),
    .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
    .LOG_QUEUE_SIZE_WIDTH(LOG_QUEUE_SIZE_WIDTH),
    .DESC_SIZE(DESC_SIZE),
    .LOG_BLOCK_SIZE_WIDTH(LOG_BLOCK_SIZE_WIDTH),
    .PIPELINE(RX_QUEUE_PIPELINE),
    .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
    .AXIL_ADDR_WIDTH(AXIL_RX_QM_ADDR_WIDTH),
    .AXIL_STRB_WIDTH(AXIL_STRB_WIDTH)
)
rx_qm_inst (
    .clk(clk),
    .rst(rst),

    /*
     * Dequeue request input
     */
    .s_axis_dequeue_req_queue(rx_desc_dequeue_req_queue),
    .s_axis_dequeue_req_tag(rx_desc_dequeue_req_tag),
    .s_axis_dequeue_req_valid(rx_desc_dequeue_req_valid),
    .s_axis_dequeue_req_ready(rx_desc_dequeue_req_ready),

    /*
     * Dequeue response output
     */
    .m_axis_dequeue_resp_queue(rx_desc_dequeue_resp_queue),
    .m_axis_dequeue_resp_ptr(rx_desc_dequeue_resp_ptr),
    .m_axis_dequeue_resp_addr(rx_desc_dequeue_resp_addr),
    .m_axis_dequeue_resp_block_size(rx_desc_dequeue_resp_block_size),
    .m_axis_dequeue_resp_cpl(rx_desc_dequeue_resp_cpl),
    .m_axis_dequeue_resp_tag(rx_desc_dequeue_resp_tag),
    .m_axis_dequeue_resp_op_tag(rx_desc_dequeue_resp_op_tag),
    .m_axis_dequeue_resp_empty(rx_desc_dequeue_resp_empty),
    .m_axis_dequeue_resp_error(rx_desc_dequeue_resp_error),
    .m_axis_dequeue_resp_valid(rx_desc_dequeue_resp_valid),
    .m_axis_dequeue_resp_ready(rx_desc_dequeue_resp_ready),

    /*
     * Dequeue commit input
     */
    .s_axis_dequeue_commit_op_tag(rx_desc_dequeue_commit_op_tag),
    .s_axis_dequeue_commit_valid(rx_desc_dequeue_commit_valid),
    .s_axis_dequeue_commit_ready(rx_desc_dequeue_commit_ready),

    /*
     * Doorbell output
     */
    .m_axis_doorbell_queue(),
    .m_axis_doorbell_valid(),

    /*
     * AXI-Lite slave interface 
     */
    .s_axil_awaddr(axil_rx_qm_awaddr),
    .s_axil_awprot(axil_rx_qm_awprot),
    .s_axil_awvalid(axil_rx_qm_awvalid),
    .s_axil_awready(axil_rx_qm_awready),
    .s_axil_wdata(axil_rx_qm_wdata),
    .s_axil_wstrb(axil_rx_qm_wstrb),
    .s_axil_wvalid(axil_rx_qm_wvalid),
    .s_axil_wready(axil_rx_qm_wready),
    .s_axil_bresp(axil_rx_qm_bresp),
    .s_axil_bvalid(axil_rx_qm_bvalid),
    .s_axil_bready(axil_rx_qm_bready),
    .s_axil_araddr(axil_rx_qm_araddr),
    .s_axil_arprot(axil_rx_qm_arprot),
    .s_axil_arvalid(axil_rx_qm_arvalid),
    .s_axil_arready(axil_rx_qm_arready),
    .s_axil_rdata(axil_rx_qm_rdata),
    .s_axil_rresp(axil_rx_qm_rresp),
    .s_axil_rvalid(axil_rx_qm_rvalid),
    .s_axil_rready(axil_rx_qm_rready),

    /*
     * Configuration
     */
    .enable(1'b1)
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

wire [AXIS_IF_DATA_WIDTH-1:0] if_tx_axis_tdata;
wire [AXIS_IF_KEEP_WIDTH-1:0] if_tx_axis_tkeep;
wire if_tx_axis_tvalid;
wire if_tx_axis_tready;
wire if_tx_axis_tlast;
wire [AXIS_IF_TX_ID_WIDTH-1:0] if_tx_axis_tid;
wire [AXIS_IF_TX_DEST_WIDTH-1:0] if_tx_axis_tdest;
wire [AXIS_IF_TX_USER_WIDTH-1:0] if_tx_axis_tuser;

wire [PTP_TS_WIDTH-1:0] if_tx_cpl_ts;
wire [TX_TAG_WIDTH-1:0] if_tx_cpl_tag;
wire if_tx_cpl_valid;
wire if_tx_cpl_ready;

//mqnic_interface_tx



mqnic_interface_rx #(
    // Structural configuration
    .PORTS(PORTS),

    // PTP configuration
    .PTP_TS_WIDTH(PTP_TS_WIDTH),

    // Queue manager configuration
    .RX_QUEUE_INDEX_WIDTH(RX_QUEUE_INDEX_WIDTH),
    .QUEUE_INDEX_WIDTH(QUEUE_INDEX_WIDTH),
    .CQN_WIDTH(CQN_WIDTH),
    .QUEUE_PTR_WIDTH(QUEUE_PTR_WIDTH),
    .LOG_QUEUE_SIZE_WIDTH(LOG_QUEUE_SIZE_WIDTH),
    .LOG_BLOCK_SIZE_WIDTH(LOG_BLOCK_SIZE_WIDTH),

    // Descriptor management
    .RX_MAX_DESC_REQ(RX_MAX_DESC_REQ),
    .RX_DESC_FIFO_SIZE(RX_DESC_FIFO_SIZE),
    .DESC_SIZE(DESC_SIZE),
    .CPL_SIZE(CPL_SIZE),
    .AXIS_DESC_DATA_WIDTH(AXIS_DESC_DATA_WIDTH),
    .AXIS_DESC_KEEP_WIDTH(AXIS_DESC_KEEP_WIDTH),
    .DESC_REQ_TAG_WIDTH(DESC_REQ_TAG_WIDTH_INT),
    .CPL_REQ_TAG_WIDTH(CPL_REQ_TAG_WIDTH_INT),

    // RX engine configuration
    .RX_DESC_TABLE_SIZE(RX_DESC_TABLE_SIZE),
    .DESC_TABLE_DMA_OP_COUNT_WIDTH(((2**LOG_BLOCK_SIZE_WIDTH)-1)+1),
    .RX_INDIR_TBL_ADDR_WIDTH(RX_INDIR_TBL_ADDR_WIDTH),

    // Interface configuration
    .PTP_TS_ENABLE(PTP_TS_ENABLE),
    .RX_HASH_ENABLE(RX_HASH_ENABLE),
    .RX_CHECKSUM_ENABLE(RX_CHECKSUM_ENABLE),
    .MAX_RX_SIZE(MAX_RX_SIZE),
    .RX_RAM_SIZE(RX_RAM_SIZE),

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

    // Register interface configuration
    .REG_ADDR_WIDTH(REG_ADDR_WIDTH),
    .REG_DATA_WIDTH(REG_DATA_WIDTH),
    .REG_STRB_WIDTH(REG_STRB_WIDTH),
    .RB_BASE_ADDR(RX_RB_BASE_ADDR),
    .RB_NEXT_PTR(PORT_RB_BASE_ADDR),

    // AXI lite interface configuration
    .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
    .AXIL_ADDR_WIDTH(AXIL_RX_INDIR_TBL_ADDR_WIDTH),
    .AXIL_STRB_WIDTH(AXIL_STRB_WIDTH),
    .AXIL_BASE_ADDR(AXIL_RX_INDIR_TBL_BASE_ADDR),

    // Streaming interface configuration
    .AXIS_DATA_WIDTH(AXIS_IF_DATA_WIDTH),
    .AXIS_KEEP_WIDTH(AXIS_IF_KEEP_WIDTH),
    .AXIS_RX_ID_WIDTH(AXIS_IF_RX_ID_WIDTH),
    .AXIS_RX_DEST_WIDTH(AXIS_IF_RX_DEST_WIDTH),
    .AXIS_RX_USER_WIDTH(AXIS_IF_RX_USER_WIDTH)
)
interface_rx_inst (
    .clk(clk),
    .rst(rst),

    /*
     * Control register interface
     */
    .ctrl_reg_wr_addr(ctrl_reg_wr_addr),
    .ctrl_reg_wr_data(ctrl_reg_wr_data),
    .ctrl_reg_wr_strb(ctrl_reg_wr_strb),
    .ctrl_reg_wr_en(ctrl_reg_wr_en),
    .ctrl_reg_wr_wait(if_rx_ctrl_reg_wr_wait),
    .ctrl_reg_wr_ack(if_rx_ctrl_reg_wr_ack),
    .ctrl_reg_rd_addr(ctrl_reg_rd_addr),
    .ctrl_reg_rd_en(ctrl_reg_rd_en),
    .ctrl_reg_rd_data(if_rx_ctrl_reg_rd_data),
    .ctrl_reg_rd_wait(if_rx_ctrl_reg_rd_wait),
    .ctrl_reg_rd_ack(if_rx_ctrl_reg_rd_ack),

    /*
     * AXI-Lite slave interface (indirection table)
     */
    .s_axil_awaddr(axil_rx_indir_tbl_awaddr),
    .s_axil_awprot(axil_rx_indir_tbl_awprot),
    .s_axil_awvalid(axil_rx_indir_tbl_awvalid),
    .s_axil_awready(axil_rx_indir_tbl_awready),
    .s_axil_wdata(axil_rx_indir_tbl_wdata),
    .s_axil_wstrb(axil_rx_indir_tbl_wstrb),
    .s_axil_wvalid(axil_rx_indir_tbl_wvalid),
    .s_axil_wready(axil_rx_indir_tbl_wready),
    .s_axil_bresp(axil_rx_indir_tbl_bresp),
    .s_axil_bvalid(axil_rx_indir_tbl_bvalid),
    .s_axil_bready(axil_rx_indir_tbl_bready),
    .s_axil_araddr(axil_rx_indir_tbl_araddr),
    .s_axil_arprot(axil_rx_indir_tbl_arprot),
    .s_axil_arvalid(axil_rx_indir_tbl_arvalid),
    .s_axil_arready(axil_rx_indir_tbl_arready),
    .s_axil_rdata(axil_rx_indir_tbl_rdata),
    .s_axil_rresp(axil_rx_indir_tbl_rresp),
    .s_axil_rvalid(axil_rx_indir_tbl_rvalid),
    .s_axil_rready(axil_rx_indir_tbl_rready),

    /*
     * Descriptor request output
     */
    .m_axis_desc_req_queue(rx_desc_req_queue),
    .m_axis_desc_req_tag(rx_desc_req_tag),
    .m_axis_desc_req_valid(rx_desc_req_valid),
    .m_axis_desc_req_ready(rx_desc_req_ready),

    /*
     * Descriptor request status input
     */
    .s_axis_desc_req_status_queue(rx_desc_req_status_queue),
    .s_axis_desc_req_status_ptr(rx_desc_req_status_ptr),
    .s_axis_desc_req_status_cpl(rx_desc_req_status_cpl),
    .s_axis_desc_req_status_tag(rx_desc_req_status_tag),
    .s_axis_desc_req_status_empty(rx_desc_req_status_empty),
    .s_axis_desc_req_status_error(rx_desc_req_status_error),
    .s_axis_desc_req_status_valid(rx_desc_req_status_valid),

    /*
     * Descriptor data input
     */
    .s_axis_desc_tdata(rx_desc_tdata),
    .s_axis_desc_tkeep(rx_desc_tkeep),
    .s_axis_desc_tvalid(rx_desc_tvalid),
    .s_axis_desc_tready(rx_desc_tready),
    .s_axis_desc_tlast(rx_desc_tlast),
    .s_axis_desc_tid(rx_desc_tid),
    .s_axis_desc_tuser(rx_desc_tuser),

    /*
     * Completion request output
     */
    .m_axis_cpl_req_queue(rx_cpl_req_queue),
    .m_axis_cpl_req_tag(rx_cpl_req_tag),
    .m_axis_cpl_req_data(rx_cpl_req_data),
    .m_axis_cpl_req_valid(rx_cpl_req_valid),
    .m_axis_cpl_req_ready(rx_cpl_req_ready),

    /*
     * Completion request status input
     */
    .s_axis_cpl_req_status_tag(rx_cpl_req_status_tag),
    .s_axis_cpl_req_status_full(rx_cpl_req_status_full),
    .s_axis_cpl_req_status_error(rx_cpl_req_status_error),
    .s_axis_cpl_req_status_valid(rx_cpl_req_status_valid),

    /*
     * DMA write descriptor output (data)
     */
    .m_axis_dma_write_desc_dma_addr(m_axis_data_dma_write_desc_dma_addr),
    .m_axis_dma_write_desc_ram_addr(m_axis_data_dma_write_desc_ram_addr),
    .m_axis_dma_write_desc_len(m_axis_data_dma_write_desc_len),
    .m_axis_dma_write_desc_tag(m_axis_data_dma_write_desc_tag),
    .m_axis_dma_write_desc_valid(m_axis_data_dma_write_desc_valid),
    .m_axis_dma_write_desc_ready(m_axis_data_dma_write_desc_ready),

    /*
     * DMA write descriptor status input (data)
     */
    .s_axis_dma_write_desc_status_tag(s_axis_data_dma_write_desc_status_tag),
    .s_axis_dma_write_desc_status_error(s_axis_data_dma_write_desc_status_error),
    .s_axis_dma_write_desc_status_valid(s_axis_data_dma_write_desc_status_valid),

    /*
     * RAM interface (data)
     */
    .dma_ram_rd_cmd_addr(data_dma_ram_rd_cmd_addr),
    .dma_ram_rd_cmd_valid(data_dma_ram_rd_cmd_valid),
    .dma_ram_rd_cmd_ready(data_dma_ram_rd_cmd_ready),

    .dma_ram_rd_resp_data(data_dma_ram_rd_resp_data),
    .dma_ram_rd_resp_valid(data_dma_ram_rd_resp_valid),
    .dma_ram_rd_resp_ready(data_dma_ram_rd_resp_ready),


    /*
     * Receive data input
     */
    .s_axis_rx_tdata(if_rx_axis_tdata),
    .s_axis_rx_tkeep(if_rx_axis_tkeep),
    .s_axis_rx_tvalid(if_rx_axis_tvalid),
    .s_axis_rx_tready(if_rx_axis_tready),
    .s_axis_rx_tlast(if_rx_axis_tlast),
    .s_axis_rx_tid(if_rx_axis_tid),
    .s_axis_rx_tdest(if_rx_axis_tdest),
    .s_axis_rx_tuser(if_rx_axis_tuser),

    /*
     * Configuration
     */
    .mtu(rx_mtu_reg)
);

wire [AXIS_IF_DATA_WIDTH-1:0] if_rx_axis_tdata;
wire [AXIS_IF_KEEP_WIDTH-1:0] if_rx_axis_tkeep;
wire if_rx_axis_tvalid;
wire if_rx_axis_tready;
wire if_rx_axis_tlast;
wire [AXIS_IF_RX_ID_WIDTH-1:0] if_rx_axis_tid;
wire [AXIS_IF_RX_DEST_WIDTH-1:0] if_rx_axis_tdest;
wire [AXIS_IF_RX_USER_WIDTH-1:0] if_rx_axis_tuser;





wire [PORTS*PTP_TS_WIDTH-1:0] axis_if_tx_cpl_ts;
wire [PORTS*TX_TAG_WIDTH-1:0] axis_if_tx_cpl_tag;
wire [PORTS-1:0] axis_if_tx_cpl_valid;
wire [PORTS-1:0] axis_if_tx_cpl_ready;

wire [PTP_TS_WIDTH-1:0] axis_tx_cpl_ts;
wire [TX_TAG_WIDTH-1:0] axis_tx_cpl_tag;
wire axis_tx_cpl_valid;
wire axis_tx_cpl_ready;


assign axis_tx_cpl_ts = PTP_TS_ENABLE ? axis_if_tx_cpl_ts : 0;
assign axis_tx_cpl_tag = axis_if_tx_cpl_tag;
assign axis_tx_cpl_valid = axis_if_tx_cpl_valid;
assign axis_if_tx_cpl_ready = axis_tx_cpl_ready;

assign if_tx_cpl_ts = PTP_TS_ENABLE ? axis_tx_cpl_ts : 0;
assign if_tx_cpl_tag = axis_tx_cpl_tag;
assign if_tx_cpl_valid = axis_tx_cpl_valid;
assign axis_tx_cpl_ready = if_tx_cpl_ready;


wire [AXIS_IF_DATA_WIDTH-1:0] axis_if_tx_tdata;
wire [AXIS_IF_KEEP_WIDTH-1:0] axis_if_tx_tkeep;
wire axis_if_tx_tvalid;
wire axis_if_tx_tready;
wire axis_if_tx_tlast;
wire [AXIS_IF_TX_ID_WIDTH-1:0] axis_if_tx_tid;
wire [AXIS_IF_TX_DEST_WIDTH-1:0] axis_if_tx_tdest;
wire [AXIS_IF_TX_USER_WIDTH-1:0] axis_if_tx_tuser;

wire [PORTS*AXIS_SYNC_DATA_WIDTH-1:0] axis_if_tx_fifo_tdata;
wire [PORTS*AXIS_SYNC_KEEP_WIDTH-1:0] axis_if_tx_fifo_tkeep;
wire [PORTS-1:0] axis_if_tx_fifo_tvalid;
wire [PORTS-1:0] axis_if_tx_fifo_tready;
wire [PORTS-1:0] axis_if_tx_fifo_tlast;
wire [PORTS*AXIS_IF_TX_ID_WIDTH-1:0] axis_if_tx_fifo_tid;
wire [PORTS*AXIS_IF_TX_USER_WIDTH-1:0] axis_if_tx_fifo_tuser;

wire [RX_FIFO_DEPTH_WIDTH*PORTS-1:0]  tx_fifo_status_depth;



assign axis_if_tx_tdata = if_tx_axis_tdata;
assign axis_if_tx_tkeep = if_tx_axis_tkeep;
assign axis_if_tx_tvalid = if_tx_axis_tvalid;
assign if_tx_axis_tready = axis_if_tx_tready;
assign axis_if_tx_tlast = if_tx_axis_tlast;
assign axis_if_tx_tid = if_tx_axis_tid;
assign axis_if_tx_tdest = if_tx_axis_tdest;
assign axis_if_tx_tuser = if_tx_axis_tuser;


tx_fifo #(
    .FIFO_DEPTH(TX_FIFO_DEPTH),
    .FIFO_DEPTH_WIDTH(TX_FIFO_DEPTH_WIDTH),
    .PORTS(PORTS),
    .S_DATA_WIDTH(AXIS_IF_DATA_WIDTH),
    .S_KEEP_ENABLE(AXIS_IF_KEEP_WIDTH > 1),
    .S_KEEP_WIDTH(AXIS_IF_KEEP_WIDTH),
    .M_DATA_WIDTH(AXIS_SYNC_DATA_WIDTH),
    .M_KEEP_ENABLE(AXIS_SYNC_KEEP_WIDTH > 1),
    .M_KEEP_WIDTH(AXIS_SYNC_KEEP_WIDTH),
    .ID_ENABLE(1),
    .ID_WIDTH(AXIS_IF_TX_ID_WIDTH),
    .S_DEST_WIDTH(AXIS_IF_TX_DEST_WIDTH),
    .M_DEST_WIDTH(AXIS_IF_TX_DEST_WIDTH),
    .USER_ENABLE(1),
    .USER_WIDTH(AXIS_IF_TX_USER_WIDTH),
    .RAM_PIPELINE(AXIS_TX_FIFO_PIPELINE)
)
tx_fifo_inst (
    .clk(clk),
    .rst(rst),

    /*
     * AXI Stream input
     */
    .s_axis_tdata(axis_if_tx_tdata),
    .s_axis_tkeep(axis_if_tx_tkeep),
    .s_axis_tvalid(axis_if_tx_tvalid),
    .s_axis_tready(axis_if_tx_tready),
    .s_axis_tlast(axis_if_tx_tlast),
    .s_axis_tid(axis_if_tx_tid),
    .s_axis_tdest(axis_if_tx_tdest),
    .s_axis_tuser(axis_if_tx_tuser),

    /*
     * AXI Stream outputs
     */
    .m_axis_tdata(axis_if_tx_fifo_tdata),
    .m_axis_tkeep(axis_if_tx_fifo_tkeep),
    .m_axis_tvalid(axis_if_tx_fifo_tvalid),
    .m_axis_tready(axis_if_tx_fifo_tready),
    .m_axis_tlast(axis_if_tx_fifo_tlast),
    .m_axis_tid(axis_if_tx_fifo_tid),
    .m_axis_tdest(),
    .m_axis_tuser(axis_if_tx_fifo_tuser),

    /*
     * Status
     */
    .status_depth(tx_fifo_status_depth),
    .status_depth_commit(),
    .status_overflow(),
    .status_bad_frame(),
    .status_good_frame()
);

// RX FIFO

wire [PORTS*AXIS_SYNC_DATA_WIDTH-1:0] axis_if_rx_fifo_tdata;
wire [PORTS*AXIS_SYNC_KEEP_WIDTH-1:0] axis_if_rx_fifo_tkeep;
wire [PORTS-1:0] axis_if_rx_fifo_tvalid;
wire [PORTS-1:0] axis_if_rx_fifo_tready;
wire [PORTS-1:0] axis_if_rx_fifo_tlast;
wire [PORTS*AXIS_IF_RX_DEST_WIDTH-1:0] axis_if_rx_fifo_tdest = 0;
wire [PORTS*AXIS_IF_RX_USER_WIDTH-1:0] axis_if_rx_fifo_tuser;

wire [AXIS_IF_DATA_WIDTH-1:0] axis_if_rx_tdata;
wire [AXIS_IF_KEEP_WIDTH-1:0] axis_if_rx_tkeep;
wire axis_if_rx_tvalid;
wire axis_if_rx_tready;
wire axis_if_rx_tlast;
wire [AXIS_IF_RX_ID_WIDTH-1:0] axis_if_rx_tid;
wire [AXIS_IF_RX_DEST_WIDTH-1:0] axis_if_rx_tdest;
wire [AXIS_IF_RX_USER_WIDTH-1:0] axis_if_rx_tuser;

wire [RX_FIFO_DEPTH_WIDTH*PORTS-1:0]  rx_fifo_status_depth;

assign if_rx_axis_tdata = axis_if_rx_tdata;
assign if_rx_axis_tkeep = axis_if_rx_tkeep;
assign if_rx_axis_tvalid = axis_if_rx_tvalid;
assign axis_if_rx_tready = if_rx_axis_tready;
assign if_rx_axis_tlast = axis_if_rx_tlast;
assign if_rx_axis_tid = axis_if_rx_tid;
assign if_rx_axis_tdest = axis_if_rx_tdest;
assign if_rx_axis_tuser = axis_if_rx_tuser;

rx_fifo #(
    .FIFO_DEPTH(RX_FIFO_DEPTH),
    .FIFO_DEPTH_WIDTH(RX_FIFO_DEPTH_WIDTH),
    .PORTS(PORTS),
    .S_DATA_WIDTH(AXIS_SYNC_DATA_WIDTH),
    .S_KEEP_ENABLE(AXIS_SYNC_KEEP_WIDTH > 1),
    .S_KEEP_WIDTH(AXIS_SYNC_KEEP_WIDTH),
    .M_DATA_WIDTH(AXIS_IF_DATA_WIDTH),
    .M_KEEP_ENABLE(AXIS_IF_KEEP_WIDTH > 1),
    .M_KEEP_WIDTH(AXIS_IF_KEEP_WIDTH),
    .ID_ENABLE(1),
    .M_ID_WIDTH(AXIS_IF_RX_ID_WIDTH),
    .DEST_WIDTH(AXIS_IF_RX_DEST_WIDTH),
    .USER_ENABLE(1),
    .USER_WIDTH(AXIS_IF_RX_USER_WIDTH),
    .RAM_PIPELINE(AXIS_RX_FIFO_PIPELINE)
)
rx_fifo_inst (
    .clk(clk),
    .rst(rst),

    /*
     * AXI Stream input
     */
    .s_axis_tdata(axis_if_rx_fifo_tdata),
    .s_axis_tkeep(axis_if_rx_fifo_tkeep),
    .s_axis_tvalid(axis_if_rx_fifo_tvalid),
    .s_axis_tready(axis_if_rx_fifo_tready),
    .s_axis_tlast(axis_if_rx_fifo_tlast),
    .s_axis_tid(0),
    .s_axis_tdest(axis_if_rx_fifo_tdest),
    .s_axis_tuser(axis_if_rx_fifo_tuser),

    /*
     * AXI Stream outputs
     */
    .m_axis_tdata(axis_if_rx_tdata),
    .m_axis_tkeep(axis_if_rx_tkeep),
    .m_axis_tvalid(axis_if_rx_tvalid),
    .m_axis_tready(axis_if_rx_tready),
    .m_axis_tlast(axis_if_rx_tlast),
    .m_axis_tid(axis_if_rx_tid),
    .m_axis_tdest(axis_if_rx_tdest),
    .m_axis_tuser(axis_if_rx_tuser),

    /*
     * Status
     */
    .status_depth(rx_fifo_status_depth),
    .status_depth_commit(),
    .status_overflow(),
    .status_bad_frame(),
    .status_good_frame()
);





// control registers
wire [REG_ADDR_WIDTH-1:0]  ctrl_reg_wr_addr;
wire [REG_DATA_WIDTH-1:0]  ctrl_reg_wr_data;
wire [REG_STRB_WIDTH-1:0]  ctrl_reg_wr_strb;
wire                       ctrl_reg_wr_en;
wire                       ctrl_reg_wr_wait;
wire                       ctrl_reg_wr_ack;
wire [REG_ADDR_WIDTH-1:0]  ctrl_reg_rd_addr;
wire                       ctrl_reg_rd_en;
wire [REG_DATA_WIDTH-1:0]  ctrl_reg_rd_data;
wire                       ctrl_reg_rd_wait;
wire                       ctrl_reg_rd_ack;

axil_reg_if #(
    .DATA_WIDTH(REG_DATA_WIDTH),
    .ADDR_WIDTH(REG_ADDR_WIDTH),
    .STRB_WIDTH(REG_STRB_WIDTH),
    .TIMEOUT(4)
)
axil_reg_if_inst (
    .clk(clk),
    .rst(rst),

    /*
     * AXI-Lite slave interface
     */
    .s_axil_awaddr(axil_ctrl_awaddr),
    .s_axil_awprot(axil_ctrl_awprot),
    .s_axil_awvalid(axil_ctrl_awvalid),
    .s_axil_awready(axil_ctrl_awready),
    .s_axil_wdata(axil_ctrl_wdata),
    .s_axil_wstrb(axil_ctrl_wstrb),
    .s_axil_wvalid(axil_ctrl_wvalid),
    .s_axil_wready(axil_ctrl_wready),
    .s_axil_bresp(axil_ctrl_bresp),
    .s_axil_bvalid(axil_ctrl_bvalid),
    .s_axil_bready(axil_ctrl_bready),
    .s_axil_araddr(axil_ctrl_araddr),
    .s_axil_arprot(axil_ctrl_arprot),
    .s_axil_arvalid(axil_ctrl_arvalid),
    .s_axil_arready(axil_ctrl_arready),
    .s_axil_rdata(axil_ctrl_rdata),
    .s_axil_rresp(axil_ctrl_rresp),
    .s_axil_rvalid(axil_ctrl_rvalid),
    .s_axil_rready(axil_ctrl_rready),

    /*
     * Register interface
     */
    .reg_wr_addr(ctrl_reg_wr_addr),
    .reg_wr_data(ctrl_reg_wr_data),
    .reg_wr_strb(ctrl_reg_wr_strb),
    .reg_wr_en(ctrl_reg_wr_en),
    .reg_wr_wait(ctrl_reg_wr_wait),
    .reg_wr_ack(ctrl_reg_wr_ack),

    .reg_rd_addr(ctrl_reg_rd_addr),
    .reg_rd_en(ctrl_reg_rd_en),
    .reg_rd_data(ctrl_reg_rd_data),
    .reg_rd_wait(ctrl_reg_rd_wait),
    .reg_rd_ack(ctrl_reg_rd_ack)
);


reg ctrl_reg_wr_ack_reg = 1'b0;
reg [AXIL_DATA_WIDTH-1:0] ctrl_reg_rd_data_reg = {AXIL_DATA_WIDTH{1'b0}};
reg ctrl_reg_rd_ack_reg = 1'b0;

//todo
wire if_rx_ctrl_reg_wr_wait = 1'b0;
wire if_rx_ctrl_reg_wr_ack = 1'b0;
wire [AXIL_DATA_WIDTH-1:0] if_rx_ctrl_reg_rd_data = {AXIL_DATA_WIDTH{1'b0}};
wire if_rx_ctrl_reg_rd_wait = 1'b0;
wire if_rx_ctrl_reg_rd_ack = 1'b0;

wire port_ctrl_reg_wr_wait[PORTS-1:0];
wire port_ctrl_reg_wr_ack[PORTS-1:0];
wire [AXIL_DATA_WIDTH-1:0] port_ctrl_reg_rd_data[PORTS-1:0];
wire port_ctrl_reg_rd_wait[PORTS-1:0];
wire port_ctrl_reg_rd_ack[PORTS-1:0];

reg ctrl_reg_wr_wait_cmb;
reg ctrl_reg_wr_ack_cmb;
reg [AXIL_DATA_WIDTH-1:0] ctrl_reg_rd_data_cmb;
reg ctrl_reg_rd_wait_cmb;
reg ctrl_reg_rd_ack_cmb;

assign ctrl_reg_wr_wait = ctrl_reg_wr_wait_cmb;
assign ctrl_reg_wr_ack = ctrl_reg_wr_ack_cmb;

assign ctrl_reg_rd_data = ctrl_reg_rd_data_cmb;
assign ctrl_reg_rd_wait = ctrl_reg_rd_wait_cmb;
assign ctrl_reg_rd_ack = ctrl_reg_rd_ack_cmb;

integer k;

always @* begin
    ctrl_reg_wr_wait_cmb = if_rx_ctrl_reg_wr_wait;
    ctrl_reg_wr_ack_cmb = ctrl_reg_wr_ack_reg | if_rx_ctrl_reg_wr_ack;
    ctrl_reg_rd_data_cmb = ctrl_reg_rd_data_reg | if_rx_ctrl_reg_rd_data;
    ctrl_reg_rd_wait_cmb = if_rx_ctrl_reg_rd_wait;
    ctrl_reg_rd_ack_cmb = ctrl_reg_rd_ack_reg | if_rx_ctrl_reg_rd_ack;

    // for (k = 0; k < SCHEDULERS; k = k + 1) begin
    //     ctrl_reg_wr_wait_cmb = ctrl_reg_wr_wait_cmb | sched_ctrl_reg_wr_wait[k];
    //     ctrl_reg_wr_ack_cmb = ctrl_reg_wr_ack_cmb | sched_ctrl_reg_wr_ack[k];
    //     ctrl_reg_rd_data_cmb = ctrl_reg_rd_data_cmb | sched_ctrl_reg_rd_data[k];
    //     ctrl_reg_rd_wait_cmb = ctrl_reg_rd_wait_cmb | sched_ctrl_reg_rd_wait[k];
    //     ctrl_reg_rd_ack_cmb = ctrl_reg_rd_ack_cmb | sched_ctrl_reg_rd_ack[k];
    // end

    for (k = 0; k < PORTS; k = k + 1) begin
        ctrl_reg_wr_wait_cmb = ctrl_reg_wr_wait_cmb | port_ctrl_reg_wr_wait[k];
        ctrl_reg_wr_ack_cmb = ctrl_reg_wr_ack_cmb | port_ctrl_reg_wr_ack[k];
        ctrl_reg_rd_data_cmb = ctrl_reg_rd_data_cmb | port_ctrl_reg_rd_data[k];
        ctrl_reg_rd_wait_cmb = ctrl_reg_rd_wait_cmb | port_ctrl_reg_rd_wait[k];
        ctrl_reg_rd_ack_cmb = ctrl_reg_rd_ack_cmb | port_ctrl_reg_rd_ack[k];
    end
end


reg [DMA_CLIENT_LEN_WIDTH-1:0] tx_mtu_reg = MAX_TX_SIZE;
reg [DMA_CLIENT_LEN_WIDTH-1:0] rx_mtu_reg = MAX_RX_SIZE;

always @(posedge clk) begin
    ctrl_reg_wr_ack_reg <= 1'b0;
    ctrl_reg_rd_data_reg <= {AXIL_DATA_WIDTH{1'b0}};
    ctrl_reg_rd_ack_reg <= 1'b0;

    if (ctrl_reg_wr_en && !ctrl_reg_wr_ack_reg) begin
        // write operation
        ctrl_reg_wr_ack_reg <= 1'b1;
        case ({ctrl_reg_wr_addr >> 2, 2'b00})
            // Interface control
            RBB+8'h28: tx_mtu_reg <= ctrl_reg_wr_data;                      // IF ctrl: TX MTU
            RBB+8'h2C: rx_mtu_reg <= ctrl_reg_wr_data;                      // IF ctrl: RX MTU
            default: ctrl_reg_wr_ack_reg <= 1'b0;
        endcase
    end

    if (ctrl_reg_rd_en && !ctrl_reg_rd_ack_reg) begin
        // read operation
        ctrl_reg_rd_ack_reg <= 1'b1;
        case ({ctrl_reg_rd_addr >> 2, 2'b00})
            // Interface control
            RBB+8'h00: ctrl_reg_rd_data_reg <= 32'h0000C001;                // IF ctrl: Type
            RBB+8'h04: ctrl_reg_rd_data_reg <= 32'h00000400;                // IF ctrl: Version
            RBB+8'h08: ctrl_reg_rd_data_reg <= RB_BASE_ADDR+8'h40;          // IF ctrl: Next header
            RBB+8'h0C: begin
                // IF ctrl: features
                ctrl_reg_rd_data_reg[0] <= RX_HASH_ENABLE;
                ctrl_reg_rd_data_reg[4] <= PTP_TS_ENABLE;
                ctrl_reg_rd_data_reg[8] <= TX_CHECKSUM_ENABLE;
                ctrl_reg_rd_data_reg[9] <= RX_CHECKSUM_ENABLE;
                ctrl_reg_rd_data_reg[10] <= RX_HASH_ENABLE;
                ctrl_reg_rd_data_reg[11] <= LFC_ENABLE;
                ctrl_reg_rd_data_reg[12] <= PFC_ENABLE;
            end
            RBB+8'h10: ctrl_reg_rd_data_reg <= PORTS;                       // IF ctrl: Port count
            RBB+8'h14: ctrl_reg_rd_data_reg <= SCHEDULERS;                  // IF ctrl: Scheduler count
            RBB+8'h20: ctrl_reg_rd_data_reg <= MAX_TX_SIZE;                 // IF ctrl: Max TX MTU
            RBB+8'h24: ctrl_reg_rd_data_reg <= MAX_RX_SIZE;                 // IF ctrl: Max RX MTU
            RBB+8'h28: ctrl_reg_rd_data_reg <= tx_mtu_reg;                  // IF ctrl: TX MTU
            RBB+8'h2C: ctrl_reg_rd_data_reg <= rx_mtu_reg;                  // IF ctrl: RX MTU
            RBB+8'h30: ctrl_reg_rd_data_reg <= TX_FIFO_DEPTH;               // IF ctrl: TX FIFO depth
            RBB+8'h34: ctrl_reg_rd_data_reg <= RX_FIFO_DEPTH;               // IF ctrl: RX FIFO depth
            // Event queue manager
            RBB+8'h40: ctrl_reg_rd_data_reg <= 32'h0000C010;                // Event QM: Type
            RBB+8'h44: ctrl_reg_rd_data_reg <= 32'h00000400;                // Event QM: Version
            RBB+8'h48: ctrl_reg_rd_data_reg <= RB_BASE_ADDR+8'h60;          // Event QM: Next header
            RBB+8'h4C: ctrl_reg_rd_data_reg <= AXIL_EQM_BASE_ADDR;          // Event QM: Offset
            RBB+8'h50: ctrl_reg_rd_data_reg <= 2**EQN_WIDTH;                // Event QM: Count
            RBB+8'h54: ctrl_reg_rd_data_reg <= 16;                          // Event QM: Stride
            // Completion queue manager
            RBB+8'h60: ctrl_reg_rd_data_reg <= 32'h0000C020;                // CPL QM: Type
            RBB+8'h64: ctrl_reg_rd_data_reg <= 32'h00000400;                // CPL QM: Version
            RBB+8'h68: ctrl_reg_rd_data_reg <= RB_BASE_ADDR+8'h80;          // CPL QM: Next header
            RBB+8'h6C: ctrl_reg_rd_data_reg <= AXIL_CQM_BASE_ADDR;          // CPL QM: Offset
            RBB+8'h70: ctrl_reg_rd_data_reg <= 2**CQN_WIDTH;                // CPL QM: Count
            RBB+8'h74: ctrl_reg_rd_data_reg <= 16;                          // CPL QM: Stride
            // Queue manager (TX)
            RBB+8'h80: ctrl_reg_rd_data_reg <= 32'h0000C030;                // TX QM: Type
            RBB+8'h84: ctrl_reg_rd_data_reg <= 32'h00000400;                // TX QM: Version
            RBB+8'h88: ctrl_reg_rd_data_reg <= RB_BASE_ADDR+8'hA0;          // TX QM: Next header
            RBB+8'h8C: ctrl_reg_rd_data_reg <= AXIL_TX_QM_BASE_ADDR;        // TX QM: Offset
            RBB+8'h90: ctrl_reg_rd_data_reg <= 2**TX_QUEUE_INDEX_WIDTH;     // TX QM: Count
            RBB+8'h94: ctrl_reg_rd_data_reg <= 32;                          // TX QM: Stride
            // Queue manager (RX)
            RBB+8'hA0: ctrl_reg_rd_data_reg <= 32'h0000C031;                // RX QM: Type
            RBB+8'hA4: ctrl_reg_rd_data_reg <= 32'h00000400;                // RX QM: Version
            RBB+8'hA8: ctrl_reg_rd_data_reg <= RX_RB_BASE_ADDR;             // RX QM: Next header
            RBB+8'hAC: ctrl_reg_rd_data_reg <= AXIL_RX_QM_BASE_ADDR;        // RX QM: Offset
            RBB+8'hB0: ctrl_reg_rd_data_reg <= 2**RX_QUEUE_INDEX_WIDTH;     // RX QM: Count
            RBB+8'hB4: ctrl_reg_rd_data_reg <= 32;                          // RX QM: Stride
            default: ctrl_reg_rd_ack_reg <= 1'b0;
        endcase
    end

    if (rst) begin
        ctrl_reg_wr_ack_reg <= 1'b0;
        ctrl_reg_rd_ack_reg <= 1'b0;

        tx_mtu_reg <= MAX_TX_SIZE;
        rx_mtu_reg <= MAX_RX_SIZE;
    end
end


generate
genvar n;

for (n = 0; n < PORTS; n = n + 1) begin : port
    mqnic_port #(
        // PTP configuration
        .PTP_TS_WIDTH(PTP_TS_WIDTH),

        // Interface configuration
        .PTP_TS_ENABLE(PTP_TS_ENABLE),
        .TX_CPL_ENABLE(TX_CPL_ENABLE),
        .TX_CPL_FIFO_DEPTH(TX_CPL_FIFO_DEPTH),
        .TX_TAG_WIDTH(TX_TAG_WIDTH),
        .PFC_ENABLE(PFC_ENABLE),
        .LFC_ENABLE(LFC_ENABLE),
        .MAC_CTRL_ENABLE(MAC_CTRL_ENABLE),
        .TX_FIFO_DEPTH(TX_FIFO_DEPTH),
        .RX_FIFO_DEPTH(RX_FIFO_DEPTH),
        .TX_FIFO_DEPTH_WIDTH(TX_FIFO_DEPTH_WIDTH),
        .RX_FIFO_DEPTH_WIDTH(RX_FIFO_DEPTH_WIDTH),
        .MAX_TX_SIZE(MAX_TX_SIZE),
        .MAX_RX_SIZE(MAX_RX_SIZE),

        // Application block configuration
        .APP_AXIS_DIRECT_ENABLE(0),
        .APP_AXIS_SYNC_ENABLE(0),

        // Register interface configuration
        .REG_ADDR_WIDTH(AXIL_CTRL_ADDR_WIDTH),
        .REG_DATA_WIDTH(AXIL_DATA_WIDTH),
        .REG_STRB_WIDTH(AXIL_STRB_WIDTH),
        .RB_BASE_ADDR(PORT_RB_BASE_ADDR + PORT_RB_STRIDE*n),
        .RB_NEXT_PTR(n < PORTS-1 ? PORT_RB_BASE_ADDR + PORT_RB_STRIDE*(n+1) : SCHED_RB_BASE_ADDR),

        // Streaming interface configuration
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .AXIS_TX_USER_WIDTH(AXIS_TX_USER_WIDTH),
        .AXIS_RX_USER_WIDTH(AXIS_RX_USER_WIDTH),
        .AXIS_RX_USE_READY(AXIS_RX_USE_READY),
        .AXIS_TX_PIPELINE(AXIS_TX_PIPELINE),
        .AXIS_TX_FIFO_PIPELINE(AXIS_TX_FIFO_PIPELINE),
        .AXIS_TX_TS_PIPELINE(AXIS_TX_TS_PIPELINE),
        .AXIS_RX_PIPELINE(AXIS_RX_PIPELINE),
        .AXIS_RX_FIFO_PIPELINE(AXIS_RX_FIFO_PIPELINE),
        .AXIS_SYNC_DATA_WIDTH(AXIS_SYNC_DATA_WIDTH),
        .AXIS_SYNC_KEEP_WIDTH(AXIS_SYNC_KEEP_WIDTH),
        .AXIS_SYNC_TX_USER_WIDTH(AXIS_SYNC_TX_USER_WIDTH),
        .AXIS_SYNC_RX_USER_WIDTH(AXIS_SYNC_RX_USER_WIDTH)
    )
    port_inst (
        .clk(clk),
        .rst(rst),

        /*
         * Control register interface
         */
        .ctrl_reg_wr_addr(ctrl_reg_wr_addr),
        .ctrl_reg_wr_data(ctrl_reg_wr_data),
        .ctrl_reg_wr_strb(ctrl_reg_wr_strb),
        .ctrl_reg_wr_en(ctrl_reg_wr_en),
        .ctrl_reg_wr_wait(port_ctrl_reg_wr_wait[n]),
        .ctrl_reg_wr_ack(port_ctrl_reg_wr_ack[n]),
        .ctrl_reg_rd_addr(ctrl_reg_rd_addr),
        .ctrl_reg_rd_en(ctrl_reg_rd_en),
        .ctrl_reg_rd_data(port_ctrl_reg_rd_data[n]),
        .ctrl_reg_rd_wait(port_ctrl_reg_rd_wait[n]),
        .ctrl_reg_rd_ack(port_ctrl_reg_rd_ack[n]),

        //Transmit data from interface FIFO
        .s_axis_if_tx_tdata(axis_if_tx_fifo_tdata[n*AXIS_SYNC_DATA_WIDTH +: AXIS_SYNC_DATA_WIDTH]),
        .s_axis_if_tx_tkeep(axis_if_tx_fifo_tkeep[n*AXIS_SYNC_KEEP_WIDTH +: AXIS_SYNC_KEEP_WIDTH]),
        .s_axis_if_tx_tvalid(axis_if_tx_fifo_tvalid[n +: 1]),
        .s_axis_if_tx_tready(axis_if_tx_fifo_tready[n +: 1]),
        .s_axis_if_tx_tlast(axis_if_tx_fifo_tlast[n +: 1]),
        .s_axis_if_tx_tuser(axis_if_tx_fifo_tuser[n*AXIS_TX_USER_WIDTH +: AXIS_TX_USER_WIDTH]),

        .m_axis_if_tx_cpl_ts(axis_if_tx_cpl_ts[n*PTP_TS_WIDTH +: PTP_TS_WIDTH]),
        .m_axis_if_tx_cpl_tag(axis_if_tx_cpl_tag[n*TX_TAG_WIDTH +: TX_TAG_WIDTH]),
        .m_axis_if_tx_cpl_valid(axis_if_tx_cpl_valid[n +: 1]),
        .m_axis_if_tx_cpl_ready(axis_if_tx_cpl_ready[n +: 1]),

        // Receive data to interface FIFO
        .m_axis_if_rx_tdata(axis_if_rx_fifo_tdata[n*AXIS_SYNC_DATA_WIDTH +: AXIS_SYNC_DATA_WIDTH]),
        .m_axis_if_rx_tkeep(axis_if_rx_fifo_tkeep[n*AXIS_SYNC_KEEP_WIDTH +: AXIS_SYNC_KEEP_WIDTH]),
        .m_axis_if_rx_tvalid(axis_if_rx_fifo_tvalid[n +: 1]),
        .m_axis_if_rx_tready(axis_if_rx_fifo_tready[n +: 1]),
        .m_axis_if_rx_tlast(axis_if_rx_fifo_tlast[n +: 1]),
        .m_axis_if_rx_tuser(axis_if_rx_fifo_tuser[n*AXIS_SYNC_RX_USER_WIDTH +: AXIS_SYNC_RX_USER_WIDTH]),


        // 将所有 app_sync 和 app_direct 接口悬空
        .m_axis_app_sync_tx_tdata(),
        .m_axis_app_sync_tx_tkeep(),
        .m_axis_app_sync_tx_tvalid(),
        .m_axis_app_sync_tx_tready(),
        .m_axis_app_sync_tx_tlast(),
        .m_axis_app_sync_tx_tuser(),

        .s_axis_app_sync_tx_tdata(),
        .s_axis_app_sync_tx_tkeep(),
        .s_axis_app_sync_tx_tvalid(),
        .s_axis_app_sync_tx_tready(),
        .s_axis_app_sync_tx_tlast(),
        .s_axis_app_sync_tx_tuser(),

        .m_axis_app_sync_tx_cpl_ts(),
        .m_axis_app_sync_tx_cpl_tag(),
        .m_axis_app_sync_tx_cpl_valid(),
        .m_axis_app_sync_tx_cpl_ready(),

        .s_axis_app_sync_tx_cpl_ts(),
        .s_axis_app_sync_tx_cpl_tag(),
        .s_axis_app_sync_tx_cpl_valid(),
        .s_axis_app_sync_tx_cpl_ready(),

        .m_axis_app_sync_rx_tdata(),
        .m_axis_app_sync_rx_tkeep(),
        .m_axis_app_sync_rx_tvalid(),
        .m_axis_app_sync_rx_tready(),
        .m_axis_app_sync_rx_tlast(),
        .m_axis_app_sync_rx_tuser(),

        .s_axis_app_sync_rx_tdata(),
        .s_axis_app_sync_rx_tkeep(),
        .s_axis_app_sync_rx_tvalid(),
        .s_axis_app_sync_rx_tready(),
        .s_axis_app_sync_rx_tlast(),
        .s_axis_app_sync_rx_tuser(),

        .m_axis_app_direct_tx_tdata(),
        .m_axis_app_direct_tx_tkeep(),
        .m_axis_app_direct_tx_tvalid(),
        .m_axis_app_direct_tx_tready(),
        .m_axis_app_direct_tx_tlast(),
        .m_axis_app_direct_tx_tuser(),

        .s_axis_app_direct_tx_tdata(),
        .s_axis_app_direct_tx_tkeep(),
        .s_axis_app_direct_tx_tvalid(),
        .s_axis_app_direct_tx_tready(),
        .s_axis_app_direct_tx_tlast(),
        .s_axis_app_direct_tx_tuser(),

        .m_axis_app_direct_tx_cpl_ts(),
        .m_axis_app_direct_tx_cpl_tag(),
        .m_axis_app_direct_tx_cpl_valid(),
        .m_axis_app_direct_tx_cpl_ready(),

        .s_axis_app_direct_tx_cpl_ts(),
        .s_axis_app_direct_tx_cpl_tag(),
        .s_axis_app_direct_tx_cpl_valid(),
        .s_axis_app_direct_tx_cpl_ready(),

        .m_axis_app_direct_rx_tdata(),
        .m_axis_app_direct_rx_tkeep(),
        .m_axis_app_direct_rx_tvalid(),
        .m_axis_app_direct_rx_tready(),
        .m_axis_app_direct_rx_tlast(),
        .m_axis_app_direct_rx_tuser(),

        .s_axis_app_direct_rx_tdata(),
        .s_axis_app_direct_rx_tkeep(),
        .s_axis_app_direct_rx_tvalid(),
        .s_axis_app_direct_rx_tready(),
        .s_axis_app_direct_rx_tlast(),
        .s_axis_app_direct_rx_tuser(),


        /*
         * Transmit data output
         */
        .tx_clk(tx_clk[n +: 1]),
        .tx_rst(tx_rst[n +: 1]),

        .m_axis_tx_tdata(m_axis_tx_tdata[n*AXIS_DATA_WIDTH +: AXIS_DATA_WIDTH]),
        .m_axis_tx_tkeep(m_axis_tx_tkeep[n*AXIS_KEEP_WIDTH +: AXIS_KEEP_WIDTH]),
        .m_axis_tx_tvalid(m_axis_tx_tvalid[n +: 1]),
        .m_axis_tx_tready(m_axis_tx_tready[n +: 1]),
        .m_axis_tx_tlast(m_axis_tx_tlast[n +: 1]),
        .m_axis_tx_tuser(m_axis_tx_tuser[n*AXIS_TX_USER_WIDTH +: AXIS_TX_USER_WIDTH]),

        .s_axis_tx_cpl_ts(s_axis_tx_cpl_ts[n*PTP_TS_WIDTH +: PTP_TS_WIDTH]),
        .s_axis_tx_cpl_tag(s_axis_tx_cpl_tag[n*TX_TAG_WIDTH +: TX_TAG_WIDTH]),
        .s_axis_tx_cpl_valid(s_axis_tx_cpl_valid[n +: 1]),
        .s_axis_tx_cpl_ready(s_axis_tx_cpl_ready[n +: 1]),

        .tx_enable(tx_enable[n +: 1]),
        .tx_status(tx_status[n +: 1]),
        .tx_lfc_en(tx_lfc_en[n +: 1]),
        .tx_lfc_req(tx_lfc_req[n +: 1]),
        .tx_pfc_en(tx_pfc_en[n*8 +: 8]),
        .tx_pfc_req(tx_pfc_req[n*8 +: 8]),
        .tx_fc_quanta_clk_en(tx_fc_quanta_clk_en[n +: 1]),

        .tx_fifo_status_depth(tx_fifo_status_depth[n*TX_FIFO_DEPTH_WIDTH +: TX_FIFO_DEPTH_WIDTH]),

        /*
         * Receive data input
         */
        .rx_clk(rx_clk[n +: 1]),
        .rx_rst(rx_rst[n +: 1]),

        .s_axis_rx_tdata(s_axis_rx_tdata[n*AXIS_DATA_WIDTH +: AXIS_DATA_WIDTH]),
        .s_axis_rx_tkeep(s_axis_rx_tkeep[n*AXIS_KEEP_WIDTH +: AXIS_KEEP_WIDTH]),
        .s_axis_rx_tvalid(s_axis_rx_tvalid[n +: 1]),
        .s_axis_rx_tready(s_axis_rx_tready[n +: 1]),
        .s_axis_rx_tlast(s_axis_rx_tlast[n +: 1]),
        .s_axis_rx_tuser(s_axis_rx_tuser[n*AXIS_RX_USER_WIDTH +: AXIS_RX_USER_WIDTH]),

        .rx_enable(rx_enable[n +: 1]),
        .rx_status(rx_status[n +: 1]),
        .rx_lfc_en(rx_lfc_en[n +: 1]),
        .rx_lfc_req(rx_lfc_req[n +: 1]),
        .rx_lfc_ack(rx_lfc_ack[n +: 1]),
        .rx_pfc_en(rx_pfc_en[n*8 +: 8]),
        .rx_pfc_req(rx_pfc_req[n*8 +: 8]),
        .rx_pfc_ack(rx_pfc_ack[n*8 +: 8]),
        .rx_fc_quanta_clk_en(rx_fc_quanta_clk_en[n +: 1]),

        .rx_fifo_status_depth(rx_fifo_status_depth[n*RX_FIFO_DEPTH_WIDTH +: RX_FIFO_DEPTH_WIDTH])
    );
    
end

endgenerate


endmodule