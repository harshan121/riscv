// Fault handling test. One build, case chosen with +CASE=<n>.
//
// Program layout for faulting cases:
//   0  addi x1, x0, 11        older: must retire
//   4  addi x5, x0, 77        older (a faulting load must not overwrite x5)
//   8  lui  x10, 8            older: x10 = 0x8000 (start of the D-side error region)
//   12 sd   x1, 0(x0)         older store: must complete (mem[0] = 11)
//   16 <faulting instruction>
//   .. addi x3, x0, 33        younger: must not retire
//   .. sd   x1, 64(x0)        younger store: must not reach memory
//   .. ebreak
//
// After the halt the test also checks that the core keeps both AXI ports
// idle with nothing outstanding.
`timescale 1ns/1ps
module tb_fault #(
    parameter bit BP_ENABLE  = 1,
    parameter bit USE_GSHARE = 1,
    parameter bit ENABLE_RAS = 1,
    parameter int MEM_LAT    = 1,
    parameter bit RAND_STALL = 0
);
    import riscv_pkg::*;

    localparam int PAD = 0;

    logic clk = 0;
    logic rst = 1;
    logic halt;

    `define TB_ERR_BASES
    localparam logic [63:0] IERR_BASE = 64'h4000;   // instruction fetch error region
    localparam logic [63:0] DERR_BASE = 64'h8000;   // data access error region
    `include "tb_soc.svh"

    always #5 clk = ~clk;

    `include "rv_asm.svh"

    function automatic logic [63:0] dword(input int a);
        logic [63:0] d;
        for (int i = 0; i < 8; i++) d[i*8 +: 8] = dmem.mem[a + i];
        return d;
    endfunction

    task automatic expect_eq(input logic [63:0] got, exp, input string what);
        if (got !== exp) begin
            $display("FAIL %s: got %h expected %h", what, got, exp);
            errors++;
        end else begin
            $display("ok   %s = %h", what, got);
        end
    endtask

    int    tcase;
    string name;
    logic [3:0]  exp_cause;
    logic [63:0] exp_pc;
    bit    faulting;

    initial begin
        if (!$value$plusargs("CASE=%d", tcase)) tcase = 0;
        #1;
        faulting  = 1;
        exp_pc    = 64'd16;

        emit(i_t(11, 0, 3'b000, 1, OPC_I_ALU));        // 0  addi x1, x0, 11
        emit(i_t(77, 0, 3'b000, 5, OPC_I_ALU));        // 4  addi x5, x0, 77
        emit(u_t(8, 10, OPC_LUI));                     // 8  lui  x10, 8
        emit(s_t(0, 1, 0, F3_D));                      // 12 sd   x1, 0(x0)

        case (tcase)                                   // 16 ...
            0: begin name = "illegal (mul, M ext.)";  exp_cause = CAUSE_ILLEGAL;
                     emit(r_t(7'h01, 2, 1, 3'b000, 5, OPC_ALU)); end
            1: begin name = "illegal compressed 0000"; exp_cause = CAUSE_ILLEGAL;
                     emitc(16'h0000); end
            2: begin name = "unsupported csrrs";       exp_cause = CAUSE_ILLEGAL;
                     emit(i_t(12'hB00, 0, 3'b010, 5, OPC_SYSTEM)); end
            3: begin name = "ecall";                   exp_cause = CAUSE_ECALL_M;
                     emit(INS_ECALL); end
            4: begin name = "misaligned load";         exp_cause = CAUSE_LOAD_MISALIGN;
                     emit(i_t(4, 0, F3_D, 5, OPC_I_LOAD)); end          // ld x5, 4(x0)
            5: begin name = "misaligned store";        exp_cause = CAUSE_STORE_MISALIGN;
                     emit(s_t(34, 1, 0, F3_W)); end                     // sw x1, 34(x0)
            6: begin name = "load access fault";       exp_cause = CAUSE_LOAD_ACCESS;
                     emit(i_t(0, 10, F3_D, 5, OPC_I_LOAD)); end         // ld x5, 0(x10)
            7: begin name = "store access fault";      exp_cause = CAUSE_STORE_ACCESS;
                     emit(s_t(0, 1, 10, F3_D)); end                     // sd x1, 0(x10)
            8: begin name = "fetch access fault";      exp_cause = CAUSE_FETCH_ACCESS;
                     exp_pc = IERR_BASE;
                     emit(j_t(int'(IERR_BASE) - 16, 0)); end            // jal x0, 0x4000
            9: begin name = "illegal on wrong path (no fault)";
                     faulting = 0;
                     emit(b_t(8, 0, 0, F3_BEQ));                        // 16 beq x0,x0,+8
                     emit(32'hFFFF_FFFF);                               // 20 illegal, never executed
                     emit(i_t(33, 0, 3'b000, 3, OPC_I_ALU));            // 24 addi x3, x0, 33
                     emit(INS_EBREAK); end                              // 28
            default: $fatal(1, "unknown CASE %0d", tcase);
        endcase

        if (faulting) begin
            emit(i_t(33, 0, 3'b000, 3, OPC_I_ALU));    // younger: addi x3, x0, 33
            emit(s_t(64, 1, 0, F3_D));                 // younger: sd x1, 64(x0)
            emit(INS_EBREAK);
        end

        repeat (3) @(posedge clk);
        rst = 0;
        while (!halt && cycles < 2000) begin
            @(posedge clk);
            cycles++;
        end
        repeat (50) @(posedge clk);                    // let the bus drain

        $display("case %0d: %s", tcase, name);
        expect_eq(halt,        1, "halted");
        expect_eq(fault_valid, 1, "fault_valid");
        if (faulting) begin
            expect_eq(fault_cause, exp_cause, "fault_cause");
            expect_eq(fault_pc,    exp_pc,    "fault_pc");
            expect_eq(dut.u_id.u_reg_file.regs[3], 0, "younger addi not retired (x3)");
            expect_eq(dword(64), 0,                   "younger store not performed");
        end else begin
            expect_eq(fault_cause, CAUSE_BREAKPOINT,  "fault_cause (ebreak)");
            expect_eq(fault_pc,    64'd28,            "fault_pc (ebreak)");
            expect_eq(dut.u_id.u_reg_file.regs[3], 33, "branch target executed (x3)");
        end
        expect_eq(dut.u_id.u_reg_file.regs[1],  11,      "older addi retired (x1)");
        expect_eq(dut.u_id.u_reg_file.regs[5],  77,      "x5 not written by fault");
        expect_eq(dut.u_id.u_reg_file.regs[10], 64'h8000, "older lui retired (x10)");
        expect_eq(dword(0),  11, "older store performed");
        expect_eq(dword(32), 0,  "misaligned store not performed");

        // AXI quiescent after the halt
        expect_eq(i_arvalid, 0, "I-side ARVALID low");
        expect_eq(imem.rq_addr.size(), 0, "I-side reads drained");
        expect_eq(d_arvalid | d_awvalid | d_wvalid, 0, "D-side idle");
        expect_eq(dut.u_if.if_fetch_unit.m_count, 0, "fetch: no outstanding requests");

        finish();
    end
endmodule
