// Return Address Stack (circular, no overflow/underflow detection:
// overflow overwrites the oldest entry, underflow just mispredicts).
//
// Pushed / popped speculatively at fetch. Each instruction carries the
// stack pointer from before it as a checkpoint; on a mispredict the pointer
// is restored and the mispredicted instruction's own push/pop is re-applied.
// Entries overwritten on the wrong path are not restored (standard trade-off).
module ras #(
    parameter int PTR_BITS = 3
) (
    input  logic                clk,
    input  logic                rst,

    // Fetch side
    input  logic                push,
    input  logic                pop,
    input  logic [63:0]         push_addr,
    output logic [63:0]         top,
    output logic [PTR_BITS-1:0] ptr_ckpt,      // pointer before this instruction

    // Recovery (EX mispredict)
    input  logic                recover,
    input  logic [PTR_BITS-1:0] rec_ptr,
    input  logic                rec_push,      // mispredicted instruction was a call
    input  logic                rec_pop,       // ... or a return
    input  logic [63:0]         rec_addr       // its pc + 4
);

localparam int DEPTH = 1 << PTR_BITS;

logic [63:0]         stack [DEPTH];
logic [PTR_BITS-1:0] ptr;
logic [PTR_BITS-1:0] ptr_base;

always_comb begin
    if (!recover)      ptr_base = ptr;
    else if (rec_push) ptr_base = rec_ptr + 1'b1;
    else if (rec_pop)  ptr_base = rec_ptr - 1'b1;
    else               ptr_base = rec_ptr;
end

assign ptr_ckpt = ptr_base;

// Bypass the entry being written by a recovering call this same cycle
assign top = (recover && rec_push) ? rec_addr : stack[ptr_base];

always_ff @(posedge clk) begin
    if (rst) begin
        ptr <= '0;
    end else begin
        if (recover && rec_push)
            stack[ptr_base] <= rec_addr;

        if (push) begin
            stack[ptr_base + 1'b1] <= push_addr;
            ptr <= ptr_base + 1'b1;
        end else if (pop) begin
            ptr <= ptr_base - 1'b1;
        end else begin
            ptr <= ptr_base;
        end
    end
end

endmodule
