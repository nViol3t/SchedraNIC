`ifndef _PIFO_SRAM_DATA_TYPE_SV_
`define _PIFO_SRAM_DATA_TYPE_SV_

`define ADW  20   // ADDRESS WDITH  
`define PTW  16   // RANK WIDTH
`define MTW  32   // Meta Data WIDTH
`define CTW  10   // COUNT WIDTH
`define SINGLE_DATA_WIDTH  ((`PTW) + (`MTW) + (`CTW))
`define SINGLE_DATA_WITHOUT_COUNTER ((`PTW) + (`MTW))
`define SINGLE_DATA_WITHOUT_COUNTER_RESET_VALUE ({{`PTW{1'b1}},{`MTW{1'b0}}})
`define RAM_DATA_WIDTH  4*(`SINGLE_DATA_WIDTH)
package Data_Type_Setting ;
    localparam WAYS = 4 ;
     typedef struct packed {
         logic [`PTW -1 : 0]        rank      ;
         logic [`MTW -1 : 0]        meta_data ; 
      } Word_type_t ;    
     typedef struct packed {
          Word_type_t               word    ;
          logic [`CTW - 1 : 0]      counter ;
      } Data_type_t ;   

     typedef union packed{
          Data_type_t       [WAYS-1:0]     line_data    ;
          logic [`RAM_DATA_WIDTH-1:0]      ram_data     ;
     } Ram_type_t ;               
endpackage
    //4 ways
/*
interface Push_Io();
    import Data_Type_Setting::* ;
    logic Push_valid ;
    logic Push_ready ;    
    Word_type_t Push_Data ;

    modport Push_From_TOP(
        input  Push_valid , 
        input  Push_Data      
        output Push_ready         
    );
    //modport Push_From_Parents(
    //    input  Push_valid  ,
    //    input  Push_Data   
    //) ;
    //modport Push_To_Child(
    //    output  Push_valid  ,
    //    output  Push_Data     
    //) ;
endinterface
//
interface Pop_Io();
    import Data_Type_Setting :: * ;
    logic Pop_req_valid ;
    logic Pop_req_ready ;    
    logic Pop_resp_valid ;
    logic Pop_resp_ready ;   
    Word_type_t Pop_Data ;

    modport Pop_From_Top(
        input  Pop_req_valid    ,
        output Pop_req_ready    ,
        output Pop_resp_valid   ,
        input  Pop_resp_ready   ,          
        output Pop_resp_Data           
    ) ;

    modport Pop_From_Parents(
        input  Pop_req_valid    ,
        output Pop_resp_valid   ,      
        output Pop_Data       
    ) ;
    modport Pop_To_Child(
        output  Pop_req_valid    ,
        input   Pop_resp_valid   ,       
        input   Pop_Data      
    ) ;
endinterface

interface Addr_Io();
    logic [`ADW-1:0] My_Addr    ;
    logic [`ADW-1:0] Child_Addr ;  
      
    modport Init_Addr_Io(
        input   My_Addr ,
        output  Child_Addr
    ) ;
endinterface
*/
interface Ram_Io #(parameter ADDR_WIDTH = 20);
    import Data_Type_Setting :: * ; 

    logic                              wren       ;
    logic     [ADDR_WIDTH-1:0]         write_addr ;
    Ram_type_t                         write_data ;
    logic                              rden       ;
    logic     [ADDR_WIDTH-1:0]         read_addr  ; 
    Ram_type_t                         read_data  ;
endinterface //


`endif