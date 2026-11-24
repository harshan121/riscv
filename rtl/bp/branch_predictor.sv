// Branch predictor: BTB + direction predictor (bimodal / gshare) + RAS.
//
//   BP_ENABLE  = 0 : static not-taken baseline (all tables removed)
//   USE_GSHARE = 0 : bimodal direction predictor, 1 : gshare
//   ENABLE_RAS = 0 : returns predicted from the BTB, 1 : from the RAS
//
// The prediction is made from the fetch address alone (the instruction has
// not arrived yet), so the BTB tells us whether the 32-bit fetch word ends a
// branch at all, and in which 16-bit half (RVC).
module branch_predictor #(
    parameter bit BP_ENABLE  = 1,
    parameter bit USE_GSHARE = 0,
    parameter bit ENABLE_RAS = 1,
    parameter int BTB_BITS   = 6,
    parameter int PHT_BITS   = 6,
    parameter int RAS_BITS   = 3
) (
    input  logic                clk,
    input  logic                rst,

    // Lookup (IF): lookup_valid = the fetch request is accepted this cycle.
    // lookup_pc is the fetch address; bit 1 = first half used (jump target).
    input  logic                lookup_valid,
    input  logic [63:0]         lookup_pc,
    output logic                pred_taken,
    output logic                pred_half,      // half the predicted branch ends in
    output logic [63:0]         pred_target,
    output logic [PHT_BITS-1:0] pred_pht_idx,
    output logic [PHT_BITS-1:0] pred_ghr,
    output logic [RAS_BITS-1:0] pred_ras_ptr,

    // Resolution (EX)
    input  logic                upd_valid,      // branch / jump resolved
    input  logic [63:0]         upd_pc,         // address of its last parcel
    input  logic [63:0]         upd_link,       // its pc + 2 / 4
    input  logic [63:0]         upd_target,
    input  logic                upd_is_cond,
    input  logic                upd_is_call,
    input  logic                upd_is_ret,
    input  logic                upd_taken,
    input  logic [PHT_BITS-1:0] upd_pht_idx,
    input  logic                recover,        // mispredict
    input  logic [PHT_BITS-1:0] rec_ghr,
    input  logic [RAS_BITS-1:0] rec_ras_ptr
);

localparam logic [1:0] K_COND = 2'd0;   // conditional branch
localparam logic [1:0] K_JUMP = 2'd1;   // jal / jalr that is neither call nor return
localparam logic [1:0] K_CALL = 2'd2;   // jal / jalr with rd = x1 / x5
localparam logic [1:0] K_RET  = 2'd3;   // jalr with rs1 = x1 / x5

generate if (!BP_ENABLE) begin : g_static

    assign pred_taken   = 1'b0;
    assign pred_half    = 1'b1;
    assign pred_target  = {lookup_pc[63:2], 2'b00} + 64'd4;
    assign pred_pht_idx = '0;
    assign pred_ghr     = '0;
    assign pred_ras_ptr = '0;

end else begin : g_dynamic

    logic        btb_hit;
    logic [63:0] btb_target;
    logic [1:0]  btb_kind;
    logic        btb_half;
    logic [63:0] word_pc;

    assign word_pc = {lookup_pc[63:2], 2'b00};
    logic        dir_taken;
    logic [63:0] ras_top;
    logic [1:0]  upd_kind;

    assign upd_kind = upd_is_cond ? K_COND :
                      upd_is_call ? K_CALL :
                      upd_is_ret  ? K_RET  : K_JUMP;

    btb #(.IDX_BITS(BTB_BITS)) u_btb (
        .clk        (clk),
        .rst        (rst),
        .lookup_pc  (lookup_pc),
        .hit        (btb_hit),
        .half       (btb_half),
        .target     (btb_target),
        .kind       (btb_kind),
        .we         (upd_valid),
        .upd_pc     (upd_pc),
        .upd_target (upd_target),
        .upd_kind   (upd_kind)
    );

    direction_predictor #(.IDX_BITS(PHT_BITS), .USE_GSHARE(USE_GSHARE)) u_dir (
        .clk         (clk),
        .rst         (rst),
        .lookup_pc   (lookup_pc),
        .taken       (dir_taken),
        .idx         (pred_pht_idx),
        .ghr_ckpt    (pred_ghr),
        .spec_shift  (lookup_valid && btb_hit && btb_kind == K_COND),
        .recover     (recover),
        .rec_ghr     (rec_ghr),
        .rec_is_cond (upd_is_cond),
        .rec_taken   (upd_taken),
        .upd_we      (upd_valid && upd_is_cond),
        .upd_idx     (upd_pht_idx),
        .upd_taken   (upd_taken)
    );

    if (ENABLE_RAS) begin : g_ras
        ras #(.PTR_BITS(RAS_BITS)) u_ras (
            .clk       (clk),
            .rst       (rst),
            .push      (lookup_valid && btb_hit && btb_kind == K_CALL),
            .pop       (lookup_valid && btb_hit && btb_kind == K_RET),
            // return address = end of the call's last parcel + 2
            .push_addr (word_pc + {61'd0, btb_half, 1'b0} + 64'd2),
            .top       (ras_top),
            .ptr_ckpt  (pred_ras_ptr),
            .recover   (recover),
            .rec_ptr   (rec_ras_ptr),
            .rec_push  (upd_is_call),
            .rec_pop   (upd_is_ret),
            .rec_addr  (upd_link)
        );
    end else begin : g_no_ras
        assign ras_top      = btb_target;
        assign pred_ras_ptr = '0;
    end

    assign pred_half = btb_half;

    // Next-PC selection (not taken: next sequential fetch word)
    always_comb begin
        pred_taken  = 1'b0;
        pred_target = word_pc + 64'd4;

        if (btb_hit) begin
            case (btb_kind)
                K_COND: if (dir_taken) begin
                            pred_taken  = 1'b1;
                            pred_target = btb_target;
                        end
                K_RET:  begin
                            pred_taken  = 1'b1;
                            pred_target = ras_top;
                        end
                default: begin                      // K_JUMP, K_CALL
                            pred_taken  = 1'b1;
                            pred_target = btb_target;
                        end
            endcase
        end
    end

end endgenerate

endmodule
