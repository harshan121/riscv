module imm_generator
    import riscv_pkg::*;
(
    input  logic [31:0] ins,
    output logic [63:0] imm
);

    // Select immediate format based on opcode
    always_comb begin
        case (ins[6:0])

            // I-type (shift-immediates use imm[5:0] as shamt)
            OPC_I_ALU, OPC_I_ALU_32, OPC_I_LOAD, OPC_JALR:
                imm = {{52{ins[31]}}, ins[31:20]};

            // S-type
            OPC_STORE:
                imm = {{52{ins[31]}}, ins[31:25], ins[11:7]};

            // B-type
            OPC_BRANCH:
                imm = {{52{ins[31]}}, ins[7], ins[30:25], ins[11:8], 1'b0};

            // U-type
            OPC_LUI, OPC_AUIPC:
                imm = {{32{ins[31]}}, ins[31:12], 12'b0};

            // J-type
            OPC_JAL:
                imm = {{44{ins[31]}}, ins[19:12], ins[20], ins[30:21], 1'b0};

            default:
                imm = 64'd0;

        endcase
    end

endmodule
