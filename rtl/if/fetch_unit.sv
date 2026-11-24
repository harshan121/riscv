// Instruction fetch: AXI4-Lite read master (32-bit data), branch predictor,
// and a queue of 16-bit parcels for the RVC aligner.
//
//  - Requests are aligned 32-bit words; the next fetch address comes from
//    the branch predictor (which is looked up with the request address).
//  - Up to MAX_OUT reads may be outstanding (AXI4-Lite has no IDs, so
//    responses return in order). A small FIFO remembers each request's
//    address and prediction until its response arrives.
//  - A redirect cannot cancel an AXI read, so in-flight requests are marked
//    "killed" and their responses are dropped.
//  - AXI rules kept: ARVALID never depends on ARREADY, and once raised it
//    stays high with a stable address until accepted, even across a redirect.
//  - The parcel queue never overflows: a request is only issued while
//    queue entries + 2 x (live outstanding requests) leave room for 2 more.
//  - An error response (RRESP != OKAY) marks the word's parcels as faulted;
//    the fault is only taken if such an instruction reaches MEM.
//  - stop (core halted): no new requests are issued. A request already
//    raised on AR is still completed, and every outstanding response is
//    accepted (RREADY stays high) and dropped, so the bus drains cleanly.
module fetch_unit
    import riscv_pkg::*;
#(
    parameter bit BP_ENABLE  = 1,
    parameter bit USE_GSHARE = 1,
    parameter bit ENABLE_RAS = 1,
    parameter int QDEPTH     = 8,       // parcel queue entries (power of 2)
    parameter int MAX_OUT    = 4        // outstanding reads (power of 2)
) (
    input  logic        clk,
    input  logic        rst,

    // Redirect (EX mispredict) and predictor training
    input  logic        redirect,
    input  logic [63:0] redirect_pc,
    input  bp_update_t  bp_upd,
    input  logic        stop,           // halted: issue no new requests

    // AXI4-Lite read address / data channels
    output logic        m_arvalid,
    input  logic        m_arready,
    output logic [63:0] m_araddr,
    output logic [2:0]  m_arprot,
    input  logic        m_rvalid,
    output logic        m_rready,
    input  logic [31:0] m_rdata,
    input  logic [1:0]  m_rresp,

    // Parcel queue head (to the aligner)
    output parcel_t     q0,
    output parcel_t     q1,
    output logic [$clog2(QDEPTH):0] q_count,
    input  logic [1:0]  q_pop
);

localparam int QB = $clog2(QDEPTH);
localparam int MB = $clog2(MAX_OUT);

typedef struct packed {
    logic        killed;
    logic [63:0] addr;        // bit 1 = first half used
    logic        pred_half;
    bp_info_t    bp;
} meta_t;

// ----------------------------------------------------------------------
// State
// ----------------------------------------------------------------------
logic [63:0]  fetch_pc;            // next address to request
logic         ar_pending;          // ARVALID raised last cycle, not accepted
logic [63:0]  held_addr;
logic         held_killed;

meta_t        meta [MAX_OUT];
logic [MB-1:0] m_head, m_tail;
logic [MB:0]   m_count;
logic [MB:0]   live_out;           // outstanding requests that are not killed

parcel_t      pq [QDEPTH];
logic [QB-1:0] pq_head;
logic [QB:0]   pq_count;

// ----------------------------------------------------------------------
// Branch predictor (looked up with the address being requested)
// ----------------------------------------------------------------------
bp_info_t     pred;
logic         pred_half;
logic [63:0]  present_addr;
logic         present_killed;
logic         ar_hs;
logic         can_issue;

branch_predictor #(
    .BP_ENABLE  (BP_ENABLE),
    .USE_GSHARE (USE_GSHARE),
    .ENABLE_RAS (ENABLE_RAS),
    .BTB_BITS   (BP_BTB_BITS),
    .PHT_BITS   (BP_PHT_BITS),
    .RAS_BITS   (BP_RAS_BITS)
) u_bp (
    .clk          (clk),
    .rst          (rst),
    .lookup_valid (ar_hs && !present_killed),
    .lookup_pc    (present_addr),
    .pred_taken   (pred.pred_taken),
    .pred_half    (pred_half),
    .pred_target  (pred.pred_target),
    .pred_pht_idx (pred.pht_idx),
    .pred_ghr     (pred.ghr),
    .pred_ras_ptr (pred.ras_ptr),
    .upd_valid    (bp_upd.valid),
    .upd_pc       (bp_upd.end_pc),
    .upd_link     (bp_upd.link),
    .upd_target   (bp_upd.target),
    .upd_is_cond  (bp_upd.is_cond),
    .upd_is_call  (bp_upd.is_call),
    .upd_is_ret   (bp_upd.is_ret),
    .upd_taken    (bp_upd.taken),
    .upd_pht_idx  (bp_upd.pht_idx),
    .recover      (bp_upd.recover),
    .rec_ghr      (bp_upd.ghr),
    .rec_ras_ptr  (bp_upd.ras_ptr)
);

