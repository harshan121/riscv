// Core + AXI4-Lite instruction / data memories. Included inside each
// testbench module, which must declare clk, rst, halt and the parameters
// BP_ENABLE, USE_GSHARE, ENABLE_RAS, MEM_LAT, RAND_STALL.
//
// Harvard setup: instructions and data live in separate memories, both
// starting at address 0 (`imem.mem`, `dmem.mem` are byte arrays).
// Optional IERR_BASE / DERR_BASE parameters: AXI error regions.
`ifndef TB_ERR_BASES
localparam logic [63:0] IERR_BASE = 64'hFFFF_FFFF_FFFF_FFFF;
localparam logic [63:0] DERR_BASE = 64'hFFFF_FFFF_FFFF_FFFF;
`endif

logic        fault_valid;
logic [63:0] fault_pc;
logic [3:0]  fault_cause;

logic        i_arvalid, i_arready, i_rvalid, i_rready;
logic [63:0] i_araddr;
logic [2:0]  i_arprot;
logic [31:0] i_rdata;
logic [1:0]  i_rresp;

logic        d_awvalid, d_awready, d_wvalid, d_wready, d_bvalid, d_bready;
logic        d_arvalid, d_arready, d_rvalid, d_rready;
logic [63:0] d_awaddr, d_araddr, d_wdata, d_rdata;
logic [2:0]  d_awprot, d_arprot;
logic [7:0]  d_wstrb;
logic [1:0]  d_bresp, d_rresp;

core #(
    .BP_ENABLE  (BP_ENABLE),
    .USE_GSHARE (USE_GSHARE),
    .ENABLE_RAS (ENABLE_RAS)
) dut (
    .clk (clk), .rst (rst), .halted (halt),
    .fault_valid (fault_valid), .fault_pc (fault_pc), .fault_cause (fault_cause),
    .m_axi_i_arvalid (i_arvalid), .m_axi_i_arready (i_arready), .m_axi_i_araddr (i_araddr),
    .m_axi_i_arprot  (i_arprot),  .m_axi_i_rvalid  (i_rvalid),  .m_axi_i_rready (i_rready),
    .m_axi_i_rdata   (i_rdata),   .m_axi_i_rresp   (i_rresp),
    .m_axi_d_awvalid (d_awvalid), .m_axi_d_awready (d_awready), .m_axi_d_awaddr (d_awaddr),
    .m_axi_d_awprot  (d_awprot),  .m_axi_d_wvalid  (d_wvalid),  .m_axi_d_wready (d_wready),
    .m_axi_d_wdata   (d_wdata),   .m_axi_d_wstrb   (d_wstrb),   .m_axi_d_bvalid (d_bvalid),
    .m_axi_d_bready  (d_bready),  .m_axi_d_bresp   (d_bresp),   .m_axi_d_arvalid (d_arvalid),
    .m_axi_d_arready (d_arready), .m_axi_d_araddr  (d_araddr),  .m_axi_d_arprot (d_arprot),
    .m_axi_d_rvalid  (d_rvalid),  .m_axi_d_rready  (d_rready),  .m_axi_d_rdata  (d_rdata),
    .m_axi_d_rresp   (d_rresp)
);

axi_lite_mem #(
    .DATA_W (32), .MEM_BYTES (65536), .LATENCY (MEM_LAT),
    .RAND_STALL (RAND_STALL), .SEED (11), .NAME ("imem"), .ERR_BASE (IERR_BASE)
) imem (
    .clk (clk), .rst (rst),
    .awvalid (1'b0), .awready (), .awaddr ('0), .wvalid (1'b0), .wready (),
    .wdata ('0), .wstrb ('0), .bvalid (), .bready (1'b1), .bresp (),
    .arvalid (i_arvalid), .arready (i_arready), .araddr (i_araddr),
    .rvalid (i_rvalid), .rready (i_rready), .rdata (i_rdata), .rresp (i_rresp)
);

axi_lite_mem #(
    .DATA_W (64), .MEM_BYTES (65536), .LATENCY (MEM_LAT),
    .RAND_STALL (RAND_STALL), .SEED (22), .NAME ("dmem"), .ERR_BASE (DERR_BASE)
) dmem (
    .clk (clk), .rst (rst),
    .awvalid (d_awvalid), .awready (d_awready), .awaddr (d_awaddr),
    .wvalid (d_wvalid), .wready (d_wready), .wdata (d_wdata), .wstrb (d_wstrb),
    .bvalid (d_bvalid), .bready (d_bready), .bresp (d_bresp),
    .arvalid (d_arvalid), .arready (d_arready), .araddr (d_araddr),
    .rvalid (d_rvalid), .rready (d_rready), .rdata (d_rdata), .rresp (d_rresp)
);
