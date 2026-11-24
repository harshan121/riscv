// RVC system test: mixed 16/32-bit code running on the full core.
//   - 32-bit instructions at 2-mod-4 addresses (span two fetch words)
//   - every RV64C integer instruction class
//   - compressed branches / jumps, a branch that lands on an upper half-word
//   - calls via c.jalr (link pc+2) and jal (link pc+4), returns via c.jr ra
//   - two compressed branches in one fetch word, taken on alternate
//     iterations (they share one BTB entry, which keeps being retrained)
`timescale 1ns/1ps
module tb_rvc #(
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

    task automatic at(input int addr);   // assert the assembler is where the listing says
        if (pc_addr != addr) $fatal(1, "assembler at %0d, listing says %0d", pc_addr, addr);
    endtask

    initial begin
        #1;
        // Encoder spot checks against toolchain encodings
        if (c_jr(1) != 16'h8082 || c_addi(2, -16) != 16'h1141 || c_sdsp(1, 8) != 16'he406 ||
            c_ldsp(1, 8) != 16'h60a2 || c_li(10, 1) != 16'h4505 || c_mv(10, 11) != 16'h852e)
            $fatal(1, "compressed encoder mismatch");

        // ---------------- ALU, straddling 32-bit instructions ----------------
        at(0);   emit (i_t(256, 0, 3'b000, 2, OPC_I_ALU));     // addi  sp, x0, 256
        at(4);   emitc(c_li(10, 5));                           // c.li  x10, 5
                 emitc(c_li(11, -3));                          // c.li  x11, -3
        at(8);   emitc(c_mv(13, 10));                          // c.mv  x13, x10
        at(10);  emit (r_t(7'h00, 11, 10, 3'b000, 14, OPC_ALU));  // add x14, x10, x11  (spans words)
        at(14);  emitc(c_add(13, 11));                         // c.add   x13, x11   -> 2
                 emitc(c_addi(13, 7));                         // c.addi  x13, 7    -> 9
                 emitc(c_addiw(13, -1));                       // c.addiw x13, -1   -> 8
                 emitc(c_lui(15, 1));                          // c.lui   x15, 1    -> 0x1000
                 emitc(c_slli(15, 4));                         // c.slli  x15, 4    -> 0x10000
                 emitc(c_srli(15, 8));                         // c.srli  x15, 8    -> 0x100
                 emitc(c_srai(11, 1));                         // c.srai  x11, 1    -> -2
                 emitc(c_andi(10, 4));                         // c.andi  x10, 4    -> 4
                 emitc(c_sub(10, 11));                         // c.sub   x10, x11  -> 6
                 emitc(c_xor(10, 11));                         // c.xor   x10, x11  -> -8
        at(34);  emit (i_t(105, 0, 3'b000, 12, OPC_I_ALU));    // addi x12, x0, 105 (spans words)
        at(38);  emitc(c_or(12, 11));                          // c.or   x12, x11 -> -1
                 emitc(c_and(12, 14));                         // c.and  x12, x14 -> 2
                 emitc(c_subw(12, 10));                        // c.subw x12, x10 -> 10
                 emitc(c_addw(12, 12));                        // c.addw x12, x12 -> 20
        // ---------------- Loads / stores ----------------
        at(46);  emitc(c_addi16sp(-16));                       // sp = 240
                 emitc(c_addi4spn(8, 8));                      // x8 = sp + 8 = 248
                 emitc(c_sdsp(12, 0));                         // mem[240] = 20
                 emitc(c_ldsp(9, 0));                          // x9  = 20
                 emitc(c_swsp(11, 4));                         // mem32[244] = -2
                 emitc(c_lwsp(16, 4));                         // x16 = -2
                 emitc(c_sd(13, 8, 8));                        // mem[256] = 8
                 emitc(c_ld(14, 8, 8));                        // x14 = 8
                 emitc(c_sw(11, 8, 0));                        // mem32[248] = -2
                 emitc(c_lw(10, 8, 0));                        // x10 = -2
        // Save results before the prime registers are reused
        at(66);  emitc(c_mv(20, 10));  emitc(c_mv(21, 12));  emitc(c_mv(22, 13));  emitc(c_mv(23, 14));
                 emitc(c_mv(24, 15));  emitc(c_mv(25, 11));  emitc(c_mv(26, 8));   emitc(c_mv(27, 9));
        // ---------------- Control flow ----------------
        at(82);  emitc(c_j(4));                                // c.j  +4 -> 86
                 emitc(c_li(17, 31));                          //   (skipped)
        at(86);  emitc(c_li(8, 0));                            // i = 0
                 emitc(c_li(9, 10));                           // n = 10
        at(90);  emitc(c_addi(8, 1));                          // L1: i++
                 emitc(c_addi(9, -1));                         //     n--
                 emitc(c_bnez(9, -4));                         //     c.bnez n, L1
        at(96);  emitc(c_beqz(9, 6));                          // c.beqz n, +6 (taken) -> 102
        at(98);  emit (i_t(99, 0, 3'b000, 17, OPC_I_ALU));     //   (skipped, spans words)
        at(102); emitc(c_bnez(9, 4));                          // c.bnez n, +4 (not taken)
                 emitc(c_li(10, 7));                           // x10 = 7
        at(106); emit (b_t(8, 0, 0, F3_BEQ));                  // beq x0, x0, +8 -> 114 (upper half)
        at(110); emit (i_t(98, 0, 3'b000, 17, OPC_I_ALU));     //   (skipped)
        at(114); emitc(c_li(11, 3));                           // x11 = 3
        // ---------------- Calls / returns ----------------
        at(116); emit (u_t(0, 6, OPC_AUIPC));                  // auipc x6, 0       -> 116
                 emit (i_t(24, 6, 3'b000, 6, OPC_I_ALU));      // addi  x6, x6, 24  -> F = 140
        at(124); emitc(c_li(12, 0));                           // acc = 0
                 emitc(c_li(13, 3));                           // k = 3
        at(128); emitc(c_jalr(6));                             // L2: c.jalr x6   (x1 = 130)
        at(130); emit (j_t(140 - 130, 1));                     //     jal x1, F   (x1 = 134, spans words)
        at(134); emitc(c_addi(13, -1));                        //     k--
                 emitc(c_bnez(13, -8));                        //     c.bnez k, L2
        at(138); emitc(c_j(6));                                // c.j PAIR
        at(140); emitc(c_addi(12, 1));                         // F: acc++
                 emitc(c_jr(1));                               //    ret
        // ---------------- Two compressed branches in one fetch word ----------------
        at(144); emitc(c_li(14, 0));                           // PAIR: t = 0
                 emitc(c_li(19, 8));                           //   n = 8
                 emitc(c_li(18, 0));                           //   a = 0
                 emitc(c_li(28, 0));                           //   b = 0
        at(152); emitc(c_beqz(14, 6));                         // L3: A: if t == 0 -> 158  (word 152, half 0)
        at(154); emitc(c_bnez(14, 6));                         //     B: if t != 0 -> 160  (word 152, half 1)
                 emitc(c_li(17, 31));                          //     (never executed)
        at(158); emitc(c_addi(18, 1));                         //     a++  (A taken)
        at(160); emitc(c_addi(28, 1));                         //     b++  (every iteration)
                 emitc(c_li(15, 1));                           //     t = 1 - t
                 emitc(c_sub(15, 14));
                 emitc(c_mv(14, 15));
                 emitc(c_addi(19, -1));                        //     n--
        at(170); emit (b_t(152 - 170, 0, 19, F3_BNE));         //     bne n, x0, L3 (spans words)
        at(174); emitc(C_EBREAK);                              // END

        run_to_halt(5000);

        check(1,  64'd134,     "jal link (pc+4)");
        check(2,  64'd240,     "c.addi16sp");
        check(6,  64'd140,     "auipc+addi");
        check(8,  64'd10,      "c.bnez loop");
        check(9,  64'd0,       "loop counter");
        check(10, 64'd7,       "c.bnez not taken");
        check(11, 64'd3,       "beq to upper half");
        check(12, 64'd6,       "6 calls");
        check(13, 64'd0,       "call loop");
        check(16, -64'sd2,     "c.swsp/c.lwsp");
        check(17, 64'd0,       "skipped instructions");
        check(20, -64'sd2,     "c.sw/c.lw");
        check(21, 64'd20,      "c.or/and/subw/addw");
        check(22, 64'd8,       "c.add/addi/addiw");
        check(23, 64'd8,       "c.sd/c.ld");
        check(24, 64'h100,     "c.lui/slli/srli");
        check(25, -64'sd2,     "c.srai");
        check(26, 64'd248,     "c.addi4spn");
        check(27, 64'd20,      "c.sdsp/c.ldsp");
        check(18, 64'd4,       "branch pair: A taken 4x");
        check(28, 64'd8,       "branch pair: 8 iterations");
        check(14, 64'd0,       "branch pair: toggle");

        finish();
    end
endmodule
