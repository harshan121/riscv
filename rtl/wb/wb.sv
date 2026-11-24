// Write-back stage: choose the result and drive the register-file write port.
module wb_stage
    import riscv_pkg::*;
(
    input  mem_wb_t     mem_wb,
    output logic        reg_write,
    output logic [4:0]  rd,
    output logic [63:0] rd_data
);

always_comb begin
    case (mem_wb.ctrl.wb_sel)
        WB_MEM:  rd_data = mem_wb.mem_data;
        WB_PC4:  rd_data = mem_wb.pc_seq;
        default: rd_data = mem_wb.alu_result;
    endcase
end

assign reg_write = mem_wb.valid && mem_wb.ctrl.reg_write;
assign rd        = mem_wb.rd;

endmodule
