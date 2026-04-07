module iverilog_dump();
initial begin
    $dumpfile("tx_queue_manager_change.fst");
    $dumpvars(0, tx_queue_manager_change);
end
endmodule
