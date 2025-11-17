module iverilog_dump();
initial begin
    $dumpfile("tx_core_with_cpl.fst");
    $dumpvars(0, tx_core_with_cpl);
end
endmodule
