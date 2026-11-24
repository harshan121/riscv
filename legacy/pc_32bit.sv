module pc(

    input logic clk,
    input logic rst_n,
    input logic [31:0] pc_in,
    output logic [31:0] pc_out

);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out <= 32'b0; // Reset PC to 0 on reset
        end else begin
            pc_out <= pc_in; // Update PC with the input value
        end
    end