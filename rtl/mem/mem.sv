// Memory stage: AXI4-Lite data master (64-bit data bus).
//
//   load : AR (8-byte aligned address) -> R, then pick / extend the bytes
//   store: AW + W (shifted data, byte strobes) -> wait for B
//
// While a load or store waits for its response the stage raises mem_stall,
// which freezes IF/ID, ID/EX and EX/MEM; MEM/WB receives bubbles. Waiting
// for B keeps every later load ordered after the store.
//
// Faults are taken here, in program order (everything older has already
// left MEM, everything younger is flushed by the core):
//   - a fault carried from IF / ID (illegal, ecall, ebreak, fetch error)
//   - a misaligned load / store: detected before any AXI request is raised
//   - an AXI error response (RRESP / BRESP != OKAY): the transaction has
//     completed, so nothing is left outstanding on the bus
// A faulting instruction writes no register (MEM/WB gets a bubble).
module mem_stage
    import riscv_pkg::*;
(
    input  logic        clk,
    input  logic        rst,
    input  ex_mem_t     ex_mem,
    output mem_wb_t     mem_wb,
    output logic        mem_stall,
    output logic        take_fault,     // the instruction in MEM faults this cycle
    output logic [3:0]  fault_cause,

    // AXI4-Lite master
    output logic        m_awvalid,
    input  logic        m_awready,
    output logic [63:0] m_awaddr,
    output logic [2:0]  m_awprot,
    output logic        m_wvalid,
    input  logic        m_wready,
    output logic [63:0] m_wdata,
    output logic [7:0]  m_wstrb,
    input  logic        m_bvalid,
    output logic        m_bready,
    input  logic [1:0]  m_bresp,
    output logic        m_arvalid,
    input  logic        m_arready,
    output logic [63:0] m_araddr,
    output logic [2:0]  m_arprot,
    input  logic        m_rvalid,
    output logic        m_rready,
    input  logic [63:0] m_rdata,
    input  logic [1:0]  m_rresp
);

logic        is_load, is_store;
logic        misaligned;
logic        access_err;
logic        ar_done, aw_done, w_done;
logic        done;
logic [2:0]  offset;
logic [5:0]  bit_off;
logic [7:0]  byte_en;
logic [63:0] rword;
logic [63:0] load_data;

assign offset   = ex_mem.alu_result[2:0];

// Natural alignment required: halfword even, word 4-byte, doubleword 8-byte
always_comb begin
    case (ex_mem.funct3[1:0])
        2'b00:   misaligned = 1'b0;
        2'b01:   misaligned = offset[0];
        2'b10:   misaligned = |offset[1:0];
        default: misaligned = |offset;
    endcase
end

// Only well-formed accesses go to the bus (faulted instructions have a nop
// ctrl, so mem_read / mem_write are already clear for them)
assign is_load  = ex_mem.valid && ex_mem.ctrl.mem_read  && !misaligned;
assign is_store = ex_mem.valid && ex_mem.ctrl.mem_write && !misaligned;
assign bit_off  = {offset, 3'b000};

// ----------------------------------------------------------------------
// Request channels (payload comes from EX/MEM, which is frozen while
// waiting, so it stays stable until the handshake as AXI requires)
// ----------------------------------------------------------------------
always_comb begin
    case (ex_mem.funct3[1:0])
        2'b00:   byte_en = 8'b0000_0001;
        2'b01:   byte_en = 8'b0000_0011;
        2'b10:   byte_en = 8'b0000_1111;
        default: byte_en = 8'b1111_1111;
    endcase
    byte_en = byte_en << offset;
end

assign m_araddr  = {ex_mem.alu_result[63:3], 3'b000};
assign m_arprot  = 3'b000;
assign m_arvalid = !rst && is_load && !ar_done;     // AXI: VALID low in reset
assign m_rready  = 1'b1;

assign m_awaddr  = {ex_mem.alu_result[63:3], 3'b000};
assign m_awprot  = 3'b000;
assign m_awvalid = !rst && is_store && !aw_done;
assign m_wdata   = ex_mem.store_data << bit_off;
assign m_wstrb   = byte_en;
assign m_wvalid  = !rst && is_store && !w_done;
assign m_bready  = 1'b1;

// The response can only come after the request handshake
assign done      = is_load ? m_rvalid : is_store ? m_bvalid : 1'b1;
assign mem_stall = (is_load || is_store) && !done;

// ----------------------------------------------------------------------
// Faults
// ----------------------------------------------------------------------
assign access_err = (is_load  && m_rvalid && m_rresp != 2'b00) ||
                    (is_store && m_bvalid && m_bresp != 2'b00);

always_comb begin
    take_fault  = ex_mem.valid;
    fault_cause = 4'd0;
    if      (ex_mem.fault)                                      fault_cause = ex_mem.cause;
    else if (misaligned && ex_mem.ctrl.mem_read)                fault_cause = CAUSE_LOAD_MISALIGN;
    else if (misaligned && ex_mem.ctrl.mem_write)               fault_cause = CAUSE_STORE_MISALIGN;
    else if (access_err && is_load)                             fault_cause = CAUSE_LOAD_ACCESS;
    else if (access_err && is_store)                            fault_cause = CAUSE_STORE_ACCESS;
    else                                                        take_fault  = 1'b0;
end

always_ff @(posedge clk) begin
    if (rst) begin
        ar_done   <= 1'b0;
        aw_done   <= 1'b0;
        w_done    <= 1'b0;
    end else begin
        if (done) begin
            ar_done <= 1'b0;
            aw_done <= 1'b0;
            w_done  <= 1'b0;
        end else begin
            if (m_arvalid && m_arready) ar_done <= 1'b1;
            if (m_awvalid && m_awready) aw_done <= 1'b1;
            if (m_wvalid  && m_wready)  w_done  <= 1'b1;
        end
    end
end

// ----------------------------------------------------------------------
// Load data: select the addressed bytes and extend
// ----------------------------------------------------------------------
always_comb begin
    rword = m_rdata >> bit_off;

    case (ex_mem.funct3)
        F3_B:    load_data = {{56{rword[7]}},  rword[7:0]};
        F3_H:    load_data = {{48{rword[15]}}, rword[15:0]};
        F3_W:    load_data = {{32{rword[31]}}, rword[31:0]};
        F3_D:    load_data = rword;
        F3_BU:   load_data = {56'b0, rword[7:0]};
        F3_HU:   load_data = {48'b0, rword[15:0]};
        F3_WU:   load_data = {32'b0, rword[31:0]};
        default: load_data = 64'b0;
    endcase
end

// ----------------------------------------------------------------------
// MEM/WB pipeline register
// ----------------------------------------------------------------------
always_ff @(posedge clk) begin
    if (rst || !ex_mem.valid || mem_stall || take_fault) begin
        mem_wb      <= '0;
        mem_wb.ctrl <= CTRL_NOP;
    end else begin
        mem_wb.valid      <= 1'b1;
        mem_wb.pc_seq     <= ex_mem.pc_seq;
        mem_wb.alu_result <= ex_mem.alu_result;
        mem_wb.mem_data   <= load_data;
        mem_wb.rd         <= ex_mem.rd;
        mem_wb.ctrl       <= ex_mem.ctrl;
    end
end

endmodule
