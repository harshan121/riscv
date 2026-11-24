// RV64C: expand a 16-bit compressed instruction into its 32-bit equivalent.
// Floating-point forms (C.FLD/C.FSD/C.FLDSP/C.FSDSP) and reserved encodings
// are reported as illegal and expand to 32'h0 (decoded as a nop: the core
// has no exceptions yet). HINT encodings expand normally (they write x0).
module rvc_expander
    import riscv_pkg::*;
(
    input  logic [15:0] c,
    output logic [31:0] ins,
    output logic        illegal
);

// ---------------------------------------------------------------------
// 32-bit format encoders
// ---------------------------------------------------------------------
function automatic logic [31:0] enc_i(input logic [11:0] imm, input logic [4:0] rs1,
                                      input logic [2:0] f3, input logic [4:0] rd, input logic [6:0] op);
    return {imm, rs1, f3, rd, op};
endfunction

function automatic logic [31:0] enc_s(input logic [11:0] imm, input logic [4:0] rs2,
                                      input logic [4:0] rs1, input logic [2:0] f3);
    return {imm[11:5], rs2, rs1, f3, imm[4:0], OPC_STORE};
endfunction

function automatic logic [31:0] enc_b(input logic [12:0] imm, input logic [4:0] rs1, input logic [2:0] f3);
    return {imm[12], imm[10:5], 5'd0, rs1, f3, imm[4:1], imm[11], OPC_BRANCH};
endfunction

function automatic logic [31:0] enc_j(input logic [20:0] imm, input logic [4:0] rd);
    return {imm[20], imm[10:1], imm[11], imm[19:12], rd, OPC_JAL};
endfunction

function automatic logic [31:0] enc_r(input logic [6:0] f7, input logic [4:0] rs2, input logic [4:0] rs1,
                                      input logic [2:0] f3, input logic [4:0] rd, input logic [6:0] op);
    return {f7, rs2, rs1, f3, rd, op};
endfunction

// ---------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------
logic [4:0]  rd, rs2, rdp, rs1p;
logic [5:0]  imm6;           // CI-format signed immediate / shamt
logic [11:0] simm;           // imm6 sign-extended to 12 bits
logic [9:0]  addi4spn_imm, addi16sp_imm;
logic [11:0] j_off;
logic [8:0]  b_off;

assign rd    = c[11:7];      // also rs1 for CR/CI
assign rs2   = c[6:2];
assign rdp   = {2'b01, c[4:2]};
assign rs1p  = {2'b01, c[9:7]};
assign imm6  = {c[12], c[6:2]};
assign simm  = {{6{c[12]}}, imm6};

assign addi4spn_imm = {c[10:7], c[12:11], c[5], c[6], 2'b00};
assign addi16sp_imm = {c[12], c[4:3], c[5], c[2], c[6], 4'b0000};
assign j_off        = {c[12], c[8], c[10:9], c[6], c[7], c[2], c[11], c[5:3], 1'b0};
assign b_off        = {c[12], c[6:5], c[2], c[11:10], c[4:3], 1'b0};

always_comb begin
    ins     = 32'h0;
    illegal = 1'b0;

    case ({c[1:0], c[15:13]})

        // ------------------------------- Quadrant 0
        5'b00_000:  // C.ADDI4SPN  addi rd', x2, nzuimm
            if (addi4spn_imm == 10'd0) illegal = 1'b1;
            else ins = enc_i({2'b00, addi4spn_imm}, 5'd2, 3'b000, rdp, OPC_I_ALU);

        5'b00_010:  // C.LW  lw rd', off(rs1')
            ins = enc_i({5'b0, c[5], c[12:10], c[6], 2'b00}, rs1p, F3_W, rdp, OPC_I_LOAD);

        5'b00_011:  // C.LD  ld rd', off(rs1')
            ins = enc_i({4'b0, c[6:5], c[12:10], 3'b000}, rs1p, F3_D, rdp, OPC_I_LOAD);

        5'b00_110:  // C.SW  sw rs2', off(rs1')
            ins = enc_s({5'b0, c[5], c[12:10], c[6], 2'b00}, rdp, rs1p, F3_W);

        5'b00_111:  // C.SD  sd rs2', off(rs1')
            ins = enc_s({4'b0, c[6:5], c[12:10], 3'b000}, rdp, rs1p, F3_D);

        // ------------------------------- Quadrant 1
        5'b01_000:  // C.ADDI / C.NOP
            ins = enc_i(simm, rd, 3'b000, rd, OPC_I_ALU);

        5'b01_001:  // C.ADDIW
            if (rd == 5'd0) illegal = 1'b1;
            else ins = enc_i(simm, rd, 3'b000, rd, OPC_I_ALU_32);

        5'b01_010:  // C.LI  addi rd, x0, imm
            ins = enc_i(simm, 5'd0, 3'b000, rd, OPC_I_ALU);

        5'b01_011:
            if (rd == 5'd2) begin   // C.ADDI16SP
                if (addi16sp_imm == 10'd0) illegal = 1'b1;
                else ins = enc_i({{2{addi16sp_imm[9]}}, addi16sp_imm}, 5'd2, 3'b000, 5'd2, OPC_I_ALU);
            end else begin          // C.LUI
                if (imm6 == 6'd0) illegal = 1'b1;
                else ins = {{14{c[12]}}, imm6, rd, OPC_LUI};
            end

        5'b01_100:
            case (c[11:10])
                2'b00: ins = enc_i({6'b000000, imm6}, rs1p, 3'b101, rs1p, OPC_I_ALU);  // C.SRLI
                2'b01: ins = enc_i({6'b010000, imm6}, rs1p, 3'b101, rs1p, OPC_I_ALU);  // C.SRAI
                2'b10: ins = enc_i(simm,              rs1p, 3'b111, rs1p, OPC_I_ALU);  // C.ANDI
                default:
                    case ({c[12], c[6:5]})
                        3'b000: ins = enc_r(7'h20, rdp, rs1p, 3'b000, rs1p, OPC_ALU);     // C.SUB
                        3'b001: ins = enc_r(7'h00, rdp, rs1p, 3'b100, rs1p, OPC_ALU);     // C.XOR
                        3'b010: ins = enc_r(7'h00, rdp, rs1p, 3'b110, rs1p, OPC_ALU);     // C.OR
                        3'b011: ins = enc_r(7'h00, rdp, rs1p, 3'b111, rs1p, OPC_ALU);     // C.AND
                        3'b100: ins = enc_r(7'h20, rdp, rs1p, 3'b000, rs1p, OPC_ALU_32);  // C.SUBW
                        3'b101: ins = enc_r(7'h00, rdp, rs1p, 3'b000, rs1p, OPC_ALU_32);  // C.ADDW
                        default: illegal = 1'b1;
                    endcase
            endcase

        5'b01_101:  // C.J  jal x0, off
            ins = enc_j({{9{j_off[11]}}, j_off}, 5'd0);

        5'b01_110:  // C.BEQZ  beq rs1', x0, off
            ins = enc_b({{4{b_off[8]}}, b_off}, rs1p, F3_BEQ);

        5'b01_111:  // C.BNEZ  bne rs1', x0, off
            ins = enc_b({{4{b_off[8]}}, b_off}, rs1p, F3_BNE);

        // ------------------------------- Quadrant 2
        5'b10_000:  // C.SLLI
            ins = enc_i({6'b000000, imm6}, rd, 3'b001, rd, OPC_I_ALU);

        5'b10_010:  // C.LWSP  lw rd, off(x2)
            if (rd == 5'd0) illegal = 1'b1;
            else ins = enc_i({4'b0, c[3:2], c[12], c[6:4], 2'b00}, 5'd2, F3_W, rd, OPC_I_LOAD);

        5'b10_011:  // C.LDSP  ld rd, off(x2)
            if (rd == 5'd0) illegal = 1'b1;
            else ins = enc_i({3'b0, c[4:2], c[12], c[6:5], 3'b000}, 5'd2, F3_D, rd, OPC_I_LOAD);

        5'b10_100:
            if (!c[12]) begin
                if (rs2 == 5'd0) begin                      // C.JR  jalr x0, 0(rs1)
                    if (rd == 5'd0) illegal = 1'b1;
                    else ins = enc_i(12'd0, rd, 3'b000, 5'd0, OPC_JALR);
                end else begin                              // C.MV  add rd, x0, rs2
                    ins = enc_r(7'h00, rs2, 5'd0, 3'b000, rd, OPC_ALU);
                end
            end else begin
                if (rs2 == 5'd0) begin
                    if (rd == 5'd0) ins = INS_EBREAK;       // C.EBREAK
                    else ins = enc_i(12'd0, rd, 3'b000, 5'd1, OPC_JALR);   // C.JALR
                end else begin                              // C.ADD  add rd, rd, rs2
                    ins = enc_r(7'h00, rs2, rd, 3'b000, rd, OPC_ALU);
                end
            end

        5'b10_110:  // C.SWSP  sw rs2, off(x2)
            ins = enc_s({4'b0, c[8:7], c[12:9], 2'b00}, rs2, 5'd2, F3_W);

        5'b10_111:  // C.SDSP  sd rs2, off(x2)
            ins = enc_s({3'b0, c[9:7], c[12:10], 3'b000}, rs2, 5'd2, F3_D);

        // FP loads/stores, reserved, and c[1:0] == 11 (not compressed)
        default: illegal = 1'b1;

    endcase

    if (illegal) ins = 32'h0;
end

endmodule
