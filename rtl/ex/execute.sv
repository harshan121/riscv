// Execute stage
//   - selects ALU operands
//   - runs the ALU
//   - resolves branches / jumps and drives the PC redirect
//   - registers results into the EX/MEM pipeline register
module ex_stage
    import riscv_pkg::*;
(
    input  logic        clk,
    input  logic        rst,

    input  id_ex_t      id_ex,
    input  logic        hold,           // memory wait: EX does not advance
    input  logic        kill,           // fault taken / halted: flush, no side effects

    // Forwarding (from hazard unit)
    input  fwd_sel_t    fwd_a,
    input  fwd_sel_t    fwd_b,
    input  logic [63:0] ex_mem_result,  // value produced by the instruction in MEM
    input  logic [63:0] wb_result,      // value being written back in WB

    // Mispredict: redirect IF to the correct PC (also flushes IF/ID and ID/EX)
    output logic        redirect,
    output logic [63:0] redirect_pc,

    // Resolution for the branch predictor
    output bp_update_t  bp_upd,

    output ex_mem_t     ex_mem
);

logic [63:0] rs1_val;
logic [63:0] rs2_val;
logic [63:0] a;
logic [63:0] b;
logic [63:0] alu_result;
logic [63:0] pc_target;
logic        take_branch;
logic        actual_taken;
logic [63:0] pc_seq;
logic [63:0] end_pc;
logic        held;
logic [63:0] held_a;
logic [63:0] held_b;
logic [63:0] actual_next;
logic [63:0] pred_next;
logic        is_call;
logic        is_ret;
logic        active;     // a real instruction leaves EX this cycle

// ----------------------------------------------------------------------
// Forwarding muxes
// ----------------------------------------------------------------------
// While EX is held by a memory wait, the producer being forwarded from
// MEM/WB retires and disappears, so the forwarded operands are captured on
// the first held cycle and reused until EX advances.
always_comb begin
    case (fwd_a)
        FWD_EX_MEM: rs1_val = ex_mem_result;
        FWD_MEM_WB: rs1_val = wb_result;
        default:    rs1_val = id_ex.rs1_data;
    endcase

    case (fwd_b)
        FWD_EX_MEM: rs2_val = ex_mem_result;
        FWD_MEM_WB: rs2_val = wb_result;
        default:    rs2_val = id_ex.rs2_data;
    endcase

    if (held) begin
        rs1_val = held_a;
        rs2_val = held_b;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        held <= 1'b0;
    end else begin
        held <= hold;
        if (hold) begin
            held_a <= rs1_val;
            held_b <= rs2_val;
        end
    end
end

// ----------------------------------------------------------------------
// Operand select
// ----------------------------------------------------------------------
always_comb begin
    case (id_ex.ctrl.a_sel)
        A_PC:    a = id_ex.pc;
        A_ZERO:  a = 64'b0;
        default: a = rs1_val;
    endcase

    b = (id_ex.ctrl.b_sel == B_IMM) ? id_ex.imm : rs2_val;
end

alu alu_ex (
    .a      (a),
    .b      (b),
    .alu_op (id_ex.ctrl.alu_op),
    .word   (id_ex.ctrl.word),
    .result (alu_result)
);

// ----------------------------------------------------------------------
// Branch / jump resolution
// ----------------------------------------------------------------------
always_comb begin
    case (id_ex.funct3)
        F3_BEQ:  take_branch = (rs1_val == rs2_val);
        F3_BNE:  take_branch = (rs1_val != rs2_val);
        F3_BLT:  take_branch = ($signed(rs1_val) <  $signed(rs2_val));
        F3_BGE:  take_branch = ($signed(rs1_val) >= $signed(rs2_val));
        F3_BLTU: take_branch = (rs1_val <  rs2_val);
        F3_BGEU: take_branch = (rs1_val >= rs2_val);
        default: take_branch = 1'b0;
    endcase
end

// Branches and JAL jump to pc + imm, JALR to (rs1 + imm) & ~1 (the ALU result)
assign pc_target   = id_ex.ctrl.jalr ? {alu_result[63:1], 1'b0} : id_ex.pc + id_ex.imm;

assign pc_seq       = id_ex.pc + (id_ex.rvc ? 64'd2 : 64'd4);
assign end_pc       = id_ex.rvc ? id_ex.pc : id_ex.pc + 64'd2;   // last 16-bit parcel
assign actual_taken = id_ex.ctrl.jal || id_ex.ctrl.jalr || (id_ex.ctrl.branch && take_branch);
assign actual_next  = actual_taken ? pc_target : pc_seq;
assign pred_next    = id_ex.bp.pred_taken ? id_ex.bp.pred_target : pc_seq;

// Faulting instructions (and everything after a fault) neither redirect
// fetch nor train the predictor.
assign active       = id_ex.valid && !id_ex.fault && !hold && !kill;

// Any instruction whose predicted next PC was wrong redirects fetch.
// (With the predictor disabled pred_next is always pc + 2/4, so this is
//  exactly "redirect on every taken branch / jump".)
// Only once, when the instruction leaves EX (not while held by MEM).
assign redirect     = active && (actual_next != pred_next);
assign redirect_pc  = actual_next;

// ----------------------------------------------------------------------
// Predictor update. Call / return follow the RISC-V hint convention:
//   call   = jal / jalr with rd  in {x1, x5}
//   return = jalr      with rs1 in {x1, x5} (and not a call)
// ----------------------------------------------------------------------
function automatic logic is_link(input logic [4:0] r);
    return (r == 5'd1) || (r == 5'd5);
endfunction

assign is_call = (id_ex.ctrl.jal || id_ex.ctrl.jalr) && is_link(id_ex.rd);
assign is_ret  = id_ex.ctrl.jalr && is_link(id_ex.rs1) && !is_call;

always_comb begin
    bp_upd         = '0;
    bp_upd.valid   = active && (id_ex.ctrl.branch || id_ex.ctrl.jal || id_ex.ctrl.jalr);
    bp_upd.end_pc  = end_pc;
    bp_upd.link    = pc_seq;
    bp_upd.target  = pc_target;
    bp_upd.is_cond = active && id_ex.ctrl.branch;
    bp_upd.is_call = active && is_call;
    bp_upd.is_ret  = active && is_ret;
    bp_upd.taken   = actual_taken;
    bp_upd.pht_idx = id_ex.bp.pht_idx;
    bp_upd.recover = redirect;
    bp_upd.ghr     = id_ex.bp.ghr;
    bp_upd.ras_ptr = id_ex.bp.ras_ptr;
end

// ----------------------------------------------------------------------
// EX/MEM pipeline register
// ----------------------------------------------------------------------
always_ff @(posedge clk) begin
    if (rst || kill) begin
        ex_mem      <= '0;
        ex_mem.ctrl <= CTRL_NOP;
    end else if (hold) begin
        // memory wait: keep the instruction in MEM
    end else if (!id_ex.valid) begin
        ex_mem      <= '0;
        ex_mem.ctrl <= CTRL_NOP;
    end else begin
        ex_mem.valid      <= 1'b1;
        ex_mem.pc         <= id_ex.pc;
        ex_mem.pc_seq     <= pc_seq;
        ex_mem.alu_result <= alu_result;
        ex_mem.store_data <= rs2_val;
        ex_mem.rd         <= id_ex.rd;
        ex_mem.funct3     <= id_ex.funct3;
        ex_mem.fault      <= id_ex.fault;
        ex_mem.cause      <= id_ex.cause;
        ex_mem.ctrl       <= id_ex.ctrl;
    end
end

endmodule
