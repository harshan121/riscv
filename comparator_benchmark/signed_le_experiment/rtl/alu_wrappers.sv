`timescale 1ns/1ps

module rv64_alu_common (
    input  logic [63:0] a,
    input  logic [63:0] b,
    input  logic [1:0]  op,
    input  logic        signed_lte,
    output logic [63:0] result
);
    always_comb begin
        case (op)
            2'b00: result = a + b;
            2'b01: result = a - b;
            2'b10: result = {63'b0, signed_lte};
            2'b11: result = b;
            default: result = 64'b0;
        endcase
    end
endmodule

module rv64_alu_inferred (
    input logic [63:0] a, b,
    input logic [1:0] op,
    output logic [63:0] result
);
    logic signed_lte;
    less_than_equal_inferred comparator (.a(a), .b(b), .result(signed_lte));
    rv64_alu_common datapath (.a(a), .b(b), .op(op), .signed_lte(signed_lte), .result(result));
endmodule

module rv64_alu_tree (
    input logic [63:0] a, b,
    input logic [1:0] op,
    output logic [63:0] result
);
    logic signed_lte;
    less_than_equal_tree comparator (.a(a), .b(b), .result(signed_lte));
    rv64_alu_common datapath (.a(a), .b(b), .op(op), .signed_lte(signed_lte), .result(result));
endmodule

module rv64_alu_tree_optimized (
    input logic [63:0] a, b,
    input logic [1:0] op,
    output logic [63:0] result
);
    logic signed_lte;
    less_than_equal_tree_optimized comparator (.a(a), .b(b), .result(signed_lte));
    rv64_alu_common datapath (.a(a), .b(b), .op(op), .signed_lte(signed_lte), .result(result));
endmodule
