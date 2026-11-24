module equivalence (
    input logic [63:0] a,
    input logic [63:0] b
);
    logic inferred_result, tree_result, optimized_result;
    less_than_equal_inferred inferred_dut (.a(a), .b(b), .result(inferred_result));
    less_than_equal_tree tree_dut (.a(a), .b(b), .result(tree_result));
    less_than_equal_tree_optimized optimized_dut (.a(a), .b(b), .result(optimized_result));

    always_comb begin
        assert(tree_result == inferred_result);
        assert(optimized_result == inferred_result);
    end
endmodule
