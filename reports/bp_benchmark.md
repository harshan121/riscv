# Branch predictor benchmark

> Generated before fault handling was added to v1.0.0-baseline: `ebreak` now
> stops the core in MEM instead of WB, so cycle / retired counts may differ by
> one. Prediction accuracy is unaffected. Re-run `make bench` to refresh.

Same programs and memory for every configuration; 64-entry BTB, 64 2-bit counters, 6-bit global history, 8-entry RAS. AXI4-Lite memories with 1-cycle latency (every load/store costs one extra cycle). Mispredict penalty = 3 cycles.

## Cycles (CPI)

| Program | static | bimodal | gshare | bimodal_ras | gshare_ras |
|---|---:|---:|---:|---:|---:|
| loop | 506 (2.49) | 215 (1.06) | 233 (1.15) | 215 (1.06) | 233 (1.15) |
| nested | 637 (1.91) | 379 (1.13) | 409 (1.22) | 379 (1.13) | 409 (1.22) |
| alternating | 907 (2.00) | 766 (1.69) | 487 (1.07) | 766 (1.69) | 487 (1.07) |
| correlated | 3609 (1.50) | 3066 (1.27) | 2757 (1.15) | 3066 (1.27) | 2757 (1.15) |
| calls | 687 (2.60) | 408 (1.55) | 426 (1.61) | 291 (1.10) | 309 (1.17) |

## Mispredicts / branches+jumps (accuracy)

| Program | static | bimodal | gshare | bimodal_ras | gshare_ras |
|---|---:|---:|---:|---:|---:|
| loop | 99/100 (1.0%) | 2/100 (98.0%) | 8/100 (92.0%) | 2/100 (98.0%) | 8/100 (92.0%) |
| nested | 99/110 (10.0%) | 13/110 (88.2%) | 23/110 (79.1%) | 13/110 (88.2%) | 23/110 (79.1%) |
| alternating | 149/200 (25.5%) | 102/200 (49.0%) | 9/200 (95.5%) | 102/200 (49.0%) | 9/200 (95.5%) |
| correlated | 399/600 (33.5%) | 218/600 (63.7%) | 115/600 (80.8%) | 218/600 (63.7%) | 115/600 (80.8%) |
| calls | 140/141 (0.7%) | 47/141 (66.7%) | 53/141 (62.4%) | 8/141 (94.3%) | 14/141 (90.1%) |

## Hardware cost (branch_predictor alone, Yosys + Nangate45 typical, OpenSTA)

Pre-layout: ABC buffering (max fanout 8) and gate sizing, no wire parasitics. 2 ns clock.

| Config | Area (um^2) | Cells | Flip-flops | Fetch path lookup_pc -> pred_target (ns) | Worst path (ns) |
|---|---:|---:|---:|---:|---:|
| static | 189 | 178 | 0 | 0.903 | 0.903 |
| bimodal | 68,017 | 40335 | 8064 | 0.944 | 0.944 |
| gshare | 68,106 | 40471 | 8070 | 1.156 | 1.156 |
| bimodal_ras | 73,192 | 43970 | 8579 | 1.059 | 1.117 |
| gshare_ras | 74,072 | 45758 | 8585 | 1.084 | 1.102 |
