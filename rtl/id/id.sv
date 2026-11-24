// Instruction Decode stage
//   - splits the instruction into fields
//   - generates the immediate
//   - reads the register file (written back from WB)
//   - generates control signals
//   - detects illegal / unsupported instructions, ecall and ebreak
//     (the instruction becomes a nop carrying a fault to MEM)
//   - registers everything into the ID/EX pipeline register
module id_stage
    import riscv_pkg::*;
(
    input  logic        clk,
    input  logic        rst,
    input  logic        flush,      // kill the instruction being decoded (redirect)
    input  logic        stall,      // load-use: hold this instruction, send a bubble
    input  logic        hold,       // memory wait: freeze ID/EX
    input  logic        kill,       // fault taken / halted: flush

    // From IF/ID
    input  logic [31:0] ins,
    input  logic [63:0] pc,
    input  logic        valid,
    input  logic        rvc,        // compressed instruction (already expanded)
    input  logic        fetch_fault,// AXI error while fetching this instruction
    input  bp_info_t    bp,         // branch prediction made in IF

    // Write-back port into the register file
    input  logic        wb_write,
    input  logic [4:0]  wb_rd,
    input  logic [63:0] wb_data,

    // To the hazard unit
    output logic [4:0]  id_rs1,
    output logic [4:0]  id_rs2,
    output logic        id_uses_rs1,
    output logic        id_uses_rs2,

    // ID/EX pipeline register
    output id_ex_t      id_ex
);

logic [6:0]  opcode;
logic [4:0]  rd;
logic [2:0]  funct3;
logic [4:0]  rs1;
logic [4:0]  rs2;
logic [6:0]  funct7;
logic [63:0] imm;
logic [63:0] rs1_data;
logic [63:0] rs2_data;
ctrl_t       ctrl;
logic        illegal;
logic        fault;
logic [3:0]  cause;

ins_decode ins_dec (
    .ins    (ins),
    .opcode (opcode),
    .rd     (rd),
    .funct3 (funct3),
    .rs1    (rs1),
    .rs2    (rs2),
    .funct7 (funct7)
);

imm_generator imm_gen (
    .ins (ins),
    .imm (imm)
);

reg_file u_reg_file (
    .clk      (clk),
    .reset    (rst),
    .rs1      (rs1),
    .rs2      (rs2),
    .write    (wb_write),
    .rd       (wb_rd),
    .rd_data  (wb_data),
    .rs1_data (rs1_data),
    .rs2_data (rs2_data)
);

