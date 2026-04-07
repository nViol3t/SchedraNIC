module PIFO_SRAM_Top#(
   parameter PTW = 16   ,// RANK WIDTH
   parameter MTW = 32   ,// Meta Data WIDTH
   parameter CTW = 15   ,// COUNT WIDTH
   parameter LEVEL_TOTAL = 8,
   parameter SINGLE_DATA_WITHOUT_COUNTER             = PTW + MTW        
   //Don't Touch
   //parameter SINGLE_DATA_WIDTH                       = PTW + MTW + CTW              ,
   //parameter SINGLE_DATA_INIT_VALUE                  = {SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE,{CTW{1'b0}}},
   //parameter RAM_DATA_INIT_VALUE                     = {4{SINGLE_DATA_INIT_VALUE}},
   //parameter RAM_DATA_WIDTH                          = 4*SINGLE_DATA_WIDTH 
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

   output   logic                                              Pifo_Empty           
   //statusLEVELITHOUT_COUNTER_RESET_VALUE = ({{PTW{1'b1}},{MTW{1'b0}}})  ,
       //parameter SINGLE_DATA_INIT_VALUE                  = {SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE,{CTW{1'b0}}},
       //parameter RAM_DATA_INIT_VALUE                     = {4{SINGLE_DATA_INIT_VALUE}},
       //parameter RAM_DATA_WIDTH                          = 4*SINGLE_DATA_WIDTH 
    ) ;
parameter SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE = ({{PTW{1'b1}},{MTW{1'b0}}})  ;

logic                                   Parents2Child_Push_valid [0:LEVEL_TOTAL-1] ;
logic [SINGLE_DATA_WITHOUT_COUNTER-1:0] Parents2Child_Push_Data  [0:LEVEL_TOTAL-1] ; 

logic                                   Parents2Child_Pop_req_valid [0:LEVEL_TOTAL-1] ;
logic                                   Child2Parents_Pop_resp_valid[0:LEVEL_TOTAL-1] ;
logic [SINGLE_DATA_WITHOUT_COUNTER-1:0] Child2Parents_Pop_resp_data [0:LEVEL_TOTAL-1] ;

logic [2*LEVEL_TOTAL-1:0]               Parents2Child_Addr          [0:LEVEL_TOTAL-1] ;


