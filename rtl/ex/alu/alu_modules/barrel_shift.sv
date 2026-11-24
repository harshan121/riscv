module barrel_shift
    import riscv_pkg::*;
(
    input  logic [63:0] a,
    input  logic [5:0]  b,       // shift amount
    input  logic [3:0]  alu_op,
    output logic [63:0] y
);

    always_comb begin
        case (alu_op)
            ALU_SLL: y = a << b;
            ALU_SRL: y = a >> b;
            ALU_SRA: y = $signed(a) >>> b;
            default: y = 64'b0;
        endcase
    end

endmodule
