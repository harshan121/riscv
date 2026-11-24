# RV64 Comparator Benchmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, verify, synthesize where supported, and report an isolated comparison of inferred and explicit prefix-tree RV64 comparators.

**Architecture:** Both comparator modules expose the same six-port, four-result combinational interface.  The inferred module uses signed and unsigned relational operators; the tree module reduces per-bit `lt`/`eq` values through six MSB-priority levels and chooses signed ordering explicitly from the input sign bits.  A self-checking simulation bench verifies both designs, while tool-detecting scripts independently process standalone and wrapper top modules.

**Tech Stack:** SystemVerilog, Verilator, Bash, Yosys/OpenSTA/SymbiYosys when installed, optional Nangate45 Liberty.

**Spec:** `docs/superpowers/specs/2026-11-05-rv64-comparator-benchmark-design.md`

## Global Constraints

- Preserve all existing RISC-V project files; all experiment artifacts live under `comparator_benchmark/`.
- Both comparators use `input logic [63:0] a, b` and outputs `signed_lt`, `signed_lte`, `unsigned_lt`, and `unsigned_lte`.
- The prefix-tree comparison datapath must not use relational operators.
- Both implementations are fully combinational, synthesizable, and free of latches, feedback, and multiple drivers.
- Run at least 100,000 deterministic random pairs plus the specified directed edge cases.
- Baseline and tree synthesis use identical settings, constraints, libraries, and output preservation.
- Report unavailable tools or unsupported power/formal flows explicitly; do not fabricate measurements.
- No Git repository was detected at workspace root; do not create commits unless a repository is supplied.

## Review Focus

- Opposite-sign operands: test signed ordering derives from sign, not unsigned magnitude (Task 2).
- Equal operands: test both `<=` outputs are asserted while both `<` outputs are deasserted (Task 3).
- `0x8000...0` versus `0x7fff...f`: test signed and unsigned results intentionally disagree (Task 3).
- Tree grouping order: test pairs differing only at bit 63 and bit 0, catching reversed high/low combine inputs (Task 3).
- Tool absence: test scripts terminate with a clear “unavailable” report rather than a false PPA result (Task 5).

### Task 1: Comparator interface and inferred baseline

**Files:**
- Create: `comparator_benchmark/rtl/comparator_inferred.sv`

**Interfaces:**
- Produces module `comparator_inferred(input logic [63:0] a, b, output logic signed_lt, signed_lte, unsigned_lt, unsigned_lte)`.
- Consumed by `tb_comparator` and `comparator_alu_wrapper` in later tasks.

- [ ] **Step 1: Create the inferred comparator module**

Assign each output continuously. Use `$signed(a) < $signed(b)` and `$signed(a) <= $signed(b)` for signed outputs; use `a < b` and `a <= b` for unsigned outputs.

- [ ] **Step 2: Lint the standalone baseline**

Run: `verilator --lint-only -Wall comparator_benchmark/rtl/comparator_inferred.sv`

Expected: exit status 0 with no syntax or width errors.

### Task 2: Six-level custom comparison tree

**Files:**
- Create: `comparator_benchmark/rtl/comparator_tree.sv`

**Interfaces:**
- Produces module `comparator_tree` with the exact `comparator_inferred` interface.
- Consumes `a[63:0]` and `b[63:0]`; provides all four comparison results to the testbench and wrapper.

- [ ] **Step 1: Define unsigned leaf and reduction signals**

Use packed `logic` arrays for 64 `lt` and `eq` leaves and one clearly sized packed array per six reduction levels. At each leaf, form `~a[i] & b[i]` and `~(a[i] ^ b[i])`.

- [ ] **Step 2: Define the six generate levels**

For every pair, treat index `2*i+1` as high and `2*i` as low; assign `lt_next[i] = lt_high | (eq_high & lt_low)` and `eq_next[i] = eq_high & eq_low`. Reduce 64 leaves to one root using six generate loops and continuous assignments.

- [ ] **Step 3: Define signed outputs without relational operators**

