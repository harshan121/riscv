// RV64IC 5-stage in-order pipeline: IF -> ID -> EX -> MEM -> WB
//
// Memory: two AXI4-Lite masters
//   - m_axi_i_*: instruction fetch, 32-bit data, read only, up to 4 reads
//                outstanding
//   - m_axi_d_*: loads / stores, 64-bit data, one access at a time
//
// Faults (minimal, no CSRs / privileged architecture):
//   Illegal or unsupported instructions, ecall, ebreak, misaligned loads /
//   stores and AXI error responses are taken precisely in MEM. The core then
//   halts: fault_valid / fault_pc / fault_cause / halted hold their values
//   until reset. Older instructions complete; the faulting instruction and
//   everything younger have no architectural effect. ebreak is the normal
//   way for a program to stop (cause 3, CAUSE_BREAKPOINT).
//
// Hazards:
//   - Data:    full forwarding into EX (EX/MEM, MEM/WB) + reg file write-through.
//              Load-use costs one stall cycle.
//   - Memory:  a load/store in MEM holds IF/ID, ID/EX and EX/MEM until its
//              AXI response arrives (mem_stall).
//   - Control: next PC predicted in IF (BTB + bimodal/gshare + RAS),
//              checked in EX; a mispredict flushes the front end.
//              BP_ENABLE = 0 gives the static not-taken baseline.
module core
    import riscv_pkg::*;
#(
    parameter bit BP_ENABLE  = 1,
    parameter bit USE_GSHARE = 1,
    parameter bit ENABLE_RAS = 1
) (
    input  logic        clk,
    input  logic        rst,            // synchronous, active high

    // Fault / halt status (registered, sticky until reset)
    output logic        halted,
    output logic        fault_valid,
    output logic [63:0] fault_pc,
    output logic [3:0]  fault_cause,    // RISC-V mcause exception code

    // AXI4-Lite instruction port (read channels only)
    output logic        m_axi_i_arvalid,
    input  logic        m_axi_i_arready,
    output logic [63:0] m_axi_i_araddr,
    output logic [2:0]  m_axi_i_arprot,
    input  logic        m_axi_i_rvalid,
    output logic        m_axi_i_rready,
    input  logic [31:0] m_axi_i_rdata,
    input  logic [1:0]  m_axi_i_rresp,

    // AXI4-Lite data port
    output logic        m_axi_d_awvalid,
    input  logic        m_axi_d_awready,
    output logic [63:0] m_axi_d_awaddr,
    output logic [2:0]  m_axi_d_awprot,
    output logic        m_axi_d_wvalid,
    input  logic        m_axi_d_wready,
    output logic [63:0] m_axi_d_wdata,
    output logic [7:0]  m_axi_d_wstrb,
    input  logic        m_axi_d_bvalid,
    output logic        m_axi_d_bready,
    input  logic [1:0]  m_axi_d_bresp,
    output logic        m_axi_d_arvalid,
    input  logic        m_axi_d_arready,
    output logic [63:0] m_axi_d_araddr,
    output logic [2:0]  m_axi_d_arprot,
    input  logic        m_axi_d_rvalid,
    output logic        m_axi_d_rready,
    input  logic [63:0] m_axi_d_rdata,
    input  logic [1:0]  m_axi_d_rresp
);

// IF -> ID
logic [31:0] if_ins;
logic [63:0] if_pc;
logic        if_valid;
logic        if_rvc;

// Pipeline registers
id_ex_t  id_ex;
ex_mem_t ex_mem;
mem_wb_t mem_wb;

// EX -> IF redirect
logic        redirect;
logic [63:0] redirect_pc;

// Branch prediction
bp_info_t    if_bp;
bp_update_t  bp_upd;

// WB -> reg file
logic        wb_write;
logic [4:0]  wb_rd;
logic [63:0] wb_data;

// ID -> hazard unit
logic [4:0]  id_rs1;
logic [4:0]  id_rs2;
logic        id_uses_rs1;
logic        id_uses_rs2;

// Hazards
logic        stall;          // load-use
logic        mem_stall;      // waiting for the data bus
fwd_sel_t    fwd_a;
fwd_sel_t    fwd_b;
logic [63:0] ex_mem_result;
logic        if_fault;

// Faults
logic        take_fault;     // instruction in MEM faults this cycle
logic [3:0]  mem_fault_cause;
logic        kill;           // flush everything younger, stop fetching

assign kill = take_fault || halted;

always_ff @(posedge clk) begin
    if (rst) begin
        halted      <= 1'b0;
        fault_valid <= 1'b0;
        fault_pc    <= 64'd0;
        fault_cause <= 4'd0;
    end else if (take_fault && !halted) begin
        halted      <= 1'b1;
        fault_valid <= 1'b1;
        fault_pc    <= ex_mem.pc;
        fault_cause <= mem_fault_cause;
    end
