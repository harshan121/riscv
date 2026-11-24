# SDD ledger — plan: docs/superpowers/plans/2026-11-05-rv64-comparator-benchmark.md
Pre-flight: Task 1 -> Tasks 3/4 comparator_inferred exact six-port interface: planned, no conflict.
Pre-flight: Task 2 -> Tasks 3/4 comparator_tree exact six-port interface: planned, no conflict.
Pre-flight: Task 3 -> Task 5 comparator_activity.vcd: planned, no conflict.
Task 2: complete (no Git repository; lint and shared red→green testbench compile/simulation → PASS)
Task 3: Ruling: Braced the PASS/FAIL conditional — the $fatal was unconditionally executed after $finish — cost if wrong: a false failing test run.
Task 3: complete (100015 cases, 0 mismatches, VCD captured → PASS)
Task 3: complete (run_verification.sh; 100015 cases, 0 mismatches, VCD captured → PASS)
Task 4: Ruling: Used a USE_TREE module parameter rather than a compile-wide macro — permits both otherwise-identical wrappers to be tested in one executable — cost if wrong: parameter elaboration must be supported by synthesis tools.
Task 4: complete (wrapper red→green test and lint → PASS)
Task 5: Ruling: Used the cached Yosys 0.52 and locally extracted OpenSTA 2.0.17 with the same Nangate45 Liberty for both designs — system installation required an unavailable sudo terminal and direct download provided a reproducible local alternative — cost if wrong: host-specific tool paths must be rediscovered on a different machine.
Task 5: Ruling: Used Yosys equiv_make/equiv_simple for formal equivalence because SymbiYosys was unavailable — it proves all four combinational outputs rather than relying on random simulation — cost if wrong: sequential/protocol properties are outside this combinational proof's scope.
Task 5: complete (independent generic/mapped synthesis, OpenSTA timing, and formal equivalence → PASS)
Task 6: complete (summary and README written; end-to-end scripts, lint, report-artifact, and formal checks → PASS)
Final review: self-review (fresh delegation not requested). Reviewed RTL interfaces, signed ordering, tree high/low order, wrapper parameter elaboration, script syntax, and every summary metric against fresh generated reports; no critical, important, or minor findings.
