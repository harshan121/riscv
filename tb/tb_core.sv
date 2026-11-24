// Self-checking functional test for the 5-stage core.
// PAD = NOPs inserted after every instruction (0 = back-to-back, relies on
// the hazard unit; 2 = no hazards at all).
`timescale 1ns/1ps
module tb_core #(
    parameter int PAD        = 0,
    parameter bit BP_ENABLE  = 1,
    parameter bit USE_GSHARE = 1,
    parameter bit ENABLE_RAS = 1,
    parameter int MEM_LAT    = 1,
    parameter bit RAND_STALL = 0
);
    import riscv_pkg::*;

    logic clk = 0;
    logic rst = 1;
    logic halt;

    `include "tb_soc.svh"

    always #5 clk = ~clk;

    `include "rv_asm.svh"

    initial begin
        #1;
        // ---------------- ALU / immediates ----------------
        emit(i_t(5,  0, 3'b000, 1, OPC_I_ALU));                // addi  x1, x0, 5
        emit(i_t(-3, 0, 3'b000, 2, OPC_I_ALU));                // addi  x2, x0, -3
        emit(r_t(7'h00, 2, 1, 3'b000, 3, OPC_ALU));            // add   x3, x1, x2
        emit(r_t(7'h20, 2, 1, 3'b000, 4, OPC_ALU));            // sub   x4, x1, x2
        emit(r_t(7'h00, 2, 1, 3'b111, 5, OPC_ALU));            // and   x5, x1, x2
        emit(r_t(7'h00, 2, 1, 3'b110, 6, OPC_ALU));            // or    x6, x1, x2
        emit(r_t(7'h00, 2, 1, 3'b100, 7, OPC_ALU));            // xor   x7, x1, x2
        emit(r_t(7'h00, 1, 2, 3'b010, 8, OPC_ALU));            // slt   x8, x2, x1
        emit(r_t(7'h00, 1, 2, 3'b011, 9, OPC_ALU));            // sltu  x9, x2, x1
        emit(i_t(60, 1, 3'b001, 10, OPC_I_ALU));               // slli  x10, x1, 60
        emit(i_t(12'h400 | 1, 2, 3'b101, 11, OPC_I_ALU));      // srai  x11, x2, 1
        emit(i_t(60, 2, 3'b101, 12, OPC_I_ALU));               // srli  x12, x2, 60
        emit(u_t(20'h12345, 13, OPC_LUI));                     // lui   x13, 0x12345
        emit(u_t(20'h80000, 14, OPC_LUI));                     // lui   x14, 0x80000
        emit(i_t(-1, 14, 3'b000, 14, OPC_I_ALU_32));           // addiw x14, x14, -1  -> 0x7fffffff
        emit(i_t(1, 14, 3'b000, 15, OPC_I_ALU_32));            // addiw x15, x14, 1   -> sext 0x80000000
        emit(i_t(12'h400 | 4, 15, 3'b101, 16, OPC_I_ALU_32));  // sraiw x16, x15, 4
        emit(i_t(4, 15, 3'b101, 17, OPC_I_ALU_32));            // srliw x17, x15, 4
        emit(r_t(7'h20, 1, 2, 3'b000, 18, OPC_ALU_32));        // subw  x18, x2, x1  -> -8
        emit(u_t(0, 19, OPC_AUIPC));                           // auipc x19, 0  (pc = 19*SLOT)

        // ---------------- Loads / stores ----------------
        emit(s_t(0,  4, 0, F3_D));                             // sd  x4, 0(x0)
        emit(s_t(8,  2, 0, F3_W));                             // sw  x2, 8(x0)
        emit(s_t(17, 1, 0, F3_B));                             // sb  x1, 17(x0)
        emit(s_t(20, 2, 0, F3_H));                             // sh  x2, 20(x0)
        emit(i_t(0,  0, F3_D,  20, OPC_I_LOAD));               // ld  x20, 0(x0)
        emit(i_t(8,  0, F3_W,  21, OPC_I_LOAD));               // lw  x21, 8(x0)
        emit(i_t(8,  0, F3_WU, 22, OPC_I_LOAD));               // lwu x22, 8(x0)
        emit(i_t(17, 0, F3_B,  23, OPC_I_LOAD));               // lb  x23, 17(x0)
        emit(i_t(20, 0, F3_H,  24, OPC_I_LOAD));               // lh  x24, 20(x0)
        emit(i_t(20, 0, F3_HU, 25, OPC_I_LOAD));               // lhu x25, 20(x0)

        // ---------------- Control flow ----------------
        emit(b_t(2*SLOT, 1, 1, F3_BEQ));                       // beq  x1, x1, +2  (taken)
        emit(i_t(99, 0, 3'b000, 26, OPC_I_ALU));               //   addi x26, x0, 99  (skipped)
        emit(b_t(2*SLOT, 1, 1, F3_BNE));                       // bne  x1, x1, +2  (not taken)
        emit(i_t(1, 26, 3'b000, 26, OPC_I_ALU));               //   addi x26, x26, 1  (runs)
        emit(b_t(2*SLOT, 1, 2, F3_BLTU));                      // bltu x2, x1, +2  (not taken)
        emit(i_t(2, 26, 3'b000, 26, OPC_I_ALU));               //   addi x26, x26, 2  (runs) -> 3
        emit(b_t(2*SLOT, 1, 2, F3_BLT));                       // blt  x2, x1, +2  (taken)
        emit(i_t(100, 26, 3'b000, 26, OPC_I_ALU));             //   (skipped)
        emit(j_t(2*SLOT, 27));                                 // jal  x27, +2
        emit(i_t(100, 26, 3'b000, 26, OPC_I_ALU));             //   (skipped)
        emit(u_t(0, 28, OPC_AUIPC));                           // auipc x28, 0
        emit(i_t(3*SLOT, 28, 3'b000, 29, OPC_JALR));           // jalr x29, 3*SLOT(x28)
        emit(i_t(100, 26, 3'b000, 26, OPC_I_ALU));             //   (skipped)
        emit(r_t(7'h20, 28, 29, 3'b000, 30, OPC_ALU));         // sub  x30, x29, x28
        emit(INS_EBREAK);

        run_to_halt(2000);

        check(1,  64'd5,                    "addi");
        check(2,  -64'sd3,                  "addi neg");
        check(3,  64'd2,                    "add");
        check(4,  64'd8,                    "sub");
        check(5,  64'd5,                    "and");
        check(6,  -64'sd3,                  "or");
        check(7,  -64'sd8,                  "xor");
        check(8,  64'd1,                    "slt");
        check(9,  64'd0,                    "sltu");
        check(10, 64'h5000_0000_0000_0000,  "slli");
        check(11, -64'sd2,                  "srai");
        check(12, 64'hF,                    "srli");
        check(13, 64'h0000_0000_1234_5000,  "lui");
        check(14, 64'h0000_0000_7FFF_FFFF,  "addiw");
        check(15, 64'hFFFF_FFFF_8000_0000,  "addiw ovf");
        check(16, 64'hFFFF_FFFF_F800_0000,  "sraiw");
        check(17, 64'h0000_0000_0800_0000,  "srliw");
        check(18, -64'sd8,                  "subw");
        check(19, 64'(19*SLOT),             "auipc");
        check(20, 64'd8,                    "sd/ld");
        check(21, -64'sd3,                  "sw/lw");
        check(22, 64'h0000_0000_FFFF_FFFD,  "lwu");
        check(23, 64'd5,                    "sb/lb");
        check(24, -64'sd3,                  "sh/lh");
        check(25, 64'h0000_0000_0000_FFFD,  "lhu");
        check(26, 64'd3,                    "branches");
        check(27, 64'(38*SLOT + 4),         "jal link");
        check(28, 64'(40*SLOT),             "auipc2");
        check(30, 64'(SLOT + 4),            "jalr link");

        finish();
    end
endmodule
