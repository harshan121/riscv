// Conditional-branch direction predictor: table of 2-bit saturating counters.
//   USE_GSHARE = 0 : bimodal, index = PC[IDX_BITS+1:2]
//   USE_GSHARE = 1 : gshare,  index = PC[IDX_BITS+1:2] ^ GHR
//
// The global history register (GHR) is updated speculatively at fetch with
// the predicted direction. Each instruction carries the GHR value from
// before it as a checkpoint; on a mispredict the GHR is rebuilt from that
// checkpoint plus the real outcome.
module direction_predictor #(
    parameter int IDX_BITS   = 6,
    parameter bit USE_GSHARE = 0
) (
    input  logic                clk,
    input  logic                rst,

    // Lookup (IF)
    input  logic [63:0]         lookup_pc,
    output logic                taken,
    output logic [IDX_BITS-1:0] idx,
    output logic [IDX_BITS-1:0] ghr_ckpt,      // history before this instruction
    input  logic                spec_shift,    // fetched a predicted cond. branch

    // Recovery (EX mispredict)
    input  logic                recover,
    input  logic [IDX_BITS-1:0] rec_ghr,
    input  logic                rec_is_cond,
    input  logic                rec_taken,

    // Training (EX)
    input  logic                upd_we,
    input  logic [IDX_BITS-1:0] upd_idx,
    input  logic                upd_taken
);

localparam int N = 1 << IDX_BITS;

logic [1:0]          pht [N];
logic [IDX_BITS-1:0] ghr;
logic [IDX_BITS-1:0] ghr_base;

// History as it should be this cycle (a recovery takes effect immediately,
// because the redirected fetch is looked up in the same cycle)
always_comb begin
    if (recover)
        ghr_base = rec_is_cond ? {rec_ghr[IDX_BITS-2:0], rec_taken} : rec_ghr;
    else
        ghr_base = ghr;
end

assign ghr_ckpt = USE_GSHARE ? ghr_base : '0;   // bimodal: no history kept
assign idx      = USE_GSHARE ? (lookup_pc[IDX_BITS+1:2] ^ ghr_base) : lookup_pc[IDX_BITS+1:2];
assign taken    = pht[idx][1];

always_ff @(posedge clk) begin
    if (rst) begin
        ghr <= '0;
        for (int i = 0; i < N; i++) pht[i] <= 2'b01;    // weakly not taken
    end else begin
        if (USE_GSHARE) ghr <= spec_shift ? {ghr_base[IDX_BITS-2:0], taken} : ghr_base;

        if (upd_we) begin
            if (upd_taken && pht[upd_idx] != 2'b11)
                pht[upd_idx] <= pht[upd_idx] + 2'b01;
            else if (!upd_taken && pht[upd_idx] != 2'b00)
                pht[upd_idx] <= pht[upd_idx] - 2'b01;
        end
    end
end

endmodule
