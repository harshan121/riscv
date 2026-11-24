# Signed `<=` Comparator Experiment

Independent follow-on benchmark for the MSB-first signed comparison tree.

```bash
comparator_benchmark/signed_le_experiment/scripts/run_all.sh
```

The command runs 100,016 functional tests, formal equivalence, generic/mapped synthesis, OpenSTA timing, width scaling, ALU integration, and Graphviz netlist diagrams. Results are in `reports/`; start with `reports/final_comparison.md`.

Tool configuration and assumptions are recorded in `reports/tool_versions.txt`. The scripts reuse the parent benchmark's local OpenSTA cache and the detected Nangate45 Liberty file.
