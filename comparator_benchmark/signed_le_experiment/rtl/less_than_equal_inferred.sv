`timescale 1ns/1ps

/* verilator lint_off DECLFILENAME */

module less_than_equal_inferred_param #(
    parameter int WIDTH = 64
) (
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    output logic             result
);
    assign result = $signed(a) <= $signed(b);
endmodule
/* verilator lint_on DECLFILENAME */

module less_than_equal_inferred (
    input  logic [63:0] a,
    input  logic [63:0] b,
    output logic        result
);
    less_than_equal_inferred_param #(.WIDTH(64)) comparator (
        .a(a), .b(b), .result(result)
    );
endmodule
