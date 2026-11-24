module add_sub (
    input logic [63:0] a,
    input logic [63:0] b,
    input logic sub,
    input logic [2:0] alu_op,
    output logic [63:0] sum,
    output logic cout

);



genvar i, level;

logic [63:0] g [6:0]; // Generate signals
logic [63:0] p [6:0]; // Propagate signals
logic [63:0] b_eff; // Effective b after considering subtraction
assign b_eff =b ^ {64{sub}}; // If sub is 1, invert b for subtraction
assign g[0] [63 :1] = a[63 :1] & b_eff[63 :1];
assign p[0] [63 :0] = a ^ b_eff;
assign g[0] [0] = a[0] & b_eff[0] | (sub & (a[0] ^ b_eff[0]));

for(level=1;level<=6;level++) begin : kogge_stone_gen_prop
    for(i=0;i<64;i++) begin : kogge_stone_64_prefix_gen_prop
        if(i < (1 << (level - 1))) begin
            assign g[level][i] = g[level-1][i];
            assign p[level][i] = p[level-1][i];
        end else begin
            assign g[level][i] = g[level-1][i] | (p[level-1][i] & g[level-1][i - (1 << (level - 1))]);
            assign p[level][i] = p[level-1][i] & p[level-1][i - (1 << (level - 1))];
        end
    end
end

assign cout = g[6][63];
assign sum = p[0] ^ {g[6][62:0], sub};



    
endmodule