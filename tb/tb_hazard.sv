// Directed hazard test: every instruction back-to-back, each case aimed at
// one forwarding / stall path. Also checks the exact number of stall cycles
// so that missing stalls *and* false stalls are caught.
`timescale 1ns/1ps
module tb_hazard #(
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

    `include "tb_soc.svh"

    always #5 clk = ~clk;

    `include "rv_asm.svh"

    int stalls = 0;
    // load-use bubbles actually inserted (not cycles frozen by a memory wait)
    always @(posedge clk) if (!rst && dut.stall && !dut.mem_stall) stalls++;

    localparam int EXPECTED_STALLS = 4;

    initial begin
        #1;
        // ---- ALU -> ALU forwarding
        emit(i_t(16, 0, 3'b000, 1, OPC_I_ALU));        // addi x1, x0, 16
        emit(i_t(8,  1, 3'b000, 2, OPC_I_ALU));        // addi x2, x1, 8      EX/MEM -> rs1
        emit(r_t(7'h00, 2, 1, 3'b000, 3, OPC_ALU));    // add  x3, x1, x2     MEM/WB -> rs1, EX/MEM -> rs2
        // ---- Forwarding priority: newest value wins
        emit(i_t(1, 0, 3'b000, 4, OPC_I_ALU));         // addi x4, x0, 1
        emit(i_t(2, 0, 3'b000, 4, OPC_I_ALU));         // addi x4, x0, 2
        emit(r_t(7'h00, 4, 4, 3'b000, 5, OPC_ALU));    // add  x5, x4, x4     -> 4, not 2/3
        // ---- x0 is never forwarded
        emit(i_t(7, 0, 3'b000, 0, OPC_I_ALU));         // addi x0, x0, 7
        emit(r_t(7'h00, 0, 0, 3'b000, 6, OPC_ALU));    // add  x6, x0, x0     -> 0
        // ---- Store data forwarding
        emit(i_t(-5, 0, 3'b000, 7, OPC_I_ALU));        // addi x7, x0, -5
        emit(s_t(0, 7, 1, F3_D));                      // sd   x7, 0(x1)      EX/MEM -> store data
        // ---- Load-use (stall #1)
        emit(i_t(0, 1, F3_D, 8, OPC_I_LOAD));          // ld   x8, 0(x1)
        emit(i_t(1, 8, 3'b000, 9, OPC_I_ALU));         // addi x9, x8, 1      -> -4
        // ---- Load -> store data (stall #2)
        emit(i_t(0, 1, F3_D, 10, OPC_I_LOAD));         // ld   x10, 0(x1)
        emit(s_t(8, 10, 1, F3_D));                     // sd   x10, 8(x1)     mem[24] = -5
        emit(i_t(8, 1, F3_D, 11, OPC_I_LOAD));         // ld   x11, 8(x1)     -> -5
        // ---- Load -> load address (stall #3)
        emit(s_t(0, 2, 0, F3_D));                      // sd   x2, 0(x0)      mem[0] = 24
        emit(i_t(0, 0, F3_D, 12, OPC_I_LOAD));         // ld   x12, 0(x0)     -> 24
        emit(i_t(0, 12, F3_D, 13, OPC_I_LOAD));        // ld   x13, 0(x12)    -> mem[24] = -5
        // ---- Load at distance 2: MEM/WB forwarding, no stall
        emit(i_t(0, 1, F3_D, 14, OPC_I_LOAD));         // ld   x14, 0(x1)     -> -5
        emit(i_t(3, 0, 3'b000, 15, OPC_I_ALU));        // addi x15, x0, 3
        emit(r_t(7'h00, 15, 14, 3'b000, 16, OPC_ALU)); // add  x16, x14, x15  -> -2
        // ---- Load -> branch (stall #4), branch taken
        emit(i_t(0, 0, F3_D, 17, OPC_I_LOAD));         // ld   x17, 0(x0)     -> 24
        emit(b_t(8, 2, 17, F3_BEQ));                   // beq  x17, x2, +8
        emit(i_t(99, 0, 3'b000, 18, OPC_I_ALU));       //   addi x18, x0, 99  (skipped)
        // ---- LUI -> ALU forwarding
        emit(u_t(1, 21, OPC_LUI));                     // lui  x21, 1
        emit(i_t(5, 21, 3'b000, 21, OPC_I_ALU));       // addi x21, x21, 5    -> 0x1005
        // ---- No false stall: LUI whose imm bits look like rs1 = x22
        emit(i_t(0, 0, F3_D, 22, OPC_I_LOAD));         // ld   x22, 0(x0)
        emit(u_t(22 << 3, 23, OPC_LUI));               // lui  x23, 0xB0      (ins[19:15] == 22)
        // ---- ALU -> JALR forwarding
        emit(u_t(0, 25, OPC_AUIPC));                   // auipc x25, 0
        emit(i_t(12, 25, 3'b000, 26, OPC_JALR));       // jalr x26, 12(x25)   EX/MEM -> rs1
        emit(i_t(99, 0, 3'b000, 27, OPC_I_ALU));       //   addi x27, x0, 99  (skipped)
        emit(r_t(7'h20, 25, 26, 3'b000, 28, OPC_ALU)); // sub  x28, x26, x25  -> 8
        emit(INS_EBREAK);

        run_to_halt(500);

        check(2,  64'd24,                 "alu->alu ex/mem");
        check(3,  64'd40,                 "alu->alu both paths");
        check(5,  64'd4,                  "forward priority");
        check(6,  64'd0,                  "x0 not forwarded");
        check(9,  -64'sd4,                "load-use");
        check(11, -64'sd5,                "load->store data");
        check(13, -64'sd5,                "load->load address");
        check(16, -64'sd2,                "load dist 2");
        check(18, 64'd0,                  "load->branch taken");
        check(21, 64'h1005,               "lui->alu");
        check(23, 64'h000B_0000,          "lui after load");
        check(27, 64'd0,                  "jalr skipped");
        check(28, 64'd8,                  "alu->jalr");

        // With slow / irregular fetch a consumer can arrive late and need no
        // bubble, so the exact count only holds with ideal memory.
        if ((MEM_LAT == 1 && !RAND_STALL) ? (stalls != EXPECTED_STALLS) : (stalls > EXPECTED_STALLS)) begin
            $display("FAIL stall cycles: got %0d expected %0d", stalls, EXPECTED_STALLS);
            errors++;
        end else begin
            $display("ok   stall cycles = %0d", stalls);
        end

        finish();
    end
endmodule
