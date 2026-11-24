`timescale 1ns/1ps

module tb_comparator;
    logic [63:0] a;
    logic [63:0] b;
    logic tree_result;
    logic inferred_result;
    logic optimized_result;
    longint unsigned tests = 0;
    longint unsigned mismatches = 0;
    logic [63:0] state = 64'h9e37_79b9_7f4a_7c15;

    less_than_equal_tree tree_dut (.a(a), .b(b), .result(tree_result));
    less_than_equal_inferred inferred_dut (.a(a), .b(b), .result(inferred_result));
    less_than_equal_tree_optimized optimized_dut (.a(a), .b(b), .result(optimized_result));

    function automatic logic [63:0] next_random();
        state = state ^ (state << 13);
        state = state ^ (state >> 7);
        state = state ^ (state << 17);
        return state;
    endfunction

    task automatic check_case(input logic [63:0] test_a, input logic [63:0] test_b);
        logic expected;
        begin
            a = test_a;
            b = test_b;
            #1;
            expected = $signed(a) <= $signed(b);
            tests++;
            if (tree_result !== expected) begin
                mismatches++;
                $display("TREE_MISMATCH a=%h b=%h got=%b expected=%b", a, b, tree_result, expected);
                $fatal(1, "tree comparison failure");
            end
            if (inferred_result !== expected) begin
                mismatches++;
                $display("INFERRED_MISMATCH a=%h b=%h got=%b expected=%b", a, b, inferred_result, expected);
                $fatal(1, "inferred comparison failure");
            end
            if (optimized_result !== expected) begin
                mismatches++;
                $display("OPTIMIZED_MISMATCH a=%h b=%h got=%b expected=%b", a, b, optimized_result, expected);
                $fatal(1, "optimized comparison failure");
            end
        end
    endtask

    initial begin
        integer i;
        $dumpfile("comparator_benchmark/signed_le_experiment/reports/activity.vcd");
        $dumpvars(0, tb_comparator);
        check_case(64'h0, 64'h0);
        check_case(64'h1234_5678_9abc_def0, 64'h1234_5678_9abc_def0);
        check_case(64'd17, 64'd42);
        check_case(64'hffff_ffff_ffff_fff0, 64'hffff_ffff_ffff_fff8);
        check_case(64'd1, 64'hffff_ffff_ffff_ffff);
        check_case(64'hffff_ffff_ffff_ffff, 64'd1);
        check_case(64'h8000_0000_0000_0000, 64'h7fff_ffff_ffff_ffff);
        check_case(64'h7fff_ffff_ffff_ffff, 64'h8000_0000_0000_0000);
        check_case(64'h8000_0000_0000_0000, 64'h8000_0000_0000_0000);
        check_case(64'hffff_ffff_ffff_ffff, 64'hffff_ffff_ffff_ffff);
        check_case(64'h8000_0000_0000_0000, 64'h0);
        check_case(64'h0, 64'h8000_0000_0000_0000);
        check_case(64'h0, 64'h1);
        check_case(64'h1, 64'h0);
        check_case(64'haaaa_aaaa_aaaa_aaaa, 64'h5555_5555_5555_5555);
        check_case(64'h5555_5555_5555_5555, 64'haaaa_aaaa_aaaa_aaaa);
        for (i = 0; i < 100000; i++) begin
            check_case(next_random(), next_random());
        end
        $display("TESTS=%0d MISMATCHES=%0d", tests, mismatches);
        $display("FUNCTIONAL_VERIFICATION_PASS");
        $finish;
    end
endmodule
