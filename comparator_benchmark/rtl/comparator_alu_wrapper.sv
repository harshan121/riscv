`timescale 1ns/1ps

module comparator_alu_wrapper #(
    parameter bit USE_TREE = 1'b0
) (
    input  logic [63:0] a,
    input  logic [63:0] b,
    input  logic [1:0]  compare_op,
    output logic        result
);
    logic signed_lt;
    logic signed_lte;
    logic unsigned_lt;
    logic unsigned_lte;

    generate
        if (USE_TREE) begin : gen_tree_comparator
            comparator_tree comparator (
                .a(a), .b(b), .signed_lt(signed_lt), .signed_lte(signed_lte),
                .unsigned_lt(unsigned_lt), .unsigned_lte(unsigned_lte)
            );
        end else begin : gen_inferred_comparator
            comparator_inferred comparator (
                .a(a), .b(b), .signed_lt(signed_lt), .signed_lte(signed_lte),
                .unsigned_lt(unsigned_lt), .unsigned_lte(unsigned_lte)
            );
        end
    endgenerate

    always_comb begin
        case (compare_op)
            2'b00: result = signed_lt;
            2'b01: result = signed_lte;
            2'b10: result = unsigned_lt;
            2'b11: result = unsigned_lte;
            default: result = 1'b0;
        endcase
    end
endmodule
