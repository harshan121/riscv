#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

reports_dir=comparator_benchmark/reports
mkdir -p "$reports_dir"
tool_versions="$reports_dir/tool_versions.txt"
timing_report="$reports_dir/timing_comparison.txt"
power_report="$reports_dir/power_comparison.txt"

find_executable() {
    local candidate
    for candidate in "$@"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

yosys_bin=$(find_executable "$(command -v yosys 2>/dev/null || true)" \
    /home/harshan/harshan-project-2026/sha3-koika-archive-20261004/tool-cache/adder-eda/bin/yosys \
    /home/harshan/harshan-project-2026/sha3-koika-archive-20261004/build-output/build/open_source_tools/usr/bin/yosys || true)

liberty_file=
for candidate in \
    /home/harshan/harshan-project-2026/sha3-koika-archive-20261004/tool-cache/adder-eda/technology/typical.lib \
    /home/harshan/harshan-project-2026/sha3-koika-archive-20261004/build-output/build/nangate45/typical.lib; do
    if [[ -r "$candidate" ]]; then
        liberty_file=$candidate
        break
    fi
done

{
    echo "Comparator benchmark tool discovery"
    echo "Date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [[ -n "$yosys_bin" ]]; then "$yosys_bin" -V; else echo "Yosys: unavailable"; fi
    if command -v verilator >/dev/null 2>&1; then verilator --version; else echo "Verilator: unavailable"; fi
    if command -v sby >/dev/null 2>&1; then sby --version; else echo "SymbiYosys: unavailable"; fi
    if [[ -n "$liberty_file" ]]; then echo "Liberty: $liberty_file"; else echo "Nangate45 Liberty: unavailable"; fi
} > "$tool_versions"

if [[ -z "$yosys_bin" ]]; then
    printf 'Yosys unavailable; no generic or mapped synthesis measurements.\n' > "$reports_dir/inferred_synthesis.txt"
    printf 'Yosys unavailable; no generic or mapped synthesis measurements.\n' > "$reports_dir/tree_synthesis.txt"
else
    "$yosys_bin" -ql "$reports_dir/inferred_synthesis.txt" -s comparator_benchmark/scripts/synth_inferred.ys
    "$yosys_bin" -ql "$reports_dir/tree_synthesis.txt" -s comparator_benchmark/scripts/synth_tree.ys

    run_mapped() {
        local name=$1
        local source=$2
        local top=$3
        local use_tree=${4:-}
        local extra=""
        if [[ -n "$use_tree" ]]; then
            extra="chparam -set USE_TREE $use_tree comparator_alu_wrapper;"
        fi
        "$yosys_bin" -ql "$reports_dir/${name}_mapped_synthesis.txt" -p "read_verilog -sv $source; $extra hierarchy -check -top $top; proc; opt; flatten; opt; techmap; opt; dfflibmap -liberty $liberty_file; abc -liberty $liberty_file; clean; tee -o $reports_dir/${name}_mapped_stats.txt stat -liberty $liberty_file; write_verilog -noattr $reports_dir/${name}_mapped.v"
    }

    if [[ -n "$liberty_file" ]]; then
        run_mapped inferred comparator_benchmark/rtl/comparator_inferred.sv comparator_inferred
        run_mapped tree comparator_benchmark/rtl/comparator_tree.sv comparator_tree
        run_mapped inferred_wrapper "comparator_benchmark/rtl/comparator_inferred.sv comparator_benchmark/rtl/comparator_tree.sv comparator_benchmark/rtl/comparator_alu_wrapper.sv" comparator_alu_wrapper 0
        run_mapped tree_wrapper "comparator_benchmark/rtl/comparator_inferred.sv comparator_benchmark/rtl/comparator_tree.sv comparator_benchmark/rtl/comparator_alu_wrapper.sv" comparator_alu_wrapper 1
    else
        printf 'Mapped synthesis unavailable: no common Liberty file found.\n' > "$reports_dir/inferred_mapped_synthesis.txt"
        printf 'Mapped synthesis unavailable: no common Liberty file found.\n' > "$reports_dir/tree_mapped_synthesis.txt"
    fi
fi

sta_bin=$(find_executable "$(command -v sta 2>/dev/null || true)" "$(command -v opensta 2>/dev/null || true)" \
    comparator_benchmark/.tool-cache/opensta/usr/bin/sta || true)
if [[ -z "$sta_bin" || -z "$liberty_file" ]]; then
    printf 'Static timing unavailable: no working OpenSTA-compatible executable on PATH or no Liberty file.\n' > "$timing_report"
else
    run_sta() {
        local name=$1
        local top=$2
        if LIBERTY_FILE="$liberty_file" NETLIST_FILE="$reports_dir/${name}_mapped.v" TOP_MODULE="$top" \
            "$sta_bin" comparator_benchmark/scripts/run_sta.tcl > "$reports_dir/${name}_timing.txt" 2>&1; then
            printf '%s timing completed.\n' "$name" >> "$timing_report"
        else
            printf '%s timing failed; see %s_timing.txt.\n' "$name" "$name" >> "$timing_report"
        fi
    }
    : > "$timing_report"
    echo "OpenSTA: $sta_bin" >> "$timing_report"
    echo "Constraints: comparator_benchmark/scripts/constraints.sdc" >> "$timing_report"
    run_sta inferred comparator_inferred
    run_sta tree comparator_tree
    run_sta inferred_wrapper comparator_alu_wrapper
    run_sta tree_wrapper comparator_alu_wrapper
fi

if [[ -n "$yosys_bin" ]]; then
    "$yosys_bin" -ql "$reports_dir/formal_equivalence.txt" -s comparator_benchmark/scripts/formal_equivalence.ys
elif command -v sby >/dev/null 2>&1; then
    sby -f comparator_benchmark/scripts/formal_equivalence.sby > "$reports_dir/formal_equivalence.txt" 2>&1 || true
else
    printf 'Formal equivalence unavailable: neither Yosys equivalence nor SymbiYosys is installed.\n' > "$reports_dir/formal_equivalence.txt"
fi

printf 'Power unavailable: no supported power-analysis tool/flow was detected; no numerical power estimate is reported.\n' > "$power_report"
printf 'Comparison flow completed. See tool_versions.txt and individual reports.\n'
