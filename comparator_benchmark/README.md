# RV64 Comparator Benchmark

This directory is an isolated experiment comparing an inferred 64-bit signed
and unsigned comparator against a six-level explicit parallel-prefix tree. It
does not modify processor RTL.

## Layout

- `rtl/`: both comparators and a common operation-select wrapper.
- `tb/`: self-checking Verilator testbenches.
- `scripts/`: verification, generic/mapped synthesis, timing, and formal
  equivalence flows.
- `reports/`: generated simulation, mapping, timing, and summary reports.

## Reproduce

Run from the repository root:

```bash
comparator_benchmark/scripts/run_verification.sh
comparator_benchmark/scripts/run_comparison.sh
```

The verification run uses a fixed xorshift seed, executes 15 directed edge
cases and 100,000 random pairs, writes `reports/verification.txt`, and emits
`reports/comparator_activity.vcd`. It exits nonzero on any mismatch.

The comparison runner locates Yosys and a common Nangate45 Liberty library,
runs independent generic and mapped flows for both standalone tops and both
wrapper variants, runs Yosys formal equivalence, and uses a local OpenSTA
package when available. It records any unavailable tool rather than inventing
a metric.

## Latest result

See [reports/comparison_summary.md](reports/comparison_summary.md). In this
environment the custom tree was 7.04% smaller and 17.12% faster standalone,
but became 4.20% larger in the common wrapper while retaining only a 1.41%
timing improvement. The inferred implementation is therefore the recommended
RV64 ALU default pending post-layout analysis.
