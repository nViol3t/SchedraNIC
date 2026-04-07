// SPDX-License-Identifier: BSD-2-Clause-Views
/*
 * Copyright (c) 2019-2023 The Regents of the University of California
 */

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * Queue manager
 */
module tx_queue_manager_change #
(
    // Base address width
    parameter ADDR_WIDTH = 64,
    // Request tag field width
    parameter REQ_TAG_WIDTH = 8,
    // Number of outstanding operations
    parameter OP_TABLE_SIZE = 16,
    // Operation tag field width
    parameter OP_TAG_WIDTH = 8,
    // Queue index width (log2 of number of queues)
    parameter QUEUE_INDEX_WIDTH = 11,
    // Completion queue index width
    parameter CPL_INDEX_WIDTH = 8,
    // Queue element pointer width (log2 of number of elements)
    parameter QUEUE_PTR_WIDTH = 16,
    // Log queue size field width
    parameter LOG_QUEUE_SIZE_WIDTH = $clog2(QUEUE_PTR_WIDTH),
    // Queue element size
    parameter DESC_SIZE = 16,
    // Log desc block size field width
    parameter LOG_BLOCK_SIZE_WIDTH = 2,
    // Pipeline stages
    parameter PIPELINE = 2,
    // Width of AXI lite data bus in bits
    parameter AXIL_DATA_WIDTH = 32,
    // Width of AXI lite address bus in bits
    parameter AXIL_ADDR_WIDTH = QUEUE_INDEX_WIDTH+5,
    // Width of AXI lite wstrb (width of data bus in words)
    parameter AXIL_STRB_WIDTH = (AXIL_DATA_WIDTH/8),
    //rank
    parameter RANK_WIDTH = 13,
    //wqe
    parameter WQE_WIDTH = 3,

    parameter DOORBELL_DEPTH      = 256,

    parameter DOORBELL_IDX_WIDTH  = $clog2(DOORBELL_DEPTH),

    parameter DOORBELL_PTR_WIDTH  = DOORBELL_IDX_WIDTH + 1
)
(
    input  wire                            clk,
    input  wire                            rst,

    /*
     * Dequeue request input
     */
    input  wire [QUEUE_INDEX_WIDTH-1:0]    s_axis_dequeue_req_queue,
    input  wire [WQE_WIDTH-1:0]            s_axis_dequeue_req_wqe,
    input  wire [REQ_TAG_WIDTH-1:0]        s_axis_dequeue_req_tag,
    input  wire                            s_axis_dequeue_req_valid,
    output wire                            s_axis_dequeue_req_ready,

    /*
     * Dequeue response output
     */
    output wire [QUEUE_INDEX_WIDTH-1:0]    m_axis_dequeue_resp_queue,
    output wire [QUEUE_PTR_WIDTH-1:0]      m_axis_dequeue_resp_ptr,
    output wire                            m_axis_dequeue_resp_phase,
    output wire [ADDR_WIDTH-1:0]           m_axis_dequeue_resp_addr,
    output wire [LOG_BLOCK_SIZE_WIDTH-1:0] m_axis_dequeue_resp_block_size,
    output wire [CPL_INDEX_WIDTH-1:0]      m_axis_dequeue_resp_cpl,
    output wire [REQ_TAG_WIDTH-1:0]        m_axis_dequeue_resp_tag,
    output wire [OP_TAG_WIDTH-1:0]         m_axis_dequeue_resp_op_tag,
    output wire                            m_axis_dequeue_resp_empty,
    output wire                            m_axis_dequeue_resp_error,
    output wire                            m_axis_dequeue_resp_valid,
    input  wire                            m_axis_dequeue_resp_ready,
    output wire [WQE_WIDTH-1:0]            m_axis_dequeue_resp_wqe,

    /*
     * Dequeue commit input
     */
    input  wire [OP_TAG_WIDTH-1:0]         s_axis_dequeue_commit_op_tag,
    input  wire                            s_axis_dequeue_commit_valid,
    output wire                            s_axis_dequeue_commit_ready,

    /*
     * Doorbell output
     */
    output wire [QUEUE_INDEX_WIDTH-1:0]    m_axis_doorbell_queue,
    output wire [DOORBELL_PTR_WIDTH-1:0]   m_axis_doorbell_tag,
    output wire [RANK_WIDTH-1:0]           m_axis_doorbell_rank,
    output wire [WQE_WIDTH-1:0]            m_axis_doorbell_wqe,
    output wire                            m_axis_doorbell_valid,
    input  wire                            m_axis_doorbell_ready,

    /*
     * Pifo Complete input
     */
    input  wire[QUEUE_INDEX_WIDTH-1:0]     s_axis_pifo_comp_queue,
    input  wire [DOORBELL_PTR_WIDTH-1:0]   s_axis_pifo_comp_tag,
    input  wire                            s_axis_pifo_comp_valid,

    /*
     * AXI-Lite slave interface
     */
    input  wire [AXIL_ADDR_WIDTH-1:0]      s_axil_awaddr,
    input  wire [2:0]                      s_axil_awprot,
    input  wire                            s_axil_awvalid,
    output wire                            s_axil_awready,
    input  wire [AXIL_DATA_WIDTH-1:0]      s_axil_wdata,
    input  wire [AXIL_STRB_WIDTH-1:0]      s_axil_wstrb,
    input  wire                            s_axil_wvalid,
    output wire                            s_axil_wready,
    output wire [1:0]                      s_axil_bresp,
    output wire                            s_axil_bvalid,
    input  wire                            s_axil_bready,
    input  wire [AXIL_ADDR_WIDTH-1:0]      s_axil_araddr,
    input  wire [2:0]                      s_axil_arprot,
    input  wire                            s_axil_arvalid,
    output wire                            s_axil_arready,
    output wire [AXIL_DATA_WIDTH-1:0]      s_axil_rdata,
    output wire [1:0]                      s_axil_rresp,
    output wire                            s_axil_rvalid,
    input  wire                            s_axil_rready,

    /*
     * Configuration
     */
    input  wire                            enable
);

parameter QUEUE_COUNT = 2**QUEUE_INDEX_WIDTH;

parameter CL_OP_TABLE_SIZE = $clog2(OP_TABLE_SIZE);

parameter CL_DESC_SIZE = $clog2(DESC_SIZE);

parameter QUEUE_RAM_BE_WIDTH = 16;
parameter QUEUE_RAM_WIDTH = QUEUE_RAM_BE_WIDTH*8;

parameter DOORBELL_RAM_WIDTH = RANK_WIDTH+WQE_WIDTH;



// parameter FIFO_DEPTH = 32;

// bus width assertions
initial begin
    if (OP_TAG_WIDTH < CL_OP_TABLE_SIZE) begin
        $error("Error: OP_TAG_WIDTH insufficient for OP_TABLE_SIZE (instance %m)");
        $finish;
    end

    if (AXIL_DATA_WIDTH != 32) begin
        $error("Error: AXI lite interface width must be 32 (instance %m)");
        $finish;
    end

    if (AXIL_STRB_WIDTH * 8 != AXIL_DATA_WIDTH) begin
        $error("Error: AXI lite interface requires byte (8-bit) granularity (instance %m)");
        $finish;
    end

    if (AXIL_ADDR_WIDTH < QUEUE_INDEX_WIDTH+5) begin
        $error("Error: AXI lite address width too narrow (instance %m)");
        $finish;
    end

    if (2**$clog2(DESC_SIZE) != DESC_SIZE) begin
        $error("Error: Descriptor size must be even power of two (instance %m)");
        $finish;
    end

    if (PIPELINE < 2) begin
        $error("Error: PIPELINE must be at least 2 (instance %m)");
        $finish;
    end
