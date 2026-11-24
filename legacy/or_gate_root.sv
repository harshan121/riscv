module or_gate(
    input logic [63:0] a,
    input logic [63:0] b,
    output logic [63:0] result
);

always comb begin
    result = a | b;
end

endmodule