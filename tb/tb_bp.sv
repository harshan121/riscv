// Branch predictor benchmark. One build per predictor configuration,
// program chosen at run time with +PROG=<n>. Every program self-checks.
//
//   0 loop        : 100-iteration counting loop
//   1 nested      : 10 x 10 nested loops
//   2 alternating : branch on (i & 1) inside a loop  -> T,NT,T,NT...
//   3 correlated  : two branches on the same random bit (B2 follows B1)
//   4 calls       : function called from two sites + a nested call
`timescale 1ns/1ps
module tb_bp #(
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

    // ------------------------------------------------------------------
    // Performance counters
    // ------------------------------------------------------------------
    int retired  = 0;
    int ctrl     = 0;
    int mispred  = 0;

    always @(posedge clk) if (!rst) begin
        if (dut.mem_wb.valid)  retired++;
        if (dut.bp_upd.valid)  ctrl++;
        if (dut.redirect)      mispred++;
    end

    // Short-hands
    localparam logic [2:0] ADD = 3'b000, AND = 3'b111, XOR = 3'b100, SLL = 3'b001, SRL = 3'b101;
    function automatic logic [31:0] addi(input int rd, rs1, imm); return i_t(imm, rs1, ADD, rd, OPC_I_ALU); endfunction
    function automatic logic [31:0] jalr(input int rd, rs1, imm); return i_t(imm, rs1, ADD, rd, OPC_JALR);  endfunction
    function automatic logic [31:0] blt (input int rs1, rs2, off); return b_t(off, rs2, rs1, F3_BLT);       endfunction
    function automatic logic [31:0] beq (input int rs1, rs2, off); return b_t(off, rs2, rs1, F3_BEQ);       endfunction

    int    prog;
    string name;

    initial begin
        if (!$value$plusargs("PROG=%d", prog)) prog = 0;
        #1;

        case (prog)
        0: begin
            name = "loop";
            emit(addi(5, 0, 0));                         // 0  i = 0
            emit(addi(6, 0, 100));                       // 1  n = 100
            emit(addi(5, 5, 1));                         // 2  loop: i++
            emit(blt(5, 6, -4));                         // 3  if i < n goto loop
            emit(INS_EBREAK);
        end
        1: begin
            name = "nested";
            emit(addi(5, 0, 0));                         // 0  i = 0
            emit(addi(6, 0, 10));                        // 1  n = 10
            emit(addi(7, 0, 0));                         // 2  count = 0
            emit(addi(8, 0, 0));                         // 3  outer: j = 0
            emit(addi(7, 7, 1));                         // 4  inner: count++
            emit(addi(8, 8, 1));                         // 5  j++
            emit(blt(8, 6, -8));                         // 6  if j < n goto inner
            emit(addi(5, 5, 1));                         // 7  i++
            emit(blt(5, 6, -20));                        // 8  if i < n goto outer
            emit(INS_EBREAK);
        end
        2: begin
            name = "alternating";
            emit(addi(5, 0, 0));                         // 0  i = 0
            emit(addi(6, 0, 100));                       // 1  n = 100
            emit(addi(9, 0, 0));                         // 2  odd = 0
            emit(i_t(1, 5, AND, 8, OPC_I_ALU));          // 3  loop: t = i & 1
            emit(beq(8, 0, 8));                          // 4  if t == 0 skip
            emit(addi(9, 9, 1));                         // 5  odd++
            emit(addi(5, 5, 1));                         // 6  skip: i++
            emit(blt(5, 6, -16));                        // 7  if i < n goto loop
            emit(INS_EBREAK);
        end
        3: begin
            name = "correlated";
            emit(addi(10, 0, 1445));                     // 0  x = seed
            emit(addi(5, 0, 0));                         // 1  i = 0
            emit(addi(6, 0, 200));                       // 2  n = 200
            emit(addi(11, 0, 0));                        // 3  c1 = 0
            emit(addi(12, 0, 0));                        // 4  c2 = 0
            emit(i_t(13, 10, SLL, 13, OPC_I_ALU));       // 5  loop: xorshift64
            emit(r_t(7'h00, 13, 10, XOR, 10, OPC_ALU));  // 6
            emit(i_t(7, 10, SRL, 13, OPC_I_ALU));        // 7
            emit(r_t(7'h00, 13, 10, XOR, 10, OPC_ALU));  // 8
            emit(i_t(17, 10, SLL, 13, OPC_I_ALU));       // 9
            emit(r_t(7'h00, 13, 10, XOR, 10, OPC_ALU));  // 10
            emit(i_t(1, 10, AND, 8, OPC_I_ALU));         // 11 b = x & 1
            emit(beq(8, 0, 8));                          // 12 B1: if b == 0 skip
            emit(addi(11, 11, 1));                       // 13   c1++
            emit(beq(8, 0, 8));                          // 14 B2: same condition
            emit(addi(12, 12, 1));                       // 15   c2++
            emit(addi(5, 5, 1));                         // 16 i++
            emit(blt(5, 6, -48));                        // 17 if i < n goto loop
            emit(INS_EBREAK);
        end
        4: begin
            name = "calls";
            emit(addi(9, 0, 0));                         // 0  acc = 0
            emit(addi(6, 0, 0));                         // 1  i = 0
            emit(addi(7, 0, 20));                        // 2  n = 20
            emit(j_t(20, 1));                            // 3  loop: call fA
            emit(j_t(24, 1));                            // 4  call fB
            emit(addi(6, 6, 1));                         // 5  i++
            emit(blt(6, 7, -12));                        // 6  if i < n goto loop
            emit(INS_EBREAK);                            // 7
            emit(addi(9, 9, 1));                         // 8  fA: acc += 1
            emit(jalr(0, 1, 0));                         // 9      ret
            emit(addi(28, 1, 0));                        // 10 fB: save ra
            emit(j_t(-12, 1));                           // 11     call fA (nested)
            emit(addi(9, 9, 10));                        // 12     acc += 10
            emit(addi(1, 28, 0));                        // 13     restore ra
            emit(jalr(0, 1, 0));                         // 14     ret
        end
        default: $fatal(1, "unknown PROG %0d", prog);
        endcase

        run_to_halt(20000);

        case (prog)
        0: check(5, 64'd100, "loop count");
        1: check(7, 64'd100, "nested count");
        2: check(9, 64'd50,  "odd count");
        3: begin
            // Reference model of the xorshift sequence
            logic [63:0] x = 64'd1445;
            int c = 0;
            for (int i = 0; i < 200; i++) begin
                x ^= x << 13; x ^= x >> 7; x ^= x << 17;
                c += int'(x[0]);
            end
            check(11, 64'(c), "B1 count");
            check(12, 64'(c), "B2 count");
        end
        4: check(9, 64'd240, "call accumulator");
        default: ;
        endcase

        $display("RESULT prog=%-12s cycles=%0d retired=%0d ctrl=%0d mispred=%0d errors=%0d",
                 name, cycles, retired, ctrl, mispred, errors);
        finish();
    end
endmodule
