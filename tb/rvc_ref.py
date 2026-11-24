#!/usr/bin/env python3
"""Independent RV64C reference expander.

Writes one line per 16-bit encoding with c[1:0] != 0b11:
    <16-bit hex> <expanded 32-bit hex>
Illegal / reserved / floating-point forms expand to 00000000.
Immediates are assembled bit-by-bit from the spec's scramble tables and
then re-encoded with ordinary 32-bit assemblers, so this shares no code
or structure with rtl/if/rvc_expander.sv.
"""
import sys


def bit(x, i):
    return (x >> i) & 1


def gather(c, layout):
    """layout: list of (imm_bit, c_bit) pairs."""
    v = 0
    for ib, cb in layout:
        v |= bit(c, cb) << ib
    return v


def sext(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def m(v, bits):
    return v & ((1 << bits) - 1)


# ---- 32-bit assemblers ----------------------------------------------
def I(op, rd, f3, rs1, imm):       return m(imm, 12) << 20 | rs1 << 15 | f3 << 12 | rd << 7 | op
def S(op, f3, rs1, rs2, imm):
    imm = m(imm, 12)
    return (imm >> 5) << 25 | rs2 << 20 | rs1 << 15 | f3 << 12 | (imm & 31) << 7 | op
def R(op, rd, f3, rs1, rs2, f7):   return f7 << 25 | rs2 << 20 | rs1 << 15 | f3 << 12 | rd << 7 | op
def U(op, rd, imm20):              return m(imm20, 20) << 12 | rd << 7 | op
def B(f3, rs1, rs2, imm):
    imm = m(imm, 13)
    return (bit(imm, 12) << 31 | ((imm >> 5) & 0x3f) << 25 | rs2 << 20 | rs1 << 15 | f3 << 12
            | ((imm >> 1) & 0xf) << 8 | bit(imm, 11) << 7 | 0x63)
def J(rd, imm):
    imm = m(imm, 21)
    return (bit(imm, 20) << 31 | ((imm >> 1) & 0x3ff) << 21 | bit(imm, 11) << 20
            | ((imm >> 12) & 0xff) << 12 | rd << 7 | 0x6f)


OP_IMM, OP_IMM32, LOAD, STORE, OP, OP32, LUI, JALR = 0x13, 0x1b, 0x03, 0x23, 0x33, 0x3b, 0x37, 0x67

# Immediate scramble tables: (imm bit, instruction bit)
CIW_ADDI4SPN = [(5, 12), (4, 11), (9, 10), (8, 9), (7, 8), (6, 7), (2, 6), (3, 5)]
CL_W  = [(5, 12), (4, 11), (3, 10), (2, 6), (6, 5)]
CL_D  = [(5, 12), (4, 11), (3, 10), (7, 6), (6, 5)]
CI6   = [(5, 12), (4, 6), (3, 5), (2, 4), (1, 3), (0, 2)]
ADDI16SP = [(9, 12), (4, 6), (6, 5), (8, 4), (7, 3), (5, 2)]
CJ    = [(11, 12), (4, 11), (9, 10), (8, 9), (10, 8), (6, 7), (7, 6), (3, 5), (2, 4), (1, 3), (5, 2)]
CB    = [(8, 12), (4, 11), (3, 10), (7, 6), (6, 5), (2, 4), (1, 3), (5, 2)]
LWSP  = [(5, 12), (4, 6), (3, 5), (2, 4), (7, 3), (6, 2)]
LDSP  = [(5, 12), (4, 6), (3, 5), (8, 4), (7, 3), (6, 2)]
SWSP  = [(5, 12), (4, 11), (3, 10), (2, 9), (7, 8), (6, 7)]
SDSP  = [(5, 12), (4, 11), (3, 10), (8, 9), (7, 8), (6, 7)]


def expand(c):
    q, f3 = c & 3, (c >> 13) & 7
    rd = (c >> 7) & 31
    rs2 = (c >> 2) & 31
    rdp = 8 + ((c >> 2) & 7)
    rs1p = 8 + ((c >> 7) & 7)
    ci = gather(c, CI6)

    if q == 0:
        if f3 == 0:
            u = gather(c, CIW_ADDI4SPN)
            return I(OP_IMM, rdp, 0, 2, u) if u else 0
        if f3 == 2: return I(LOAD, rdp, 2, rs1p, gather(c, CL_W))
        if f3 == 3: return I(LOAD, rdp, 3, rs1p, gather(c, CL_D))
        if f3 == 6: return S(STORE, 2, rs1p, rdp, gather(c, CL_W))
        if f3 == 7: return S(STORE, 3, rs1p, rdp, gather(c, CL_D))
        return 0
    if q == 1:
        if f3 == 0: return I(OP_IMM, rd, 0, rd, sext(ci, 6))
        if f3 == 1: return I(OP_IMM32, rd, 0, rd, sext(ci, 6)) if rd else 0
        if f3 == 2: return I(OP_IMM, rd, 0, 0, sext(ci, 6))
        if f3 == 3:
            if rd == 2:
                v = gather(c, ADDI16SP)
                return I(OP_IMM, 2, 0, 2, sext(v, 10)) if v else 0
            return U(LUI, rd, sext(ci, 6)) if ci else 0
        if f3 == 4:
            sub = (c >> 10) & 3
            if sub == 0: return I(OP_IMM, rs1p, 5, rs1p, ci)
            if sub == 1: return I(OP_IMM, rs1p, 5, rs1p, ci | 0x400)
            if sub == 2: return I(OP_IMM, rs1p, 7, rs1p, sext(ci, 6))
            k = (bit(c, 12) << 2) | ((c >> 5) & 3)
            table = {0: (OP, 0, 0x20), 1: (OP, 4, 0), 2: (OP, 6, 0), 3: (OP, 7, 0),
                     4: (OP32, 0, 0x20), 5: (OP32, 0, 0)}
            if k not in table: return 0
            op, fn3, f7 = table[k]
            return R(op, rs1p, fn3, rs1p, rdp, f7)
        if f3 == 5: return J(0, sext(gather(c, CJ), 12))
        if f3 == 6: return B(0, rs1p, 0, sext(gather(c, CB), 9))
        if f3 == 7: return B(1, rs1p, 0, sext(gather(c, CB), 9))
    if q == 2:
        if f3 == 0: return I(OP_IMM, rd, 1, rd, ci)
        if f3 == 2: return I(LOAD, rd, 2, 2, gather(c, LWSP)) if rd else 0
        if f3 == 3: return I(LOAD, rd, 3, 2, gather(c, LDSP)) if rd else 0
        if f3 == 4:
            if not bit(c, 12):
                if rs2 == 0: return I(JALR, 0, 0, rd, 0) if rd else 0
                return R(OP, rd, 0, 0, rs2, 0)
            if rs2 == 0:
                return 0x00100073 if rd == 0 else I(JALR, 1, 0, rd, 0)
            return R(OP, rd, 0, rd, rs2, 0)
        if f3 == 6: return S(STORE, 2, 2, rs2, gather(c, SWSP))
        if f3 == 7: return S(STORE, 3, 2, rs2, gather(c, SDSP))
        return 0
    return 0


if __name__ == "__main__":
    out = open(sys.argv[1], "w") if len(sys.argv) > 1 else sys.stdout
    for c in range(1 << 16):
        if c & 3 != 3:
            out.write(f"{c:04x} {expand(c):08x}\n")
