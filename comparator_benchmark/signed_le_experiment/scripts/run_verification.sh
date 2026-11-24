#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$root"
exp=comparator_benchmark/signed_le_experiment
mkdir -p "$exp/reports"
rm -rf "$exp/obj_dir" "$exp/obj_alu"
{
    verilator --version
    verilator --binary --timing --trace --top-module tb_comparator -Mdir "$exp/obj_dir" \
        "$exp/rtl/less_than_equal_tree.sv" "$exp/rtl/less_than_equal_inferred.sv" \
        "$exp/rtl/less_than_equal_tree_optimized.sv" "$exp/tb/tb_comparator.sv"
    "$exp/obj_dir/Vtb_comparator"
} > "$exp/reports/verification.txt" 2>&1
{
    verilator --binary --timing --top-module tb_alu_wrappers -Mdir "$exp/obj_alu" \
        "$exp/rtl/less_than_equal_tree.sv" "$exp/rtl/less_than_equal_inferred.sv" \
        "$exp/rtl/less_than_equal_tree_optimized.sv" "$exp/rtl/alu_wrappers.sv" "$exp/tb/tb_alu_wrappers.sv"
    "$exp/obj_alu/Vtb_alu_wrappers"
} > "$exp/reports/alu_functional.txt" 2>&1
cat "$exp/reports/verification.txt"
cat "$exp/reports/alu_functional.txt"
