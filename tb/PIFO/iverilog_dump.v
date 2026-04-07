module iverilog_dump();
initial begin
    $dumpfile("PIFO_SRAM_Top.fst");
    $dumpvars(0, PIFO_SRAM_Top);
end
endmodule
