// Tiny RV64IC assembler + helpers shared by the testbenches.
// Expects the core instance `dut`, the instruction memory model `imem`
// (tb_soc.svh) and a `PAD` parameter (NOPs emitted after every emit()).

function automatic logic [31:0] r_t(input logic [6:0] f7, input int rs2, rs1,
                                    input logic [2:0] f3, input int rd, input logic [6:0] op);
    return {f7, 5'(rs2), 5'(rs1), f3, 5'(rd), op};
endfunction

function automatic logic [31:0] i_t(input int imm, rs1, input logic [2:0] f3,
                                    input int rd, input logic [6:0] op);
    return {12'(imm), 5'(rs1), f3, 5'(rd), op};
endfunction

function automatic logic [31:0] s_t(input int imm, rs2, rs1, input logic [2:0] f3);
    logic [11:0] i = 12'(imm);
    return {i[11:5], 5'(rs2), 5'(rs1), f3, i[4:0], OPC_STORE};
endfunction

function automatic logic [31:0] b_t(input int imm, rs2, rs1, input logic [2:0] f3);
    logic [12:0] i = 13'(imm);
    return {i[12], i[10:5], 5'(rs2), 5'(rs1), f3, i[4:1], i[11], OPC_BRANCH};
endfunction

function automatic logic [31:0] u_t(input int imm20, rd, input logic [6:0] op);
    return {20'(imm20), 5'(rd), op};
endfunction

function automatic logic [31:0] j_t(input int imm, rd);
    logic [20:0] i = 21'(imm);
    return {i[20], i[10:1], i[11], i[19:12], 5'(rd), OPC_JAL};
endfunction

// ---- RV64C encoders (prime registers x8-x15 are passed as 8..15) ------
function automatic logic [2:0]  p(input int r);  return 3'(r - 8); endfunction
function automatic logic [4:0]  r5(input int r); return 5'(r);     endfunction

function automatic logic [15:0] c_addi (input int rd, imm);  logic [5:0] i = 6'(imm); return {3'b000, i[5], r5(rd), i[4:0], 2'b01}; endfunction
function automatic logic [15:0] c_addiw(input int rd, imm);  logic [5:0] i = 6'(imm); return {3'b001, i[5], r5(rd), i[4:0], 2'b01}; endfunction
function automatic logic [15:0] c_li   (input int rd, imm);  logic [5:0] i = 6'(imm); return {3'b010, i[5], r5(rd), i[4:0], 2'b01}; endfunction
function automatic logic [15:0] c_lui  (input int rd, imm);  logic [5:0] i = 6'(imm); return {3'b011, i[5], r5(rd), i[4:0], 2'b01}; endfunction
function automatic logic [15:0] c_addi16sp(input int imm);
    logic [9:0] i = 10'(imm); return {3'b011, i[9], 5'd2, i[4], i[6], i[8:7], i[5], 2'b01};
endfunction
function automatic logic [15:0] c_addi4spn(input int rd, imm);
    logic [9:0] i = 10'(imm); return {3'b000, i[5:4], i[9:6], i[2], i[3], p(rd), 2'b00};
endfunction
function automatic logic [15:0] c_srli(input int rd, sh); logic [5:0] i = 6'(sh);  return {3'b100, i[5], 2'b00, p(rd), i[4:0], 2'b01}; endfunction
function automatic logic [15:0] c_srai(input int rd, sh); logic [5:0] i = 6'(sh);  return {3'b100, i[5], 2'b01, p(rd), i[4:0], 2'b01}; endfunction
function automatic logic [15:0] c_andi(input int rd, imm); logic [5:0] i = 6'(imm); return {3'b100, i[5], 2'b10, p(rd), i[4:0], 2'b01}; endfunction
function automatic logic [15:0] c_ca  (input logic w, input logic [1:0] f2, input int rd, rs2);
    return {3'b100, w, 2'b11, p(rd), f2, p(rs2), 2'b01};
endfunction
function automatic logic [15:0] c_sub (input int rd, rs2); return c_ca(1'b0, 2'b00, rd, rs2); endfunction
function automatic logic [15:0] c_xor (input int rd, rs2); return c_ca(1'b0, 2'b01, rd, rs2); endfunction
function automatic logic [15:0] c_or  (input int rd, rs2); return c_ca(1'b0, 2'b10, rd, rs2); endfunction
function automatic logic [15:0] c_and (input int rd, rs2); return c_ca(1'b0, 2'b11, rd, rs2); endfunction
function automatic logic [15:0] c_subw(input int rd, rs2); return c_ca(1'b1, 2'b00, rd, rs2); endfunction
function automatic logic [15:0] c_addw(input int rd, rs2); return c_ca(1'b1, 2'b01, rd, rs2); endfunction
function automatic logic [15:0] c_j(input int off);
    logic [11:0] o = 12'(off); return {3'b101, o[11], o[4], o[9:8], o[10], o[6], o[7], o[3:1], o[5], 2'b01};
endfunction
function automatic logic [15:0] c_bz(input logic ne, input int rs1, off);
    logic [8:0] o = 9'(off); return {2'b11, ne, o[8], o[4:3], p(rs1), o[7:6], o[2:1], o[5], 2'b01};
endfunction
function automatic logic [15:0] c_beqz(input int rs1, off); return c_bz(1'b0, rs1, off); endfunction
function automatic logic [15:0] c_bnez(input int rs1, off); return c_bz(1'b1, rs1, off); endfunction
function automatic logic [15:0] c_slli(input int rd, sh); logic [5:0] i = 6'(sh); return {3'b000, i[5], r5(rd), i[4:0], 2'b10}; endfunction
function automatic logic [15:0] c_lwsp(input int rd, off); logic [7:0] o = 8'(off); return {3'b010, o[5], r5(rd), o[4:2], o[7:6], 2'b10}; endfunction
function automatic logic [15:0] c_ldsp(input int rd, off); logic [8:0] o = 9'(off); return {3'b011, o[5], r5(rd), o[4:3], o[8:6], 2'b10}; endfunction
function automatic logic [15:0] c_swsp(input int rs2, off); logic [7:0] o = 8'(off); return {3'b110, o[5:2], o[7:6], r5(rs2), 2'b10}; endfunction
function automatic logic [15:0] c_sdsp(input int rs2, off); logic [8:0] o = 9'(off); return {3'b111, o[5:3], o[8:6], r5(rs2), 2'b10}; endfunction
function automatic logic [15:0] c_jr  (input int rs1);      return {4'b1000, r5(rs1), 5'd0,     2'b10}; endfunction
function automatic logic [15:0] c_mv  (input int rd, rs2);  return {4'b1000, r5(rd),  r5(rs2),  2'b10}; endfunction
function automatic logic [15:0] c_jalr(input int rs1);      return {4'b1001, r5(rs1), 5'd0,     2'b10}; endfunction
function automatic logic [15:0] c_add (input int rd, rs2);  return {4'b1001, r5(rd),  r5(rs2),  2'b10}; endfunction
function automatic logic [15:0] c_lw(input int rd, rs1, off); logic [6:0] o = 7'(off); return {3'b010, o[5:3], p(rs1), o[2], o[6], p(rd), 2'b00}; endfunction
function automatic logic [15:0] c_ld(input int rd, rs1, off); logic [7:0] o = 8'(off); return {3'b011, o[5:3], p(rs1), o[7:6], p(rd), 2'b00}; endfunction
function automatic logic [15:0] c_sw(input int rs2, rs1, off); logic [6:0] o = 7'(off); return {3'b110, o[5:3], p(rs1), o[2], o[6], p(rs2), 2'b00}; endfunction
function automatic logic [15:0] c_sd(input int rs2, rs1, off); logic [7:0] o = 8'(off); return {3'b111, o[5:3], p(rs1), o[7:6], p(rs2), 2'b00}; endfunction
localparam logic [15:0] C_EBREAK = 16'h9002;

localparam int SLOT = (PAD + 1) * 4;   // bytes per emit() of a 32-bit instruction

int pc_addr = 0;                        // byte address of the next instruction

task automatic put32(input int addr, input logic [31:0] ins);
    for (int i = 0; i < 4; i++) imem.mem[addr + i] = ins[i*8 +: 8];
endtask

task automatic put16(input int addr, input logic [15:0] c);
    imem.mem[addr]     = c[7:0];
    imem.mem[addr + 1] = c[15:8];
endtask

// 32-bit instruction (+ PAD nops)
task automatic emit(input logic [31:0] ins);
    put32(pc_addr, ins);
    pc_addr += 4;
    for (int i = 0; i < PAD; i++) begin
        put32(pc_addr, INS_NOP);
        pc_addr += 4;
    end
endtask

// 16-bit compressed instruction (no padding)
task automatic emitc(input logic [15:0] c);
    put16(pc_addr, c);
    pc_addr += 2;
endtask

int errors = 0;

task automatic check(input int r, input logic [63:0] exp, input string what);
    logic [63:0] got = dut.u_id.u_reg_file.regs[r];
    if (got !== exp) begin
        $display("FAIL x%0d (%s): got %h expected %h", r, what, got, exp);
        errors++;
    end else begin
        $display("ok   x%0d (%s) = %h", r, what, got);
    end
endtask

// Release reset and run until the core halts; a normal program ends with
// ebreak (fault_cause = CAUSE_BREAKPOINT)
int cycles = 0;

task automatic run_to_halt(input int max_cycles);
    logic halted;
    repeat (3) @(posedge clk);
    rst = 0;
    while (!halt && cycles < max_cycles) begin
        @(posedge clk);
        cycles++;
    end
    halted = halt;
    @(posedge clk);   // let the last WB write land
    if (!halted) begin
        $display("FAIL: timeout, core did not halt");
        errors++;
    end else if (fault_cause != CAUSE_BREAKPOINT) begin
        $display("FAIL: unexpected fault cause %0d at pc %h", fault_cause, fault_pc);
        errors++;
    end
endtask

task automatic finish();
    $display("%0d cycles, %0d error(s)", cycles, errors);
    if (errors == 0) $display("PASS");
    else             $display("FAIL");
    $finish;
endtask
