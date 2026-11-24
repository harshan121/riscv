// Hazard detection and forwarding control.
//
// Data hazards (RAW) by distance between producer and consumer:
//   1  producer in MEM, consumer in EX -> forward EX/MEM
//      (if the producer is a load its data isn't ready yet -> load-use stall)
//   2  producer in WB,  consumer in EX -> forward MEM/WB
//   3  producer in WB,  consumer in ID -> register file write-through
//
// Load-use: a load in EX whose rd is read by the instruction in ID.
//   Stall IF and IF/ID for one cycle and put a bubble into ID/EX; the value
//   is then forwarded from MEM/WB.
//
// Control hazards are handled in EX (redirect flushes IF/ID and ID/EX).
module hazard_unit
    import riscv_pkg::*;
(
    // Instruction currently in ID
    input  logic       id_valid,
    input  logic [4:0] id_rs1,
    input  logic [4:0] id_rs2,
    input  logic       id_uses_rs1,
    input  logic       id_uses_rs2,

    // Pipeline registers
    input  id_ex_t     id_ex,
    input  ex_mem_t    ex_mem,
    input  mem_wb_t    mem_wb,

    output logic       stall,
    output fwd_sel_t   fwd_a,      // EX operand rs1
    output fwd_sel_t   fwd_b       // EX operand rs2 (also store data)
);

// ctrl.reg_write is already cleared for rd == x0, so x0 is never forwarded
logic ex_mem_writes;
logic mem_wb_writes;

assign ex_mem_writes = ex_mem.valid && ex_mem.ctrl.reg_write && !ex_mem.ctrl.mem_read;
assign mem_wb_writes = mem_wb.valid && mem_wb.ctrl.reg_write;

// ----------------------------------------------------------------------
// Forwarding (the newest value, EX/MEM, has priority)
// ----------------------------------------------------------------------
always_comb begin
    fwd_a = FWD_NONE;
    if      (ex_mem_writes && ex_mem.rd == id_ex.rs1) fwd_a = FWD_EX_MEM;
    else if (mem_wb_writes && mem_wb.rd == id_ex.rs1) fwd_a = FWD_MEM_WB;

    fwd_b = FWD_NONE;
    if      (ex_mem_writes && ex_mem.rd == id_ex.rs2) fwd_b = FWD_EX_MEM;
    else if (mem_wb_writes && mem_wb.rd == id_ex.rs2) fwd_b = FWD_MEM_WB;
end

// ----------------------------------------------------------------------
// Load-use stall
// ----------------------------------------------------------------------
assign stall = id_valid &&
               id_ex.valid && id_ex.ctrl.mem_read && id_ex.ctrl.reg_write &&
               ((id_uses_rs1 && id_rs1 == id_ex.rd) ||
                (id_uses_rs2 && id_rs2 == id_ex.rd));

endmodule