end

hazard_unit u_hazard (
    .id_valid    (if_valid),
    .id_rs1      (id_rs1),
    .id_rs2      (id_rs2),
    .id_uses_rs1 (id_uses_rs1),
    .id_uses_rs2 (id_uses_rs2),
    .id_ex       (id_ex),
    .ex_mem      (ex_mem),
    .mem_wb      (mem_wb),
    .stall       (stall),
    .fwd_a       (fwd_a),
    .fwd_b       (fwd_b)
);

// Value the instruction in MEM will write back (loads are excluded by the
// hazard unit, their data is forwarded one cycle later from MEM/WB)
assign ex_mem_result = (ex_mem.ctrl.wb_sel == WB_PC4) ? ex_mem.pc_seq : ex_mem.alu_result;

if_stage #(
    .BP_ENABLE  (BP_ENABLE),
    .USE_GSHARE (USE_GSHARE),
    .ENABLE_RAS (ENABLE_RAS)
) u_if (
    .clk         (clk),
    .rst         (rst),
    .stall       (stall || mem_stall),
    .kill        (kill),
    .redirect_pc (redirect_pc),
    .redirect    (redirect),
    .m_arvalid   (m_axi_i_arvalid),
    .m_arready   (m_axi_i_arready),
    .m_araddr    (m_axi_i_araddr),
    .m_arprot    (m_axi_i_arprot),
    .m_rvalid    (m_axi_i_rvalid),
    .m_rready    (m_axi_i_rready),
    .m_rdata     (m_axi_i_rdata),
    .m_rresp     (m_axi_i_rresp),
    .if_id       (if_ins),
    .if_valid    (if_valid),
    .if_rvc      (if_rvc),
    .if_fault    (if_fault),
    .pc          (if_pc),
    .if_bp       (if_bp),
    .bp_upd      (bp_upd)
);

id_stage u_id (
    .clk           (clk),
    .rst           (rst),
    .flush         (redirect),
    .stall         (stall),
    .hold          (mem_stall),
    .kill          (kill),
    .ins           (if_ins),
    .pc            (if_pc),
    .valid         (if_valid),
    .rvc           (if_rvc),
    .fetch_fault   (if_fault),
    .bp            (if_bp),
    .wb_write      (wb_write),
    .wb_rd         (wb_rd),
    .wb_data       (wb_data),
    .id_rs1        (id_rs1),
    .id_rs2        (id_rs2),
    .id_uses_rs1   (id_uses_rs1),
    .id_uses_rs2   (id_uses_rs2),
    .id_ex         (id_ex)
);

ex_stage u_ex (
    .clk           (clk),
    .rst           (rst),
    .id_ex         (id_ex),
    .hold          (mem_stall),
    .kill          (kill),
    .fwd_a         (fwd_a),
    .fwd_b         (fwd_b),
    .ex_mem_result (ex_mem_result),
    .wb_result     (wb_data),
    .redirect      (redirect),
    .redirect_pc   (redirect_pc),
    .bp_upd        (bp_upd),
    .ex_mem        (ex_mem)
);

mem_stage u_mem (
    .clk       (clk),
    .rst       (rst),
    .ex_mem    (ex_mem),
    .mem_wb    (mem_wb),
    .mem_stall (mem_stall),
    .take_fault  (take_fault),
    .fault_cause (mem_fault_cause),
    .m_awvalid (m_axi_d_awvalid),
    .m_awready (m_axi_d_awready),
    .m_awaddr  (m_axi_d_awaddr),
    .m_awprot  (m_axi_d_awprot),
    .m_wvalid  (m_axi_d_wvalid),
    .m_wready  (m_axi_d_wready),
    .m_wdata   (m_axi_d_wdata),
    .m_wstrb   (m_axi_d_wstrb),
    .m_bvalid  (m_axi_d_bvalid),
    .m_bready  (m_axi_d_bready),
    .m_bresp   (m_axi_d_bresp),
    .m_arvalid (m_axi_d_arvalid),
    .m_arready (m_axi_d_arready),
    .m_araddr  (m_axi_d_araddr),
    .m_arprot  (m_axi_d_arprot),
    .m_rvalid  (m_axi_d_rvalid),
    .m_rready  (m_axi_d_rready),
    .m_rdata   (m_axi_d_rdata),
    .m_rresp   (m_axi_d_rresp)
);

wb_stage u_wb (
    .mem_wb    (mem_wb),
    .reg_write (wb_write),
    .rd        (wb_rd),
    .rd_data   (wb_data)
);

endmodule
