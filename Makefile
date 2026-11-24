# Kreacher RV64IC baseline core
#
#   make lint        Verilator lint of the core (-Wall)
#   make test        lint + all directed tests (quick, ~1-2 min)
#   make regress     every predictor config x memory latency x AXI back-pressure
#   make bench       branch predictor benchmark  -> reports/bp_benchmark.md
#   make synth_bp    predictor area / timing     -> reports/bp_benchmark.md
#   make clean

VFLAGS = --binary --timing -Wno-fatal -Wno-UNOPTFLAT -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Itb
SRCS   = -f rtl/files.f
TBLIB  = tb/axi_lite_mem.sv

.PHONY: lint sim sim_pad hazard rvc rvc_expand fault test regress bench synth_bp clean

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-EOFNEWLINE -Wno-GENUNNAMED \
		-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-UNOPTFLAT --top-module core $(SRCS)

# Functional test, instructions back-to-back (exercises forwarding/stalls)
sim:
	verilator $(VFLAGS) --top-module tb_core -GPAD=0 -Mdir build/obj_core $(SRCS) $(TBLIB) tb/tb_core.sv -o Vtb_core
	./build/obj_core/Vtb_core

# Same program with 2 NOPs after each instruction (no hazards)
sim_pad:
	verilator $(VFLAGS) --top-module tb_core -GPAD=2 -Mdir build/obj_core_pad $(SRCS) $(TBLIB) tb/tb_core.sv -o Vtb_core
	./build/obj_core_pad/Vtb_core

# Directed hazard test
hazard:
	verilator $(VFLAGS) --top-module tb_hazard -Mdir build/obj_hazard $(SRCS) $(TBLIB) tb/tb_hazard.sv -o Vtb_hazard
	./build/obj_hazard/Vtb_hazard

# Compressed (RVC) code on the full core
rvc:
	verilator $(VFLAGS) --top-module tb_rvc -Mdir build/obj_rvc $(SRCS) $(TBLIB) tb/tb_rvc.sv -o Vtb_rvc
	./build/obj_rvc/Vtb_rvc

# Exhaustive RVC expander check against the Python reference
rvc_expand:
	mkdir -p build && python3 tb/rvc_ref.py build/rvc_golden.txt
	verilator --binary --timing -Wno-fatal -Wno-TIMESCALEMOD --top-module tb_rvc_expand -Mdir build/obj_rvc_expand \
		rtl/riscv_pkg.sv rtl/if/rvc_expander.sv tb/tb_rvc_expand.sv -o V
	./build/obj_rvc_expand/V

# Fault handling: illegal / ecall / misaligned / AXI errors (10 cases)
fault:
	verilator $(VFLAGS) --top-module tb_fault -Mdir build/obj_fault $(SRCS) $(TBLIB) tb/tb_fault.sv -o Vtb_fault
	@fail=0; for c in 0 1 2 3 4 5 6 7 8 9; do \
		if ./build/obj_fault/Vtb_fault +CASE=$$c | grep -q '^PASS'; then echo "fault case $$c PASS"; \
		else echo "fault case $$c FAIL"; fail=1; fi; done; exit $$fail

test: lint sim sim_pad hazard rvc rvc_expand fault

# All predictor configs x memory latency x random AXI back-pressure
regress:
	./scripts/regress.sh

# Branch predictor: 5 configs x (correctness tests + benchmark programs)
bench:
	./scripts/bp_bench.sh

# Branch predictor area / timing per config (Yosys + Nangate45 + OpenSTA)
synth_bp:
	./scripts/bp_synth.sh

clean:
	rm -rf build
