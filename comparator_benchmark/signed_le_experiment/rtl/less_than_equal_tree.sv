`timescale 1ns/1ps

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNOPTFLAT */

module less_than_equal_tree_param #(
    parameter int WIDTH = 64
) (
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    output logic             result
);
    localparam int LEVELS = $clog2(WIDTH);
    logic [WIDTH-1:0] lt [0:LEVELS];
    logic [WIDTH-1:0] eq [0:LEVELS];

    // Leaf 0 is the sign bit; subsequent leaves proceed MSB to LSB.
    assign lt[0][0] = a[WIDTH-1] & ~b[WIDTH-1];
    assign eq[0][0] = ~(a[WIDTH-1] ^ b[WIDTH-1]);

    genvar j;
    generate
        for (j = 1; j < WIDTH; j++) begin : gen_bits
            assign lt[0][j] = ~a[WIDTH-1-j] & b[WIDTH-1-j];
            assign eq[0][j] = ~(a[WIDTH-1-j] ^ b[WIDTH-1-j]);
        end
    endgenerate

    genvar level;
    genvar node;
    generate
        for (level = 1; level <= LEVELS; level++) begin : gen_levels
            for (node = 0; node < (WIDTH >> level); node++) begin : gen_nodes
                // The lower index is the higher-significance group.
                assign lt[level][node] = lt[level-1][2*node] |
                                         (eq[level-1][2*node] & lt[level-1][2*node+1]);
                assign eq[level][node] = eq[level-1][2*node] & eq[level-1][2*node+1];
            end
        end
    endgenerate

    assign result = lt[LEVELS][0] | eq[LEVELS][0];
endmodule
/* verilator lint_on UNOPTFLAT */
/* verilator lint_on DECLFILENAME */

module less_than_equal_tree (
    input  logic [63:0] a,
    input  logic [63:0] b,
    output logic        result
);
    less_than_equal_tree_param #(.WIDTH(64)) comparator (
        .a(a), .b(b), .result(result)
    );
endmodule