// ----------------------------------------------------------------------
// Read address channel
// ----------------------------------------------------------------------
// After a redirect the queue is flushed and every outstanding request is
// killed, so only the request-tracking FIFO limits issue in that cycle.
localparam int CW = QB + MB + 3;    // wide enough for the credit sum
logic [CW-1:0] credit_need;
assign credit_need = CW'(pq_count) + CW'({live_out, 1'b0}) + CW'(2);
assign can_issue   = !stop && (m_count < (MB+1)'(MAX_OUT)) &&
                     (redirect || credit_need <= CW'(QDEPTH));

assign present_addr   = ar_pending ? held_addr : (redirect ? redirect_pc : fetch_pc);
assign present_killed = ar_pending && (held_killed || redirect);

assign m_arvalid = !rst && (ar_pending || can_issue);
assign m_araddr  = {present_addr[63:2], 2'b00};
assign m_arprot  = 3'b100;                         // instruction access
assign ar_hs     = m_arvalid && m_arready;

// ----------------------------------------------------------------------
// Read data channel -> parcels
// ----------------------------------------------------------------------
meta_t   rmeta;
logic    r_use;
logic    use0, use1;
logic    end_half;
parcel_t p0, p1;
logic [1:0] push_n;

assign m_rready = 1'b1;
assign rmeta    = meta[m_head];
assign r_use    = m_rvalid && !rmeta.killed && !redirect;

// Parcels used from the word: from the start half up to the predicted end
assign end_half = rmeta.bp.pred_taken ? rmeta.pred_half : 1'b1;
assign use0     = r_use && !rmeta.addr[1];
assign use1     = r_use && end_half;

always_comb begin
    p0 = '0;
    p0.data           = m_rdata[15:0];
    p0.pc             = {rmeta.addr[63:2], 2'b00};
    p0.fault          = (m_rresp != 2'b00);
    p0.bp             = rmeta.bp;
    p0.bp.pred_taken  = rmeta.bp.pred_taken && !end_half;

    p1 = '0;
    p1.data           = m_rdata[31:16];
    p1.pc             = {rmeta.addr[63:2], 2'b10};
    p1.fault          = (m_rresp != 2'b00);
    p1.bp             = rmeta.bp;
    p1.bp.pred_taken  = rmeta.bp.pred_taken && end_half;
end

assign push_n = {1'b0, use0} + {1'b0, use1};

// ----------------------------------------------------------------------
// Queue head to the aligner
// ----------------------------------------------------------------------
assign q0      = pq[pq_head];
assign q1      = pq[pq_head + 1'b1];
assign q_count = pq_count;

// ----------------------------------------------------------------------
// Sequential
// ----------------------------------------------------------------------
logic [QB-1:0] tail;
assign tail = pq_head + pq_count[QB-1:0];

always_ff @(posedge clk) begin
    if (rst) begin
        fetch_pc    <= 64'd0;
        ar_pending  <= 1'b0;
        held_addr   <= 64'd0;
        held_killed <= 1'b0;
        m_head      <= '0;
        m_tail      <= '0;
        m_count     <= '0;
        live_out    <= '0;
        pq_head     <= '0;
        pq_count    <= '0;
    end else begin

        // ---- AR: hold an unaccepted request
        ar_pending  <= m_arvalid && !m_arready;
        held_addr   <= present_addr;
        held_killed <= present_killed;

        // ---- Next fetch address
        if (ar_hs && !present_killed)
            fetch_pc <= pred.pred_taken ? pred.pred_target
                                        : {present_addr[63:2], 2'b00} + 64'd4;
        else if (redirect)
            fetch_pc <= redirect_pc;

        // ---- Request tracking FIFO
        if (redirect)
            for (int i = 0; i < MAX_OUT; i++) meta[i].killed <= 1'b1;

        if (ar_hs) begin
            meta[m_tail].killed    <= present_killed;
            meta[m_tail].addr      <= present_addr;
            meta[m_tail].pred_half <= pred_half;
            meta[m_tail].bp        <= pred;
            m_tail                 <= m_tail + 1'b1;
        end
        if (m_rvalid) m_head <= m_head + 1'b1;

        m_count  <= m_count + (MB+1)'(ar_hs) - (MB+1)'(m_rvalid);
        live_out <= (redirect ? '0 : live_out - (MB+1)'(m_rvalid && !rmeta.killed))
                    + (MB+1)'(ar_hs && !present_killed);

        // ---- Parcel queue
        if (use0)
            pq[tail] <= p0;
        if (use1)
            pq[use0 ? tail + 1'b1 : tail] <= p1;

        if (redirect) begin
            pq_count <= '0;
        end else begin
            pq_head  <= pq_head + q_pop;
            pq_count <= pq_count + (QB+1)'(push_n) - (QB+1)'(q_pop);
        end
    end
end

// Responses must match a tracked request
always_ff @(posedge clk)
    if (!rst && m_rvalid && m_count == 0) $error("fetch: R response with no outstanding request");

endmodule
