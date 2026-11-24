module xor_gate(
    input logic [63:0] a,
    input logic [63:0] b,
    output logic [63:0] result
);
    always_comb begin
        result = a ^ b;
    end
endmodule