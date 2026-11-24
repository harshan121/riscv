#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$root"
exp=comparator_benchmark/signed_le_experiment
yosys_bin=${YOSYS_BIN:-/home/harshan/harshan-project-2026/sha3-koika-archive-20261004/tool-cache/adder-eda/bin/yosys}
if [[ ! -x "$yosys_bin" ]]; then
    echo "FORMAL_EQUIVALENCE_UNAVAILABLE: Yosys not found" > "$exp/reports/formal_results.txt"
    exit 0
fi
"$yosys_bin" -ql "$exp/reports/formal_results.txt" -p "read_verilog -formal -sv $exp/rtl/less_than_equal_tree.sv; read_verilog -formal -sv $exp/rtl/less_than_equal_inferred.sv; miter -equiv -make_assert -flatten less_than_equal_inferred less_than_equal_tree inferred_vs_tree; prep -top inferred_vs_tree -flatten; techmap; opt; sat -prove-asserts -verify"
"$yosys_bin" -ql "$exp/reports/formal_optimized_results.txt" -p "read_verilog -formal -sv $exp/rtl/less_than_equal_tree_optimized.sv; read_verilog -formal -sv $exp/rtl/less_than_equal_inferred.sv; miter -equiv -make_assert -flatten less_than_equal_inferred less_than_equal_tree_optimized inferred_vs_optimized; prep -top inferred_vs_optimized -flatten; techmap; opt; sat -prove-asserts -verify"
cat "$exp/reports/formal_optimized_results.txt" >> "$exp/reports/formal_results.txt"
echo FORMAL_EQUIVALENCE_PASS >> "$exp/reports/formal_results.txt"
tail -30 "$exp/reports/formal_results.txt"
