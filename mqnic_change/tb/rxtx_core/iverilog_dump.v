module iverilog_dump();
initial begin
    $dumpfile("rxtx_core.fst");
    $dumpvars(0, rxtx_core);
end
endmodule
