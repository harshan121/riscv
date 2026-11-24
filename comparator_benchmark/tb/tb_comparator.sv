`timescale 1ns/1ps

module tb_comparator;
    logic [63:0] a;
    logic [63:0] b;
    logic inferred_signed_lt;
    logic inferred_signed_lte;
    logic inferred_unsigned_lt;
    logic inferred_unsigned_lte;
    logic tree_signed_lt;
    logic tree_signed_lte;
    logic tree_unsigned_lt;
    logic tree_unsigned_lte;

    longint unsigned test_count = 0;
    longint unsigned mismatch_count = 0;
    logic [63:0] prng_state = 64'h4d59_5df4_d0f3_3173;

    comparator_inferred inferred_dut (
        .a(a), .b(b),
        .signed_lt(inferred_signed_lt), .signed_lte(inferred_signed_lte),
        .unsigned_lt(inferred_unsigned_lt), .unsigned_lte(inferred_unsigned_lte)
    );

    comparator_tree tree_dut (
        .a(a), .b(b),
        .signed_lt(tree_signed_lt), .signed_lte(tree_signed_lte),
        .unsigned_lt(tree_unsigned_lt), .unsigned_lte(tree_unsigned_lte)
    );

    function automatic logic [63:0] next_random();
        prng_state = prng_state ^ (prng_state << 13);
        prng_state = prng_state ^ (prng_state >> 7);
        prng_state = prng_state ^ (prng_state << 17);
        return prng_state;
    endfunction

    task automatic report_mismatch(
        input string dut_name,
        input logic got_signed_lt,
        input logic got_signed_lte,
        input logic got_unsigned_lt,
        input logic got_unsigned_lte,
        input logic expected_signed_lt,
        input logic expected_signed_lte,
        input logic expected_unsigned_lt,
        input logic expected_unsigned_lte
    );
        begin
            mismatch_count++;
            $display("MISMATCH %s a=%h b=%h got=%b%b%b%b expected=%b%b%b%b",
                     dut_name, a, b, got_signed_lt, got_signed_lte,
                     got_unsigned_lt, got_unsigned_lte, expected_signed_lt,
                     expected_signed_lte, expected_unsigned_lt, expected_unsigned_lte);
        end
    endtask

    task automatic check_case(input logic [63:0] test_a, input logic [63:0] test_b);
        logic expected_signed_lt;
        logic expected_signed_lte;
        logic expected_unsigned_lt;
        logic expected_unsigned_lte;
        begin
            a = test_a;
            b = test_b;
            #1;
            expected_signed_lt = $signed(a) < $signed(b);
            expected_signed_lte = $signed(a) <= $signed(b);
            expected_unsigned_lt = a < b;
            expected_unsigned_lte = a <= b;
            test_count++;

            if ({inferred_signed_lt, inferred_signed_lte, inferred_unsigned_lt, inferred_unsigned_lte} !==
                {expected_signed_lt, expected_signed_lte, expected_unsigned_lt, expected_unsigned_lte}) begin
                report_mismatch("inferred", inferred_signed_lt, inferred_signed_lte,
                                inferred_unsigned_lt, inferred_unsigned_lte, expected_signed_lt,
                                expected_signed_lte, expected_unsigned_lt, expected_unsigned_lte);
            end
            if ({tree_signed_lt, tree_signed_lte, tree_unsigned_lt, tree_unsigned_lte} !==
                {expected_signed_lt, expected_signed_lte, expected_unsigned_lt, expected_unsigned_lte}) begin
                report_mismatch("tree", tree_signed_lt, tree_signed_lte, tree_unsigned_lt,
                                tree_unsigned_lte, expected_signed_lt, expected_signed_lte,
                                expected_unsigned_lt, expected_unsigned_lte);
            end
        end
    endtask

    initial begin : run_tests
        integer i;
        $dumpfile("comparator_benchmark/reports/comparator_activity.vcd");
        $dumpvars(0, tb_comparator);

        check_case(64'h0, 64'h0);
        check_case(64'h0123_4567_89ab_cdef, 64'h0123_4567_89ab_cdef);
        check_case(64'd17, 64'd42);
        check_case(64'hffff_ffff_ffff_fff0, 64'hffff_ffff_ffff_fff8);
        check_case(64'd1, 64'hffff_ffff_ffff_ffff);
        check_case(64'hffff_ffff_ffff_ffff, 64'd1);
        check_case(64'h7fff_ffff_ffff_ffff, 64'h8000_0000_0000_0000);
        check_case(64'h8000_0000_0000_0000, 64'h7fff_ffff_ffff_ffff);
        check_case(64'hffff_ffff_ffff_ffff, 64'h0);
        check_case(64'h8000_0000_0000_0000, 64'h0);
        check_case(64'h0, 64'h8000_0000_0000_0000);
        check_case(64'h0, 64'h1);
        check_case(64'h1, 64'h0);
        check_case(64'haaaa_aaaa_aaaa_aaaa, 64'h5555_5555_5555_5555);
        check_case(64'h5555_5555_5555_5555, 64'haaaa_aaaa_aaaa_aaaa);

        for (i = 0; i < 100000; i++) begin
            check_case(next_random(), next_random());
        end

        $display("TESTS=%0d MISMATCHES=%0d", test_count, mismatch_count);
        if (mismatch_count == 0) begin
            $display("PASS");
            $finish;
        end else begin
            $display("FAIL");
            $fatal(1, "Comparator verification failed");
        end
    end
endmodule
