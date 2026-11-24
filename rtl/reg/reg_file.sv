// 32 x 64-bit register file, 2 read ports, 1 write port.
// x0 is hardwired to zero. A write and a read of the same register in the
// same cycle returns the new value (WB -> ID write-through bypass).
module reg_file(
    input  logic        clk,
    input  logic        reset,
    input  logic [4:0]  rs1,
    input  logic [4:0]  rs2,
    input  logic        write,
    input  logic [4:0]  rd,
    input  logic [63:0] rd_data,
    output logic [63:0] rs1_data,
    output logic [63:0] rs2_data
);

logic [63:0] regs [31:0];

always_comb begin
    if (rs1 == 5'd0)                rs1_data = 64'd0;
    else if (write && rs1 == rd)    rs1_data = rd_data;
    else                            rs1_data = regs[rs1];
end

always_comb begin
    if (rs2 == 5'd0)                rs2_data = 64'd0;
    else if (write && rs2 == rd)    rs2_data = rd_data;
    else                            rs2_data = regs[rs2];
end

always_ff @(posedge clk) begin
    if (reset) begin
        for (int i = 0; i < 32; i++) regs[i] <= 64'd0;
    end else if (write && rd != 5'd0) begin
        regs[rd] <= rd_data;
    end
end

endmodule
