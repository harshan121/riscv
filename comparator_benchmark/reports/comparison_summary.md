# RV64 Comparator Benchmark Results

## Configuration and evidence

- Functional simulator: Verilator 5.032 (2025-01-01).
- Synthesis/formal engine: Yosys 0.52 (`fee39a3284c90249e1d9684cf6944ffbbcbb8f90`).
- Timing engine: OpenSTA 2.0.17, locally extracted into the experiment cache.
- Mapping library: Nangate45 `typical.lib`, 1.10 V nominal, 25 C nominal,
  1 ns time unit, and 1 ff capacitance unit.
- Constraints: 1.000 ns virtual clock, 0.100 ns input and output delays, and
  0.010 output load, identically applied to both designs.
- Functional workload: 15 directed pairs plus 100,000 deterministic random
  pairs; total 100,015 pairs.  Both designs had 0 mismatches.
- Formal: Yosys `equiv_simple` proved all four outputs equivalent for all
  64-bit input combinations; see `formal_equivalence.txt`.

## Standalone mapped comparison

| Metric | Inferred Comparator | Custom Tree | Difference (custom - inferred) |
|---|---:|---:|---:|
| Functional verification | PASS, 0/100,015 mismatches | PASS, 0/100,015 mismatches | 0 |
| Formal equivalence | Proven | Proven equivalent | N/A |
| Generic logic cells | 417 | 406 | -11 |
| Mapped standard cells | 275 | 256 | -19 (-6.91%) |
| Cell area (library units) | 272.118 | 252.966 | -19.152 (-7.04%) |
| Critical-path delay (ns) | 0.5789 | 0.4798 | -0.0991 (-17.12%) |
| Logic depth (cell arcs) | 12 | 9 | -3 |
| Critical path | `a[11]` -> `signed_lte` | `a[38]` -> `signed_lte` | Different sensitized path |
| Slack at 1 ns (ns) | 0.3211 | 0.4202 | +0.0991 |
| Estimated dynamic power | N/A | N/A | No supported power flow |
| Estimated leakage power | N/A | N/A | No supported power flow |

`Area reduction = (272.118 - 252.966) / 272.118 * 100 = 7.04%`.

`Delay improvement = (0.5789 - 0.4798) / 0.5789 * 100 = 17.12%`.

Positive reduction/improvement values favor the custom tree.

## Identical wrapper integration comparison

The common wrapper accepts `a`, `b`, and a two-bit operation select for SLT,
SLTE, SLTU, or SLTUE. The physical cell count excludes Yosys's one
non-physical `$scopeinfo` metadata cell in each wrapper result.

| Metric | Inferred Wrapper | Custom-Tree Wrapper | Difference (custom - inferred) |
|---|---:|---:|---:|
| Physical mapped cells | 260 | 277 | +17 (+6.54%) |
| Cell area (library units) | 259.616 | 270.522 | +10.906 (+4.20%) |
| Critical-path delay (ns) | 0.4742 | 0.4675 | -0.0067 (-1.41%) |
| Logic depth (cell arcs) | 9 | 9 | 0 |
| Critical path | `a[22]` -> `result` | `a[62]` -> `result` | Different sensitized path |
| Slack at 1 ns (ns) | 0.4258 | 0.4325 | +0.0067 |

After integration, the tree's area reduction is **-4.20%** (that is, it is
larger) while its delay improvement is only **1.41%**. The standalone result
therefore does not fully predict the wrapper result.

## Structural analysis

1. **Yosys implementation of relational operators:** Yosys lowered the
   inferred signed/unsigned relations into Boolean comparison logic, then ABC
   remapped it into a mixed AOI/OAI/NAND/NOR/XOR network. It was not preserved
   as one opaque comparator cell.
2. **Subtractor/carry/tree resemblance:** The mapped inferred netlist is an
   optimized comparison network with complex gates; the reports do not
   justify calling it a simple ripple subtractor or a dedicated carry chain.
3. **Custom-tree structure:** The RTL explicitly builds six high-priority
   `LT_H | (EQ_H & LT_L)`/`EQ_H & EQ_L` levels from 64 bit leaves. ABC retains
   a shallower critical path in this standalone mapping, although it changes
   the exact gate decomposition.
4. **Area:** Standalone, the explicit tree is 7.04% smaller. In the wrapper,
   the added operation mux and restructuring reverse that result and make it
   4.20% larger.
5. **Timing:** Standalone, the tree removes three mapped cell arcs and improves
   the measured path by 17.12%. Wrapper timing is nearly tied: 1.41% in favor
   of the tree.
6. **Fanout/routing:** The tree distributes equality signals at each level and
   exposes regular internal boundaries. This can increase local fanout and
   routing demand; this cell-level experiment does not include placement or
   routed parasitics, so it is not a physical-routing conclusion.
7. **Synthesis restructuring:** Both designs are substantially rewritten into
   complex standard cells. The final wrapper area reversal demonstrates that
   RTL topology alone does not lock down mapped PPA.
8. **Equality sharing:** The tree shares its final equality root across both
   `<=` outputs, avoiding separate equality comparators. Yosys similarly
   shares/optimizes logic where profitable in the inferred implementation.
9. **Recommendation:** Use the **inferred comparator** in the RV64 ALU unless
   post-layout timing specifically requires the small tree-wrapper timing
   advantage. It is simpler to verify and, in the integration measurement,
   uses 4.20% less mapped area with only 6.7 ps more delay. The custom tree is
   a valid timing-oriented alternative for a standalone comparator, not an
   automatic default.

## Limitations

- The local OpenSTA package supplied timing, but no supported power-analysis
  flow was available; the VCD is retained for a future power run and no power
  numbers are claimed.
- Results are pre-layout standard-cell estimates. Routing congestion,
  wire parasitics, and the processor's real ALU control/data context can
  change the final trade-off.
- The benchmark does not alter or compile the existing processor ALU, by
  design.
