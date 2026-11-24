#!/usr/bin/env bash
# Branch predictor benchmark: builds the core in 5 predictor configurations,
# runs the correctness tests and the tb_bp programs on each, and writes
# reports/bp_benchmark.md. Run from the repository root.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

VFLAGS="--binary --timing -Wno-fatal -Wno-UNOPTFLAT -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Itb -f rtl/files.f tb/axi_lite_mem.sv"

#        name        BP_ENABLE USE_GSHARE ENABLE_RAS
CONFIGS=("static      0 0 0"
         "bimodal     1 0 0"
         "gshare      1 1 0"
         "bimodal_ras 1 0 1"
         "gshare_ras  1 1 1")
PROGS=(loop nested alternating correlated calls)

out=reports/bp_benchmark.md
raw=build/bp_results.txt
mkdir -p build; : > "$raw"
fail=0

for cfg in "${CONFIGS[@]}"; do
    read -r name en gs ras <<< "$cfg"
    G="-GBP_ENABLE=$en -GUSE_GSHARE=$gs -GENABLE_RAS=$ras"
    echo "== $name"

    for tb in tb_core tb_hazard tb_rvc tb_bp; do
        mkdir -p build/bp_$name/$tb
        verilator $VFLAGS --top-module $tb $G -Mdir build/bp_$name/$tb tb/$tb.sv -o V >/dev/null 2>&1
    done
    for tb in tb_core tb_hazard tb_rvc; do
        if build/bp_$name/$tb/V | grep -q '^PASS'; then echo "   $tb PASS"; else echo "   $tb FAIL"; fail=1; fi
    done
    for i in "${!PROGS[@]}"; do
        line=$(build/bp_$name/tb_bp/V +PROG=$i | grep '^RESULT')
        echo "   $line"
        echo "$name $line" >> "$raw"
        [[ $line == *errors=0* ]] || fail=1
    done
done

python3 - "$raw" "$out" <<'PY'
import sys, re, collections
rows = collections.OrderedDict()
for line in open(sys.argv[1]):
    cfg, rest = line.split(' ', 1)
    d = dict(re.findall(r'(\w+)=(\S+)', rest))
    rows.setdefault(d['prog'], {})[cfg] = d
cfgs = ['static', 'bimodal', 'gshare', 'bimodal_ras', 'gshare_ras']
with open(sys.argv[2], 'w') as f:
    f.write('# Branch predictor benchmark\n\n')
    f.write('Same programs and memory for every configuration; 64-entry BTB, 64 2-bit counters, '
            '6-bit global history, 8-entry RAS. AXI4-Lite memories with 1-cycle latency '
            '(every load/store costs one extra cycle). Mispredict penalty = 3 cycles.\n\n')
    f.write('## Cycles (CPI)\n\n| Program | ' + ' | '.join(cfgs) + ' |\n|---|' + '---:|' * len(cfgs) + '\n')
    for p, r in rows.items():
        cells = [f"{r[c]['cycles']} ({int(r[c]['cycles'])/int(r[c]['retired']):.2f})" for c in cfgs]
        f.write(f'| {p} | ' + ' | '.join(cells) + ' |\n')
    f.write('\n## Mispredicts / branches+jumps (accuracy)\n\n| Program | ' + ' | '.join(cfgs) + ' |\n|---|' + '---:|' * len(cfgs) + '\n')
    for p, r in rows.items():
        cells = []
        for c in cfgs:
            m, n = int(r[c]['mispred']), int(r[c]['ctrl'])
            cells.append(f"{m}/{n} ({100*(n-m)/n:.1f}%)")
        f.write(f'| {p} | ' + ' | '.join(cells) + ' |\n')
print(open(sys.argv[2]).read())
PY
exit $fail
