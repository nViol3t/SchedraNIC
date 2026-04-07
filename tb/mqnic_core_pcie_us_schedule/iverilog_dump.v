module iverilog_dump();
initial begin
    $dumpfile("mqnic_core_pcie_us.fst");
    $dumpvars(0, mqnic_core_pcie_us);
end
endmodule
