`timescale 1ns/1ps

module comparator_inferred (
    input  logic [63:0] a,
    input  logic [63:0] b,
    output logic        signed_lt,
    output logic        signed_lte,
    output logic        unsigned_lt,
    output logic        unsigned_lte
);
    assign signed_lt   = $signed(a) <  $signed(b);
    assign signed_lte  = $signed(a) <= $signed(b);
    assign unsigned_lt = a < b;
    assign unsigned_lte = a <= b;
endmodule
