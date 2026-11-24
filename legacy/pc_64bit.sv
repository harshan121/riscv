module pc(

    input logic clk,
    input logic reset,
    input logic pc_update,
    input logic pc_get,
    input logic [63:0] pc_add,
    output logic [63:0] pc_out

);

logic [63:0] pc_reg;
logic [63:0] pc_update_reg;
logic pc_reg_update_flg;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pc_reg <= 64'd0;
            pc_reg_update_flg <= 1'b0;
            pc_update_reg <= 64'd0;
            
        end
        else if (pc_reg_update_flg) begin
            pc_reg<= pc_update_reg;
        end
         
        else begin
            pc_reg <= pc_reg + 64'd4;
        end 
    end

    alwyays_comb begin
        if (pc_update) begin
            pc_update_reg = pc_reg + pc_add;
            pc_reg_update_flg = 1'b1;
        end
        else begin
            pc_update_reg = pc_reg;
            pc_reg_update_flg = 1'b0;
        end

        if(pc_get) begin
            pc_out = pc_reg;
        end
        else begin
            pc_out = 64'd0;
        end
    end
            

    endmodule