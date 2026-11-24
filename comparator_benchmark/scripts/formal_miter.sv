module formal_miter (
    input logic [63:0] a,
    input logic [63:0] b
);
    logic inferred_signed_lt, inferred_signed_lte, inferred_unsigned_lt, inferred_unsigned_lte;
    logic tree_signed_lt, tree_signed_lte, tree_unsigned_lt, tree_unsigned_lte;

    comparator_inferred inferred_dut (
        .a(a), .b(b), .signed_lt(inferred_signed_lt), .signed_lte(inferred_signed_lte),
        .unsigned_lt(inferred_unsigned_lt), .unsigned_lte(inferred_unsigned_lte)
    );
    comparator_tree tree_dut (
        .a(a), .b(b), .signed_lt(tree_signed_lt), .signed_lte(tree_signed_lte),
        .unsigned_lt(tree_unsigned_lt), .unsigned_lte(tree_unsigned_lte)
    );

    always_comb begin
        assert(inferred_signed_lt == tree_signed_lt);
        assert(inferred_signed_lte == tree_signed_lte);
        assert(inferred_unsigned_lt == tree_unsigned_lt);
        assert(inferred_unsigned_lte == tree_unsigned_lte);
    end
endmodule
