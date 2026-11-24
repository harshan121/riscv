// Instruction Fetch stage (RV64IC)
//
//   fetch_unit (AXI4-Lite reads + branch predictor + parcel queue)
//     -> aligner: 1 parcel (compressed, expanded to 32 bits) or
//                 2 parcels (32-bit instruction, may span two fetch words)
//     -> IF/ID pipeline register
module if_stage
    import riscv_pkg::*;
#(
    parameter bit BP_ENABLE  = 1,
    parameter bit USE_GSHARE = 1,
    parameter bit ENABLE_RAS = 1
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        stall,          // hold IF/ID (load-use or memory wait)
    input  logic        kill,           // fault taken / halted: flush, stop fetching
    input  logic [63:0] redirect_pc,
    input  logic        redirect,

    // AXI4-Lite instruction port (read only)
    output logic        m_arvalid,
    input  logic        m_arready,
    output logic [63:0] m_araddr,
    output logic [2:0]  m_arprot,
    input  logic        m_rvalid,
    output logic        m_rready,
    input  logic [31:0] m_rdata,
    input  logic [1:0]  m_rresp,

    // IF/ID
    output logic [31:0] if_id,
    output logic        if_valid,
    output logic        if_rvc,         // instruction was compressed (2 bytes)
    output logic        if_fault,       // instruction fetch returned an AXI error
    output logic [63:0] pc,
    output bp_info_t    if_bp,

    input  bp_update_t  bp_upd          // resolution from EX
);

    localparam int QDEPTH = 8;

    parcel_t                q0, q1;
    logic [$clog2(QDEPTH):0] q_count;
    logic [1:0]             q_pop;

    fetch_unit #(
        .BP_ENABLE  (BP_ENABLE),
        .USE_GSHARE (USE_GSHARE),
        .ENABLE_RAS (ENABLE_RAS),
        .QDEPTH     (QDEPTH)
    ) if_fetch_unit (
        .clk         (clk),
        .rst         (rst),
        .redirect    (redirect),
        .redirect_pc (redirect_pc),
        .bp_upd      (bp_upd),
        .stop        (kill),
        .m_arvalid   (m_arvalid),
        .m_arready   (m_arready),
        .m_araddr    (m_araddr),
        .m_arprot    (m_arprot),
        .m_rvalid    (m_rvalid),
        .m_rready    (m_rready),
        .m_rdata     (m_rdata),
        .m_rresp     (m_rresp),
        .q0          (q0),
        .q1          (q1),
        .q_count     (q_count),
        .q_pop       (q_pop)
    );


    // --------------------------------
    // Aligner
    // --------------------------------

    logic        is32;
    logic        avail;
    logic        fault;
    logic        take;
    logic [31:0] expanded;      // 32'h0 for illegal encodings: ID rejects opcode 0
    logic [31:0] ins;
    bp_info_t    ins_bp;

    /* verilator lint_off PINCONNECTEMPTY */
    rvc_expander if_rvc_expander (
        .c       (q0.data),
        .ins     (expanded),
        .illegal ()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // A faulted first parcel is passed on at once (its contents are
    // meaningless, so do not wait for a second half).
    assign is32   = (q0.data[1:0] == 2'b11) && !q0.fault;
    assign avail  = (q_count >= 1) && (!is32 || q_count >= 2);
    assign fault  = q0.fault || (is32 && q1.fault);

    assign ins    = is32 ? {q1.data, q0.data} : expanded;

    // The prediction belongs to the parcel the instruction ends in
    assign ins_bp = is32 ? q1.bp : q0.bp;

    assign take   = avail && !stall && !redirect && !kill;
    assign q_pop  = take ? (is32 ? 2'd2 : 2'd1) : 2'd0;

    // A predicted-taken mark on the first half of a 32-bit instruction can
    // only come from a stale BTB entry (self-modifying code), not supported.
    always_ff @(posedge clk)
        if (!rst && avail && is32 && !fault && q0.bp.pred_taken)
            $error("aligner: prediction points into the middle of a 32-bit instruction at %h", q0.pc);


    // --------------------------------
    // IF / ID Pipeline Register
    // --------------------------------

    always_ff @(posedge clk) begin

        if (rst || kill || redirect) begin

            // Flush instruction currently in IF/ID
            if_id    <= 32'd0;
            pc       <= 64'd0;
            if_rvc   <= 1'b0;
            if_fault <= 1'b0;
            if_bp    <= '0;
            if_valid <= 1'b0;

        end

        else if (stall) begin

            // hold

        end

        else if (avail) begin

            if_id    <= ins;
            pc       <= q0.pc;
            if_rvc   <= !is32;
            if_fault <= fault;
            if_bp    <= ins_bp;
            if_valid <= 1'b1;

        end

        else begin

            // Nothing fetched yet: bubble
            if_valid <= 1'b0;

        end

    end

endmodule