PIFO_SRAM_Level_1#(
   .PTW(PTW),// RANK WIDTH
   .MTW(MTW),// Meta Data WIDTH
   .CTW(CTW)// COUNT WIDTH
   //Don't Touch
   //parameter SINGLE_DATA_WIDTH                       = PTW + MTW + CTW              ,
   //parameter SINGLE_DATA_WITHOUT_COUNTER             = PTW + MTW                    ,
   //parameter SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE = ({{PTW{1'b1}},{MTW{1'b0}}})  ,
   //parameter SINGLE_DATA_INIT_VALUE                  = {SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE,{CTW{1'b0}}},
   //parameter RAM_DATA_INIT_VALUE                     = {4{SINGLE_DATA_INIT_VALUE}},
   //parameter RAM_DATA_WIDTH                          = 4*SINGLE_DATA_WIDTH 
) PIFO_SRAM_Level_1_Inst
    (
       // Clock and Reset
       .clk   (clk),              // I - Clock
       .rst   (rst),              // I - Active Low Async Reset
       //Push From Top 
       .Top_Push_valid (Top_Push_valid),
       .Top_Push_Data  (Top_Push_Data ),
       .Top_Push_ready (Top_Push_ready),
       //Pop from Top
       .Top_Pop_req_valid  (Top_Pop_req_valid ),
    //    .Top_Pop_req_DATA   (Top_Pop_req_DATA  ),//temp
       .Top_Pop_req_ready  (Top_Pop_req_ready ),
       .Top_Pop_resp_valid (Top_Pop_resp_valid),
       .Top_Pop_resp_Data  (Top_Pop_resp_Data ),    
       .Top_Pop_resp_ready (Top_Pop_resp_ready),
       //Push to Child
       .Parents_Push_valid (Parents2Child_Push_valid[0]),
       .Parents_Push_Data  (Parents2Child_Push_Data [0]),
       //Pop  to Child
       .Parents_Pop_req_valid  (Parents2Child_Pop_req_valid [0]),
       .Parents_Pop_resp_valid (Child2Parents_Pop_resp_valid[0]),
       .Parents_Pop_resp_data  (Child2Parents_Pop_resp_data [0]),//[SINGLE_DATA_WITHOUT_COUNTER-1:0]
       //Addr Io
       .Top_My_addr            (1'b0),
       .Pifo_Empty             (Pifo_Empty),
       .Parents_Child_Addr(Parents2Child_Addr[0])
    );

   genvar i ;
   generate 
      for(i = 1; i < LEVEL_TOTAL - 1; i = i + 1) begin
         PIFO_SRAM_Level_other#(
            .PTW     (PTW),// RANK WIDTH
            .MTW     (MTW),// Meta Data WIDTH
            .CTW     (CTW),// COUNT WIDTH
            .LEVEL   (i)
            //Don't Touch
            //parameter LEVEL_ADW                               = 2*LEVEL                      ,
            //parameter NEXT_LEVEL_ADW                          = 2*(LEVEL+1)                  ,
            //parameter SINGLE_DATA_WIDTH                       = PTW + MTW + CTW              ,
            //parameter SINGLE_DATA_WITHOUT_COUNTER             = PTW + MTW                    ,
            //parameter SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE = ({{PTW{1'b1}},{MTW{1'b0}}})  ,
            //parameter SINGLE_DATA_INIT_VALUE                  = {SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE,{CTW{1'b0}}},
            //parameter RAM_DATA_INIT_VALUE                     = {4{SINGLE_DATA_INIT_VALUE}}  ,
            //parameter RAM_DATA_WIDTH                          = 4*SINGLE_DATA_WIDTH 
         ) PIFO_SRAM_Level_other_inst
         (
            // Clock and Reset
            .clk   (clk),              // I - Clock
            .rst   (rst),              // I - Active Low Async Reset
            //Push From Top 
            .Parents_Push_valid (Parents2Child_Push_valid[i-1]),
            .Parents_Push_Data  (Parents2Child_Push_Data [i-1]),
            //Pop from Top
            .Parents_Pop_req_valid  (Parents2Child_Pop_req_valid[i-1]),
            .Parents_Pop_req_DATA   (),//temp
            .Parents_Pop_resp_valid (Child2Parents_Pop_resp_valid[i-1]),
            .Parents_Pop_resp_data  (Child2Parents_Pop_resp_data [i-1]),    
            //Push to Child
            .Child_Push_valid (Parents2Child_Push_valid[i]),
            .Child_Push_Data  (Parents2Child_Push_Data [i]),
            //Pop  to Child
            .Child_Pop_req_valid  (Parents2Child_Pop_req_valid [i]),
            .Child_Pop_resp_valid (Child2Parents_Pop_resp_valid[i]),
            .Child_Pop_resp_data  (Child2Parents_Pop_resp_data [i]),//[SINGLE_DATA_WITHOUT_COUNTER-1:0]
            //Addr Io
            .Parents_My_addr        (Parents2Child_Addr[i-1] & {2*i{1'b1}}),
            .Parents2Child_Addr     (Parents2Child_Addr[i])
         );            
      end
   endgenerate

   PIFO_SRAM_Level_other#(
      .PTW     (PTW),// RANK WIDTH
      .MTW     (MTW),// Meta Data WIDTH
      .CTW     (CTW),// COUNT WIDTH
      .LEVEL   (LEVEL_TOTAL-1)
      //Don't Touch
      //parameter LEVEL_ADW                               = 2*LEVEL                      ,
      //parameter NEXT_LEVEL_ADW                          = 2*(LEVEL+1)                  ,
      //parameter SINGLE_DATA_WIDTH                       = PTW + MTW + CTW              ,
      //parameter SINGLE_DATA_WITHOUT_COUNTER             = PTW + MTW                    ,
      //parameter SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE = ({{PTW{1'b1}},{MTW{1'b0}}})  ,
      //parameter SINGLE_DATA_INIT_VALUE                  = {SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE,{CTW{1'b0}}},
      //parameter RAM_DATA_INIT_VALUE                     = {4{SINGLE_DATA_INIT_VALUE}}  ,
      //parameter RAM_DATA_WIDTH                          = 4*SINGLE_DATA_WIDTH 
   ) PIFO_SRAM_Level_last_inst
   (
      // Clock and Reset
      .clk   (clk),              // I - Clock
      .rst   (rst),              // I - Active Low Async Reset
      //Push From Top 
      .Parents_Push_valid (Parents2Child_Push_valid[LEVEL_TOTAL-2]),
      .Parents_Push_Data  (Parents2Child_Push_Data [LEVEL_TOTAL-2]),
      //Pop from Top
      .Parents_Pop_req_valid  (Parents2Child_Pop_req_valid[LEVEL_TOTAL-2]),
      .Parents_Pop_req_DATA   (),//temp
      .Parents_Pop_resp_valid (Child2Parents_Pop_resp_valid[LEVEL_TOTAL-2]),
      .Parents_Pop_resp_data  (Child2Parents_Pop_resp_data [LEVEL_TOTAL-2]),    
      //Push to Child
      .Child_Push_valid (Parents2Child_Push_valid[LEVEL_TOTAL-1]),
      .Child_Push_Data  (Parents2Child_Push_Data [LEVEL_TOTAL-1]),
      //Pop  to Child
      .Child_Pop_req_valid  (Parents2Child_Pop_req_valid [LEVEL_TOTAL-1]),
      .Child_Pop_resp_valid (1'b0),
      .Child_Pop_resp_data  (SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE),//[SINGLE_DATA_WITHOUT_COUNTER-1:0]
      //Addr Io
      .Parents_My_addr        (Parents2Child_Addr[LEVEL_TOTAL-2] & {2*(LEVEL_TOTAL-1){1'b1}}),
      .Parents2Child_Addr     (Parents2Child_Addr[LEVEL_TOTAL-1])
   );   

endmodule