// ----------------------------------------------------------------------
// Control generation
// ----------------------------------------------------------------------
always_comb begin
    ctrl    = CTRL_NOP;
    illegal = 1'b0;

    case (opcode)

        OPC_LUI: begin                       // rd = imm
            ctrl.a_sel     = A_ZERO;
            ctrl.b_sel     = B_IMM;
            ctrl.reg_write = 1'b1;
        end

        OPC_AUIPC: begin                     // rd = pc + imm
            ctrl.a_sel     = A_PC;
            ctrl.b_sel     = B_IMM;
            ctrl.reg_write = 1'b1;
        end

        OPC_I_ALU, OPC_I_ALU_32: begin       // rd = rs1 op imm
            // Shift-immediates: RV64 SLLI/SRLI/SRAI use a 6-bit shamt
            // (funct6 = ins[31:26]); the W forms a 5-bit shamt (funct7).
            if (opcode == OPC_I_ALU) begin
                if (funct3 == 3'b001) illegal = (ins[31:26] != 6'b000000);
                if (funct3 == 3'b101) illegal = (ins[31:26] != 6'b000000) && (ins[31:26] != 6'b010000);
            end else begin
                case (funct3)
                    3'b000:  ;                                               // ADDIW
                    3'b001:  illegal = (funct7 != 7'h00);                    // SLLIW
                    3'b101:  illegal = (funct7 != 7'h00) && (funct7 != 7'h20); // SRLIW / SRAIW
                    default: illegal = 1'b1;
                endcase
            end
            ctrl.b_sel     = B_IMM;
            // Only SRAI(W) uses funct7[5]; ADDI has no SUBI
            ctrl.alu_op    = {(funct3 == F3_SRL_SRA) & funct7[5], funct3};
            ctrl.word      = (opcode == OPC_I_ALU_32);
            ctrl.reg_write = 1'b1;
        end

        OPC_ALU, OPC_ALU_32: begin           // rd = rs1 op rs2
            // funct7 = 0x20 only for SUB(W) / SRA(W); 0x01 (M extension) unsupported
            if (funct7 == 7'h20)
                illegal = (funct3 != 3'b000) && (funct3 != 3'b101);
            else
                illegal = (funct7 != 7'h00);
            if (opcode == OPC_ALU_32 && funct3 != 3'b000 && funct3 != 3'b001 && funct3 != 3'b101)
                illegal = 1'b1;
            ctrl.b_sel     = B_RS2;
            ctrl.alu_op    = {funct7[5], funct3};
            ctrl.word      = (opcode == OPC_ALU_32);
            ctrl.reg_write = 1'b1;
        end

        OPC_I_LOAD: begin                    // rd = mem[rs1 + imm]
            illegal        = (funct3 == 3'b111);
            ctrl.b_sel     = B_IMM;
            ctrl.mem_read  = 1'b1;
            ctrl.wb_sel    = WB_MEM;
            ctrl.reg_write = 1'b1;
        end

        OPC_STORE: begin                     // mem[rs1 + imm] = rs2
            illegal        = funct3[2];
            ctrl.b_sel     = B_IMM;
            ctrl.mem_write = 1'b1;
        end

        OPC_BRANCH: begin                    // if (rs1 cmp rs2) pc = pc + imm
            illegal        = (funct3 == 3'b010) || (funct3 == 3'b011);
            ctrl.branch    = 1'b1;
        end

        OPC_JAL: begin                       // rd = pc + 2/4; pc = pc + imm
            ctrl.jal       = 1'b1;
            ctrl.wb_sel    = WB_PC4;
            ctrl.reg_write = 1'b1;
        end

        OPC_JALR: begin                      // rd = pc + 2/4; pc = (rs1 + imm) & ~1
            illegal        = (funct3 != 3'b000);
            ctrl.b_sel     = B_IMM;
            ctrl.jalr      = 1'b1;
            ctrl.wb_sel    = WB_PC4;
            ctrl.reg_write = 1'b1;
        end

        OPC_FENCE: begin                     // FENCE: nop (all accesses are in order)
            illegal        = (funct3 != 3'b000);  // FENCE.I (Zifencei) unsupported
        end

        // ECALL / EBREAK are decoded below; CSR*, MRET, WFI, ... unsupported
        OPC_SYSTEM: illegal = (ins != INS_ECALL) && (ins != INS_EBREAK);

        default:    illegal = 1'b1;          // unknown opcode (includes RVC illegal -> 0)

    endcase

    // Writes to x0 are discarded
    if (rd == 5'd0) ctrl.reg_write = 1'b0;
end

// Faults, in priority order. A faulting instruction has no side effects:
// its control bundle is a nop and the fault is taken when it reaches MEM.
always_comb begin
    fault = 1'b1;
    if      (fetch_fault)          cause = CAUSE_FETCH_ACCESS;
    else if (illegal)              cause = CAUSE_ILLEGAL;
    else if (ins == INS_ECALL)     cause = CAUSE_ECALL_M;
    else if (ins == INS_EBREAK)    cause = CAUSE_BREAKPOINT;
    else begin
        fault = 1'b0;
        cause = 4'd0;
    end
end

// ----------------------------------------------------------------------
// Which source registers this instruction really reads (avoids false
// load-use stalls on U/J-type instructions whose rs fields are immediate bits)
// ----------------------------------------------------------------------
always_comb begin
    case (opcode)
        OPC_ALU, OPC_ALU_32, OPC_STORE, OPC_BRANCH: begin
            id_uses_rs1 = 1'b1;
            id_uses_rs2 = 1'b1;
        end
        OPC_I_ALU, OPC_I_ALU_32, OPC_I_LOAD, OPC_JALR: begin
            id_uses_rs1 = 1'b1;
            id_uses_rs2 = 1'b0;
        end
        default: begin
            id_uses_rs1 = 1'b0;
            id_uses_rs2 = 1'b0;
        end
    endcase
end

assign id_rs1 = rs1;
assign id_rs2 = rs2;

// ----------------------------------------------------------------------
// ID/EX pipeline register
// ----------------------------------------------------------------------
always_ff @(posedge clk) begin
    if (rst || kill) begin
        id_ex       <= '0;
        id_ex.ctrl  <= CTRL_NOP;
    end else if (hold) begin
        // memory wait: keep the instruction in EX
    end else if (flush || stall || !valid) begin
        id_ex       <= '0;
        id_ex.ctrl  <= CTRL_NOP;
    end else begin
        id_ex.valid    <= 1'b1;
        id_ex.pc       <= pc;
        id_ex.rs1_data <= rs1_data;
        id_ex.rs2_data <= rs2_data;
        id_ex.imm      <= imm;
        id_ex.rs1      <= rs1;
        id_ex.rs2      <= rs2;
        id_ex.rd       <= rd;
        id_ex.funct3   <= funct3;
        id_ex.rvc      <= rvc;
        id_ex.fault    <= fault;
        id_ex.cause    <= cause;
        id_ex.ctrl     <= fault ? CTRL_NOP : ctrl;
        id_ex.bp       <= bp;
    end
end

endmodule
