#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

reports_dir=comparator_benchmark/reports
build_dir=comparator_benchmark/obj_dir
report_file="$reports_dir/verification.txt"
mkdir -p "$reports_dir"
rm -rf "$build_dir"

{
    echo "Comparator functional verification"
    echo "Command: $0"
    echo "Date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    verilator --version
    echo
    verilator --binary --timing --trace --top-module tb_comparator \
        -Mdir "$build_dir" \
        comparator_benchmark/rtl/comparator_inferred.sv \
        comparator_benchmark/rtl/comparator_tree.sv \
        comparator_benchmark/tb/tb_comparator.sv
    "$build_dir/Vtb_comparator"
} > "$report_file" 2>&1

cat "$report_file"
