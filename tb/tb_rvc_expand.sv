// Exhaustive check of rvc_expander against tb/rvc_ref.py (every 16-bit
// encoding with c[1:0] != 11), plus a few encodings produced by a real
// RISC-V toolchain.
`timescale 1ns/1ps
module tb_rvc_expand;
    import riscv_pkg::*;

    logic [15:0] c;
    logic [31:0] ins;
    logic        illegal;

    rvc_expander dut (.c(c), .ins(ins), .illegal(illegal));

    int errors = 0;
    int n = 0;

    task automatic expect_ins(input logic [15:0] cc, input logic [31:0] exp, input string what);
        c = cc; #1;
        if (ins !== exp) begin
            if (errors < 20) $display("FAIL %s: %h -> %h expected %h", what, cc, ins, exp);
            errors++;
        end
    endtask

    initial begin
        int fd, code;
        logic [15:0] cc;
        logic [31:0] exp;

        // Known toolchain encodings (GNU as / objdump)
        expect_ins(16'h0001, 32'h0000_0013, "c.nop");
        expect_ins(16'h4505, 32'h0010_0513, "c.li a0,1");
        expect_ins(16'h1141, 32'hff01_0113, "c.addi sp,sp,-16");
        expect_ins(16'he406, 32'h0011_3423, "c.sdsp ra,8(sp)");
        expect_ins(16'h60a2, 32'h0081_3083, "c.ldsp ra,8(sp)");
        expect_ins(16'h0141, 32'h0101_0113, "c.addi sp,sp,16");
        expect_ins(16'h8082, 32'h0000_8067, "c.jr ra (ret)");
        expect_ins(16'h852e, 32'h00b0_0533, "c.mv a0,a1");
        expect_ins(16'h9002, 32'h0010_0073, "c.ebreak");
        expect_ins(16'h0000, 32'h0000_0000, "illegal 0000");
        $display("toolchain spot checks: %0d error(s)", errors);

        fd = $fopen("build/rvc_golden.txt", "r");
        if (fd == 0) $fatal(1, "run tb/rvc_ref.py build/rvc_golden.txt first");
        while ($fscanf(fd, "%h %h\n", cc, exp) == 2) begin
            expect_ins(cc, exp, "golden");
            n++;
        end
        $fclose(fd);

        $display("%0d encodings checked, %0d error(s)", n, errors);
        if (errors == 0 && n == 49152) $display("PASS");
        else                           $display("FAIL");
        $finish;
    end
endmodule
