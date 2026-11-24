#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$root"
exp=comparator_benchmark/signed_le_experiment
reports="$exp/reports"
mkdir -p "$reports"
yosys_bin=${YOSYS_BIN:-/home/harshan/harshan-project-2026/sha3-koika-archive-20261004/tool-cache/adder-eda/bin/yosys}
sta_bin=${STA_BIN:-comparator_benchmark/.tool-cache/opensta/usr/bin/sta}
lib=/home/harshan/harshan-project-2026/sha3-koika-archive-20261004/tool-cache/adder-eda/technology/typical.lib
tree_src="$exp/rtl/less_than_equal_tree.sv"
inferred_src="$exp/rtl/less_than_equal_inferred.sv"
optimized_src="$exp/rtl/less_than_equal_tree_optimized.sv"
alu_src="$exp/rtl/alu_wrappers.sv"

"$yosys_bin" -V > "$reports/tool_versions.txt"
"$sta_bin" -version >> "$reports/tool_versions.txt"
echo "Liberty: $lib" >> "$reports/tool_versions.txt"

generic() {
    local name=$1 top=$2 sources=$3 params=${4:-}
    "$yosys_bin" -ql "$reports/${name}_synthesis.txt" -p "read_verilog -sv $sources; $params hierarchy -check -top $top; proc; flatten; opt; techmap; opt; abc -g simple; clean; tee -o $reports/${name}_generic_stats.txt stat"
}
mapped() {
    local name=$1 top=$2 sources=$3 params=${4:-}
    "$yosys_bin" -ql "$reports/${name}_mapped_synthesis.txt" -p "read_verilog -sv $sources; $params hierarchy -check -top $top; proc; flatten; opt; techmap; opt; dfflibmap -liberty $lib; abc -liberty $lib; clean; tee -o $reports/${name}_mapped_stats.txt stat -liberty $lib; write_verilog -noattr $reports/${name}_mapped.v"
    LIBERTY_FILE="$lib" NETLIST_FILE="$reports/${name}_mapped.v" TOP_MODULE="$top" "$sta_bin" "$exp/scripts/run_sta.tcl" > "$reports/${name}_timing.txt" 2>&1
}

generic inferred less_than_equal_inferred "$inferred_src"
generic tree less_than_equal_tree "$tree_src"
generic optimized less_than_equal_tree_optimized "$optimized_src"
mapped inferred less_than_equal_inferred "$inferred_src"
mapped tree less_than_equal_tree "$tree_src"
mapped optimized less_than_equal_tree_optimized "$optimized_src"

: > "$reports/width_scaling_raw.txt"
for width in 8 16 32 64; do
    mapped "width${width}_inferred" less_than_equal_inferred_param "$inferred_src" "chparam -set WIDTH $width less_than_equal_inferred_param;"
    mapped "width${width}_tree" less_than_equal_tree_param "$tree_src" "chparam -set WIDTH $width less_than_equal_tree_param;"
    echo "WIDTH=$width" >> "$reports/width_scaling_raw.txt"
    rg 'Number of cells:|Chip area' "$reports/width${width}_inferred_mapped_stats.txt" "$reports/width${width}_tree_mapped_stats.txt" >> "$reports/width_scaling_raw.txt"
    rg 'Startpoint:|Endpoint:|data arrival time' "$reports/width${width}_inferred_timing.txt" "$reports/width${width}_tree_timing.txt" >> "$reports/width_scaling_raw.txt"
done

mapped alu_inferred rv64_alu_inferred "$tree_src $inferred_src $optimized_src $alu_src"
mapped alu_tree rv64_alu_tree "$tree_src $inferred_src $optimized_src $alu_src"
mapped alu_optimized rv64_alu_tree_optimized "$tree_src $inferred_src $optimized_src $alu_src"

for name in inferred tree; do
    "$yosys_bin" -p "read_liberty -lib $lib; read_verilog $reports/${name}_mapped.v; hierarchy -top less_than_equal_${name}; show -format dot -prefix $reports/${name}_netlist" > "$reports/${name}_diagram.log" 2>&1 || true
    if [[ -f "$reports/${name}_netlist.dot" ]]; then dot -Tsvg "$reports/${name}_netlist.dot" -o "$reports/${name}_netlist.svg"; fi
done
echo "SYNTHESIS_COMPLETE"