end

reg op_axil_write_pipe_hazard;
reg op_axil_read_pipe_hazard;
reg op_doorbell_pipe_hazard;//dyc add
reg op_req_pipe_hazard;
reg op_commit_pipe_hazard;
reg stage_active;

reg [PIPELINE-1:0] op_axil_write_pipe_reg = {PIPELINE{1'b0}}, op_axil_write_pipe_next;
reg [PIPELINE-1:0] op_axil_read_pipe_reg = {PIPELINE{1'b0}}, op_axil_read_pipe_next;
reg [PIPELINE-1:0] op_doorbell_pipe_reg = {PIPELINE{1'b0}}, op_doorbell_pipe_next;//dyc add
reg [PIPELINE-1:0] op_req_pipe_reg = {PIPELINE{1'b0}}, op_req_pipe_next;
reg [PIPELINE-1:0] op_commit_pipe_reg = {PIPELINE{1'b0}}, op_commit_pipe_next;

reg [QUEUE_INDEX_WIDTH-1:0] queue_ram_addr_pipeline_reg[PIPELINE-1:0], queue_ram_addr_pipeline_next[PIPELINE-1:0];
reg [2:0] axil_reg_pipeline_reg[PIPELINE-1:0], axil_reg_pipeline_next[PIPELINE-1:0];
reg [AXIL_DATA_WIDTH-1:0] write_data_pipeline_reg[PIPELINE-1:0], write_data_pipeline_next[PIPELINE-1:0];
reg [AXIL_STRB_WIDTH-1:0] write_strobe_pipeline_reg[PIPELINE-1:0], write_strobe_pipeline_next[PIPELINE-1:0];
reg [REQ_TAG_WIDTH-1:0] req_tag_pipeline_reg[PIPELINE-1:0], req_tag_pipeline_next[PIPELINE-1:0];
reg [WQE_WIDTH-1:0] req_wqe_pipeline_reg[PIPELINE-1:0], req_wqe_pipeline_next[PIPELINE-1:0];

reg s_axis_dequeue_req_ready_reg = 1'b0, s_axis_dequeue_req_ready_next;

reg [QUEUE_INDEX_WIDTH-1:0] m_axis_dequeue_resp_queue_reg = 0, m_axis_dequeue_resp_queue_next;
reg [QUEUE_PTR_WIDTH-1:0] m_axis_dequeue_resp_ptr_reg = 0, m_axis_dequeue_resp_ptr_next;
reg m_axis_dequeue_resp_phase_reg = 0, m_axis_dequeue_resp_phase_next;
reg [ADDR_WIDTH-1:0] m_axis_dequeue_resp_addr_reg = 0, m_axis_dequeue_resp_addr_next;
reg [LOG_BLOCK_SIZE_WIDTH-1:0] m_axis_dequeue_resp_block_size_reg = 0, m_axis_dequeue_resp_block_size_next;
reg [CPL_INDEX_WIDTH-1:0] m_axis_dequeue_resp_cpl_reg = 0, m_axis_dequeue_resp_cpl_next;
reg [REQ_TAG_WIDTH-1:0] m_axis_dequeue_resp_tag_reg = 0, m_axis_dequeue_resp_tag_next;
reg [OP_TAG_WIDTH-1:0] m_axis_dequeue_resp_op_tag_reg = 0, m_axis_dequeue_resp_op_tag_next;
reg m_axis_dequeue_resp_empty_reg = 1'b0, m_axis_dequeue_resp_empty_next;
reg m_axis_dequeue_resp_error_reg = 1'b0, m_axis_dequeue_resp_error_next;
reg m_axis_dequeue_resp_valid_reg = 1'b0, m_axis_dequeue_resp_valid_next;
reg [WQE_WIDTH-1:0] m_axis_dequeue_resp_wqe_reg = 0 , m_axis_dequeue_resp_wqe_next;

reg s_axis_dequeue_commit_ready_reg = 1'b0, s_axis_dequeue_commit_ready_next;

reg s_axil_awready_reg = 0, s_axil_awready_next;
reg s_axil_wready_reg = 0, s_axil_wready_next;
reg s_axil_bvalid_reg = 0, s_axil_bvalid_next;
reg s_axil_arready_reg = 0, s_axil_arready_next;
reg [AXIL_DATA_WIDTH-1:0] s_axil_rdata_reg = 0, s_axil_rdata_next;
reg s_axil_rvalid_reg = 0, s_axil_rvalid_next;

reg [QUEUE_INDEX_WIDTH-1:0] queue_ram_read_ptr;
reg [QUEUE_INDEX_WIDTH-1:0] queue_ram_write_ptr;
reg [QUEUE_RAM_WIDTH-1:0] queue_ram_write_data;
reg queue_ram_wr_en;
reg [QUEUE_RAM_BE_WIDTH-1:0] queue_ram_be;
reg [QUEUE_RAM_WIDTH-1:0] queue_ram_read_data_pipeline_reg[PIPELINE-1:1];

wire [QUEUE_RAM_WIDTH-1:0] queue_ram_read_data_wire;
wire [QUEUE_PTR_WIDTH-1:0] queue_ram_read_data_prod_ptr = queue_ram_read_data_pipeline_reg[PIPELINE-1][15:0];
wire [QUEUE_PTR_WIDTH-1:0] queue_ram_read_data_cons_ptr = queue_ram_read_data_pipeline_reg[PIPELINE-1][31:16];
wire [CPL_INDEX_WIDTH-1:0] queue_ram_read_data_cpl_queue = queue_ram_read_data_pipeline_reg[PIPELINE-1][47:32];
wire [LOG_QUEUE_SIZE_WIDTH-1:0] queue_ram_read_data_log_queue_size = queue_ram_read_data_pipeline_reg[PIPELINE-1][51:48];
wire [LOG_BLOCK_SIZE_WIDTH-1:0] queue_ram_read_data_log_block_size = queue_ram_read_data_pipeline_reg[PIPELINE-1][53:52];
wire queue_ram_read_data_enable = queue_ram_read_data_pipeline_reg[PIPELINE-1][55];
wire [CL_OP_TABLE_SIZE-1:0] queue_ram_read_data_op_index = queue_ram_read_data_pipeline_reg[PIPELINE-1][63:56];
wire [ADDR_WIDTH-1:0] queue_ram_read_data_base_addr = {queue_ram_read_data_pipeline_reg[PIPELINE-1][127:76], 12'd0};

reg [OP_TABLE_SIZE-1:0] op_table_active = 0;
reg [OP_TABLE_SIZE-1:0] op_table_commit = 0;
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg [QUEUE_INDEX_WIDTH-1:0] op_table_queue[OP_TABLE_SIZE-1:0];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg [QUEUE_PTR_WIDTH-1:0] op_table_queue_ptr[OP_TABLE_SIZE-1:0];
reg [CL_OP_TABLE_SIZE-1:0] op_table_start_ptr_reg = 0;
reg [QUEUE_INDEX_WIDTH-1:0] op_table_start_queue;
reg [QUEUE_PTR_WIDTH-1:0] op_table_start_queue_ptr;
reg op_table_start_en;
reg [CL_OP_TABLE_SIZE-1:0] op_table_commit_ptr;
reg op_table_commit_en;
reg [CL_OP_TABLE_SIZE-1:0] op_table_finish_ptr_reg = 0;
reg op_table_finish_en;

reg [DOORBELL_PTR_WIDTH-1:0] doorbell_prod_ptr[QUEUE_COUNT-1:0];
reg [DOORBELL_PTR_WIDTH-1:0] doorbell_cons_ptr[QUEUE_COUNT-1:0];


reg [DOORBELL_RAM_WIDTH-1:0] doorbell_ram_write_data;

reg doorbell_ram_wr_en,doorbell_addr_prod_ram_wr_en,doorbell_addr_cons_ram_wr_en;

reg [DOORBELL_RAM_WIDTH-1:0] doorbell_ram_read_data_pipeline_reg[PIPELINE-1:1];

wire [RANK_WIDTH-1:0] ram_rank_data = doorbell_ram_read_data_pipeline_reg[PIPELINE-1][15:3];//15:3
wire [WQE_WIDTH-1:0] ram_wqe_data = doorbell_ram_read_data_pipeline_reg[PIPELINE-1][2:0];//2:0
wire [DOORBELL_RAM_WIDTH-1:0] doorbell_ram_read_data_wire;


assign s_axis_dequeue_req_ready = s_axis_dequeue_req_ready_reg;

assign m_axis_dequeue_resp_queue = m_axis_dequeue_resp_queue_reg;
assign m_axis_dequeue_resp_ptr = m_axis_dequeue_resp_ptr_reg;
assign m_axis_dequeue_resp_phase = m_axis_dequeue_resp_phase_reg;
assign m_axis_dequeue_resp_addr = m_axis_dequeue_resp_addr_reg;
assign m_axis_dequeue_resp_block_size = m_axis_dequeue_resp_block_size_reg;
assign m_axis_dequeue_resp_cpl = m_axis_dequeue_resp_cpl_reg;
assign m_axis_dequeue_resp_tag = m_axis_dequeue_resp_tag_reg;
assign m_axis_dequeue_resp_op_tag = m_axis_dequeue_resp_op_tag_reg;
assign m_axis_dequeue_resp_empty = m_axis_dequeue_resp_empty_reg;
assign m_axis_dequeue_resp_error = m_axis_dequeue_resp_error_reg;
assign m_axis_dequeue_resp_valid = m_axis_dequeue_resp_valid_reg;
assign m_axis_dequeue_resp_wqe = m_axis_dequeue_resp_wqe_reg;

assign s_axis_dequeue_commit_ready = s_axis_dequeue_commit_ready_reg;

assign s_axil_awready = s_axil_awready_reg;
assign s_axil_wready = s_axil_wready_reg;
assign s_axil_bresp = 2'b00;
assign s_axil_bvalid = s_axil_bvalid_reg;
assign s_axil_arready = s_axil_arready_reg;
assign s_axil_rdata = s_axil_rdata_reg;
assign s_axil_rresp = 2'b00;
assign s_axil_rvalid = s_axil_rvalid_reg;

wire [QUEUE_INDEX_WIDTH-1:0] s_axil_awaddr_queue = s_axil_awaddr >> 5;
wire [2:0] s_axil_awaddr_reg = s_axil_awaddr >> 2;
wire [QUEUE_INDEX_WIDTH-1:0] s_axil_araddr_queue = s_axil_araddr >> 5;
wire [2:0] s_axil_araddr_reg = s_axil_araddr >> 2;

wire queue_active = op_table_active[queue_ram_read_data_op_index] && op_table_queue[queue_ram_read_data_op_index] == queue_ram_addr_pipeline_reg[PIPELINE-1];
wire queue_empty_idle = queue_ram_read_data_prod_ptr == queue_ram_read_data_cons_ptr;
wire queue_empty_active = queue_ram_read_data_prod_ptr == op_table_queue_ptr[queue_ram_read_data_op_index];
wire queue_empty = queue_active ? queue_empty_active : queue_empty_idle;
wire [QUEUE_PTR_WIDTH-1:0] queue_ram_read_active_cons_ptr = queue_active ? op_table_queue_ptr[queue_ram_read_data_op_index] : queue_ram_read_data_cons_ptr;


reg [DOORBELL_PTR_WIDTH-1:0] doorbell_addr_prod_ram_write_data,doorbell_addr_cons_ram_write_data;

reg [DOORBELL_PTR_WIDTH-1:0] doorbell_addr_prod_ram_read_data_pipeline_reg[PIPELINE-1:1];
reg [DOORBELL_PTR_WIDTH-1:0] doorbell_addr_cons_ram_read_data_pipeline_reg[PIPELINE-1:1];

wire [DOORBELL_IDX_WIDTH-1:0] db_prod_idx = doorbell_addr_prod_ram_read_data_pipeline_reg[PIPELINE-1][DOORBELL_IDX_WIDTH-1:0];
wire [DOORBELL_IDX_WIDTH-1:0] db_cons_idx = doorbell_addr_cons_ram_read_data_pipeline_reg[PIPELINE-1][DOORBELL_IDX_WIDTH-1:0];

wire [DOORBELL_PTR_WIDTH-1:0] db_prod_tag = doorbell_addr_prod_ram_read_data_pipeline_reg[PIPELINE-1];
wire [DOORBELL_PTR_WIDTH-1:0] db_cons_tag = doorbell_addr_cons_ram_read_data_pipeline_reg[PIPELINE-1];

wire db_prod_high = doorbell_addr_prod_ram_read_data_pipeline_reg[PIPELINE-1][DOORBELL_PTR_WIDTH-1];
wire db_cons_high = doorbell_addr_cons_ram_read_data_pipeline_reg[PIPELINE-1][DOORBELL_PTR_WIDTH-1];

wire doorbell_empty_idle = (db_prod_tag == db_cons_tag);
wire doorbell_full = (db_prod_high != db_cons_high)
                    && (db_prod_idx == db_cons_idx);

wire [DOORBELL_PTR_WIDTH-1:0] doorbell_addr_prod_ram_read_data_wire;
wire [DOORBELL_PTR_WIDTH-1:0] doorbell_addr_cons_ram_read_data_wire;

reg [QUEUE_INDEX_WIDTH+DOORBELL_IDX_WIDTH-1:0] doorbell_ram_write_ptr;
reg [QUEUE_INDEX_WIDTH+DOORBELL_IDX_WIDTH-1:0] doorbell_ram_read_ptr;



RAM_Simple_Dual_Port_byte #(
    .WORD_WIDTH(QUEUE_RAM_WIDTH),
    .BYTE_ENABLE_WIDTH(QUEUE_RAM_BE_WIDTH),
    .ADDR_WIDTH(QUEUE_INDEX_WIDTH),
    .DEPTH(QUEUE_COUNT),
    .RAMSTYLE("block"),

    .READ_NEW_DATA(0),  
    .INIT_VALUE({QUEUE_RAM_WIDTH{1'b0}})
) queue_ram_inst (
    .clock(clk),
    .wren(queue_ram_wr_en),
    .write_addr(queue_ram_write_ptr),
    .write_data(queue_ram_write_data),
    .byte_enable(queue_ram_be),
    .rden(1'b1), 
    .read_addr(queue_ram_read_ptr),
    .read_data(queue_ram_read_data_wire) 
);

RAM_Simple_Dual_Port #(
    .WORD_WIDTH(DOORBELL_RAM_WIDTH),
    .ADDR_WIDTH(QUEUE_INDEX_WIDTH + DOORBELL_IDX_WIDTH),
    .DEPTH(QUEUE_COUNT * DOORBELL_DEPTH),
    .RAMSTYLE("block"),


    .READ_NEW_DATA(0),  
    .INIT_VALUE({DOORBELL_RAM_WIDTH{1'b0}})

) doorbell_ram_inst (
    .clock(clk),
    .wren(doorbell_ram_wr_en),
    .write_addr(doorbell_ram_write_ptr),
    .write_data(doorbell_ram_write_data),

    .rden(1), 
    .read_addr(doorbell_ram_read_ptr),
    .read_data(doorbell_ram_read_data_wire) 
);

RAM_Simple_Dual_Port #(
    .WORD_WIDTH(DOORBELL_PTR_WIDTH),
    .ADDR_WIDTH(QUEUE_INDEX_WIDTH),
    .DEPTH(QUEUE_COUNT),
    .RAMSTYLE("distributed"),
    .READ_NEW_DATA(0),  
    .INIT_VALUE({DOORBELL_PTR_WIDTH{1'b0}})

) doorbell_addr_prod_ram_inst (
    .clock(clk),
    .wren(doorbell_addr_prod_ram_wr_en),
    .write_addr(queue_ram_write_ptr),
    .write_data(doorbell_addr_prod_ram_write_data),
    .rden(1), 
    .read_addr(queue_ram_read_ptr),
    .read_data(doorbell_addr_prod_ram_read_data_wire) 
);

RAM_Simple_Dual_Port #(
    .WORD_WIDTH(DOORBELL_PTR_WIDTH),
    .ADDR_WIDTH(QUEUE_INDEX_WIDTH),
    .DEPTH(QUEUE_COUNT),
    .RAMSTYLE("distributed"),
    .READ_NEW_DATA(0),  
    .INIT_VALUE({DOORBELL_PTR_WIDTH{1'b0}})

) doorbell_addr_cons_ram_inst (
    .clock(clk),
    .wren(doorbell_addr_cons_ram_wr_en),
    .write_addr(queue_ram_write_ptr),
    .write_data(doorbell_addr_cons_ram_write_data),

    .rden(1), 
    .read_addr(queue_ram_read_ptr),
    .read_data(doorbell_addr_cons_ram_read_data_wire) 
);



wire [QUEUE_INDEX_WIDTH-1:0] s_axis_doorbell_fifo_queue;
wire [DOORBELL_PTR_WIDTH-1:0] s_axis_doorbell_fifo_tag;
wire s_axis_doorbell_fifo_valid;
reg s_axis_doorbell_fifo_ready;

axis_fifo #(
    .DEPTH(256),
    .DATA_WIDTH(QUEUE_INDEX_WIDTH+DOORBELL_PTR_WIDTH),
    .KEEP_ENABLE(0),
    .KEEP_WIDTH(1),
    .OUTPUT_FIFO_ENABLE(0),
    .LAST_ENABLE(0),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(0),
    .FRAME_FIFO(0)
)
pifo_comp_fifo (
    .clk(clk),
    .rst(rst),

    // AXI input
    .s_axis_tdata({s_axis_pifo_comp_queue,s_axis_pifo_comp_tag}),
    .s_axis_tkeep(0),
    .s_axis_tvalid(s_axis_pifo_comp_valid),
    .s_axis_tready(),//s_axis_pifo_comp_ready
    .s_axis_tlast(0),
    .s_axis_tid(0),
    .s_axis_tdest(0),
    .s_axis_tuser(0),

    // AXI output
    .m_axis_tdata({s_axis_doorbell_fifo_queue,s_axis_doorbell_fifo_tag}),
    .m_axis_tkeep(),
    .m_axis_tvalid(s_axis_doorbell_fifo_valid),
    .m_axis_tready(s_axis_doorbell_fifo_ready),
    .m_axis_tlast(),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(),

    // Status
    .status_overflow(),
    .status_bad_frame(),
    .status_good_frame()
);


reg [QUEUE_INDEX_WIDTH-1:0] doorbell_fifo_input_queue;
reg [DOORBELL_PTR_WIDTH-1:0] doorbell_fifo_input_tag;
reg [RANK_WIDTH-1:0] doorbell_fifo_input_rank;
reg [WQE_WIDTH-1:0] doorbell_fifo_input_wqe;
reg doorbell_fifo_input_valid;
wire doorbell_fifo_input_ready;


wire [QUEUE_INDEX_WIDTH-1:0] doorbell_fifo_output_queue;
wire [DOORBELL_PTR_WIDTH-1:0] doorbell_fifo_output_tag;
wire [RANK_WIDTH-1:0] doorbell_fifo_output_rank;
wire [WQE_WIDTH-1:0] doorbell_fifo_output_wqe;
wire doorbell_fifo_output_valid;
wire doorbell_fifo_output_ready;//

axis_fifo #(
    .DEPTH(256),
    .DATA_WIDTH(QUEUE_INDEX_WIDTH+DOORBELL_PTR_WIDTH+RANK_WIDTH+WQE_WIDTH),
    .KEEP_ENABLE(0),
    .KEEP_WIDTH(1),
    .OUTPUT_FIFO_ENABLE(1),
    .LAST_ENABLE(0),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(0),
    .FRAME_FIFO(0)
)
doorbell_fifo (
    .clk(clk),
    .rst(rst),

    // AXI input
    .s_axis_tdata({doorbell_fifo_input_queue,doorbell_fifo_input_tag,doorbell_fifo_input_rank,doorbell_fifo_input_wqe}),//todo 
    .s_axis_tkeep(0),
    .s_axis_tvalid(doorbell_fifo_input_valid),
    .s_axis_tready(doorbell_fifo_input_ready),
    .s_axis_tlast(0),
    .s_axis_tid(0),
    .s_axis_tdest(0),
    .s_axis_tuser(0),

    // AXI output
    .m_axis_tdata({doorbell_fifo_output_queue,doorbell_fifo_output_tag,doorbell_fifo_output_rank,doorbell_fifo_output_wqe}),
    .m_axis_tkeep(),
    .m_axis_tvalid(doorbell_fifo_output_valid),
    .m_axis_tready(doorbell_fifo_output_ready),
    .m_axis_tlast(),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(),

    // Status
    .status_overflow(),
    .status_bad_frame(),
    .status_good_frame()
);

reg [QUEUE_INDEX_WIDTH-1:0] queue_fifo_input_queue;
reg [DOORBELL_PTR_WIDTH-1:0] quque_fifo_input_tag;
reg [RANK_WIDTH-1:0] queue_fifo_input_rank;
reg [WQE_WIDTH-1:0] queue_fifo_input_wqe;
reg queue_fifo_input_valid;
wire queue_fifo_input_ready;

wire [QUEUE_INDEX_WIDTH-1:0] queue_fifo_output_queue;
wire [DOORBELL_PTR_WIDTH-1:0] quque_fifo_output_tag;
wire [RANK_WIDTH-1:0] queue_fifo_output_rank;
wire [WQE_WIDTH-1:0] queue_fifo_output_wqe;
wire queue_fifo_output_valid;
wire queue_fifo_output_ready;

axis_fifo #(
    .DEPTH(256),
    .DATA_WIDTH(QUEUE_INDEX_WIDTH+DOORBELL_PTR_WIDTH+RANK_WIDTH+WQE_WIDTH),
    .KEEP_ENABLE(0),
    .KEEP_WIDTH(1),
    .OUTPUT_FIFO_ENABLE(1),
    .LAST_ENABLE(0),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(0),
    .FRAME_FIFO(0)
)
queue_fifo (
    .clk(clk),
    .rst(rst),

    // AXI input
    .s_axis_tdata({queue_fifo_input_queue,quque_fifo_input_tag,queue_fifo_input_rank,queue_fifo_input_wqe}),
    .s_axis_tkeep(0),
    .s_axis_tvalid(queue_fifo_input_valid),
    .s_axis_tready(queue_fifo_input_ready),
    .s_axis_tlast(0),
    .s_axis_tid(0),
    .s_axis_tdest(0),
    .s_axis_tuser(0),

    // AXI output
    .m_axis_tdata({queue_fifo_output_queue,quque_fifo_output_tag,queue_fifo_output_rank,queue_fifo_output_wqe}),
    .m_axis_tkeep(),
    .m_axis_tvalid(queue_fifo_output_valid),
    .m_axis_tready(queue_fifo_output_ready),
    .m_axis_tlast(),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(),

    // Status
    .status_overflow(),
    .status_bad_frame(),
    .status_good_frame()
);

axis_arb_mux #(
    .S_COUNT(2),
    .DATA_WIDTH(QUEUE_INDEX_WIDTH+DOORBELL_PTR_WIDTH+RANK_WIDTH+WQE_WIDTH),
    .KEEP_ENABLE(0),
    .LAST_ENABLE(0),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(0),
    .ARB_TYPE_ROUND_ROBIN(0),       // 不轮询
    .ARB_LSB_HIGH_PRIORITY(1)       // 通道0优先
)
axis_arb_mux_inst (
    .clk(clk),
    .rst(rst),

    .s_axis_tdata({{queue_fifo_output_queue,quque_fifo_output_tag,queue_fifo_output_rank,queue_fifo_output_wqe}, {doorbell_fifo_output_queue,doorbell_fifo_output_tag,doorbell_fifo_output_rank,doorbell_fifo_output_wqe}}),
    .s_axis_tvalid({queue_fifo_output_valid,doorbell_fifo_output_valid}),
    .s_axis_tready({queue_fifo_output_ready,doorbell_fifo_output_ready}),

    .m_axis_tdata({m_axis_doorbell_queue,m_axis_doorbell_tag,m_axis_doorbell_rank,m_axis_doorbell_wqe}),
    .m_axis_tvalid(m_axis_doorbell_valid),
    .m_axis_tready(m_axis_doorbell_ready)
    
);


integer i, j;

initial begin

    for (i = 0; i < PIPELINE; i = i + 1) begin
        queue_ram_addr_pipeline_reg[i] = 0;
        axil_reg_pipeline_reg[i] = 0;
        write_data_pipeline_reg[i] = 0;
        write_strobe_pipeline_reg[i] = 0;
        req_tag_pipeline_reg[i] = 0;
        req_wqe_pipeline_reg[i] = 0;
    end

    for (i = 0; i < OP_TABLE_SIZE; i = i + 1) begin
        op_table_queue[i] = 0;
        op_table_queue_ptr[i] = 0;
    end


    // $dumpfile("mqnic_core_pcie_us.fst");
    // $dumpvars(0, doorbell_prod_ptr[0]);

end


always @* begin
    op_axil_write_pipe_next = {op_axil_write_pipe_reg, 1'b0};
    op_axil_read_pipe_next = {op_axil_read_pipe_reg, 1'b0};
    op_doorbell_pipe_next = {op_doorbell_pipe_reg, 1'b0};//dyc add
    op_req_pipe_next = {op_req_pipe_reg, 1'b0};
    op_commit_pipe_next = {op_commit_pipe_reg, 1'b0};

    queue_ram_addr_pipeline_next[0] = 0;
    axil_reg_pipeline_next[0] = 0;
    write_data_pipeline_next[0] = 0;
    write_strobe_pipeline_next[0] = 0;
    req_tag_pipeline_next[0] = 0;
    req_wqe_pipeline_next[0] = 0;
    
    for (j = 1; j < PIPELINE; j = j + 1) begin
        queue_ram_addr_pipeline_next[j] = queue_ram_addr_pipeline_reg[j-1];
        axil_reg_pipeline_next[j] = axil_reg_pipeline_reg[j-1];
        write_data_pipeline_next[j] = write_data_pipeline_reg[j-1];
        write_strobe_pipeline_next[j] = write_strobe_pipeline_reg[j-1];
        req_tag_pipeline_next[j] = req_tag_pipeline_reg[j-1];
        req_wqe_pipeline_next[j] = req_wqe_pipeline_reg[j-1];
    end

    s_axis_dequeue_req_ready_next = 1'b0;

    m_axis_dequeue_resp_queue_next = m_axis_dequeue_resp_queue_reg;
    m_axis_dequeue_resp_ptr_next = m_axis_dequeue_resp_ptr_reg;
    m_axis_dequeue_resp_phase_next = m_axis_dequeue_resp_phase_reg;
    m_axis_dequeue_resp_addr_next = m_axis_dequeue_resp_addr_reg;
    m_axis_dequeue_resp_block_size_next = m_axis_dequeue_resp_block_size_reg;
    m_axis_dequeue_resp_cpl_next = m_axis_dequeue_resp_cpl_reg;
    m_axis_dequeue_resp_tag_next = m_axis_dequeue_resp_tag_reg;
    m_axis_dequeue_resp_op_tag_next = m_axis_dequeue_resp_op_tag_reg;
    m_axis_dequeue_resp_empty_next = m_axis_dequeue_resp_empty_reg;
    m_axis_dequeue_resp_error_next = m_axis_dequeue_resp_error_reg;
    m_axis_dequeue_resp_valid_next = m_axis_dequeue_resp_valid_reg && !m_axis_dequeue_resp_ready;
    m_axis_dequeue_resp_wqe_next = m_axis_dequeue_resp_wqe_reg;

    s_axis_dequeue_commit_ready_next = 1'b0;

    s_axil_awready_next = 1'b0;
    s_axil_wready_next = 1'b0;
    s_axil_bvalid_next = s_axil_bvalid_reg && !s_axil_bready;

    s_axil_arready_next = 1'b0;
    s_axil_rdata_next = s_axil_rdata_reg;
    s_axil_rvalid_next = s_axil_rvalid_reg && !s_axil_rready;

    queue_ram_read_ptr = 0;
    queue_ram_write_ptr = queue_ram_addr_pipeline_reg[PIPELINE-1];
    queue_ram_write_data = queue_ram_read_data_pipeline_reg[PIPELINE-1];
    
    doorbell_ram_write_data = doorbell_ram_read_data_pipeline_reg[PIPELINE-1];
    doorbell_addr_prod_ram_write_data = doorbell_addr_prod_ram_read_data_pipeline_reg[PIPELINE-1];
    doorbell_addr_cons_ram_write_data = doorbell_addr_cons_ram_read_data_pipeline_reg[PIPELINE-1];
    doorbell_ram_read_ptr = 0;
    doorbell_ram_write_ptr = {queue_ram_write_ptr,db_prod_idx};


    queue_ram_wr_en = 0;
    queue_ram_be = 0;

    doorbell_ram_wr_en = 0;
    doorbell_addr_prod_ram_wr_en = 0;
    doorbell_addr_cons_ram_wr_en = 0;

    op_table_start_queue = queue_ram_addr_pipeline_reg[PIPELINE-1];
    op_table_start_queue_ptr = queue_ram_read_active_cons_ptr + 1;
    op_table_start_en = 1'b0;
    op_table_commit_ptr = s_axis_dequeue_commit_op_tag;
    op_table_commit_en = 1'b0;
    op_table_finish_en = 1'b0;

    s_axis_doorbell_fifo_ready = 1'b0;

    queue_fifo_input_queue = queue_ram_addr_pipeline_reg[PIPELINE-1];
    queue_fifo_input_valid = 1'b0;
    quque_fifo_input_tag = db_cons_tag;
    queue_fifo_input_rank = ram_rank_data;
    queue_fifo_input_wqe  = ram_wqe_data;

    doorbell_fifo_input_queue = queue_ram_addr_pipeline_reg[PIPELINE-1];
    doorbell_fifo_input_valid = 1'b0;

    doorbell_fifo_input_rank  = ram_rank_data;
    doorbell_fifo_input_wqe   = ram_wqe_data;
    

    op_axil_write_pipe_hazard = 1'b0;
    op_axil_read_pipe_hazard = 1'b0;
    op_doorbell_pipe_hazard = 1'b0;//dyc add
    op_req_pipe_hazard = 1'b0;
    op_commit_pipe_hazard = 1'b0;

    stage_active = 1'b0;

    

    for (j = 0; j < PIPELINE; j = j + 1) begin
        stage_active = op_axil_write_pipe_reg[j] || op_axil_read_pipe_reg[j] || op_doorbell_pipe_reg[j] || op_req_pipe_reg[j] || op_commit_pipe_reg[j];
        op_axil_write_pipe_hazard = op_axil_write_pipe_hazard || (stage_active && queue_ram_addr_pipeline_reg[j] == s_axil_awaddr_queue);
        op_axil_read_pipe_hazard = op_axil_read_pipe_hazard || (stage_active && queue_ram_addr_pipeline_reg[j] == s_axil_araddr_queue);
        op_doorbell_pipe_hazard = op_doorbell_pipe_hazard || (stage_active && queue_ram_addr_pipeline_reg[j] == s_axis_doorbell_fifo_queue);
        op_req_pipe_hazard = op_req_pipe_hazard || (stage_active && queue_ram_addr_pipeline_reg[j] == s_axis_dequeue_req_queue);
        op_commit_pipe_hazard = op_commit_pipe_hazard || (stage_active && queue_ram_addr_pipeline_reg[j] == op_table_queue[op_table_finish_ptr_reg]);
        
    end

    // pipeline stage 0 - receive request
    if (s_axil_awvalid && s_axil_wvalid && (!s_axil_bvalid || s_axil_bready) && !op_axil_write_pipe_reg && !op_axil_write_pipe_hazard) begin
        // AXIL write
        op_axil_write_pipe_next[0] = 1'b1;

        s_axil_awready_next = 1'b1;
        s_axil_wready_next = 1'b1;

        write_data_pipeline_next[0] = s_axil_wdata;
        write_strobe_pipeline_next[0] = s_axil_wstrb;

        queue_ram_read_ptr = s_axil_awaddr_queue;
        queue_ram_addr_pipeline_next[0] = s_axil_awaddr_queue;
        axil_reg_pipeline_next[0] = s_axil_awaddr_reg;
    end else if (s_axil_arvalid && (!s_axil_rvalid || s_axil_rready) && !op_axil_read_pipe_reg && !op_axil_read_pipe_hazard) begin
        // AXIL read
        op_axil_read_pipe_next[0] = 1'b1;

        s_axil_arready_next = 1'b1;

        queue_ram_read_ptr = s_axil_araddr_queue;

        queue_ram_addr_pipeline_next[0] = s_axil_araddr_queue;
        axil_reg_pipeline_next[0] = s_axil_araddr_reg;

    end else if (op_table_active[op_table_finish_ptr_reg] && op_table_commit[op_table_finish_ptr_reg] && !op_commit_pipe_reg[0] && !op_commit_pipe_hazard) begin
        // dequeue commit finalize (update pointer)
        op_commit_pipe_next[0] = 1'b1;

        op_table_finish_en = 1'b1;

        write_data_pipeline_next[0] = op_table_queue_ptr[op_table_finish_ptr_reg];

        queue_ram_read_ptr = op_table_queue[op_table_finish_ptr_reg];
        queue_ram_addr_pipeline_next[0] = op_table_queue[op_table_finish_ptr_reg];

        
    end else if (enable && !op_table_active[op_table_start_ptr_reg] && s_axis_dequeue_req_valid && (!m_axis_dequeue_resp_valid || m_axis_dequeue_resp_ready) && !op_req_pipe_reg && !op_req_pipe_hazard) begin
        // dequeue request
        op_req_pipe_next[0] = 1'b1;

        s_axis_dequeue_req_ready_next = 1'b1;

        req_tag_pipeline_next[0] = s_axis_dequeue_req_tag;

        queue_ram_read_ptr = s_axis_dequeue_req_queue;
        queue_ram_addr_pipeline_next[0] = s_axis_dequeue_req_queue;

        req_wqe_pipeline_next[0] = s_axis_dequeue_req_wqe;

    end else if (s_axis_doorbell_fifo_valid && !op_doorbell_pipe_hazard) begin
        // handle pifo doorbell
        op_doorbell_pipe_next[0] = 1'b1;
        s_axis_doorbell_fifo_ready = 1'b1;

        queue_ram_read_ptr = s_axis_doorbell_fifo_queue;
        doorbell_ram_read_ptr = {s_axis_doorbell_fifo_queue,s_axis_doorbell_fifo_tag[DOORBELL_IDX_WIDTH-1:0]+1'b1};

        queue_ram_addr_pipeline_next[0] = s_axis_doorbell_fifo_queue;
    
    end

    // read complete, perform operation
    if (op_req_pipe_reg[PIPELINE-1]) begin
        // request
        m_axis_dequeue_resp_queue_next = queue_ram_addr_pipeline_reg[PIPELINE-1];
        m_axis_dequeue_resp_ptr_next = queue_ram_read_active_cons_ptr;
        m_axis_dequeue_resp_phase_next = !queue_ram_read_active_cons_ptr[queue_ram_read_data_log_queue_size];
        m_axis_dequeue_resp_addr_next = queue_ram_read_data_base_addr + ((queue_ram_read_active_cons_ptr & ({QUEUE_PTR_WIDTH{1'b1}} >> (QUEUE_PTR_WIDTH - queue_ram_read_data_log_queue_size))) << (CL_DESC_SIZE+queue_ram_read_data_log_block_size));
        m_axis_dequeue_resp_block_size_next = queue_ram_read_data_log_block_size;
        m_axis_dequeue_resp_cpl_next = queue_ram_read_data_cpl_queue;
        m_axis_dequeue_resp_tag_next = req_tag_pipeline_reg[PIPELINE-1];
        m_axis_dequeue_resp_op_tag_next = op_table_start_ptr_reg;
        m_axis_dequeue_resp_empty_next = 1'b0;
        m_axis_dequeue_resp_error_next = 1'b0;
        m_axis_dequeue_resp_wqe_next = req_wqe_pipeline_reg[PIPELINE-1];

        queue_ram_write_ptr = queue_ram_addr_pipeline_reg[PIPELINE-1];
        queue_ram_write_data[63:56] = op_table_start_ptr_reg;
        queue_ram_wr_en = 1'b1;

        op_table_start_queue = queue_ram_addr_pipeline_reg[PIPELINE-1];
        op_table_start_queue_ptr = queue_ram_read_active_cons_ptr + req_wqe_pipeline_reg[PIPELINE-1];

        if (!queue_ram_read_data_enable) begin
            // queue inactive
            m_axis_dequeue_resp_error_next = 1'b1;
            m_axis_dequeue_resp_valid_next = 1'b1;
        end else if (queue_empty) begin
            // queue empty
            m_axis_dequeue_resp_empty_next = 1'b1;
            m_axis_dequeue_resp_valid_next = 1'b1;
        end else begin
            // start dequeue
            m_axis_dequeue_resp_valid_next = 1'b1;

            queue_ram_be[7] = 1'b1;

            op_table_start_en = 1'b1;
        end
    end else if (op_commit_pipe_reg[PIPELINE-1]) begin
        // commit

        // update consumer pointer
        queue_ram_write_ptr = queue_ram_addr_pipeline_reg[PIPELINE-1];
        queue_ram_write_data[31:16] = write_data_pipeline_reg[PIPELINE-1];

        queue_ram_be[3:2] = 2'b11;
        queue_ram_wr_en = 1'b1;
    end else if (op_doorbell_pipe_reg[PIPELINE-1]) begin
        // handle pifo doorbell
        queue_ram_write_ptr = queue_ram_addr_pipeline_reg[PIPELINE-1];
        doorbell_fifo_input_queue = queue_ram_addr_pipeline_reg[PIPELINE-1];
        doorbell_fifo_input_tag   = db_cons_tag + 1'b1;
        doorbell_fifo_input_rank  = ram_rank_data;
        doorbell_fifo_input_wqe   = ram_wqe_data;

        if((db_cons_tag + 1'b1) == db_prod_tag) begin    
            doorbell_fifo_input_valid = 1'b0;
        end else begin
            doorbell_fifo_input_valid = 1'b1;
        end
        
        doorbell_addr_cons_ram_write_data = db_cons_tag + 1'b1;
        doorbell_addr_cons_ram_wr_en = 1'b1;
    end else if (op_axil_write_pipe_reg[PIPELINE-1]) begin
        // AXIL write
        s_axil_bvalid_next = 1'b1;

        queue_ram_write_ptr = queue_ram_addr_pipeline_reg[PIPELINE-1];
        queue_ram_wr_en = 1'b1;

        // TODO parametrize
        case (axil_reg_pipeline_reg[PIPELINE-1])
            3'd0: begin
                // base address lower 32
                // base address is read-only when queue is active
                if (!queue_ram_read_data_enable) begin
                    queue_ram_write_data[95:76] = write_data_pipeline_reg[PIPELINE-1][31:12];
                    queue_ram_be[11:9] = write_strobe_pipeline_reg[PIPELINE-1][3:1];
                end
            end
            3'd1: begin
                // base address upper 32
                // base address is read-only when queue is active
                if (!queue_ram_read_data_enable) begin
                    queue_ram_write_data[127:96] = write_data_pipeline_reg[PIPELINE-1];
                    queue_ram_be[15:12] = write_strobe_pipeline_reg[PIPELINE-1];
                end
            end
            3'd2, 3'd3, 3'd4: begin
                casez (write_data_pipeline_reg[PIPELINE-1])
                    32'h8001zzzz: begin
                        // set VF ID
                        //TODO
                    end
                    32'h8002zzzz: begin
                        // set size
                        if (!queue_ram_read_data_enable) begin
                            // log queue size
                            queue_ram_write_data[51:48] = write_data_pipeline_reg[PIPELINE-1][7:0];
                            // log desc block size
                            queue_ram_write_data[53:52] = write_data_pipeline_reg[PIPELINE-1][15:8];
                            queue_ram_be[6] = 1'b1;
                        end
                    end
                    32'hC0zzzzzz: begin
                        // set CQN
                        if (!queue_ram_read_data_enable) begin
                            queue_ram_write_data[47:32] = write_data_pipeline_reg[PIPELINE-1][23:0];
                            queue_ram_be[5:4] = 2'b11;
                        end
                    end
                    32'h8080zzzz: begin
                        // set producer pointer
                        queue_ram_write_data[15:0] = write_data_pipeline_reg[PIPELINE-1][15:0];
                        queue_ram_be[1:0] = 2'b11;
                    end
                    32'h8090zzzz: begin
                        // set consumer pointer
                        if (!queue_ram_read_data_enable) begin
                            queue_ram_write_data[31:16] = write_data_pipeline_reg[PIPELINE-1][15:0];
                            queue_ram_be[3:2] = 2'b11;
                        end
                    end
                    32'h400001zz: begin
                        // set enable
                        queue_ram_write_data[55] = write_data_pipeline_reg[PIPELINE-1][0];
                        queue_ram_be[6] = 1'b1;
                    end
                    default: begin
                        // invalid command
                        $display("Error: Invalid command 0x%x for queue %d (instance %m)", write_data_pipeline_reg[PIPELINE-1], queue_ram_addr_pipeline_reg[PIPELINE-1]);
                    end
                endcase
            end
            3'd5: begin
                // set rank(13bit) & wqe(3bit)
                doorbell_ram_write_data = write_data_pipeline_reg[PIPELINE-1][15:0];
                doorbell_addr_prod_ram_write_data = db_prod_tag+1'b1;
                doorbell_ram_write_ptr = {queue_ram_write_ptr,db_prod_idx};
                if(!doorbell_full) begin
                    doorbell_ram_wr_en = 1'b1;
                    doorbell_addr_prod_ram_wr_en = 1'b1;
                end

                if(doorbell_empty_idle) begin //直接发送
                    queue_fifo_input_queue  = queue_ram_addr_pipeline_reg[PIPELINE-1];
                    quque_fifo_input_tag    = db_prod_tag;
                    queue_fifo_input_rank   = write_data_pipeline_reg[PIPELINE-1][15:3];
                    queue_fifo_input_wqe    = write_data_pipeline_reg[PIPELINE-1][2:0];
                    queue_fifo_input_valid  = 1'b1;
                end 


            end
        endcase
    end else if (op_axil_read_pipe_reg[PIPELINE-1]) begin
        // AXIL read
        s_axil_rvalid_next = 1'b1;
        s_axil_rdata_next = 0;

        // TODO parametrize
        case (axil_reg_pipeline_reg[PIPELINE-1])
            3'd0: begin
                // VF ID
                s_axil_rdata_next[11:0] = 0; // TODO
                // base address lower 32
                s_axil_rdata_next[31:12] = queue_ram_read_data_base_addr[31:12];
            end
            3'd1: begin
                // base address upper 32
                s_axil_rdata_next = queue_ram_read_data_base_addr[63:32];
            end
            3'd2: begin
                // control/status
                // enable
                s_axil_rdata_next[0] = queue_ram_read_data_enable;
                // active
                s_axil_rdata_next[3] = queue_active;
            end
            3'd3: begin
                // config
                // CQN
                s_axil_rdata_next[23:0] = queue_ram_read_data_cpl_queue;
                // log queue size
                s_axil_rdata_next[27:24] = queue_ram_read_data_log_queue_size;
                // log desc block size
                s_axil_rdata_next[31:28] = queue_ram_read_data_log_block_size;
            end
            3'd4: begin
                // producer pointer
                s_axil_rdata_next[15:0] = queue_ram_read_data_prod_ptr;
                // consumer pointer
                s_axil_rdata_next[31:16] = queue_ram_read_data_cons_ptr;
            end
            3'd5: begin
                // producer pointer
                // s_axil_rdata_next[3:0] = doorbell_prod_ptr[queue_ram_addr_pipeline_reg[PIPELINE-1]][DOORBELL_IDX_WIDTH-1:0];
                // // consumer pointer
                // s_axil_rdata_next[7:4] = doorbell_cons_ptr[queue_ram_addr_pipeline_reg[PIPELINE-1]][DOORBELL_IDX_WIDTH-1:0];
            end
        endcase
    end

    // dequeue commit (record in table)
    s_axis_dequeue_commit_ready_next = enable;
    if (s_axis_dequeue_commit_ready && s_axis_dequeue_commit_valid) begin
        op_table_commit_ptr = s_axis_dequeue_commit_op_tag;
        op_table_commit_en = 1'b1;
    end
end

always @(posedge clk) begin
    if (rst) begin//todo
        op_axil_write_pipe_reg <= {PIPELINE{1'b0}};
        op_axil_read_pipe_reg <= {PIPELINE{1'b0}};
        op_doorbell_pipe_reg <= {PIPELINE{1'b0}};//dyc add
        op_req_pipe_reg <= {PIPELINE{1'b0}};
        op_commit_pipe_reg <= {PIPELINE{1'b0}};

        s_axis_dequeue_req_ready_reg <= 1'b0;
        m_axis_dequeue_resp_valid_reg <= 1'b0;
        s_axis_dequeue_commit_ready_reg <= 1'b0;

        s_axil_awready_reg <= 1'b0;
        s_axil_wready_reg <= 1'b0;
        s_axil_bvalid_reg <= 1'b0;
        s_axil_arready_reg <= 1'b0;
        s_axil_rvalid_reg <= 1'b0;

        op_table_active <= 0;

        op_table_start_ptr_reg <= 0;
        op_table_finish_ptr_reg <= 0;
    end else begin
        op_axil_write_pipe_reg <= op_axil_write_pipe_next;
        op_axil_read_pipe_reg <= op_axil_read_pipe_next;
        op_doorbell_pipe_reg <= op_doorbell_pipe_next;//dyc add

        op_req_pipe_reg <= op_req_pipe_next;
        op_commit_pipe_reg <= op_commit_pipe_next;

        s_axis_dequeue_req_ready_reg <= s_axis_dequeue_req_ready_next;
        m_axis_dequeue_resp_valid_reg <= m_axis_dequeue_resp_valid_next;
        s_axis_dequeue_commit_ready_reg <= s_axis_dequeue_commit_ready_next;

        s_axil_awready_reg <= s_axil_awready_next;
        s_axil_wready_reg <= s_axil_wready_next;
        s_axil_bvalid_reg <= s_axil_bvalid_next;
        s_axil_arready_reg <= s_axil_arready_next;
        s_axil_rvalid_reg <= s_axil_rvalid_next;

        if (op_table_start_en) begin
            op_table_start_ptr_reg <= op_table_start_ptr_reg + 1;
            op_table_active[op_table_start_ptr_reg] <= 1'b1;
        end
        if (op_table_finish_en) begin
            op_table_finish_ptr_reg <= op_table_finish_ptr_reg + 1;
            op_table_active[op_table_finish_ptr_reg] <= 1'b0;
        end
    end

    for (i = 0; i < PIPELINE; i = i + 1) begin
        queue_ram_addr_pipeline_reg[i] <= queue_ram_addr_pipeline_next[i];
        axil_reg_pipeline_reg[i] <= axil_reg_pipeline_next[i];
        write_data_pipeline_reg[i] <= write_data_pipeline_next[i];
        write_strobe_pipeline_reg[i] <= write_strobe_pipeline_next[i];
        req_tag_pipeline_reg[i] <= req_tag_pipeline_next[i];
        req_wqe_pipeline_reg[i] <= req_wqe_pipeline_next[i];
    end

    m_axis_dequeue_resp_queue_reg <= m_axis_dequeue_resp_queue_next;
    m_axis_dequeue_resp_ptr_reg <= m_axis_dequeue_resp_ptr_next;
    m_axis_dequeue_resp_phase_reg <= m_axis_dequeue_resp_phase_next;
    m_axis_dequeue_resp_addr_reg <= m_axis_dequeue_resp_addr_next;
    m_axis_dequeue_resp_block_size_reg <= m_axis_dequeue_resp_block_size_next;
    m_axis_dequeue_resp_cpl_reg <= m_axis_dequeue_resp_cpl_next;
    m_axis_dequeue_resp_tag_reg <= m_axis_dequeue_resp_tag_next;
    m_axis_dequeue_resp_op_tag_reg <= m_axis_dequeue_resp_op_tag_next;
    m_axis_dequeue_resp_empty_reg <= m_axis_dequeue_resp_empty_next;
    m_axis_dequeue_resp_error_reg <= m_axis_dequeue_resp_error_next;
    m_axis_dequeue_resp_wqe_reg <= m_axis_dequeue_resp_wqe_next;

    s_axil_rdata_reg <= s_axil_rdata_next;
    
    queue_ram_read_data_pipeline_reg[1] <= queue_ram_read_data_wire;
    doorbell_ram_read_data_pipeline_reg[1] <= doorbell_ram_read_data_wire;
    doorbell_addr_prod_ram_read_data_pipeline_reg[1] <= doorbell_addr_prod_ram_read_data_wire;
    doorbell_addr_cons_ram_read_data_pipeline_reg[1] <= doorbell_addr_cons_ram_read_data_wire;
    for (i = 2; i < PIPELINE; i = i + 1) begin
        queue_ram_read_data_pipeline_reg[i] <= queue_ram_read_data_pipeline_reg[i-1];
        doorbell_ram_read_data_pipeline_reg[i] <= doorbell_ram_read_data_pipeline_reg[i-1];
        doorbell_addr_prod_ram_read_data_pipeline_reg[i] <= doorbell_addr_prod_ram_read_data_pipeline_reg[i-1];
        doorbell_addr_cons_ram_read_data_pipeline_reg[i] <= doorbell_addr_cons_ram_read_data_pipeline_reg[i-1];
    end

    if (op_table_start_en) begin
        op_table_commit[op_table_start_ptr_reg] <= 1'b0;
        op_table_queue[op_table_start_ptr_reg] <= op_table_start_queue;
        op_table_queue_ptr[op_table_start_ptr_reg] <= op_table_start_queue_ptr;
    end
    if (op_table_commit_en) begin
        op_table_commit[op_table_commit_ptr] <= 1'b1;
    end


end

endmodule

`resetall
