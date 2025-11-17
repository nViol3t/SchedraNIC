module iverilog_dump();
initial begin
    $dumpfile("tx_queue_manager.fst");
    $dumpvars(0, tx_queue_manager);
end
endmodule
