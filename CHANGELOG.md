# Changelog

## v1.0.0-baseline (2026-11-24)

First stable baseline of the conventional five-stage core.

### Processor
- RV64I five-stage in-order pipeline (IF, ID, EX, MEM, WB).
- RV64C (integer) via an expander in IF; 16/32-bit instruction alignment
  with instructions spanning fetch words.
- Forwarding (EX/MEM, MEM/WB, register-file write-through) and 1-cycle
  load-use stall.
- Branch prediction: BTB + bimodal/gshare + RAS with speculative history and
  checkpoint recovery; static not-taken option.
- AXI4-Lite instruction (32-bit, read-only, up to 4 outstanding) and data
  (64-bit) master ports.
- Minimal precise fault handling: illegal / unsupported instructions, ecall,
  ebreak, misaligned loads/stores, instruction and data AXI error responses.
  New outputs `halted`, `fault_valid`, `fault_pc`, `fault_cause` (replace the
  former `halt` / `bus_error`). Illegal and unsupported instructions are no
  longer executed as no-ops.

### Fixes during finalization
- Data-port AXI VALID signals are now forced low during reset.
- `CTRL_NOP` written as `'0` (equivalent) so the package parses in Yosys.

### Verification
- Directed testbenches: core, hazards, RVC on the core, exhaustive RVC
  expander, fault handling (10 cases), predictor benchmark programs.
- AXI4-Lite slave model with latency, random back-pressure, error region and
  protocol assertions.
- Regression across 5 predictor configurations, 2 memory latencies and
  back-pressure on/off.

### Repository
- Removed obsolete `rtl/if/instruction_fetch.sv` and
  `rtl/if/instruction_memory.sv` (unused since the AXI front end).
- Moved unused drafts (`rtl/pc.sv`, `rtl/pc/pc.sv`, `./or_gate.sv`) to
  `legacy/`; moved the Dadda multiplier and tree comparator to
  `rtl/experimental/`.
- Added `README.md`, `docs/architecture.md`, `VERSION`, `.gitignore`.
