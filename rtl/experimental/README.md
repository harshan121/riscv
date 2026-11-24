# rtl/experimental/

Research modules that are **not** part of the v1.0.0 core (not in
`rtl/files.f`):

| File | Description | Status |
|---|---|---|
| `multiply_dadda.sv` | 64x64 -> 128-bit Dadda-tree multiplier (MUL/MULH/MULHSU/MULHU operand modes) | Candidate for a future M-extension unit; not integrated or verified in the pipeline |
| `less_than_tree.sv` | Six-level parallel-prefix signed comparator (`less_greater_equal`) | Studied in `comparator_benchmark/`; the core uses the adder-based SLT/SLTU and inferred branch compares |
