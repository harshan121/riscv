# Kreacher: RV64IC five-stage baseline processor

Kreacher is a single-issue, in-order, five-stage RISC-V processor (RV64I +
compressed instructions) with AXI4-Lite instruction and data ports, written
in synthesizable SystemVerilog. Release **v1.0.0-baseline** is a stable,
conventional reference design for later processor and accelerator research.

- 5-stage pipeline: IF, ID, EX, MEM, WB, with full forwarding and a 1-cycle
  load-use stall
- RV64I + RV64C (integer); FENCE is a no-op
- Branch prediction: 64-entry BTB, bimodal or gshare counters, 8-entry
  return address stack, or static not-taken (compile-time parameters)
- AXI4-Lite masters: 32-bit read-only instruction port (up to 4 reads
  outstanding), 64-bit data port
- Precise minimal fault handling: illegal instructions, ecall, ebreak,
  misaligned loads/stores and AXI error responses halt the core and report
  `fault_pc` / `fault_cause`
- No CSRs, privileged architecture, interrupts or caches (see limitations)

Full description: **[docs/architecture.md](docs/architecture.md)**.

## Quick start

Requirements: Verilator 5.x (with `--timing`), Python 3, make. Yosys,
a Nangate45 Liberty file and OpenSTA only for `make synth_bp`.

```bash
make lint      # Verilator -Wall lint of the core
make test      # all directed tests (~1-2 minutes)
make regress   # all predictor configs x memory latency x AXI back-pressure
```

| Target | What it runs |
|---|---|
| `sim` | `tb_core`: ALU, immediates, loads/stores, branches, jumps |
| `sim_pad` | `tb_core` with 2 NOPs after every instruction |
| `hazard` | `tb_hazard`: every forwarding path, exact load-use stall count |
| `rvc` | `tb_rvc`: mixed 16/32-bit code on the full core |
| `rvc_expand` | Exhaustive check of the RVC expander (49 152 encodings) |
| `fault` | `tb_fault`: 10 fault scenarios |
| `bench` | Branch-predictor benchmark -> `reports/bp_benchmark.md` |
| `synth_bp` | Predictor area / timing (Yosys + Nangate45 + OpenSTA) |

## Repository layout

```text
rtl/                  core RTL (source list: rtl/files.f)
  core.sv             top level
  riscv_pkg.sv        shared types and constants
  if/ id/ ex/ mem/ wb/  pipeline stages
  bp/                 branch predictor (BTB, direction, RAS)
  hazard/             forwarding / load-use stall
  reg/                register file
  experimental/       research modules not in the core (Dadda multiplier, tree comparator)
tb/                   testbenches, AXI4-Lite memory model, SV assembler
scripts/              regression, predictor benchmark and synthesis scripts
reports/              generated benchmark / synthesis reports
docs/                 architecture description, earlier design notes
comparator_benchmark/ separate study: inferred vs tree comparator
legacy/               early drafts, not built
```

## Core interface

| Port | Description |
|---|---|
| `clk`, `rst` | Clock; synchronous active-high reset (fetch starts at 0) |
| `halted`, `fault_valid`, `fault_pc[63:0]`, `fault_cause[3:0]` | Halt status (sticky until reset); `fault_cause` uses RISC-V `mcause` codes, 3 = ebreak (normal end) |
| `m_axi_i_*` | AXI4-Lite instruction port: AR + R channels, 32-bit data |
| `m_axi_d_*` | AXI4-Lite data port: all five channels, 64-bit data |

Parameters: `BP_ENABLE`, `USE_GSHARE`, `ENABLE_RAS` (all default 1).

## Status and limitations

Verified with directed self-checking simulations, an exhaustive compressed
expander check and a protocol-checking AXI slave model with random
back-pressure. Not yet run against riscv-tests / riscv-arch-test, on an FPGA,
or through full-core synthesis (the built-in Yosys front end cannot parse
the package structs; `sv2v` or yosys-slang would be needed). The complete
list is in [docs/architecture.md, Section 12](docs/architecture.md#12-known-limitations).

Connecting a memory-mapped accelerator to the data port is described in
[Section 14](docs/architecture.md#14-connecting-an-mmio-accelerator).

## Version

`v1.0.0-baseline`. See [CHANGELOG.md](CHANGELOG.md).
