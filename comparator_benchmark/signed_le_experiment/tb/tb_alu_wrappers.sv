`timescale 1ns/1ps

module tb_alu_wrappers;
    logic [63:0] a, b;
    logic [1:0] op;
    logic [63:0] inferred_result, tree_result, optimized_result;

    rv64_alu_inferred inferred_dut (.a(a), .b(b), .op(op), .result(inferred_result));
    rv64_alu_tree tree_dut (.a(a), .b(b), .op(op), .result(tree_result));
    rv64_alu_tree_optimized optimized_dut (.a(a), .b(b), .op(op), .result(optimized_result));

    task automatic check_operation(
        input logic [63:0] test_a,
        input logic [63:0] test_b,
        input logic [1:0] test_op,
        input logic [63:0] expected
    );
        begin
            a = test_a;
            b = test_b;
            op = test_op;
            #1;
            if (inferred_result !== expected || tree_result !== expected || optimized_result !== expected) begin
                $fatal(1, "ALU mismatch a=%h b=%h op=%b expected=%h inferred=%h tree=%h optimized=%h",
                       a, b, op, expected, inferred_result, tree_result, optimized_result);
            end
        end
    endtask

    initial begin
        check_operation(64'd40, 64'd2, 2'b00, 64'd42);
        check_operation(64'd40, 64'd2, 2'b01, 64'd38);
        check_operation(64'hffff_ffff_ffff_ffff, 64'd1, 2'b10, 64'd1);
        check_operation(64'd8, 64'd9, 2'b10, 64'd1);
        check_operation(64'd9, 64'd8, 2'b10, 64'd0);
        check_operation(64'd40, 64'h0123_4567_89ab_cdef, 2'b11, 64'h0123_4567_89ab_cdef);
        $display("ALU_INTEGRATION_FUNCTIONAL_PASS");
        $finish;
    end
endmodule
