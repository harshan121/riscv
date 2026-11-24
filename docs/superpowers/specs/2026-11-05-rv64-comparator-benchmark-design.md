# RV64 Comparator Benchmark Design

## Intent

Build an isolated, reproducible comparison of two functionally equivalent 64-bit
comparator implementations for an RV64 ALU.  It must establish correctness
before reporting structural, synthesis, timing, or (if tooling supports it)
power results.  The existing processor RTL, including its unfinished
`rtl/ex/alu/less_than.sv`, is out of scope and must not be changed.

## Goals

- Provide distinct inferred and explicit six-level parallel-prefix designs.
- Expose the same `a`, `b`, `signed_lt`, `signed_lte`, `unsigned_lt`, and
  `unsigned_lte` ports on both modules.
- Verify every output against SystemVerilog references over directed edge cases
  and at least 100,000 deterministic random input pairs.
- Run available tools and record exact versions, commands, measurements, and
  unavailable-tool limitations in repository-local reports.
- Compare standalone modules and each module in the same small ALU wrapper.

## Non-goals and constraints

- Do not modify or integrate with the current processor ALU.
- Do not claim equivalence, PPA, or power results that were not produced by a
  working tool flow.
- The tree datapath cannot use relational operators.  Its unsigned reduction
  tree follows `LT = LT_H | (EQ_H & LT_L)` and `EQ = EQ_H & EQ_L`; signed
  ordering is selected from sign bits, with the magnitude tree used only when
  signs match.
- All designs are combinational and synthesizable SystemVerilog with no
  latches, feedback, or multi-driven nets.

## Approaches considered

1. **Standalone common four-output interface (selected).**  Keep both designs
   in `comparator_benchmark/`, use the same ports and shared verification
   harness, and add a dedicated wrapper solely for integrated measurements.
   This is reproducible and leaves the processor unaffected.
2. **Adapt the present processor comparator interface.**  This would require
   defining control semantics for an incomplete ALU and would conflate the
   experiment with processor repair.  It is not selected.

## Implementation outline

- `rtl/comparator_inferred.sv`: relational-operator baseline.
- `rtl/comparator_tree.sv`: packed arrays for LT/EQ level values, generated
  for 64, 32, 16, 8, 4, 2, and 1 groups.  Equality is reused for `<=`.
- `rtl/comparator_alu_wrapper.sv`: identical operation-selection shell around
  either comparator, used only by the integration synth flows.
- `tb/tb_comparator.sv`: self-checking Verilator bench, deterministic seed,
  directed matrix, 100,000 random pairs, and test/mismatch/PASS summary.
- `scripts/`: executable verification, Yosys generic/mapped synthesis,
  tool/library detection, timing, and report aggregation scripts.  A local
  Nangate45 Liberty file will be detected when Yosys and a compatible timing
  tool are available; both flows use the identical file and constraints.
- `reports/`: generated raw synthesis/timing output plus a Markdown summary
  including formulas, tool versions, tool limitations, and architectural
  analysis.  Optional formal and power flows run only when available and
  record their status instead of making unsupported numerical claims.

## Validation and reporting

The verification script compiles with Verilator and fails on any mismatch.
The comparison script invokes each synthesis flow independently and emits
machine-readable intermediate summaries before producing the final table.
For this environment, initial discovery found Verilator and Icarus Verilog;
Yosys, OpenSTA, and SymbiYosys were not on `PATH`.  A Nangate45 Liberty file
exists elsewhere on the host, but it is usable only if compatible synthesis
and timing tools are available.  The finished reports will distinguish these
facts from actual measurements.
