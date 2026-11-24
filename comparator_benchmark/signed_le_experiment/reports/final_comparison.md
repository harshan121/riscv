# Signed 64-bit `<=` Comparator Comparison

## Verification

- Verilator: **100,016 tests, 0 mismatches**, including directed sign/extreme/bit-pattern cases and 100,000 deterministic random pairs.
- Formal: **FORMAL_EQUIVALENCE_PASS**. Yosys created assertion miters and SAT-proved original-tree and optimized-tree results equal to the inferred comparator for all 64-bit inputs.

## Standalone 64-bit results

| Metric | Inferred `<=` | Original custom tree | Optimized tree |
|---|---:|---:|---:|
| Generic cell count | 483 | 476 | 466 |
| Mapped cell count | 268 | 244 | 232 |
| Cell area | 262.542 | 236.208 | 223.440 |
| Critical-path delay (ns) | 0.6105 | 0.5296 | 0.5204 |
| Critical path | `a[22]` -> `result` | `a[0]` -> `result` | `a[59]` -> `result` |
| Estimated power | N/A | N/A | N/A |

Original tree vs inferred: **10.03% area reduction** and **13.25% delay improvement**. Optimized tree vs inferred: **14.89% area reduction** and **14.76% delay improvement**.

## Netlist inspection

Yosys mapped the inferred relational operator into an AOI/OAI/NAND/NOR/XOR comparison network; there is no evidence of a preserved single subtractor or dedicated carry-chain cell. The explicit tree maps into the same standard-cell vocabulary, but its MSB-priority LT/EQ decomposition survives enough restructuring to yield a shorter measured standalone path. Intermediate equality nets are aggressively absorbed into AOI/OAI gates, so the mapped netlist is not a literal one-gate-per-tree-node rendering.

Generated mapped-netlist diagrams are available as `inferred_netlist.svg` and `tree_netlist.svg`. The tree exposes equality terms at every level, increasing local fanout/routing opportunities; these pre-layout results do not include placement or parasitic wiring.

## Conclusion

The supplied MSB-first signed tree is correct. In this Nangate45/OpenSTA experiment it produces a better standalone circuit than the inferred relation, and the separate optimized form improves further. Inside the deliberately complete minimal ALU, the tree still improves timing substantially but costs area. Therefore:

- Choose the **original custom tree** for a timing-constrained RV64 ALU stage where ~9% area growth is acceptable.
- Choose the **inferred comparator** when area/simplicity dominate.
- Treat the optimized tree as an additional candidate, not an automatic replacement: it has the best standalone PPA here but loses some ALU timing versus the original tree.

The key lesson is that an explicit parallel algorithm gives synthesis useful structure, but mapping and surrounding mux/arithmetic logic decide the real PPA result. Always measure the integrated, constrained netlist rather than assuming logarithmic RTL depth wins.

## Limits

No supported power flow was available, so no dynamic or leakage power was fabricated. These are pre-layout cell-library estimates; routed parasitics may alter the ranking.
