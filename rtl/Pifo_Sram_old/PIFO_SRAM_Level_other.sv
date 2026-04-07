module PIFO_SRAM_Level_other#(
   parameter PTW     = 16   ,// RANK WIDTH
   parameter MTW     = 32   ,// Meta Data WIDTH
   parameter CTW     = 15   ,// COUNT WIDTH
   parameter LEVEL   = 2    ,
   //Don't Touch
   parameter LEVEL_ADW                               = 2*LEVEL                      ,
   parameter NEXT_LEVEL_ADW                          = 2*(LEVEL+1)                  ,
   parameter SINGLE_DATA_WIDTH                       = PTW + MTW + CTW              ,
   parameter SINGLE_DATA_WITHOUT_COUNTER             = PTW + MTW                    ,
   parameter SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE = ({{PTW{1'b1}},{MTW{1'b0}}})  ,
   parameter SINGLE_DATA_INIT_VALUE                  = {SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE,{CTW{1'b0}}},
   parameter RAM_DATA_INIT_VALUE                     = {4{SINGLE_DATA_INIT_VALUE}}  ,
   parameter RAM_DATA_WIDTH                          = 4*SINGLE_DATA_WIDTH 
) 
(
   // Clock and Reset
   input    logic                                              clk   ,              // I - Clock
   input    logic                                              rst   ,              // I - Active Low Async Reset
   //Push From Top 
   input    logic                                              Parents_Push_valid ,
   input    logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]            Parents_Push_Data  ,
   //Pop from Top
   input    logic                                              Parents_Pop_req_valid  ,
   input    logic                                              Parents_Pop_req_DATA   ,//temp
   output   logic                                              Parents_Pop_resp_valid ,
   output   logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]            Parents_Pop_resp_data  ,    
   //Push to Child
   output   logic                                              Child_Push_valid ,
   output   logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]            Child_Push_Data  ,
   //Pop  to Child
   output   logic                                              Child_Pop_req_valid  ,
   input    logic                                              Child_Pop_resp_valid ,
   input    logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]            Child_Pop_resp_data  ,//[SINGLE_DATA_WITHOUT_COUNTER-1:0]
   //Addr Io
   input    logic  [LEVEL_ADW-1:0]                             Parents_My_addr        ,
   output   logic  [NEXT_LEVEL_ADW-1:0]                        Parents2Child_Addr

);
   //localparam

   localparam  POP_REQ_PIPE_DEPTH  = 'd2 ;
   localparam  PUSH_REQ_PIPE_DEPTH = 'd1 ;


   //Ram interfaces
   logic                               ram_wren       ;
   logic     [LEVEL_ADW-1:0]           ram_write_addr ,ram_write_addr_d1;
   logic     [RAM_DATA_WIDTH-1:0]      ram_write_data ,ram_write_data_d1;
   logic                               ram_rden       ;
   logic     [LEVEL_ADW-1:0]           ram_read_addr, ram_read_addr_d1 ; 
   logic     [RAM_DATA_WIDTH-1:0]      ram_read_data  ;


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
   //Pop from Top    
   logic                                     Parents_Pop_resp_valid_reg ;// Parents_Pop_resp_valid_next ;
   logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]   Parents_Pop_resp_data_reg  ;// Parents_Pop_resp_data_next  ;  
   //Push to Child      
   logic                                     Child_Push_valid_reg       , Child_Push_valid_next ; 
   logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]   Child_Push_Data_reg        , Child_Push_Data_next  ; 
   //Pop  to Child
   logic                  Child_Pop_req_valid_reg   ;
   //Addr Io
   logic  [NEXT_LEVEL_ADW-1:0]           Parents2Child_Addr_reg    ;


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
/*
   // Clock and Reset
   input    logic                                              clk   ,              // I - Clock
   input    logic                                              rst   ,              // I - Active Low Async Reset
   //Push From Top 
   input    logic                                              Parents_Push_valid ,
   input    logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]            Parents_Push_Data  ,
   //Pop from Top
   input    logic                                              Parents_Pop_req_valid  ,
   input    logic                                              Parents_Pop_req_DATA   ,//temp
   output   logic                                              Parents_Pop_resp_valid ,
   output   logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]            Parents_Pop_resp_data  ,    
   //Push to Child
   output   logic                                              Child_Push_valid ,
   output   logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]            Child_Push_Data  ,
   //Pop  to Child
   output   logic                                              Child_Pop_req_valid  ,
   input    logic                                              Child_Pop_resp_valid ,
   input    logic [SINGLE_DATA_WITHOUT_COUNTER-1:0]            Child_Pop_resp_data  ,//[SINGLE_DATA_WITHOUT_COUNTER-1:0]
   //Addr Io
   input    logic  [LEVEL_ADW-1:0]                             Parents_My_addr        ,
   output   logic  [NEXT_LEVEL_ADW-1:0]                        Parents2Child_Addr
*/

   always_comb begin
         Parents_Pop_resp_valid     =  Parents_Pop_resp_valid_reg    ;
         Parents_Pop_resp_data      =  Parents_Pop_resp_data_reg     ;
         Child_Push_valid           =  Child_Push_valid_reg          ; 
         Child_Push_Data            =  Child_Push_Data_reg           ;
         Child_Pop_req_valid        =  Child_Pop_req_valid_reg       ;
         Parents2Child_Addr         =  Parents2Child_Addr_reg        ;
   end

   always_comb begin
      {way_0_ram_word_without_cnt,way_0_ram_word_cnt}                            = way_0_ram_word ;
      {way_0_ram_rank,way_0_ram_meta}                                            = way_0_ram_word_without_cnt ;

      {way_1_ram_word_without_cnt,way_1_ram_word_cnt}                            = way_1_ram_word ;
      {way_1_ram_rank,way_1_ram_meta}                                            = way_1_ram_word_without_cnt ;

      {way_2_ram_word_without_cnt,way_2_ram_word_cnt}                            = way_2_ram_word ;
      {way_2_ram_rank,way_2_ram_meta}                                            = way_2_ram_word_without_cnt ;

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
      
      if((way_0_ram_word_cnt  <= way_1_ram_word_cnt)&&
         (way_0_ram_word_cnt <= way_2_ram_word_cnt) &&
         (way_0_ram_word_cnt <= way_3_ram_word_cnt))begin
         Min_sub_tree = 2'b00 ;
      end else if((way_1_ram_word_cnt <= way_0_ram_word_cnt) &&
                  (way_1_ram_word_cnt <= way_2_ram_word_cnt) &&
                  (way_1_ram_word_cnt <= way_3_ram_word_cnt))begin
                     Min_sub_tree = 2'b01 ;
                  end  else if((way_2_ram_word_cnt <= way_0_ram_word_cnt) &&
                               (way_2_ram_word_cnt <= way_1_ram_word_cnt) &&
                               (way_2_ram_word_cnt <= way_3_ram_word_cnt))begin
                                 Min_sub_tree = 2'b10 ;
                              end else begin
                                    Min_sub_tree = 2'b11 ;
                                 end 
         
   end

   always_comb begin
      if((way_0_ram_rank <= way_1_ram_rank) && 
         (way_0_ram_rank <= way_2_ram_rank) &&
         (way_0_ram_rank <= way_3_ram_rank)  )begin
            Min_data_port = 2'b00 ;
         end else if((way_1_ram_rank <= way_0_ram_rank) &&
                     (way_1_ram_rank <= way_2_ram_rank) &&
                     (way_1_ram_rank <= way_3_ram_rank))begin
                        Min_data_port = 2'b01 ;
                     end  else if((way_2_ram_rank <= way_0_ram_rank) &&
                                  (way_2_ram_rank <= way_1_ram_rank) &&
                                  (way_2_ram_rank <= way_3_ram_rank))begin
                                    Min_data_port = 2'b10 ;
                                 end else begin
                                    Min_data_port = 2'b11 ;
                                 end 
   end
   always_comb begin
      //pop req
      Pop_Req_pipe_in               = 1'b0 ;
      ram_read_addr                 = ram_read_addr_d1  ;
      Pop_Req_ram_read_addr_pipe_in = 'd0  ;
      Push_Req_ram_read_addr_pipe_in = 'd0 ;
      //pop resp 
      //Parents_Pop_resp_valid_next       = 1'b0 ;
      //Parents_Pop_resp_data_next        = Parents_Pop_resp_data_reg ;
      Parents_Pop_resp_valid_reg          = 1'b0 ;
      Parents_Pop_resp_data_reg           = 'd0 ;
      //pop to child 
      //Parents_Pop_req_valid_next    = 'd0 ;
      //Parents_Child_Addr_next       = Parents_Child_Addr_reg ;
      Child_Pop_req_valid_reg          = 'd0 ;
      Parents2Child_Addr_reg           = 'd0 ;
      //push req
      Push_Req_pipe_in              = 1'b0 ;
      Push_Req_Data_pipe_in         =  'd0 ;
      //push req
      //Child_Push_valid_next         = 1'b0 ;
      //Child_Push_Data_next          = Child_Push_Data_reg ;
      Child_Push_valid_reg            = 1'b0 ;
      Child_Push_Data_reg             = 'd0 ;
      //ram io 
      Pop_Req_ram_read_data_pipe_in = ram_read_data ;
      ram_wren                      = 1'b0   ;
      ram_write_addr                = ram_write_addr_d1    ;
      ram_write_data                = ram_write_data_d1   ;      
      Write_ram_data_word_cnt       = 'd0    ;
      Write_ram_data_Without_cnt    = SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE    ;


      //pop req
      if(Parents_Pop_req_valid )begin
         Pop_Req_pipe_in               = 1'b1 ;
         ram_read_addr                 = Parents_My_addr ;
         Pop_Req_ram_read_addr_pipe_in = Parents_My_addr ;
      end
      //push req
      else if(Parents_Push_valid )begin//
         Push_Req_pipe_in              = 1'b1 ;
         Push_Req_Data_pipe_in         = Parents_Push_Data ;
         ram_read_addr                 = Parents_My_addr ;
         Push_Req_ram_read_addr_pipe_in = Parents_My_addr ;
      end

      if(Pop_Req_pipe_0)begin//data read
         Parents_Pop_resp_valid_reg          = 1'b1 ;
         Parents_Pop_resp_data_reg           = min_rank_ram_word_without_cnt ;
         Child_Pop_req_valid_reg             = 1'b1 ;
         Parents2Child_Addr_reg              = 4*Pop_ram_read_addr_pipe_0 + Min_data_port ; 
         //Parents_Pop_resp_valid_next         = 1'b1 ;   
         //Parents_Pop_resp_data_next          = min_rank_ram_word_without_cnt ;
      end
      if(Pop_Req_pipe_1)begin
         ram_write_addr                      = Pop_ram_read_addr_pipe_1  ;
         Write_ram_data_word_cnt             = min_rank_ram_word_cnt - 1 ;
         ram_wren                            = min_rank_ram_word_cnt != 0 ;
         Write_ram_data_Without_cnt          = Write_ram_data_word_cnt == 0 ? SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE : 
                                                                         Child_Pop_resp_data ;
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

      if(Push_Req_pipe_out)begin
         ram_write_addr                    = Push_Req_ram_read_addr_pipe_out ;
         ram_wren                          = 1'b1 ;
         Write_ram_data_Without_cnt        = min_sub_tree_ram_rank <= Push_Req_Data_pipe_out_data_rank ? min_sub_tree_ram_word_without_cnt : //< to <=
                                                                     Push_Req_Data_pipe_out ;     
         Write_ram_data_word_cnt           = min_sub_tree_ram_word_cnt + 1'b1 ;                                
         if(min_sub_tree_ram_rank != {PTW{1'b1}})begin
            Child_Push_valid_reg = 1'b1 ;
            Child_Push_Data_reg  = min_sub_tree_ram_rank > Push_Req_Data_pipe_out_data_rank ? min_sub_tree_ram_word_without_cnt :
                                                               Push_Req_Data_pipe_out ;
            Parents2Child_Addr_reg     = 4*Push_Req_ram_read_addr_pipe_out + Min_sub_tree ;
         end
         case (Min_sub_tree)
            2'b00 : begin
               ram_write_data = {way_3_ram_word,way_2_ram_word,way_1_ram_word,Write_ram_data} ;
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




/*
   Register
   #(
      .WORD_WIDTH  (1'b1),
      .RESET_VALUE (1'b0)
   )Parents_Pop_resp_valid_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (Parents_Pop_resp_valid_next),
       .data_out            (Parents_Pop_resp_valid_reg)
   );
   Register
   #(
      .WORD_WIDTH  (SINGLE_DATA_WITHOUT_COUNTER),
      .RESET_VALUE (SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE)
   )Parents_Pop_resp_data_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (Parents_Pop_resp_data_next),
       .data_out            (Parents_Pop_resp_data_reg)
   );
   */
   /*
   Register
   #(
      .WORD_WIDTH  (1'b1),
      .RESET_VALUE (1'b0)
   )Child_Push_valid_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (Child_Push_valid_next),
       .data_out            (Child_Push_valid_reg)
   );
   Register
   #(
      .WORD_WIDTH  (SINGLE_DATA_WITHOUT_COUNTER),
      .RESET_VALUE (SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE)
   )Child_Push_Data_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (Child_Push_Data_next),
       .data_out            (Child_Push_Data_reg)
   );
   */
   Register
   #(
      .WORD_WIDTH  (LEVEL_ADW),
      .RESET_VALUE (1'b0)
   )Read_addr_d1_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (ram_read_addr),
       .data_out            (ram_read_addr_d1)
   );
   Register
   #(
      .WORD_WIDTH  (LEVEL_ADW),
      .RESET_VALUE (1'b0)
   )Write_addr_d1_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (ram_write_addr),
       .data_out            (ram_write_addr_d1)
   );
   Register
   #(
      .WORD_WIDTH  (RAM_DATA_WIDTH),
      .RESET_VALUE (1'b0)
   )Write_data_d1_inst
   (
       .clock               (clk),
       .clock_enable        (1'b1),
       .clear               (rst),
       .data_in             (ram_write_data),
       .data_out            (ram_write_data_d1)
   );
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
      .parallel_out  (Pop_Req_pipe_total),
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
      .pipe_in       (Push_Req_pipe_in),
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
   RAM_Simple_Dual_Port 
   #(
       .WORD_WIDTH          (RAM_DATA_WIDTH),
       .ADDR_WIDTH          (LEVEL_ADW)     ,
       .DEPTH               (2**LEVEL_ADW)  ,
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