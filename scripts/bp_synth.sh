#!/usr/bin/env bash
# Synthesize branch_predictor in each configuration (Yosys + Nangate45),
# then time it with OpenSTA. Appends area/timing to reports/bp_benchmark.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

TOOLS=/home/harshan/harshan-project-2026/sha3-koika-archive-20261004/tool-cache/adder-eda
YOSYS=${YOSYS:-$(command -v yosys || echo $TOOLS/bin/yosys)}
STA=${STA:-$(command -v sta || echo comparator_benchmark/.tool-cache/opensta/usr/bin/sta)}
LIB=${LIB:-$TOOLS/technology/typical.lib}
SRC="rtl/bp/btb.sv rtl/bp/direction_predictor.sv rtl/bp/ras.sv rtl/bp/branch_predictor.sv"
D=build/bp_synth; mkdir -p $D

CONFIGS=("static      0 0 0"
         "bimodal     1 0 0"
         "gshare      1 1 0"
         "bimodal_ras 1 0 1"
         "gshare_ras  1 1 1")

# Delay-oriented mapping with buffering / gate sizing. Plain `abc -liberty`
# never buffers, so high-fanout table-index nets show up as tens of ns.
cat > $D/abc.script <<'ABC'
strash
dch -f
map -D 1000
buffer -N 8
upsize -D 1000
dnsize -D 1000
stime -p
ABC

cat > $D/clk.sdc <<'SDC'
create_clock -name clk -period 2.000 [get_ports clk]
set_input_delay  0.0 -clock clk [delete_from_list [all_inputs] [get_ports clk]]
set_output_delay 0.0 -clock clk [all_outputs]
set_load 0.010 [all_outputs]
SDC

res=$D/results.txt; : > $res
for cfg in "${CONFIGS[@]}"; do
    read -r name en gs ras <<< "$cfg"
    echo "== $name"
    "$YOSYS" -ql $D/$name.log -p "
        read_verilog -sv $SRC
        chparam -set BP_ENABLE $en -set USE_GSHARE $gs -set ENABLE_RAS $ras branch_predictor
        synth -flatten -top branch_predictor
        dfflibmap -liberty $LIB
        abc -liberty $LIB -script $D/abc.script
        opt_clean
        tee -o $D/$name.stat stat -liberty $LIB
        write_verilog -noattr $D/$name.v"
    area=$(awk '/Chip area for module/ {print $NF}' $D/$name.stat)
    cells=$(awk '/Number of cells/ {print $NF; exit}' $D/$name.stat)
    ffs=$(awk '$1 ~ /^(S|)DFF/ {s+=$2} END {print s+0}' $D/$name.stat)

    cat > $D/$name.tcl <<TCL
read_liberty $LIB
read_verilog $D/$name.v
link_design branch_predictor
read_sdc $D/clk.sdc
report_checks -path_delay max -from [get_ports lookup_pc*] -to [get_ports pred_target*] -digits 3 > $D/${name}_fetch.rpt
report_checks -path_delay max -digits 3 > $D/${name}_worst.rpt
exit
TCL
    "$STA" -no_splash $D/$name.tcl >/dev/null 2>&1 || true
    fetch=$(awk '/data arrival time/ {print $1; exit}' $D/${name}_fetch.rpt 2>/dev/null || echo NA)
    worst=$(awk '/data arrival time/ {print $1; exit}' $D/${name}_worst.rpt 2>/dev/null || echo NA)
    echo "$name $area $cells $ffs ${fetch:-NA} ${worst:-NA}" | tee -a $res
done

python3 - $res reports/bp_benchmark.md <<'PY'
import sys, re
rows = [l.split() for l in open(sys.argv[1])]
md = open(sys.argv[2]).read()
md = re.sub(r'\n## Hardware cost.*', '', md, flags=re.S)
md += ('\n## Hardware cost (branch_predictor alone, Yosys + Nangate45 typical, OpenSTA)\n\n'
       'Pre-layout: ABC buffering (max fanout 8) and gate sizing, no wire parasitics. 2 ns clock.\n\n'
       '| Config | Area (um^2) | Cells | Flip-flops | Fetch path lookup_pc -> pred_target (ns) | Worst path (ns) |\n'
       '|---|---:|---:|---:|---:|---:|\n')
for n, a, c, f, fp, w in rows:
    md += f'| {n} | {float(a):,.0f} | {c} | {f} | {fp} | {w} |\n'
open(sys.argv[2], 'w').write(md)
PY
tail -9 reports/bp_benchmark.md
