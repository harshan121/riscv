module less_greater_equal(
    input  logic [63:0] a,
    input  logic [63:0] b,
    input logic greater_than,
    input logic equal,
    output logic        result
);

    logic [63:0] lt [0:6];
    logic [63:0] eq [0:6];

    // Level 0: Signed comparison of bit 63
    assign lt[0][0] = a[63] & ~b[63];
    assign eq[0][0] = ~(a[63] ^ b[63]);

    // Level 0: Remaining bit comparisons
    for (genvar j = 1; j < 64; j++) begin
        assign lt[0][j] = ~a[63-j] & b[63-j];
        assign eq[0][j] = ~(a[63-j] ^ b[63-j]);
    end

    // Six-level comparison tree
    for (genvar level = 1; level <= 6; level++) begin
        for (genvar i = 0; i < (64 >> level); i++) begin

            assign lt[level][i] =
                lt[level-1][2*i] |
                (eq[level-1][2*i] & lt[level-1][2*i+1]);

            assign eq[level][i] =
                eq[level-1][2*i] &
                eq[level-1][2*i+1];

        end
    end

    // Signed less-than-or-equal
    assign result = (lt[6][0] | (equal & eq[6][0]) )^ greater_than;

endmodule