When `a[63] != b[63]`, signed less-than is `a[63]`; otherwise use the unsigned tree root. Compute each `<=` as its `<` value OR the shared root equality.

- [ ] **Step 4: Lint the tree**

Run: `verilator --lint-only -Wall comparator_benchmark/rtl/comparator_tree.sv`

Expected: exit status 0; no latch, circular-combinational, or multiple-driver diagnostics.

### Task 3: Self-checking functional verification and activity capture

**Files:**
- Create: `comparator_benchmark/tb/tb_comparator.sv`
- Create: `comparator_benchmark/scripts/run_verification.sh`

**Interfaces:**
- Consumes both comparator modules.
- Produces Verilator simulation executable, `reports/verification.txt`, `reports/comparator_activity.vcd`, total-test count, mismatch count, and PASS/FAIL result.

- [ ] **Step 1: Write the reference-check task in `tb_comparator.sv`**

Implement `task automatic check_case(input logic [63:0] test_a, test_b);` that drives both DUTs, delays one simulation tick, calculates the four SystemVerilog reference values, increments a case counter, and records every output mismatch with operands and expected/actual values.

- [ ] **Step 2: Add directed edge cases**

Call `check_case` for zero/equal values, positive/positive, negative/negative, both opposite-sign orders, signed extrema, all ones, MSB-only and LSB-only differences, and alternating patterns. Include explicit assertions for equal operands and the signed/unsigned disagreement at `64'h8000_0000_0000_0000` vs `64'h7fff_ffff_ffff_ffff`.

- [ ] **Step 3: Add deterministic randomized coverage and VCD dumping**

Use a fixed 64-bit PRNG seed to generate exactly 100,000 random pairs. Dump both DUT inputs and outputs to `reports/comparator_activity.vcd`; print total tests, mismatch total, and `PASS` or `FAIL`, ending nonzero on mismatch.

- [ ] **Step 4: Create the verification runner**

Make `run_verification.sh` executable. It creates `reports/`, records `verilator --version`, compiles both DUTs plus testbench with timing and tracing enabled, captures simulation output in `reports/verification.txt`, and propagates simulation failure.

- [ ] **Step 5: Execute functional verification**

Run: `comparator_benchmark/scripts/run_verification.sh`

Expected: exit status 0, a PASS line, zero mismatches, more than 100,000 total test cases, and a nonempty VCD.

### Task 4: Identical ALU-wrapper integration points

**Files:**
- Create: `comparator_benchmark/rtl/comparator_alu_wrapper.sv`

**Interfaces:**
- Consumes parameterless `comparator_inferred` or `comparator_tree` via preprocessor-selected implementation.
- Produces module `comparator_alu_wrapper(input logic [63:0] a, b, input logic [1:0] compare_op, output logic result)` where `00/01/10/11` select signed LT, signed LTE, unsigned LT, unsigned LTE.

- [ ] **Step 1: Implement the shared wrapper**

Instantiate exactly one selected comparator using `USE_TREE`; use a single combinational operation mux with a safe default. Do not use project ALU files.

- [ ] **Step 2: Lint both wrapper variants**

Run: `verilator --lint-only -Wall comparator_benchmark/rtl/comparator_inferred.sv comparator_benchmark/rtl/comparator_alu_wrapper.sv` and repeat with `-DUSE_TREE` and `comparator_tree.sv`.

Expected: both commands exit 0.

### Task 5: Independent synthesis, timing, formal, and power-aware scripts

**Files:**
- Create: `comparator_benchmark/scripts/synth_inferred.ys`
- Create: `comparator_benchmark/scripts/synth_tree.ys`
- Create: `comparator_benchmark/scripts/run_comparison.sh`
- Create: `comparator_benchmark/scripts/formal_equivalence.sby`
- Create: `comparator_benchmark/scripts/constraints.sdc`

**Interfaces:**
- Consumes comparator RTL, wrapper RTL, activity VCD, available Yosys/OpenSTA/formal/power tools, and one detected Liberty file.
- Produces raw standalone/wrapper generic and mapped reports, timing report, formal status, tool-version report, and a machine-readable metrics file used by Task 6.

