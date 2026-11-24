`timescale 1ns/1ps

module comparator_tree (
    input  logic [63:0] a,
    input  logic [63:0] b,
    output logic        signed_lt,
    output logic        signed_lte,
    output logic        unsigned_lt,
    output logic        unsigned_lte
);
    logic [63:0] lt_level0;
    logic [63:0] eq_level0;
    logic [31:0] lt_level1;
    logic [31:0] eq_level1;
    logic [15:0] lt_level2;
    logic [15:0] eq_level2;
    logic [7:0]  lt_level3;
    logic [7:0]  eq_level3;
    logic [3:0]  lt_level4;
    logic [3:0]  eq_level4;
    logic [1:0]  lt_level5;
    logic [1:0]  eq_level5;
    logic        lt_level6;
    logic        eq_level6;

    genvar bit_index;
    generate
        for (bit_index = 0; bit_index < 64; bit_index++) begin : gen_leaves
            assign lt_level0[bit_index] = ~a[bit_index] & b[bit_index];
            assign eq_level0[bit_index] = ~(a[bit_index] ^ b[bit_index]);
        end
    endgenerate

    genvar group_index;
    generate
        for (group_index = 0; group_index < 32; group_index++) begin : gen_level1
            assign lt_level1[group_index] = lt_level0[2 * group_index + 1] |
                                          (eq_level0[2 * group_index + 1] & lt_level0[2 * group_index]);
            assign eq_level1[group_index] = eq_level0[2 * group_index + 1] & eq_level0[2 * group_index];
        end
        for (group_index = 0; group_index < 16; group_index++) begin : gen_level2
            assign lt_level2[group_index] = lt_level1[2 * group_index + 1] |
                                          (eq_level1[2 * group_index + 1] & lt_level1[2 * group_index]);
            assign eq_level2[group_index] = eq_level1[2 * group_index + 1] & eq_level1[2 * group_index];
        end
        for (group_index = 0; group_index < 8; group_index++) begin : gen_level3
            assign lt_level3[group_index] = lt_level2[2 * group_index + 1] |
                                          (eq_level2[2 * group_index + 1] & lt_level2[2 * group_index]);
            assign eq_level3[group_index] = eq_level2[2 * group_index + 1] & eq_level2[2 * group_index];
        end
        for (group_index = 0; group_index < 4; group_index++) begin : gen_level4
            assign lt_level4[group_index] = lt_level3[2 * group_index + 1] |
                                          (eq_level3[2 * group_index + 1] & lt_level3[2 * group_index]);
            assign eq_level4[group_index] = eq_level3[2 * group_index + 1] & eq_level3[2 * group_index];
        end
        for (group_index = 0; group_index < 2; group_index++) begin : gen_level5
            assign lt_level5[group_index] = lt_level4[2 * group_index + 1] |
                                          (eq_level4[2 * group_index + 1] & lt_level4[2 * group_index]);
            assign eq_level5[group_index] = eq_level4[2 * group_index + 1] & eq_level4[2 * group_index];
        end
    endgenerate

    assign lt_level6 = lt_level5[1] | (eq_level5[1] & lt_level5[0]);
    assign eq_level6 = eq_level5[1] & eq_level5[0];

    assign unsigned_lt  = lt_level6;
    assign unsigned_lte = lt_level6 | eq_level6;
    assign signed_lt    = (a[63] != b[63]) ? a[63] : lt_level6;
    assign signed_lte   = signed_lt | eq_level6;
endmodule
