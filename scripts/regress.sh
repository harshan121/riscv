#!/usr/bin/env bash
# Full regression: every predictor config x memory latency x random AXI
# back-pressure, for each system test, plus the exhaustive RVC expander test.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

V="--binary --timing -Wno-fatal -Wno-UNOPTFLAT -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Itb -f rtl/files.f tb/axi_lite_mem.sv"
CONFIGS=("static 0 0 0" "bimodal 1 0 0" "gshare 1 1 0" "bimodal_ras 1 0 1" "gshare_ras 1 1 1")
pass=0; fail=0

mkdir -p build
python3 tb/rvc_ref.py build/rvc_golden.txt
mkdir -p build/reg/rvc_expand
verilator --binary --timing -Wno-fatal -Wno-TIMESCALEMOD --top-module tb_rvc_expand -Mdir build/reg/rvc_expand \
    rtl/riscv_pkg.sv rtl/if/rvc_expander.sv tb/tb_rvc_expand.sv -o V >/dev/null 2>&1
if build/reg/rvc_expand/V | grep -q '^PASS'; then echo "PASS rvc_expand (49152 encodings)"; pass=$((pass+1)); else echo "FAIL rvc_expand"; fail=$((fail+1)); fi

for cfg in "${CONFIGS[@]}"; do
    read -r name en gs ras <<< "$cfg"
    for lat in 1 3; do
        for rnd in 0 1; do
            for tb in tb_core tb_hazard tb_rvc tb_fault; do
                d=build/reg/${name}_${lat}_${rnd}_$tb; mkdir -p $d
                verilator $V --top-module $tb -GBP_ENABLE=$en -GUSE_GSHARE=$gs -GENABLE_RAS=$ras \
                    -GMEM_LAT=$lat -GRAND_STALL=$rnd -Mdir $d tb/$tb.sv -o V >/dev/null 2>&1
                runs=("")
                [[ $tb == tb_fault ]] && runs=(+CASE=0 +CASE=1 +CASE=2 +CASE=3 +CASE=4 +CASE=5 +CASE=6 +CASE=7 +CASE=8 +CASE=9)
                for arg in "${runs[@]}"; do
                    out=$($d/V $arg 2>&1)
                    if grep -q '^PASS' <<< "$out" && ! grep -q '%Error' <<< "$out"; then
                        pass=$((pass+1))
                    else
                        fail=$((fail+1)); echo "FAIL $name lat=$lat rand=$rnd $tb $arg"
                        grep -E 'FAIL|Error' <<< "$out" | head -5
                    fi
                done
            done
        done
    done
    echo "   $name done"
done
echo "regression: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
