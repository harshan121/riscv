`timescale 1ns/1ps

module less_than_equal_tree_optimized (
    input  logic [63:0] a,
    input  logic [63:0] b,
    output logic        result
);
    logic [63:0] lt0, eq0;
    logic [31:0] lt1, eq1;
    logic [15:0] lt2, eq2;
    logic [7:0]  lt3, eq3;
    logic [3:0]  lt4, eq4;
    logic [1:0]  lt5, eq5;
    logic        lt6, eq6;

    genvar bit_index;
    generate
        for (bit_index = 0; bit_index < 64; bit_index++) begin : gen_leaf
            assign lt0[bit_index] = ~a[bit_index] & b[bit_index];
            assign eq0[bit_index] = ~(a[bit_index] ^ b[bit_index]);
        end
    endgenerate

    genvar group;
    generate
        for (group = 0; group < 32; group++) begin : gen_l1
            assign lt1[group] = lt0[2*group+1] | (eq0[2*group+1] & lt0[2*group]);
            assign eq1[group] = eq0[2*group+1] & eq0[2*group];
        end
        for (group = 0; group < 16; group++) begin : gen_l2
            assign lt2[group] = lt1[2*group+1] | (eq1[2*group+1] & lt1[2*group]);
            assign eq2[group] = eq1[2*group+1] & eq1[2*group];
        end
        for (group = 0; group < 8; group++) begin : gen_l3
            assign lt3[group] = lt2[2*group+1] | (eq2[2*group+1] & lt2[2*group]);
            assign eq3[group] = eq2[2*group+1] & eq2[2*group];
        end
        for (group = 0; group < 4; group++) begin : gen_l4
            assign lt4[group] = lt3[2*group+1] | (eq3[2*group+1] & lt3[2*group]);
            assign eq4[group] = eq3[2*group+1] & eq3[2*group];
        end
        for (group = 0; group < 2; group++) begin : gen_l5
            assign lt5[group] = lt4[2*group+1] | (eq4[2*group+1] & lt4[2*group]);
            assign eq5[group] = eq4[2*group+1] & eq4[2*group];
        end
    endgenerate

    assign lt6 = lt5[1] | (eq5[1] & lt5[0]);
    assign eq6 = eq5[1] & eq5[0];
    // Equal signs use unsigned magnitude ordering; a negative sign wins otherwise.
    assign result = (a[63] != b[63]) ? a[63] : (lt6 | eq6);
endmodule
