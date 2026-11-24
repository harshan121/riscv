// RV64I ALU
//   alu_op = {funct7[5], funct3}  (see riscv_pkg ALU_*)
//   word   = *W instruction: operate on the low 32 bits, sign-extend result
module alu
    import riscv_pkg::*;
(
    input  logic [63:0] a,
    input  logic [63:0] b,
    input  logic [3:0]  alu_op,
    input  logic        word,
    output logic [63:0] result
);

logic [63:0] add_sub_result;
logic [63:0] and_result;
logic [63:0] or_result;
logic [63:0] xor_result;
logic [63:0] shift_result;
logic [63:0] shift_in;
logic [5:0]  shamt;
logic        cout;
logic        sub;
logic        slt;
logic        sltu;
logic [63:0] raw;

// SUB, SLT and SLTU all need a - b
assign sub = (alu_op == ALU_SUB) || (alu_op == ALU_SLT) || (alu_op == ALU_SLTU);

add_sub alu_add_sub (
    .a      (a),
    .b      (b),
    .sub    (sub),
    .alu_op (alu_op[2:0]),
    .sum    (add_sub_result),
    .cout   (cout)
);

// a - b = a + ~b + 1: no carry out  <=>  a < b (unsigned)
assign sltu = ~cout;
// Signed: if signs differ, a < b iff a is negative; otherwise same as unsigned
assign slt  = (a[63] ^ b[63]) ? a[63] : sltu;

and_gate alu_and (.a(a), .b(b), .result(and_result));
or_gate  alu_or  (.a(a), .b(b), .result(or_result));
xor_gate alu_xor (.a(a), .b(b), .result(xor_result));

// Word shifts: 5-bit shamt, operand is the low 32 bits (zero- or sign-extended)
always_comb begin
    if (word) begin
        shamt    = {1'b0, b[4:0]};
        shift_in = (alu_op == ALU_SRA) ? {{32{a[31]}}, a[31:0]} : {32'b0, a[31:0]};
    end else begin
        shamt    = b[5:0];
        shift_in = a;
    end
end

barrel_shift alu_barrel_shift (
    .a      (shift_in),
    .b      (shamt),
    .alu_op (alu_op),
    .y      (shift_result)
);

always_comb begin
    case (alu_op)
        ALU_ADD, ALU_SUB:          raw = add_sub_result;
        ALU_AND:                   raw = and_result;
        ALU_OR:                    raw = or_result;
        ALU_XOR:                   raw = xor_result;
        ALU_SLT:                   raw = {63'b0, slt};
        ALU_SLTU:                  raw = {63'b0, sltu};
        ALU_SLL, ALU_SRL, ALU_SRA: raw = shift_result;
        default:                   raw = 64'b0;
    endcase

    result = word ? {{32{raw[31]}}, raw[31:0]} : raw;
end

endmodule