- [ ] **Step 1: Write matched Yosys flows**

Each `.ys` script must independently read only its respective comparator, preserve all four outputs through optimization, run identical generic passes, report statistics, and—only when supplied a common Liberty path—run identical `dfflibmap`/`abc` mapping and write mapped netlist/statistics.

- [ ] **Step 2: Add common virtual timing constraints**

Create `constraints.sdc` with one virtual input clock, matching input delays, output loads, and identical output-delay assumptions for all four results. The timing scripts must measure input-to-output paths, not a sequential endpoint.

- [ ] **Step 3: Implement robust tool and library detection**

`run_comparison.sh` must detect Yosys, OpenSTA-compatible `sta`, SymbiYosys, and power tools; prefer a single Nangate45 Liberty candidate discovered locally. For each missing prerequisite, write a clear unavailable status to the appropriate raw report and retain a successful verification result.

- [ ] **Step 4: Add optional proof and power paths**

When SymbiYosys is installed, run a miter/equivalence proof over both combinators and record result. When a supported power tool and mapped netlists exist, use the VCD with identical temperature, voltage, frequency, and loads for both modules, reporting dynamic and leakage separately; otherwise mark power unavailable with no numerical estimate.

- [ ] **Step 5: Run the comparison script**

Run: `comparator_benchmark/scripts/run_comparison.sh`

Expected: raw reports exist for inferred and tree (standalone and wrapper); each installed flow either produces measurements or an explicit failure/unavailable explanation.

### Task 6: Results consolidation and technical recommendation

**Files:**
- Create: `comparator_benchmark/reports/comparison_summary.md`
- Create: `comparator_benchmark/README.md`

**Interfaces:**
- Consumes verification, tool-version, synthesis, timing, formal, power, and wrapper reports from Tasks 3–5.
- Produces a user-readable reproducibility guide, filled summary table, calculation results only where source metrics exist, and an evidence-based recommendation.

- [ ] **Step 1: Build the required summary table from generated reports**

Include functional status, cell area/count, critical delay, logic depth, dynamic/leakage power, and difference columns. Calculate area reduction and delay improvement only when both comparable numerical inputs are available; otherwise render `N/A (tool unavailable)`.

- [ ] **Step 2: Add required structural analysis**

Explain how the observed Yosys lowering represents built-in comparison, how it differs from the explicit tree, and measured/inferred effects on area, depth, fanout, routing, equality sharing, synthesis restructuring, ALU-wrapper representativeness, and RV64 suitability. Clearly label tool-unavailable analysis as an expected consequence, not a measurement.

- [ ] **Step 3: Document reproduction and recommendation**

In `README.md`, list directory layout, prerequisites, commands, expected artifacts, fixed randomization behavior, and limitations. Make the final recommendation conditional on generated evidence and verification complexity.

- [ ] **Step 4: Final end-to-end verification**

Run: `comparator_benchmark/scripts/run_verification.sh && comparator_benchmark/scripts/run_comparison.sh`

Expected: verification PASS with zero mismatches; comparison reports contain actual metrics only for tools that completed successfully and explicit statuses for the rest.

## Self-review

- **Spec coverage:** Tasks 1–2 implement both architectures; Task 3 supplies directed/random verification and activity; Task 4 measures identical integration; Tasks 5–6 cover independent generic/mapped synthesis, timing, formal/power detection, reproducibility, required table, analysis, and recommendation.
- **Step scan:** Every code step fixes a module, interface, algorithm, or required artifact; verification commands state pass criteria.
- **Type consistency:** Both comparator modules, testbench instantiations, and wrapper all use the exact same ports and widths.
- **Review focus:** Opposite signs, equality, extrema disagreement, tree priority ordering, and unavailable tools are assigned to concrete checks.
- **Proportion:** The plan specifies interfaces and acceptance criteria without reproducing RTL implementation bodies.
