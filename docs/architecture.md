# Kreacher v1.0.0-baseline: Processor Architecture

Kreacher is a single-issue, in-order, five-stage RV64IC processor with
AXI4-Lite instruction and data ports. Version 1.0.0-baseline is intended to
be a stable reference point for later processor and accelerator research.
It is deliberately conventional: no caches, no privileged architecture, no
out-of-order execution.

This document describes the RTL as it is in `rtl/`. Where behaviour is
limited or unverified, Section 12 says so explicitly.

---

## Contents

1. [Overview](#1-overview)
2. [Top level: `core`](#2-top-level-core)
3. [Pipeline](#3-pipeline)
4. [Pipeline registers and stage interfaces](#4-pipeline-registers-and-stage-interfaces)
5. [Instruction fetch, alignment and compressed instructions](#5-instruction-fetch-alignment-and-compressed-instructions)
6. [Branch prediction](#6-branch-prediction)
7. [Hazards, stalls, flushes and forwarding](#7-hazards-stalls-flushes-and-forwarding)
8. [Faults and halting](#8-faults-and-halting)
9. [AXI4-Lite interfaces](#9-axi4-lite-interfaces)
10. [Module reference](#10-module-reference)
11. [Supported instructions](#11-supported-instructions)
12. [Known limitations](#12-known-limitations)
13. [Build, test and toolchain](#13-build-test-and-toolchain)
14. [Connecting an MMIO accelerator](#14-connecting-an-mmio-accelerator)

---

## 1. Overview

| Property | Value |
|---|---|
| ISA | RV64I + RV64C (integer subset), FENCE as a no-op |
| Pipeline | 5 stages: IF, ID, EX, MEM, WB; single issue, in order |
| Instruction port | AXI4-Lite master, 32-bit data, read channels only, up to 4 reads outstanding |
| Data port | AXI4-Lite master, 64-bit data, one transaction at a time |
| Branch prediction | 64-entry BTB, 64 two-bit counters (bimodal or gshare, 6-bit history), 8-entry return address stack; compile-time selectable, or static not-taken |
| Forwarding | EX/MEM -> EX, MEM/WB -> EX, register-file write-through (WB -> ID) |
| Faults | illegal instruction, ecall, ebreak, misaligned load/store, AXI error responses; precise; core halts |
| Reset | synchronous, active high (`rst`) |
| Privileged architecture / CSRs / interrupts | not implemented |

```text
            +-------------------------------- core --------------------------------+
            |                                                                      |
 AXI4-Lite  |  +------+   IF/ID   +------+  ID/EX  +------+ EX/MEM +------+ MEM/WB  +------+
 instr  <---+--|  IF  |---------->|  ID  |-------->|  EX  |------->| MEM  |-------->|  WB  |
 (32b, R)   |  +------+           +------+         +------+        +------+         +------+
            |   ^   ^  BTB/PHT/RAS   ^ reg file        |  ^  ^          |   ^           |
            |   |   |                |  read     redirect |  | forward    |   |  AXI4-Lite  | reg write
            |   |   +----------------+----------------+  |  +------------+---+--> data (64b, RW)
            |   +---- bp update / redirect (EX) ------+  |                   |
            |                        ^-------------------+-------------------+-- WB write-through
            |   hazard_unit: forwarding selects, load-use stall                             |
            |   fault: taken in MEM -> halted, fault_pc, fault_cause; kill flushes IF..EX     |
            +-----------------------------------------------------------------------------+
```

---

## 2. Top level: `core`

File: `rtl/core.sv`.

### Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `BP_ENABLE` | 1 | 0: static not-taken (no prediction tables) |
| `USE_GSHARE` | 1 | 0: bimodal counters indexed by PC, 1: gshare (PC XOR global history) |
| `ENABLE_RAS` | 1 | 1: returns predicted from the return address stack |

Table sizes are package constants (`BP_BTB_BITS`, `BP_PHT_BITS`,
`BP_RAS_BITS` in `rtl/riscv_pkg.sv`).

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock |
| `rst` | in | 1 | Synchronous, active-high reset. The core starts fetching at address 0 |
| `halted` | out | 1 | Core has stopped (sticky until reset) |
| `fault_valid` | out | 1 | A fault/exception was taken (sticky). Always set together with `halted` |
| `fault_pc` | out | 64 | PC of the instruction that caused the halt |
| `fault_cause` | out | 4 | RISC-V `mcause` exception code (Section 8) |
| `m_axi_i_*` | | | Instruction port (Section 9.1) |
| `m_axi_d_*` | | | Data port (Section 9.2) |

A program ends normally by executing `ebreak` (or `c.ebreak`):
`halted = 1`, `fault_cause = 3`.

---

## 3. Pipeline

| Stage | Work | Module |
|---|---|---|
| IF | Issue AXI reads for 32-bit words at the predicted next address; split responses into 16-bit parcels; align and expand compressed instructions; IF/ID register | `if_stage`, `fetch_unit`, `rvc_expander`, `branch_predictor` |
| ID | Field decode, immediate generation, register-file read, control generation, illegal-instruction and ecall/ebreak detection; ID/EX register | `id_stage`, `ins_decode`, `imm_generator`, `reg_file` |
| EX | Forwarding muxes, ALU, branch comparison, jump-target calculation, misprediction check (redirect), predictor training; EX/MEM register | `ex_stage`, `alu` |
| MEM | AXI loads and stores, byte-lane alignment, sign/zero extension, misalignment and access-fault detection, fault taking; MEM/WB register | `mem_stage` |
| WB | Select ALU result / load data / link address; register-file write | `wb_stage` |

Cycle costs with a 1-cycle AXI slave:

| Event | Cost |
|---|---|
| Correctly predicted taken branch / jump | 0 extra cycles |
| Mispredicted branch / jump (or taken with predictor off) | 3 cycles |
| Load-use dependency (consumer immediately after a load) | 1 cycle |
| Any load or store | +1 cycle in MEM (AXI round trip); more with slower slaves |

---

## 4. Pipeline registers and stage interfaces

All types are in `rtl/riscv_pkg.sv`.

### Control bundle `ctrl_t` (generated in ID)

| Field | Meaning |
|---|---|
| `a_sel` | ALU operand A: `A_RS1`, `A_PC` (AUIPC), `A_ZERO` (LUI) |
| `b_sel` | ALU operand B: `B_RS2`, `B_IMM` |
| `alu_op[3:0]` | `{funct7[5], funct3}` encoding (`ALU_ADD`, `ALU_SUB`, `ALU_SLL`, ...) |
| `word` | `*W` instruction: 32-bit operation, result sign-extended |
| `reg_write` | Write `rd` (already cleared for `rd = x0`) |
| `mem_read`, `mem_write` | Load / store |
| `wb_sel` | `WB_ALU`, `WB_MEM`, `WB_PC4` (link = pc + 2/4) |
| `branch`, `jal`, `jalr` | Control-flow kind |

`CTRL_NOP` (all zero) is used for bubbles and for faulting instructions, so
a faulting instruction can never write a register, access memory or
redirect fetch.

### IF/ID (outputs of `if_stage`)

| Signal | Meaning |
|---|---|
| `if_valid` | Instruction present |
| `if_id[31:0]` | Instruction (compressed ones already expanded to 32 bits) |
| `pc` | Address of its first byte |
| `if_rvc` | Instruction was 16-bit |
| `if_fault` | An AXI error was returned for one of its fetch words |
| `if_bp` (`bp_info_t`) | Prediction made in IF (below) |

### `bp_info_t` (travels IF -> EX)

| Field | Meaning |
|---|---|
| `pred_taken`, `pred_target` | Predicted next PC (if `pred_taken`) |
| `pht_idx` | Direction counter used for this prediction, so EX trains the same counter |
| `ghr` | Global history before this instruction (checkpoint for recovery) |
| `ras_ptr` | Return-stack pointer before this instruction (checkpoint for recovery) |

### ID/EX (`id_ex_t`)

`valid, pc, rs1_data, rs2_data, imm, rs1, rs2, rd, funct3, rvc, fault, cause, ctrl, bp`

`rs1`/`rs2` are used by the hazard unit; `fault`/`cause` carry an IF/ID fault
to MEM.

### EX/MEM (`ex_mem_t`)

`valid, pc, pc_seq, alu_result, store_data, rd, funct3, fault, cause, ctrl`

`alu_result` is the memory address for loads/stores. `pc_seq = pc + 2/4`
is the link value. `pc` is kept for `fault_pc`.

### MEM/WB (`mem_wb_t`)

`valid, pc_seq, alu_result, mem_data, rd, ctrl`

### EX -> IF

| Signal | Meaning |
|---|---|
| `redirect`, `redirect_pc` | Misprediction: fetch restarts at `redirect_pc`; IF/ID and ID/EX are flushed |
| `bp_upd` (`bp_update_t`) | Predictor training and checkpoint recovery: `valid, end_pc, link, target, is_cond, is_call, is_ret, taken, pht_idx, recover, ghr, ras_ptr` |

---

## 5. Instruction fetch, alignment and compressed instructions

### 5.1 Fetch unit (`rtl/if/fetch_unit.sv`)

- Requests are naturally aligned 32-bit words. The address requested in a
  cycle is looked up in the branch predictor in the same cycle; the
  prediction decides the next request address.
- Up to 4 reads may be outstanding. AXI4-Lite has no IDs, so responses come
  back in request order. A 4-entry FIFO keeps each request's address and
  prediction until its response arrives.
- A redirect cannot cancel an AXI read. Outstanding requests are marked
  killed and their responses are accepted and dropped.
- Responses are split into 16-bit parcels and written into an 8-entry parcel
  queue (`parcel_t`: data, pc, fault, prediction). A request is issued only if
  `queue entries + 2 x live outstanding requests + 2 <= 8`, so the queue
  cannot overflow and `RREADY` is always 1.
- Which parcels of a word are used: from the starting half (bit 1 of a
  jump target) up to the half in which a predicted-taken branch ends.

### 5.2 Aligner (`rtl/if/if.sv`)

Each cycle, if IF/ID can accept an instruction:

| Head parcel `q0` | Action |
|---|---|
| `q0[1:0] != 2'b11` (compressed) | Expand `q0` with `rvc_expander`; pop 1 parcel |
| `q0[1:0] == 2'b11` (32-bit) and `q1` present | Instruction `{q1, q0}`; pop 2 parcels. `q1` may come from the next fetch word (32-bit instructions may start at a 2-mod-4 address) |
| `q0` came from an AXI error response | Pass on at once as a faulted instruction (contents ignored) |

The instruction's prediction is the one attached to the parcel it **ends**
in. Its PC is the address of `q0`.

### 5.3 Compressed instruction expansion (`rtl/if/rvc_expander.sv`)

Each RV64C instruction is rewritten as its 32-bit equivalent, so the rest of
the pipeline only sees 32-bit instructions plus an `rvc` flag (used for the
link value `pc + 2` and the sequential next PC).

- Supported: all RV64C integer instructions (Section 11).
- `C.FLD`, `C.FSD`, `C.FLDSP`, `C.FSDSP` (no FP unit) and reserved encodings
  expand to `32'h0`, which ID rejects as an illegal instruction.
- HINT encodings (e.g. `c.addi x0, ...`, `c.li x0, ...`) expand normally
  and write `x0`, i.e. execute as no-ops, as the specification permits.
- Verified exhaustively against an independent Python reference
  (`tb/rvc_ref.py`) for all 49 152 16-bit encodings.

---

## 6. Branch prediction

Files: `rtl/bp/`.

| Structure | Organisation |
|---|---|
| BTB (`btb.sv`) | 64 entries, direct mapped, indexed by fetch word (`pc[7:2]`), full tag. Entry: valid, tag, target, kind (`COND` / `JUMP` / `CALL` / `RET`), and which half of the word the instruction **ends** in |
| Direction (`direction_predictor.sv`) | 64 two-bit saturating counters (reset: weakly not taken). Bimodal: index `pc[7:2]`; gshare: `pc[7:2] ^ GHR` with a 6-bit global history register |
| RAS (`ras.sv`) | 8 entries, circular (overflow overwrites the oldest entry, underflow mispredicts) |

**Prediction (IF).** For a BTB hit whose end-half is at or after the fetch's
starting half:

- `COND`: taken if the counter's MSB is set; target from the BTB.
- `JUMP`, `CALL`: taken; target from the BTB. `CALL` pushes the return
  address (end of the call + 2) onto the RAS.
- `RET`: taken; target from the RAS top (or the BTB if `ENABLE_RAS = 0`).

Call/return follow the RISC-V hint convention: a call is `jal`/`jalr` with
`rd` in {x1, x5}; a return is `jalr` with `rs1` in {x1, x5} that is not a
call.

**Speculative history and RAS.** The GHR and the RAS pointer are updated
when a request is accepted, using the prediction. Every instruction carries
the values from before its fetch word (`bp_info_t.ghr`, `.ras_ptr`).

**Resolution (EX).** EX computes the actual next PC and compares it with the
predicted one (`pred_target` if predicted taken, else `pc + 2/4`). On a
mismatch it redirects fetch and restores the checkpoints, then applies the
instruction's own effect (shift its outcome into the GHR; push or pop the
RAS). Every resolved branch/jump writes the BTB; conditional branches train
the counter they were predicted with. Faulting instructions, and anything
in EX while the core is halting, do neither.

**Two compressed branches in one fetch word.** A BTB entry describes one
instruction per word, so two compressed branches in the same word share and
overwrite one entry (and one direction counter). This only affects accuracy:
a branch that is not the one in the entry is predicted not taken and
corrected in EX; if the entry describes the second branch, fetch never
skips the first one; if it describes the first and the first is not taken,
the refetch starts at the upper half, where the entry (ending at half 0) does
not apply. `tb_rvc` checks this case with branches that alternate.

**Static configuration** (`BP_ENABLE = 0`): no tables; every taken branch or
jump redirects from EX.

---

## 7. Hazards, stalls, flushes and forwarding

### 7.1 Forwarding (`rtl/hazard/hazard_unit.sv`)

| Producer -> consumer distance | Mechanism |
|---|---|
| 1 (producer in MEM, consumer in EX) | Forward EX/MEM (`alu_result` or link value) |
| 1, producer is a load | Load-use stall of 1 cycle, then forward from MEM/WB |
| 2 (producer in WB) | Forward MEM/WB (the write-back value) |
| 3 | Register-file write-through (a write and a read of the same register in one cycle returns the new value) |

The newer value (EX/MEM) has priority. `x0` is never forwarded
(`reg_write` is cleared for `rd = x0` in decode). Forwarded values feed ALU
operands, store data and branch/jalr operands. ID only reports a source
register as used if the instruction really reads it, so U/J-type
instructions after a load do not stall falsely.

### 7.2 Stall and flush signals

| Signal | Source | Effect |
|---|---|---|
| `stall` | hazard unit (load-use) | Hold IF/ID; bubble into ID/EX |
| `mem_stall` | MEM (waiting for an AXI response) | Hold IF/ID, ID/EX, EX/MEM; bubble into MEM/WB. EX keeps its forwarded operands while held, because the forwarding source retires meanwhile |
| `redirect` | EX (misprediction) | Flush IF/ID and ID/EX; restart fetch. Raised only once, when the instruction leaves EX (not while held) |
| `kill` = `take_fault` or `halted` | core | Flush IF/ID, ID/EX, EX/MEM; stop fetching |

Priority of each pipeline register update:

| Register | Priority (highest first) |
|---|---|
| IF/ID | reset, kill, redirect -> bubble; stall -> hold; instruction available -> capture; else bubble |
| ID/EX | reset, kill -> bubble; `mem_stall` -> hold; redirect, load-use, no instruction -> bubble; else capture |
| EX/MEM | reset, kill -> bubble; `mem_stall` -> hold; empty -> bubble; else capture |
| MEM/WB | reset, empty, `mem_stall`, fault -> bubble; else capture |

`redirect` and `kill` never coincide with `mem_stall`: a fault is taken only
after the access completes (or without one), and EX redirects only when it
advances.

---

## 8. Faults and halting

Faults are **precise** and taken in MEM, in program order:

| Cause | Code | Detected | Notes |
|---|---:|---|---|
| Instruction access fault | 1 | IF (RRESP != OKAY) | Reported at the PC of the instruction using the faulted word |
| Illegal instruction | 2 | ID | Unknown opcode, invalid funct3/funct7, M/A/F/D instructions, CSR instructions, MRET/WFI/..., FENCE.I, illegal/reserved/FP compressed encodings |
| Breakpoint | 3 | ID | `ebreak`, `c.ebreak`; the normal end of a program |
| Load address misaligned | 4 | MEM | Before any AXI request |
| Load access fault | 5 | MEM (RRESP != OKAY) | |
| Store address misaligned | 6 | MEM | Before any AXI request; memory unchanged |
| Store access fault | 7 | MEM (BRESP != OKAY) | The slave may or may not have written |
| Environment call | 11 | ID | `ecall` |

Within ID the priority is fetch fault > illegal > ecall > ebreak.

When the instruction in MEM faults:

1. Its control bundle is a no-op (or its access was never issued), so it
   writes no register and no memory. MEM/WB receives a bubble.
2. Every older instruction has already left MEM; the one in WB still
   completes in the same cycle.
3. `kill` flushes IF/ID, ID/EX and EX/MEM in the same cycle; EX's redirect and
   predictor update are suppressed.
4. On the next edge `halted`, `fault_valid`, `fault_pc` and `fault_cause` are
   set and hold until reset. While halted every younger stage keeps being
   flushed.
5. AXI obligations: the fetch unit issues no new reads but completes an
   address request that is already raised and accepts every outstanding
   response (dropped). The data port has nothing outstanding (the faulting
   access either was never issued or has received its response).

Faults on a mispredicted path are never taken: such instructions are
flushed by the redirect before they reach MEM.

There is no trap vector, no `mepc`/`mcause` CSRs and no way to resume
other than reset.

---

## 9. AXI4-Lite interfaces

Both ports are AXI4-Lite masters clocked by `clk`. The core uses an
active-high synchronous reset; connect `rst = !ARESETn` (synchronised) when
integrating with an AXI system. All VALID outputs are low during reset.

Protocol rules kept by both ports (checked by the testbench slave model):
VALID never depends on READY; once raised, VALID and the payload stay
stable until the handshake; RREADY and BREADY are always 1.

### 9.1 Instruction port `m_axi_i_*`

| Signal | Width | Notes |
|---|---|---|
| `arvalid`, `arready` | 1 | |
| `araddr` | 64 | 4-byte aligned |
| `arprot` | 3 | `3'b100` (instruction access) |
| `rvalid`, `rready` | 1 | `rready` = 1 |
| `rdata` | 32 | Little endian; bits 15:0 = parcel at `araddr`, 31:16 = parcel at `araddr + 2` |
| `rresp` | 2 | non-OKAY -> instruction access fault if the instruction is executed |

- Read-only: no AW/W/B channels. Tie them off if the interconnect requires
  all five channels.
- Up to 4 outstanding reads; responses must return in order (as AXI4-Lite
  requires).
- The core may prefetch past the end of the program and on predicted
  paths, so instruction memory reads must not have side effects.

### 9.2 Data port `m_axi_d_*`

| Signal | Width | Notes |
|---|---|---|
| `awvalid`, `awready`, `awaddr[63:0]`, `awprot[2:0]` | | 8-byte aligned address, `awprot = 3'b000` |
| `wvalid`, `wready`, `wdata[63:0]`, `wstrb[7:0]` | | Data shifted to its byte lane; `wstrb` marks the bytes written |
| `bvalid`, `bready`, `bresp[1:0]` | | `bready` = 1; non-OKAY -> store access fault |
| `arvalid`, `arready`, `araddr[63:0]`, `arprot[2:0]` | | 8-byte aligned address, `arprot = 3'b000` |
| `rvalid`, `rready`, `rdata[63:0]`, `rresp[1:0]` | | Full 64-bit word returned; the core selects and extends the bytes. Non-OKAY -> load access fault |

- One transaction at a time. A load issues AR and waits for R; a store
  issues AW and W (independently, in either order) and waits for B. The next
  access cannot start before the previous response, so all data accesses are
  strictly ordered and every store is complete (BRESP received) before
  anything after it executes.
- Loads and stores are never speculative: they are issued from MEM, after
  every older branch has been resolved in EX.
- Accesses must be naturally aligned (otherwise misaligned fault, no bus
  activity).
- A load reads the whole aligned 8-byte word that contains the address.

---

## 10. Module reference

| File | Module | Purpose |
|---|---|---|
| `rtl/riscv_pkg.sv` | `riscv_pkg` | Opcodes, funct3 codes, ALU encoding, fault causes, `ctrl_t`, predictor and pipeline-register structs |
| `rtl/core.sv` | `core` | Top level: stage instances, hazard unit, fault/halt registers, AXI ports |
| `rtl/if/if.sv` | `if_stage` | Fetch unit + aligner + RVC expansion + IF/ID register |
| `rtl/if/fetch_unit.sv` | `fetch_unit` | AXI4-Lite read master, request tracking, branch-predictor lookup, parcel queue |
| `rtl/if/rvc_expander.sv` | `rvc_expander` | RV64C -> 32-bit instruction expansion |
| `rtl/bp/branch_predictor.sv` | `branch_predictor` | Combines BTB, direction predictor and RAS; next-PC selection |
| `rtl/bp/btb.sv` | `btb` | Branch target buffer |
| `rtl/bp/direction_predictor.sv` | `direction_predictor` | Bimodal / gshare counters, speculative GHR |
| `rtl/bp/ras.sv` | `ras` | Return address stack with pointer checkpoint recovery |
| `rtl/id/id.sv` | `id_stage` | Decode, control, legality checks, register read, ID/EX register |
| `rtl/id/instruction_decoder.sv` | `ins_decode` | Instruction field extraction |
| `rtl/id/immediate_generator.sv` | `imm_generator` | I/S/B/U/J immediates |
| `rtl/reg/reg_file.sv` | `reg_file` | 32 x 64-bit registers, 2 read / 1 write, x0 = 0, write-through |
| `rtl/hazard/hazard_unit.sv` | `hazard_unit` | Forwarding selects, load-use stall |
| `rtl/ex/execute.sv` | `ex_stage` | Forwarding muxes, ALU, branch resolution, redirect, predictor update, EX/MEM register |
| `rtl/ex/alu/alu.sv` | `alu` | RV64I ALU incl. word operations |
| `rtl/ex/alu/alu_modules/add_sub.sv` | `add_sub` | 64-bit Kogge-Stone adder/subtractor (also SLT/SLTU via carry) |
| `rtl/ex/alu/alu_modules/barrel_shift.sv` | `barrel_shift` | SLL/SRL/SRA |
| `rtl/ex/alu/alu_modules/{and,or,xor}_gate.sv` | | Bitwise operations |
| `rtl/mem/mem.sv` | `mem_stage` | AXI4-Lite data master, lane alignment, load extension, fault detection, MEM/WB register |
| `rtl/wb/wb.sv` | `wb_stage` | Write-back select |
| `rtl/files.f` | | Ordered source list of the core |

Not part of the core: `rtl/experimental/` (Dadda multiplier, tree
comparator), `legacy/` (early drafts), `comparator_benchmark/` (comparator
study).

### Testbench files (`tb/`)

| File | Purpose |
|---|---|
| `axi_lite_mem.sv` | Behavioural AXI4-Lite slave memory: latency, random back-pressure, error region, protocol checks |
| `tb_soc.svh` | Core + instruction and data memory models |
| `rv_asm.svh` | Small RV64I/RV64C assembler (SV functions) and check helpers |
| `tb_core.sv` | ALU, immediates, loads/stores, branches, jumps (optionally NOP-padded) |
| `tb_hazard.sv` | Each forwarding path and load-use stall; exact stall count |
| `tb_rvc.sv` | Mixed 16/32-bit code, word-spanning instructions, compressed control flow, calls/returns, two branches in one fetch word |
| `tb_rvc_expand.sv`, `rvc_ref.py` | Exhaustive RVC expander check |
| `tb_fault.sv` | 10 fault cases: precise halt, no younger retirement, AXI drained |
| `tb_bp.sv` | Branch-predictor benchmark programs |

---

## 11. Supported instructions

**RV64I**

| Group | Instructions |
|---|---|
| Upper immediate | LUI, AUIPC |
| Jumps | JAL, JALR |
| Branches | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Loads | LB, LH, LW, LD, LBU, LHU, LWU |
| Stores | SB, SH, SW, SD |
| Register-immediate | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI |
| Register-register | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND |
| 32-bit (W) | ADDIW, SLLIW, SRLIW, SRAIW, ADDW, SUBW, SLLW, SRLW, SRAW |
| Ordering | FENCE (and FENCE.TSO): executed as a no-op; all accesses are already in order |
| System | ECALL -> fault (cause 11), EBREAK -> halt (cause 3) |

**RV64C (integer)**

C.ADDI4SPN, C.LW, C.LD, C.SW, C.SD, C.NOP, C.ADDI, C.ADDIW, C.LI,
C.ADDI16SP, C.LUI, C.SRLI, C.SRAI, C.ANDI, C.SUB, C.XOR, C.OR, C.AND,
C.SUBW, C.ADDW, C.J, C.BEQZ, C.BNEZ, C.SLLI, C.LWSP, C.LDSP, C.JR, C.MV,
C.EBREAK, C.JALR, C.ADD, C.SWSP, C.SDSP.

**Not supported (illegal-instruction fault):** M, A, F, D and their
compressed forms; Zicsr (all CSR instructions, including counters);
Zifencei (FENCE.I); privileged instructions (MRET, SRET, WFI, SFENCE.VMA).

Because C is supported, instruction addresses only need 2-byte alignment;
jump targets always satisfy that (JALR clears bit 0), so there is no
instruction-address-misaligned fault.

---

## 12. Known limitations

**Architecture**

- No privileged architecture: no CSRs, no trap vector, no interrupts, no
  timers or counters, no PMP/MMU, no debug module. Every exception halts the
  core until reset.
- Misaligned loads/stores are not emulated; they fault.
- No M, A, F or D extensions.
- No FENCE.I: self-modifying code is not supported. The parcel queue and the
  BTB are never flushed. A stale BTB entry pointing into the middle of a
  32-bit instruction can only arise from modified code; simulation reports
  it with an `$error` assertion in the aligner.
- Harvard organisation: separate instruction and data ports. Code written
  through the data port is not guaranteed to be seen by fetch.

**Microarchitecture / performance**

- Data port: one transaction at a time, and every load/store takes at least
  one extra cycle. Stores wait for BRESP.
- Instruction port: read channels only.
- Misprediction penalty 3 cycles; load-use 1 cycle.
- The EX redirect drives the instruction-port address combinationally in
  the same cycle (allowed by AXI, but a long path).
- Two compressed branches in one fetch word share a BTB entry and a counter
  (accuracy only, Section 6).
- The RAS restores only its pointer on a misprediction; entries overwritten
  on a wrong path are not repaired.

**Verification and implementation status**

- Verified with directed self-checking testbenches, an exhaustive RVC
  expander check, an AXI protocol-checking slave model with random
  back-pressure, and a regression over all predictor configurations and
  memory timings (`make regress`). It has **not** been run against
  riscv-tests, riscv-arch-test or a reference model (no RISC-V toolchain was
  available) and has not been formally verified.
- Not run on an FPGA and not taken through place and route.
- Synthesis: the branch predictor synthesizes with Yosys + Nangate45
  (`make synth_bp`). The full core uses packed structs from a package in port
  lists, which the built-in Yosys 0.52 front end cannot parse; full-core
  synthesis with open-source tools needs `sv2v` or the yosys-slang plugin
  (not set up). The RTL is Verilator `-Wall` clean (no latches, no
  multiple drivers).
- `reports/bp_benchmark.md` was produced before fault handling was added.
  Since then `ebreak` stops the core in MEM instead of WB, so cycle and
  retired counts may differ by a cycle or one instruction; prediction
  accuracy is unaffected.

---

## 13. Build, test and toolchain

### Requirements

| Tool | Used for | Tested version |
|---|---|---|
| Verilator (with `--timing`) | Lint and all simulation | 5.032 |
| Python 3 | RVC reference model, report generation | 3.12 |
| GNU make, bash | Build scripts | |
| Yosys + Nangate45 Liberty | `make synth_bp` only | Yosys 0.52 |
| OpenSTA | `make synth_bp` only | 2.0.17 |

`scripts/bp_synth.sh` looks for Yosys, the Liberty file and OpenSTA in the
paths used by `comparator_benchmark/`; override with the `YOSYS`, `LIB` and
`STA` environment variables. A RISC-V GCC toolchain is not needed: the
testbenches assemble their programs in SystemVerilog.

### Commands

```bash
make lint        # Verilator -Wall lint of the core
make test        # lint + every directed test
make regress     # 5 predictor configs x latency {1,3} x back-pressure {off,on}
make bench       # predictor benchmark -> reports/bp_benchmark.md
make synth_bp    # predictor area / timing -> reports/bp_benchmark.md
make clean
```

Individual tests: `make sim`, `sim_pad`, `hazard`, `rvc`, `rvc_expand`,
`fault`.

### Using your own program

The testbenches write programs directly into the instruction-memory model
(`imem.mem`, a byte array) before reset is released; see `tb/rv_asm.svh`.
To run compiled code, load a binary into `imem.mem` / `dmem.mem` (e.g. with
`$readmemh`) in a testbench based on `tb/tb_soc.svh`, and end the program
with `ebreak`.

---

## 14. Connecting an MMIO accelerator

The data port is a plain AXI4-Lite master, so an accelerator with an
AXI4-Lite slave register interface can be attached through an address
decoder. No change to the core is needed.

```text
                         +------------------+
 core m_axi_d_* -------->| AXI4-Lite 1:N    |----> data memory (e.g. 0x0000_0000 - 0x0FFF_FFFF)
                         | address decoder  |----> accelerator registers (e.g. 0x1000_0000 - 0x1000_0FFF)
                         +------------------+----> DECERR for unmapped addresses
 core m_axi_i_* -------------------------------> instruction memory
```

Properties of the core that make MMIO straightforward:

- **Non-speculative, in-order, one at a time.** Loads and stores are issued
  only from MEM, after all older branches are resolved, and the next access
  starts only after the previous response. A store to a "start" register is
  therefore complete (BRESP received) before any later instruction, and
  status reads are never issued speculatively, so registers with read side
  effects are safe.
- **No caches.** No cache maintenance or coherence is needed for the core's
  own accesses.
- **Errors are reported.** A SLVERR/DECERR response becomes a precise load or
  store access fault (`fault_pc` = the faulting instruction).

Points to observe:

- The decoder only has to route one transaction at a time, because the data
  port never has more than one outstanding. It must still route AW and W of a
  store to the same slave and return the B/R response of the selected slave.
- Reads are full 64-bit and 8-byte aligned. A 32-bit `lw` reads the whole
  8-byte word containing it, so place registers with read side effects at
  8-byte spacing (or make reads side-effect free).
- Writes use `wstrb`; an `sw` to a 32-bit register sets only its four strobe
  bits.
- Use naturally aligned accesses; misaligned ones fault without bus activity.
- There are no interrupts: software polls a status register.
- A slow slave stalls the whole pipeline (`mem_stall`), and there is no bus
  timeout; the slave must always respond.
- Instruction fetch may prefetch, so do not map registers with read side
  effects into the instruction address space.
- An accelerator that reads or writes data memory itself needs its own bus
  master and an interconnect shared with the core's data port. The core will
  observe its results correctly as long as software waits (polls) for
  completion before reading them; FENCE is a no-op and is not needed for
  ordering.

Example programming sequence (register map is illustrative):

```text
0x1000_0000  CTRL    (write 1 = start)
0x1000_0008  STATUS  (bit 0 = busy)
0x1000_0010  SRC     (source address in data memory)
0x1000_0018  DST
0x1000_0020  LEN
```

```asm
    lui   t0, 0x10000          # t0 = 0x1000_0000
    sd    a0, 0x10(t0)         # SRC
    sd    a1, 0x18(t0)         # DST
    sd    a2, 0x20(t0)         # LEN
    li    t1, 1
    sd    t1, 0x00(t0)         # CTRL = start
1:  ld    t1, 0x08(t0)         # poll STATUS
    andi  t1, t1, 1
    bnez  t1, 1b
    ebreak
```
