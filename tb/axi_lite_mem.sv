// Behavioural AXI4-Lite slave memory for simulation.
//
//   DATA_W     : 32 or 64
//   LATENCY    : minimum cycles from address handshake to response (>= 1)
//   RAND_STALL : 1 = randomly drop ready signals and add 0-3 cycles of
//                extra latency (exercises the master's handshake logic)
//   ERR_BASE   : accesses at or above this address get SLVERR (writes there
//                are dropped); default: no error region
//
// Reads may be outstanding (in-order responses, up to 8). One write at a
// time. Byte array `mem` is accessed directly by the testbench.
// Also checks the AXI rules a master must follow: VALID stays high and the
// payload stays stable until the handshake.
module axi_lite_mem #(
    parameter int DATA_W     = 64,
    parameter int MEM_BYTES  = 65536,
    parameter int LATENCY    = 1,
    parameter bit RAND_STALL = 0,
    parameter int SEED       = 1,
    parameter logic [63:0] ERR_BASE = 64'hFFFF_FFFF_FFFF_FFFF,
    parameter string NAME    = "mem"
) (
    input  logic                clk,
    input  logic                rst,

    input  logic                awvalid,
    output logic                awready,
    input  logic [63:0]         awaddr,
    input  logic                wvalid,
    output logic                wready,
    input  logic [DATA_W-1:0]   wdata,
    input  logic [DATA_W/8-1:0] wstrb,
    output logic                bvalid,
    input  logic                bready,
    output logic [1:0]          bresp,

    input  logic                arvalid,
    output logic                arready,
    input  logic [63:0]         araddr,
    output logic                rvalid,
    input  logic                rready,
    output logic [DATA_W-1:0]   rdata,
    output logic [1:0]          rresp
);

localparam int NB = DATA_W / 8;

logic [7:0] mem [MEM_BYTES];

initial begin
    for (int i = 0; i < MEM_BYTES; i++) mem[i] = 8'h00;
    void'($urandom(SEED));
end

function automatic int extra();
    return RAND_STALL ? int'($urandom_range(0, 3)) : 0;
endfunction

function automatic logic rnd_ready();
    return RAND_STALL ? ($urandom_range(0, 3) != 0) : 1'b1;
endfunction

function automatic logic [DATA_W-1:0] read_word(input logic [63:0] a);
    logic [DATA_W-1:0] d;
    logic [63:0] base = (a & ~64'(NB - 1)) % MEM_BYTES;
    for (int i = 0; i < NB; i++) d[i*8 +: 8] = mem[base + i];
    return d;
endfunction

longint cycle = 0;
always @(posedge clk) cycle <= cycle + 1;

// ----------------------------------------------------------------------
// Reads: queue of accepted addresses with the cycle they become ready
// ----------------------------------------------------------------------
logic [63:0] rq_addr [$];
longint      rq_time [$];

always @(posedge clk) begin
    if (rst) begin
        rq_addr.delete(); rq_time.delete();
        arready <= 1'b0;
        rvalid  <= 1'b0;
    end else begin
        if (arvalid && arready) begin
            rq_addr.push_back(araddr);
            rq_time.push_back(cycle + LATENCY - 1 + extra());
        end
        if (rvalid && rready) begin
            void'(rq_addr.pop_front()); void'(rq_time.pop_front());
        end

        // Present the head response (rvalid stays high until accepted)
        if (rq_addr.size() > 0 && (rvalid && !rready || cycle >= rq_time[0])) begin
            rvalid <= 1'b1;
            rdata  <= read_word(rq_addr[0]);
            rresp  <= (rq_addr[0] >= ERR_BASE) ? 2'b10 : 2'b00;
        end else begin
            rvalid <= 1'b0;
        end

        arready <= (rq_addr.size() < 7) && rnd_ready();
    end
end

// ----------------------------------------------------------------------
// Writes: AW and W may arrive in either order / together
// ----------------------------------------------------------------------
logic                have_aw, have_w;
logic [63:0]         w_addr;
logic [DATA_W-1:0]   w_data;
logic [NB-1:0]       w_strb;
longint              b_time;
logic                b_pend;

// Internal state uses blocking updates so a write can complete on the same
// edge its address and data are accepted; outputs are non-blocking.
always @(posedge clk) begin
    if (rst) begin
        have_aw = 0; have_w = 0; b_pend = 0;
        awready <= 0; wready <= 0; bvalid <= 0; bresp <= 2'b00;
    end else begin
        if (awvalid && awready) begin have_aw = 1; w_addr = awaddr; end
        if (wvalid  && wready)  begin have_w  = 1; w_data = wdata; w_strb = wstrb; end
        if (bvalid  && bready)  b_pend = 0;

        if (have_aw && have_w && !b_pend) begin
            logic [63:0] base = (w_addr & ~64'(NB - 1)) % MEM_BYTES;
            if (w_addr < ERR_BASE) begin
                for (int i = 0; i < NB; i++)
                    if (w_strb[i]) mem[base + i] = w_data[i*8 +: 8];
            end
            bresp  <= (w_addr >= ERR_BASE) ? 2'b10 : 2'b00;
            have_aw = 0; have_w = 0;
            b_pend  = 1;
            b_time  = cycle + LATENCY - 1 + extra();
        end

        bvalid  <= b_pend && cycle >= b_time;
        awready <= !have_aw && !b_pend && rnd_ready();
        wready  <= !have_w  && !b_pend && rnd_ready();
    end
end

// ----------------------------------------------------------------------
// Protocol checks on the master
// ----------------------------------------------------------------------
logic                pv_ar, pv_aw, pv_w;
logic [63:0]         pa_ar, pa_aw;
logic [DATA_W-1:0]   pd_w;
logic [NB-1:0]       ps_w;

always @(posedge clk) begin
    if (rst) begin
        pv_ar <= 0; pv_aw <= 0; pv_w <= 0;
    end else begin
        if (pv_ar && !arvalid)                  $error("%s: ARVALID dropped before ARREADY", NAME);
        if (pv_ar && arvalid && araddr != pa_ar) $error("%s: ARADDR changed while waiting", NAME);
        if (pv_aw && !awvalid)                  $error("%s: AWVALID dropped before AWREADY", NAME);
        if (pv_aw && awvalid && awaddr != pa_aw) $error("%s: AWADDR changed while waiting", NAME);
        if (pv_w && !wvalid)                    $error("%s: WVALID dropped before WREADY", NAME);
        if (pv_w && wvalid && (wdata != pd_w || wstrb != ps_w)) $error("%s: W payload changed while waiting", NAME);

        pv_ar <= arvalid && !arready;  pa_ar <= araddr;
        pv_aw <= awvalid && !awready;  pa_aw <= awaddr;
        pv_w  <= wvalid  && !wready;   pd_w  <= wdata; ps_w <= wstrb;
    end
end

endmodule
