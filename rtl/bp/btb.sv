// Branch Target Buffer: direct-mapped, full tag, indexed by 32-bit fetch word.
// An entry records the control-flow instruction that ENDS in that word:
// which 16-bit half it ends in, its last target and its kind (RVC: a word
// can hold the end of one instruction plus one more compressed one).
module btb #(
    parameter int IDX_BITS = 6
) (
    input  logic        clk,
    input  logic        rst,

    // Lookup (IF): lookup_pc[1] = first half of the word actually used
    input  logic [63:0] lookup_pc,
    output logic        hit,
    output logic        half,         // half (0/1) the instruction ends in
    output logic [63:0] target,
    output logic [1:0]  kind,

    // Update (EX): upd_pc = address of the instruction's last parcel
    input  logic        we,
    input  logic [63:0] upd_pc,
    input  logic [63:0] upd_target,
    input  logic [1:0]  upd_kind
);

localparam int N        = 1 << IDX_BITS;
localparam int TAG_BITS = 64 - IDX_BITS - 2;

logic [N-1:0]        valid;
logic [TAG_BITS-1:0] tags    [N];
logic [63:0]         targets [N];
logic [1:0]          kinds   [N];
logic [N-1:0]        halves;

logic [IDX_BITS-1:0] l_idx, u_idx;

assign l_idx  = lookup_pc[IDX_BITS+1:2];
assign u_idx  = upd_pc[IDX_BITS+1:2];

// Ignore an instruction that ends before where this fetch starts
// (e.g. fetch entered the word at its upper half after a jump)
assign hit    = valid[l_idx] && (tags[l_idx] == lookup_pc[63:IDX_BITS+2]) &&
                (halves[l_idx] >= lookup_pc[1]);
assign half   = halves[l_idx];
assign target = targets[l_idx];
assign kind   = kinds[l_idx];

always_ff @(posedge clk) begin
    if (rst) begin
        valid <= '0;
    end else if (we) begin
        valid[u_idx]   <= 1'b1;
        tags[u_idx]    <= upd_pc[63:IDX_BITS+2];
        targets[u_idx] <= upd_target;
        kinds[u_idx]   <= upd_kind;
        halves[u_idx]  <= upd_pc[1];
    end
end

endmodule
