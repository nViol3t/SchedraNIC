module iverilog_dump();
initial begin
    $dumpfile("rx_core.fst");
    $dumpvars(0, rx_core);
end
endmodule
