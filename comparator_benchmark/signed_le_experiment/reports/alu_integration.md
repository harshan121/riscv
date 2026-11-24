# Minimal RV64 ALU Integration

Each top preserves externally selectable ADD, SUB, signed `<=`, and pass-B operations. Area is reported in Nangate45 library units; delay is OpenSTA input-to-output delay under the common virtual-clock constraints.

| Wrapper | Cells | Area | Delay (ns) | Critical path |
|---|---:|---:|---:|---|
| Inferred | 951 | 981.806 | 2.3244 | `b[1]` -> `result[63]` |
| Original tree | 1053 | 1069.320 | 1.5940 | `a[1]` -> `result[63]` |
| Optimized tree | 1066 | 1074.374 | 1.6684 | `b[2]` -> `result[63]` |

The original tree reduces delay by 31.42% against the inferred ALU wrapper, but increases area by 8.91%. The optimized tree is 28.22% faster and 9.43% larger. This confirms that comparator-level PPA does not directly predict ALU-level PPA.
