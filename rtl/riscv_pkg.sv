// Shared definitions for the RV64IC 5-stage pipeline.
package riscv_pkg;

    // ------------------------------------------------------------------
    // Opcodes
    // ------------------------------------------------------------------
    localparam logic [6:0] OPC_I_LOAD   = 7'b0000011;
    localparam logic [6:0] OPC_FENCE    = 7'b0001111;
    localparam logic [6:0] OPC_I_ALU    = 7'b0010011;
    localparam logic [6:0] OPC_AUIPC    = 7'b0010111;
    localparam logic [6:0] OPC_I_ALU_32 = 7'b0011011;
    localparam logic [6:0] OPC_STORE    = 7'b0100011;
    localparam logic [6:0] OPC_ALU      = 7'b0110011;
    localparam logic [6:0] OPC_LUI      = 7'b0110111;
    localparam logic [6:0] OPC_ALU_32   = 7'b0111011;
    localparam logic [6:0] OPC_BRANCH   = 7'b1100011;
    localparam logic [6:0] OPC_JALR     = 7'b1100111;
    localparam logic [6:0] OPC_JAL      = 7'b1101111;
    localparam logic [6:0] OPC_SYSTEM   = 7'b1110011;

    localparam logic [31:0] INS_ECALL   = 32'h0000_0073;
    localparam logic [31:0] INS_EBREAK  = 32'h0010_0073;
    localparam logic [31:0] INS_NOP     = 32'h0000_0013; // addi x0, x0, 0

    // ------------------------------------------------------------------
    // funct3 values
    // ------------------------------------------------------------------
    // Loads / stores (bit 2 = unsigned for loads)
    localparam logic [2:0] F3_B  = 3'b000;
    localparam logic [2:0] F3_H  = 3'b001;
    localparam logic [2:0] F3_W  = 3'b010;
    localparam logic [2:0] F3_D  = 3'b011;
    localparam logic [2:0] F3_BU = 3'b100;
    localparam logic [2:0] F3_HU = 3'b101;
    localparam logic [2:0] F3_WU = 3'b110;

    // Branches
    localparam logic [2:0] F3_BEQ  = 3'b000;
    localparam logic [2:0] F3_BNE  = 3'b001;
    localparam logic [2:0] F3_BLT  = 3'b100;
    localparam logic [2:0] F3_BGE  = 3'b101;
    localparam logic [2:0] F3_BLTU = 3'b110;
    localparam logic [2:0] F3_BGEU = 3'b111;

    // ALU funct3 that need special handling in decode
    localparam logic [2:0] F3_SRL_SRA = 3'b101;

    // ------------------------------------------------------------------
    // ALU operation encoding = {funct7[5], funct3}
    // ------------------------------------------------------------------
    localparam logic [3:0] ALU_ADD  = 4'b0000;
    localparam logic [3:0] ALU_SUB  = 4'b1000;
    localparam logic [3:0] ALU_SLL  = 4'b0001;
    localparam logic [3:0] ALU_SLT  = 4'b0010;
    localparam logic [3:0] ALU_SLTU = 4'b0011;
    localparam logic [3:0] ALU_XOR  = 4'b0100;
    localparam logic [3:0] ALU_SRL  = 4'b0101;
    localparam logic [3:0] ALU_SRA  = 4'b1101;
    localparam logic [3:0] ALU_OR   = 4'b0110;
    localparam logic [3:0] ALU_AND  = 4'b0111;

    // ------------------------------------------------------------------
    // Fault causes (RISC-V mcause exception codes, no CSRs implemented)
    // ------------------------------------------------------------------
    localparam logic [3:0] CAUSE_FETCH_ACCESS   = 4'd1;   // AXI error on instruction fetch
    localparam logic [3:0] CAUSE_ILLEGAL        = 4'd2;   // illegal / unsupported instruction
    localparam logic [3:0] CAUSE_BREAKPOINT     = 4'd3;   // ebreak / c.ebreak
    localparam logic [3:0] CAUSE_LOAD_MISALIGN  = 4'd4;
    localparam logic [3:0] CAUSE_LOAD_ACCESS    = 4'd5;   // AXI error on load
    localparam logic [3:0] CAUSE_STORE_MISALIGN = 4'd6;
    localparam logic [3:0] CAUSE_STORE_ACCESS   = 4'd7;   // AXI error on store
    localparam logic [3:0] CAUSE_ECALL_M        = 4'd11;  // ecall

    // ------------------------------------------------------------------
    // Operand / writeback selects
    // ------------------------------------------------------------------
    typedef enum logic [1:0] { A_RS1, A_PC, A_ZERO }      a_sel_t;
    typedef enum logic       { B_RS2, B_IMM }             b_sel_t;
    typedef enum logic [1:0] { WB_ALU, WB_MEM, WB_PC4 }   wb_sel_t;   // WB_PC4 = link (pc + 2 / 4)
    typedef enum logic [1:0] { FWD_NONE, FWD_EX_MEM, FWD_MEM_WB } fwd_sel_t;

    // ------------------------------------------------------------------
    // Control bundle produced by decode
    // ------------------------------------------------------------------
    typedef struct packed {
        a_sel_t     a_sel;
        b_sel_t     b_sel;
        logic [3:0] alu_op;
        logic       word;       // *W instruction: 32-bit op, sign-extend result
        logic       reg_write;
        logic       mem_read;
        logic       mem_write;
        wb_sel_t    wb_sel;
        logic       branch;
        logic       jal;
        logic       jalr;
    } ctrl_t;

    // No-op control: every field's inactive value encodes as zero
    // (A_RS1, B_RS2, ALU_ADD, WB_ALU = 0). Written as '0 rather than a
    // named assignment pattern so that Yosys can parse the package.
    localparam ctrl_t CTRL_NOP = '0;

    // ------------------------------------------------------------------
    // Branch prediction
    // ------------------------------------------------------------------
    localparam int BP_BTB_BITS = 6;     // 64-entry BTB
    localparam int BP_PHT_BITS = 6;     // 64 two-bit counters, 6-bit global history
    localparam int BP_RAS_BITS = 3;     // 8-entry return address stack

    // Prediction made in IF, travels with the instruction down to EX
    typedef struct packed {
        logic                   pred_taken;
        logic [63:0]            pred_target;
        logic [BP_PHT_BITS-1:0] pht_idx;    // counter used, so EX updates the same one
        logic [BP_PHT_BITS-1:0] ghr;        // history before this instruction (checkpoint)
        logic [BP_RAS_BITS-1:0] ras_ptr;    // RAS pointer before this instruction (checkpoint)
    } bp_info_t;

    // Resolution from EX back to the predictor
    typedef struct packed {
        logic                   valid;      // a branch / jump resolved this cycle
        logic [63:0]            end_pc;     // address of the instruction's last 16-bit parcel
        logic [63:0]            link;       // pc + 2 / 4 (return address for calls)
        logic [63:0]            target;     // computed target (taken or not)
        logic                   is_cond;
        logic                   is_call;
        logic                   is_ret;
        logic                   taken;
        logic [BP_PHT_BITS-1:0] pht_idx;
        logic                   recover;    // mispredict: restore checkpoints
        logic [BP_PHT_BITS-1:0] ghr;
        logic [BP_RAS_BITS-1:0] ras_ptr;
    } bp_update_t;

    // ------------------------------------------------------------------
    // Fetch: 16-bit instruction parcels (RVC)
    // ------------------------------------------------------------------
    // Prediction info is per fetch word; pred_taken/pred_target are only set
    // on the parcel that ends the predicted-taken instruction.
    typedef struct packed {
        logic [15:0] data;
        logic [63:0] pc;
        logic        fault;     // AXI error response for this fetch word
        bp_info_t    bp;
    } parcel_t;

    // ------------------------------------------------------------------
    // Pipeline registers
    // ------------------------------------------------------------------
    typedef struct packed {
        logic        valid;
        logic [63:0] pc;
        logic [63:0] rs1_data;
        logic [63:0] rs2_data;
        logic [63:0] imm;
        logic [4:0]  rs1;       // used by the hazard unit
        logic [4:0]  rs2;
        logic [4:0]  rd;
        logic [2:0]  funct3;
        logic        rvc;       // compressed: instruction is 2 bytes
        logic        fault;     // fault detected in IF / ID (ctrl is a nop)
        logic [3:0]  cause;
        ctrl_t       ctrl;
        bp_info_t    bp;
    } id_ex_t;

    typedef struct packed {
        logic        valid;
        logic [63:0] pc;        // for fault_pc
        logic [63:0] pc_seq;    // pc + 2 / 4
        logic [63:0] alu_result;
        logic [63:0] store_data;
        logic [4:0]  rd;
        logic [2:0]  funct3;
        logic        fault;     // fault from an earlier stage
        logic [3:0]  cause;
        ctrl_t       ctrl;
    } ex_mem_t;

    typedef struct packed {
        logic        valid;
        logic [63:0] pc_seq;    // pc + 2 / 4
        logic [63:0] alu_result;
        logic [63:0] mem_data;
        logic [4:0]  rd;
        ctrl_t       ctrl;
    } mem_wb_t;

endpackage
