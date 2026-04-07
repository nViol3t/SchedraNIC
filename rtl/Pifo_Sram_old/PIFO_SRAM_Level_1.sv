module PIFO_SRAM_Level_1#(
   parameter PTW = 16   ,// RANK WIDTH,优先级位宽
   parameter MTW = 32   ,// Meta Data WIDTH,数据位宽
   parameter CTW = 10   ,// COUNT WIDTH,计数器位宽
   //Don't Touch
   parameter SINGLE_DATA_WIDTH                       = PTW + MTW + CTW              ,//每个条目包含：优先级(PTW) + 元数据(MTW) + 计数器(CTW)
   parameter SINGLE_DATA_WITHOUT_COUNTER             = PTW + MTW                    ,
   parameter SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE = ({{PTW{1'b1}},{MTW{1'b0}}})  ,
   parameter SINGLE_DATA_INIT_VALUE                  = {SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE,{CTW{1'b0}}},
   parameter RAM_DATA_INIT_VALUE                     = {4{SINGLE_DATA_INIT_VALUE}},
   parameter RAM_DATA_WIDTH                          = 4*SINGLE_DATA_WIDTH //RAM存储4个条目，总宽度4*(16+32+10)=232bit
) 
(
   // Clock and Reset
   input    logic                                              clk   ,              // I - Clock
   input    logic                                              rst   ,              // I - Active Low Async Reset
   //Push From Top 
   input    logic                                              Top_Push_valid ,
   input    logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]            Top_Push_Data  ,
   output   logic                                              Top_Push_ready ,
   //Pop from Top
   input    logic                                              Top_Pop_req_valid  ,
//    input    logic                                              Top_Pop_req_DATA   ,//temp
   output   logic                                              Top_Pop_req_ready  ,
   output   logic                                              Top_Pop_resp_valid ,
   output   logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]            Top_Pop_resp_Data  ,    
   input    logic                                              Top_Pop_resp_ready ,
   //Push to Child
   output   logic                                              Parents_Push_valid ,
   output   logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]            Parents_Push_Data  ,
   //Pop  to Child
   output   logic                                              Parents_Pop_req_valid  ,//TODO why child no need ready
   input    logic                                              Parents_Pop_resp_valid ,
   input    logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]            Parents_Pop_resp_data  ,//[SINGLE_DATA_WITHOUT_COUNTER-1:0]
   //Addr Io
   input    logic                                              Top_My_addr            ,
   output   logic                                              Pifo_Empty             ,
   output   logic  [1:0]                                       Parents_Child_Addr

);
   //localparam
   localparam  LEVEL_ADW           = 'd1 ;
   localparam  CHILD_ADW           = 'd2 ;
   localparam  POP_REQ_PIPE_DEPTH  = 'd2 ;
   localparam  PUSH_REQ_PIPE_DEPTH = 'd1 ;


   //Ram interfaces
   logic                               ram_wren       ;
   logic     [LEVEL_ADW-1:0]           ram_write_addr ,ram_write_addr_d1;
   logic     [RAM_DATA_WIDTH-1:0]      ram_write_data ,ram_write_data_d1;
   logic                               ram_rden       ;
   logic     [LEVEL_ADW-1:0]           ram_read_addr  ,ram_read_addr_d1 ; 
   logic     [RAM_DATA_WIDTH-1:0]      ram_read_data   ;


   logic     [SINGLE_DATA_WIDTH-1:0]            way_0_ram_word ;
   logic     [SINGLE_DATA_WITHOUT_COUNTER-1:0]  way_0_ram_word_without_cnt ;
   logic     [CTW-1:0]                          way_0_ram_word_cnt   ;
   logic     [PTW-1:0]                          way_0_ram_rank       ;
   logic     [MTW-1:0]                          way_0_ram_meta       ;

   logic     [SINGLE_DATA_WIDTH-1:0]            way_1_ram_word ;
   logic     [SINGLE_DATA_WITHOUT_COUNTER-1:0]  way_1_ram_word_without_cnt ;
   logic     [CTW-1:0]                          way_1_ram_word_cnt   ;
   logic     [PTW-1:0]                          way_1_ram_rank       ;
   logic     [MTW-1:0]                          way_1_ram_meta       ;

   logic     [SINGLE_DATA_WIDTH-1:0]            way_2_ram_word ;
   logic     [SINGLE_DATA_WITHOUT_COUNTER-1:0]  way_2_ram_word_without_cnt ;
   logic     [CTW-1:0]                          way_2_ram_word_cnt   ;
   logic     [PTW-1:0]                          way_2_ram_rank       ;
   logic     [MTW-1:0]                          way_2_ram_meta       ;

   logic     [SINGLE_DATA_WIDTH-1:0]            way_3_ram_word ;
   logic     [SINGLE_DATA_WITHOUT_COUNTER-1:0]  way_3_ram_word_without_cnt ;
   logic     [CTW-1:0]                          way_3_ram_word_cnt   ;
   logic     [PTW-1:0]                          way_3_ram_rank       ;
   logic     [MTW-1:0]                          way_3_ram_meta       ;


   logic     [SINGLE_DATA_WIDTH-1:0]            min_rank_ram_word ;
   logic     [SINGLE_DATA_WITHOUT_COUNTER-1:0]  min_rank_ram_word_without_cnt ;
   logic     [CTW-1:0]                          min_rank_ram_word_cnt   ;
   logic     [PTW-1:0]                          min_rank_ram_rank       ;
   logic     [MTW-1:0]                          min_rank_ram_meta       ;

   logic     [SINGLE_DATA_WIDTH-1:0]            min_sub_tree_ram_word             ;
   logic     [SINGLE_DATA_WITHOUT_COUNTER-1:0]  min_sub_tree_ram_word_without_cnt ;
   logic     [CTW-1:0]                          min_sub_tree_ram_word_cnt   ;
   logic     [PTW-1:0]                          min_sub_tree_ram_rank       ;
   logic     [MTW-1:0]                          min_sub_tree_ram_meta       ;   
   //port
   //Push From Top 
   logic                  Top_Push_ready_reg          , Top_Push_ready_next ;
   //Pop from Top    
   logic                  Top_Pop_req_ready_reg       , Top_Pop_req_ready_next  ;  
   logic                  Top_Pop_resp_valid_reg      , Top_Pop_resp_valid_next ;
   logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]            Top_Pop_resp_data_reg       , Top_Pop_resp_data_next  ;  
   //Push to Child      
   logic                  Parents_Push_valid_reg      , Parents_Push_valid_next ; 
   logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]            Parents_Push_Data_reg       , Parents_Push_Data_next  ; 
   //Pop  to Child
   logic                  Parents_Pop_req_valid_reg   ;
   //Addr Io
   logic  [1:0]           Parents_Child_Addr_reg      ;

   logic                                                 Pop_Req_pipe_in    ,   Pop_Req_pipe_out ;
   logic  [POP_REQ_PIPE_DEPTH-1:0]                       Pop_Req_pipe_total ;
   logic                                                 Pop_Req_pipe_0,Pop_Req_pipe_1 ;
   logic  [LEVEL_ADW-1:0]                                Pop_Req_ram_read_addr_pipe_in ,Pop_Req_ram_read_addr_pipe_out ;
   logic  [RAM_DATA_WIDTH-1:0]                           Pop_Req_ram_read_data_pipe_in ,Pop_Req_ram_read_data_pipe_out ;
   logic  [SINGLE_DATA_WIDTH-1:0]                        Pop_Req_ram_read_data_pipe_out_way0,Pop_Req_ram_read_data_pipe_out_way1,
                                                         Pop_Req_ram_read_data_pipe_out_way2,Pop_Req_ram_read_data_pipe_out_way3 ;
   logic  [LEVEL_ADW*POP_REQ_PIPE_DEPTH-1:0]             Pop_ram_read_addr_pipe_total  ;   
   logic  [LEVEL_ADW-1:0]                                Pop_ram_read_addr_pipe_0,Pop_ram_read_addr_pipe_1 ;



   logic  [LEVEL_ADW-1:0]                                Push_Req_ram_read_addr_pipe_in,Push_Req_ram_read_addr_pipe_out ;
   logic                                                 Push_Req_pipe_in    ,  Push_Req_pipe_out ;
   logic  [PUSH_REQ_PIPE_DEPTH-1:0]                      Push_Req_pipe_total ;
   logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]               Push_Req_Data_pipe_in,Push_Req_Data_pipe_out  ;
   logic [PTW-1:0]                                       Push_Req_Data_pipe_out_data_rank       ;
   logic [MTW-1:0]                                       Push_Req_Data_pipe_out_data_meta       ;      
   
   logic [1:0]                                           Min_data_port  ;
   logic [1:0]                                           Min_sub_tree   ;

         
   logic [SINGLE_DATA_WIDTH-1:0]                         Write_ram_data ;
   logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]               Write_ram_data_Without_cnt ;
   logic [CTW-1:0]                                       Write_ram_data_word_cnt   ;
   logic [PTW-1:0]                                       Write_ram_data_rank       ;
   logic [MTW-1:0]                                       Write_ram_data_meta       ;   

   always_comb begin
         //Top_Push_ready         =  Top_Push_ready_reg        ;   
         //TODO
         Top_Push_ready         = (!Pop_Req_pipe_total) && (!(Top_Pop_req_valid && (!Top_Pop_resp_valid || Top_Pop_resp_ready) && !Pifo_Empty)) ; 
         Top_Pop_req_ready      =  Top_Pop_req_ready_reg     ;
         Top_Pop_resp_valid     =  Top_Pop_resp_valid_reg    ;
         Top_Pop_resp_Data      =  Top_Pop_resp_data_reg     ;
         Parents_Push_valid     =  Parents_Push_valid_reg    ; 
         Parents_Push_Data      =  Parents_Push_Data_reg     ;
         Parents_Pop_req_valid  =  Parents_Pop_req_valid_reg ;
         Parents_Child_Addr     =  Parents_Child_Addr_reg    ;
   end
  

   always_comb begin
      //------------------------------------------------------------------
      // SRAM数据分解：将4路数据分解为独立条目
      //------------------------------------------------------------------

      // Way 0数据分解（优先级+元数据+计数器）
      {way_0_ram_word_without_cnt,way_0_ram_word_cnt}                            = way_0_ram_word ;
      {way_0_ram_rank,way_0_ram_meta}                                            = way_0_ram_word_without_cnt ;
      // Way 1数据分解（同上）
      {way_1_ram_word_without_cnt,way_1_ram_word_cnt}                            = way_1_ram_word ;
      {way_1_ram_rank,way_1_ram_meta}                                            = way_1_ram_word_without_cnt ;
      // Way 2
      {way_2_ram_word_without_cnt,way_2_ram_word_cnt}                            = way_2_ram_word ;
      {way_2_ram_rank,way_2_ram_meta}                                            = way_2_ram_word_without_cnt ;
      // Way 3
      {way_3_ram_word_without_cnt,way_3_ram_word_cnt}                            = way_3_ram_word ;
      {way_3_ram_rank,way_3_ram_meta}                                            = way_3_ram_word_without_cnt ;

      {min_rank_ram_word_without_cnt,min_rank_ram_word_cnt}                      = min_rank_ram_word ;
      {min_rank_ram_rank,min_rank_ram_meta}                                      = min_rank_ram_word_without_cnt ;

      {min_sub_tree_ram_word_without_cnt,min_sub_tree_ram_word_cnt}              = min_sub_tree_ram_word ;
      {min_sub_tree_ram_rank,min_sub_tree_ram_meta}                              = min_sub_tree_ram_word_without_cnt ;

      Write_ram_data                                                             = {Write_ram_data_Without_cnt,Write_ram_data_word_cnt} ;

      {Push_Req_Data_pipe_out_data_rank,Push_Req_Data_pipe_out_data_meta}        = Push_Req_Data_pipe_out  ;
      {Pop_Req_ram_read_data_pipe_out_way3,Pop_Req_ram_read_data_pipe_out_way2,
       Pop_Req_ram_read_data_pipe_out_way1,Pop_Req_ram_read_data_pipe_out_way0}  = Pop_Req_ram_read_data_pipe_out ;

 
      {Pop_ram_read_addr_pipe_1,Pop_ram_read_addr_pipe_0}                        = Pop_ram_read_addr_pipe_total ;    
      {Pop_Req_pipe_1,Pop_Req_pipe_0}                                            = Pop_Req_pipe_total ;
      
      //------------------------------------------------------------------
      // 子树选择逻辑：选择元素最少的子树，push用
      //------------------------------------------------------------------
      // 比较四个Way的计数器值（CTW），平衡子树，找出那一路计数器最小，然后把新条目插到那里
      if((way_0_ram_word_cnt  <= way_1_ram_word_cnt)&&
         (way_0_ram_word_cnt <= way_2_ram_word_cnt) &&
         (way_0_ram_word_cnt <= way_3_ram_word_cnt))begin
         Min_sub_tree = 2'b00 ;// 选择Way0对应的子树

      end else if((way_1_ram_word_cnt <= way_0_ram_word_cnt) &&
                  (way_1_ram_word_cnt <= way_2_ram_word_cnt) &&
                  (way_1_ram_word_cnt <= way_3_ram_word_cnt))begin
         Min_sub_tree = 2'b01 ;// 其他比较情况...

      end else if((way_2_ram_word_cnt <= way_0_ram_word_cnt) &&
                  (way_2_ram_word_cnt <= way_1_ram_word_cnt) &&
                  (way_2_ram_word_cnt <= way_3_ram_word_cnt))begin
         Min_sub_tree = 2'b10 ;

      end else begin

         Min_sub_tree = 2'b11 ;
      end 

      //------------------------------------------------------------------
      // 空状态检测逻辑
      //------------------------------------------------------------------
      // 当所有Way的计数器都为0时，队列为空
      Pifo_Empty  = (way_0_ram_word_cnt == 0) && (way_1_ram_word_cnt == 0) && 
                     (way_2_ram_word_cnt == 0) && (way_3_ram_word_cnt == 0) ;
   end

   //------------------------------------------------------------------
   // 优先级比较逻辑：选择当前最小优先级条目，指示出哪一路的 rank 最小，pop用
   //------------------------------------------------------------------
   always_comb begin
      // 四级比较器，选择最小PTW值
      if((way_0_ram_rank <= way_1_ram_rank) && 
         (way_0_ram_rank <= way_2_ram_rank) &&
         (way_0_ram_rank <= way_3_ram_rank)  )begin
         Min_data_port = 2'b00 ; // 选中Way0
      end else if((way_1_ram_rank <= way_0_ram_rank) && 
                  (way_1_ram_rank <= way_2_ram_rank) &&
                  (way_1_ram_rank <= way_3_ram_rank))begin
         Min_data_port = 2'b01 ; // 选中Way1
      end  else if((way_2_ram_rank <= way_0_ram_rank) &&
                     (way_2_ram_rank <= way_1_ram_rank) &&
                     (way_2_ram_rank <= way_3_ram_rank))begin
         Min_data_port = 2'b10 ;// 选中Way2
      end else begin
         Min_data_port = 2'b11 ;// 选中Way3
      end 
   end

   
   always_comb begin
      //pop req
      Pop_Req_pipe_in               = 1'b0 ;
      Top_Pop_req_ready_next        = 1'b0 ;
      ram_read_addr                 = ram_read_addr_d1  ;
      Pop_Req_ram_read_addr_pipe_in = 'd0  ;
      Push_Req_ram_read_addr_pipe_in = 'd0 ;
      //pop resp 
      Top_Pop_resp_valid_next       = Top_Pop_resp_valid & ~Top_Pop_resp_ready ;
      Top_Pop_resp_data_next        = Top_Pop_resp_data_reg ;
      //pop to child 
      //Parents_Pop_req_valid_next    = 'd0 ;
      //Parents_Child_Addr_next       = Parents_Child_Addr_reg ;
      Parents_Pop_req_valid_reg       = 'd0 ;
      Parents_Child_Addr_reg          = 'd0 ;
      //push req
      Push_Req_pipe_in              = 1'b0 ;
      Top_Push_ready_next           = !(Top_Pop_req_valid && (!Top_Pop_resp_valid || Top_Pop_resp_ready) && !Pop_Req_pipe_total) ;//1'b0 ;
      Push_Req_Data_pipe_in         =  'd0 ;
      //push req
      //Parents_Push_valid_next       = 1'b0 ;
      //Parents_Push_Data_next        = Parents_Push_Data_reg ;
      Parents_Push_valid_reg         = 1'b0 ;
      Parents_Push_Data_reg          = 'd0  ;
      //ram io 
      Pop_Req_ram_read_data_pipe_in = ram_read_data ;
      ram_wren                      = 1'b0   ;
      ram_write_addr                = ram_write_addr_d1    ;
      ram_write_data                = ram_write_data_d1    ;      
      Write_ram_data_word_cnt       = 'd0    ;
      Write_ram_data_Without_cnt    = SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE    ;


      //------------------------------------------------------------------
      // POP请求处理流水线（2级流水）
      //------------------------------------------------------------------
      // PUSH请求处理流水线（1级流水）
      //------------------------------------------------------------------

      //pop req
      // 第一级：接收Pop请求，读取SRAM
      if(Top_Pop_req_valid && (!Top_Pop_resp_valid || Top_Pop_resp_ready) && !Pop_Req_pipe_total && !Pifo_Empty)begin
         Pop_Req_pipe_in               = 1'b1 ;// 激活流水线
         Top_Pop_req_ready_next        = 1'b1 ;
         ram_read_addr                 = Top_My_addr ;// 读取父节点地址
         Pop_Req_ram_read_addr_pipe_in = Top_My_addr ;
      end
      //push req
      // 第一级：接收Push请求，读取SRAM
      else if(Top_Push_valid && !Pop_Req_pipe_total)begin//没有正在进行的 Pop 请求流水（!Pop_Req_pipe_total），并且上一次 Pop 响应已完成或空闲。
         Push_Req_pipe_in                 = 1'b1 ;// 激活流水线
         //Top_Push_ready_next           = 1'b1 ;
         Push_Req_Data_pipe_in            = Top_Push_Data ;//将来自 Top_Push_Data（包含 rank+meta，不含计数器）的有效数据打到 Push 请求流水线 的第一级。
         ram_read_addr                    = Top_My_addr ;// 将父节点地址提给 SRAM，读出本级对应的“4-way 扇区”中所有条目（每条 PTW+MTW+CTW 位）。
         Push_Req_ram_read_addr_pipe_in   = Top_My_addr ;
      end

      // 第二级：返回结果并触发子节点Pop 
      if(Pop_Req_pipe_0)begin//data read
         Top_Pop_resp_valid_next       = 1'b1 ;   
         Parents_Pop_req_valid_reg     = 1'b1 ;// 向子节点发送Pop请求
         Parents_Child_Addr_reg        = 4*Pop_ram_read_addr_pipe_0 + Min_data_port ; 
         //Parents_Pop_req_valid_next    = 1'b1 ;
         //Parents_Child_Addr_next       = Pop_ram_read_addr_pipe_0 + Min_data_port ; 
         Top_Pop_resp_data_next        = min_rank_ram_word_without_cnt ;// 返回数据
      end

      // 第三级：更新SRAM计数器（隐含在后续逻辑中）
      if(Pop_Req_pipe_1)begin
         ram_write_addr                      = Pop_ram_read_addr_pipe_1  ;
         // Pop操作时计数器减1
         Write_ram_data_word_cnt             = min_rank_ram_word_cnt - 1 ;// 更新选中Way的计数器（减1）
         ram_wren                            = min_rank_ram_word_cnt != 0 ;// 写使能
         Write_ram_data_Without_cnt          = Write_ram_data_word_cnt == 0 ? SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE : 
                                                                         Parents_Pop_resp_data ;

         /*
         如果 这一路的计数器已经减到0了，那说明这一路没有数据了，所以把它写成无效的默认值 SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE；
         如果 计数器还不是0（>0），说明还有数据，就把pop出来的Parents_Pop_resp_data写回去
         */
         case (Min_data_port)
            2'b00 : begin
               ram_write_data = {Pop_Req_ram_read_data_pipe_out_way3,Pop_Req_ram_read_data_pipe_out_way2,Pop_Req_ram_read_data_pipe_out_way1,Write_ram_data} ;
            end
            2'b01 : begin
               ram_write_data = {Pop_Req_ram_read_data_pipe_out_way3,Pop_Req_ram_read_data_pipe_out_way2,Write_ram_data,Pop_Req_ram_read_data_pipe_out_way0} ;               
            end
            2'b10 : begin
               ram_write_data = {Pop_Req_ram_read_data_pipe_out_way3,Write_ram_data,Pop_Req_ram_read_data_pipe_out_way1,Pop_Req_ram_read_data_pipe_out_way0} ;               
            end
            2'b11 : begin
               ram_write_data = {Write_ram_data,Pop_Req_ram_read_data_pipe_out_way2,Pop_Req_ram_read_data_pipe_out_way1,Pop_Req_ram_read_data_pipe_out_way0} ;      
            end
            default: ram_write_data = 'd0 ;
         endcase      
      end

      // 第二级：处理数据插入,组合逻辑已在上一周期根据读回的 4 条 CTW 计数字段算出了 Min_sub_tree（哪一路计数最小）和 min_sub_tree_ram_*（该路当前的 rank, meta, count)
      if(Push_Req_pipe_out)begin
         // 流水线数据写入
         ram_write_addr                    = Push_Req_ram_read_addr_pipe_out ;
         ram_wren                          = 1'b1 ;// 写使能
         /*
            min_sub_tree_ram_rank：从 SRAM 读回来的该子树里最小 entry 的 rank。
            Push_Req_Data_pipe_out_data_rank：新到的 Push 数据里的 rank。
            min_sub_tree_ram_word_without_cnt：该 entry 读回来的 “旧”的 rank+meta。
            Push_Req_Data_pipe_out：新到的 Push 数据里的 rank+meta。

           保证了——只有当新到的数据优先级比现有的更高时，才真正替换 metadata，否则只是对同一路 entry 的计数做累加。
         */
         Write_ram_data_Without_cnt        = min_sub_tree_ram_rank <= Push_Req_Data_pipe_out_data_rank ? min_sub_tree_ram_word_without_cnt : //< to <=
                                                                     Push_Req_Data_pipe_out ;     //在写回的时候决定把哪份 rank+meta（不含计数器）写入 SRAM
         // Push操作时计数器加1 
         Write_ram_data_word_cnt           = min_sub_tree_ram_word_cnt + 1'b1 ;  // 更新选中Way的计数器（加1） 

         if(min_sub_tree_ram_rank != {PTW{1'b1}})begin//是否为空
            Parents_Push_valid_reg = 1'b1 ;// 需要下推到子节点
            Parents_Push_Data_reg  = min_sub_tree_ram_rank > Push_Req_Data_pipe_out_data_rank ? min_sub_tree_ram_word_without_cnt :
                                                               Push_Req_Data_pipe_out ;//当前层只保留“更好”的那条（更小的 rank），把“更差”的那条通过 Parents_Push_Data 递给下一层继续调度。
            Parents_Child_Addr_reg     = 4*Push_Req_ram_read_addr_pipe_out + Min_sub_tree ;
            /*
               本质上就是把“本层节点在它父级的编号”＋“本层选中的哪一路子树”两个信息打包成一个扁平化的“子节点编号”，方便在下一级 PIFO 网络里路由这一条 Push 数据。
               4 × A + B  == { A << 2 , B }
            */
         end
         //写回 SRAM
         case (Min_sub_tree)
            2'b00 : begin
               ram_write_data = {way_3_ram_word,way_2_ram_word,way_1_ram_word,Write_ram_data} ;//write : Write_ram_data
            end
            2'b01 : begin
               ram_write_data = {way_3_ram_word,way_2_ram_word,Write_ram_data,way_0_ram_word} ;               
            end
            2'b10 : begin
               ram_write_data = {way_3_ram_word,Write_ram_data,way_1_ram_word,way_0_ram_word} ;               
            end
            2'b11 : begin
               ram_write_data = {Write_ram_data,way_2_ram_word,way_1_ram_word,way_0_ram_word} ;      
            end
            default: ram_write_data = 'd0 ;
         endcase
      end
   end



   Register
   #(
      .WORD_WIDTH  (1'b1),
      .RESET_VALUE (1'b0)
   )Top_Push_ready_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (Top_Push_ready_next),
       .data_out            (Top_Push_ready_reg)
   );
   Register
   #(
      .WORD_WIDTH  (1'b1),
      .RESET_VALUE (1'b0)
   )Top_Pop_ready_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (Top_Pop_req_ready_next),
       .data_out            (Top_Pop_req_ready_reg)
   );
   Register
   #(
      .WORD_WIDTH  (1'b1),
      .RESET_VALUE (1'b0)
   )Top_Pop_resp_valid_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (Top_Pop_resp_valid_next),
       .data_out            (Top_Pop_resp_valid_reg)
   );
   Register
   #(
      .WORD_WIDTH  (SINGLE_DATA_WITHOUT_COUNTER),
      .RESET_VALUE (SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE)
   )Top_Pop_resp_data_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (Top_Pop_resp_data_next),
       .data_out            (Top_Pop_resp_data_reg)
   );
/*
   Register
   #(
      .WORD_WIDTH  (1'b1),
      .RESET_VALUE (1'b0)
   )Parents_Push_valid_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (Parents_Push_valid_next),
       .data_out            (Parents_Push_valid_reg)
   );
   Register
   #(
      .WORD_WIDTH  (SINGLE_DATA_WITHOUT_COUNTER),
      .RESET_VALUE (SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE)
   )Parents_Push_Data_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (Parents_Push_Data_next),
       .data_out            (Parents_Push_Data_reg)
   );
*/
   /*
   Register
   #(
      .WORD_WIDTH  (1'b1),
      .RESET_VALUE (1'b0)
   )Parents_Pop_req_valid_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (Parents_Pop_req_valid_next),
       .data_out            (Parents_Pop_req_valid_reg)
   );
   Register
   #(
      .WORD_WIDTH  (2'd2),
      .RESET_VALUE (1'b0)
   )Parents_Child_Addr_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (Parents_Child_Addr_next),
       .data_out            (Parents_Child_Addr_reg)
   );
   */


   Register
   #(
      .WORD_WIDTH  (LEVEL_ADW),
      .RESET_VALUE ({LEVEL_ADW{1'b0}})
   )ram_write_addr_d1_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (ram_write_addr),
       .data_out            (ram_write_addr_d1)
   );
   Register
   #(
      .WORD_WIDTH  (LEVEL_ADW),
      .RESET_VALUE ({LEVEL_ADW{1'b0}})
   )ram_read_addr_d1_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (ram_read_addr),
       .data_out            (ram_read_addr_d1)
   );
   Register
   #(
      .WORD_WIDTH  (RAM_DATA_WIDTH),
      .RESET_VALUE ({RAM_DATA_WIDTH{1'b0}})
   )ram_write_data_d1_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (ram_write_data),
       .data_out            (ram_write_data_d1)
   );

   //------------------------------------------------------------------
   //多路选择逻辑
   //------------------------------------------------------------------
   Multiplexer_Binary_Behavioural
   #(
       .WORD_WIDTH          (SINGLE_DATA_WIDTH),
       .ADDR_WIDTH          (2),
       .INPUT_COUNT         (4)
   )way_0_ram_data
   (
      .selector(2'b0),
      .words_in(ram_read_data),
      .word_out(way_0_ram_word)
   );
   Multiplexer_Binary_Behavioural
   #(
       .WORD_WIDTH          (SINGLE_DATA_WIDTH),
       .ADDR_WIDTH          (2),
       .INPUT_COUNT         (4)
   )way_1_ram_data
   (
      .selector(2'b01),
      .words_in(ram_read_data),
      .word_out(way_1_ram_word)
   );
   Multiplexer_Binary_Behavioural
   #(
       .WORD_WIDTH          (SINGLE_DATA_WIDTH),
       .ADDR_WIDTH          (2),
       .INPUT_COUNT         (4)
   )way_2_ram_data
   (
      .selector(2'b10),
      .words_in(ram_read_data),
      .word_out(way_2_ram_word)
   );
   Multiplexer_Binary_Behavioural
   #(
       .WORD_WIDTH          (SINGLE_DATA_WIDTH),
       .ADDR_WIDTH          (2),
       .INPUT_COUNT         (4)
   )way_3_ram_data
   (
      .selector(2'b11),
      .words_in(ram_read_data),
      .word_out(way_3_ram_word)
   );
   Multiplexer_Binary_Behavioural
   #(
       .WORD_WIDTH          (SINGLE_DATA_WIDTH),
       .ADDR_WIDTH          (2),
       .INPUT_COUNT         (4)
   )Mux_Min_rank_select
   (
      .selector(Min_data_port),
      .words_in(ram_read_data),
      .word_out(min_rank_ram_word)
   );
   //例化了一个参数化的 4→1 复用器，用来从 SRAM 读回的 4 条并行数据中选出“子树”级最小的那一路。
   Multiplexer_Binary_Behavioural
   #(
       .WORD_WIDTH          (SINGLE_DATA_WIDTH),
       .ADDR_WIDTH          (2),
       .INPUT_COUNT         (4)
   )Mux_Min_sub_tree_select
   (
      .selector(Min_sub_tree),
      .words_in(ram_read_data),
      .word_out(min_sub_tree_ram_word)
   );

   //------------------------------------------------------------------
   // 流水线寄存器组
   //------------------------------------------------------------------
   Register_Pipeline
   #(
    .WORD_WIDTH      (1'b1),
    .PIPE_DEPTH      (POP_REQ_PIPE_DEPTH)
    // Don't set at instantiation
    //parameter                   TOTAL_WIDTH     = WORD_WIDTH * PIPE_DEPTH,
    // concatenation of each stage initial/reset value
    //parameter [TOTAL_WIDTH-1:0] RESET_VALUES    = 0
   )Pop_Req_Pipeline_inst
   (
      .clock         (clk),
      .clock_enable  (1'b1),
      .clear         (rst),
      .parallel_load (1'b0),
      .parallel_in   ({POP_REQ_PIPE_DEPTH{1'b0}}),  
      .parallel_out  (Pop_Req_pipe_total),//TODO:what is Pop_Req_pipe_total? 几级流水？怎么来的？阅读这个模块
      .pipe_in       (Pop_Req_pipe_in),
      .pipe_out      (Pop_Req_pipe_out)
   );
   Register_Pipeline
   #(
    .WORD_WIDTH      (LEVEL_ADW),
    .PIPE_DEPTH      (POP_REQ_PIPE_DEPTH)
    // Don't set at instantiation
    //parameter                   TOTAL_WIDTH     = WORD_WIDTH * PIPE_DEPTH,
    // concatenation of each stage initial/reset value
    //parameter [TOTAL_WIDTH-1:0] RESET_VALUES    = 0
   )Ram_Read_Addr_Pipeline_inst
   (
      .clock         (clk),
      .clock_enable  (1'b1),
      .clear         (rst),
      .parallel_load (1'b0),
      .parallel_in   ({POP_REQ_PIPE_DEPTH{1'b0}}),  
      .parallel_out  (Pop_ram_read_addr_pipe_total),
      .pipe_in       (Pop_Req_ram_read_addr_pipe_in),
      .pipe_out      (Pop_Req_ram_read_addr_pipe_out)
   );
   Register_Pipeline
   #(
    .WORD_WIDTH      (RAM_DATA_WIDTH),
    .PIPE_DEPTH      (1'b1)
    // Don't set at instantiation
    //parameter                   TOTAL_WIDTH     = WORD_WIDTH * PIPE_DEPTH,
    // concatenation of each stage initial/reset value
    //parameter [TOTAL_WIDTH-1:0] RESET_VALUES    = 0
   )Ram_Read_Data_Pipeline_inst
   (
      .clock         (clk),
      .clock_enable  (1'b1),
      .clear         (rst),
      .parallel_load (1'b0),
      .parallel_in   ({(RAM_DATA_WIDTH){1'b0}}),  
      .parallel_out  (),
      .pipe_in       (Pop_Req_ram_read_data_pipe_in),
      .pipe_out      (Pop_Req_ram_read_data_pipe_out)
   );
   Register_Pipeline
   #(
    .WORD_WIDTH      (1'b1),
    .PIPE_DEPTH      (PUSH_REQ_PIPE_DEPTH)
    // Don't set at instantiation
    //parameter                   TOTAL_WIDTH     = WORD_WIDTH * PIPE_DEPTH,
    // concatenation of each stage initial/reset value
    //parameter [TOTAL_WIDTH-1:0] RESET_VALUES    = 0
   )Push_Req_Pipeline_inst
   (
      .clock         (clk),
      .clock_enable  (1'b1),
      .clear         (rst),
      .parallel_load (1'b0),
      .parallel_in   ({PUSH_REQ_PIPE_DEPTH{1'b0}}),  
      .parallel_out  (Push_Req_pipe_total),
      .pipe_in       (Push_Req_pipe_in),//push 流水线
      .pipe_out      (Push_Req_pipe_out)
   );
   Register_Pipeline
   #(
    .WORD_WIDTH      (SINGLE_DATA_WITHOUT_COUNTER),
    .PIPE_DEPTH      (PUSH_REQ_PIPE_DEPTH)
    // Don't set at instantiation
    //parameter                   TOTAL_WIDTH     = WORD_WIDTH * PIPE_DEPTH,
    // concatenation of each stage initial/reset value
    //parameter [TOTAL_WIDTH-1:0] RESET_VALUES    = 0
   )Push_Data_Pipeline_inst
   (
      .clock         (clk),
      .clock_enable  (1'b1),
      .clear         (rst),
      .parallel_load (1'b0),
      .parallel_in   ({SINGLE_DATA_WITHOUT_COUNTER*PUSH_REQ_PIPE_DEPTH{1'b0}}),  
      .parallel_out  (),
      .pipe_in       (Push_Req_Data_pipe_in),
      .pipe_out      (Push_Req_Data_pipe_out)
   );
   Register_Pipeline
   #(
    .WORD_WIDTH      (LEVEL_ADW),
    .PIPE_DEPTH      (PUSH_REQ_PIPE_DEPTH)
    // Don't set at instantiation
    //parameter                   TOTAL_WIDTH     = WORD_WIDTH * PIPE_DEPTH,
    // concatenation of each stage initial/reset value
    //parameter [TOTAL_WIDTH-1:0] RESET_VALUES    = 0
   )Push_Addr_Pipeline_inst
   (
      .clock         (clk),
      .clock_enable  (1'b1),
      .clear         (rst),
      .parallel_load (1'b0),
      .parallel_in   ({LEVEL_ADW{1'b0}}),  
      .parallel_out  (),
      .pipe_in       (Push_Req_ram_read_addr_pipe_in),
      .pipe_out      (Push_Req_ram_read_addr_pipe_out)
   );

   //------------------------------------------------------------------
   // SRAM接口实例化（双端口存储器）
   //------------------------------------------------------------------
   RAM_Simple_Dual_Port 
   #(
       .WORD_WIDTH          (RAM_DATA_WIDTH),
       .ADDR_WIDTH          (LEVEL_ADW),
       .DEPTH               ('d1),
       // Used as attributes, not values
       // verilator lint_off UNUSED
       //parameter                       RAMSTYLE            = "",
       //parameter                       RW_ADDR_COLLISION   = "",
       // verilator lint_on  UNUSED
       .READ_NEW_DATA       (1) ,
       //parameter                       USE_INIT_FILE       = 0,
       //parameter                       INIT_FILE           = "",
       .INIT_VALUE          (RAM_DATA_INIT_VALUE)//= 0
   )Ram_init(
       .clock      (clk),
       .wren       (ram_wren),
       .write_addr (ram_write_addr),
       .write_data (ram_write_data),
       .rden       (1'b1),
       .read_addr  (ram_read_addr), 
       .read_data  (ram_read_data)
   );
//POP req > Push req
//


endmodule 