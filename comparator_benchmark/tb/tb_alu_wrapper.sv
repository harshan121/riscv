`timescale 1ns/1ps

module tb_alu_wrapper;
    logic [63:0] a;
    logic [63:0] b;
    logic [1:0] compare_op;
    logic inferred_result;
    logic tree_result;

    comparator_alu_wrapper inferred_wrapper (
        .a(a), .b(b), .compare_op(compare_op), .result(inferred_result)
    );

    comparator_alu_wrapper #(.USE_TREE(1'b1)) tree_wrapper (
        .a(a), .b(b), .compare_op(compare_op), .result(tree_result)
    );

    task automatic check_operation(
        input logic [63:0] test_a,
        input logic [63:0] test_b,
        input logic [1:0] test_op,
        input logic expected
    );
        begin
            a = test_a;
            b = test_b;
            compare_op = test_op;
            #1;
            if (inferred_result !== expected || tree_result !== expected) begin
                $fatal(1, "wrapper mismatch a=%h b=%h op=%b expected=%b inferred=%b tree=%b",
                       a, b, compare_op, expected, inferred_result, tree_result);
            end
        end
    endtask

    initial begin
        check_operation(64'hffff_ffff_ffff_ffff, 64'd1, 2'b00, 1'b1);
        check_operation(64'hffff_ffff_ffff_ffff, 64'd1, 2'b01, 1'b1);
        check_operation(64'hffff_ffff_ffff_ffff, 64'd1, 2'b10, 1'b0);
        check_operation(64'hffff_ffff_ffff_ffff, 64'd1, 2'b11, 1'b0);
        $display("WRAPPER PASS");
        $finish;
    end
endmodule
