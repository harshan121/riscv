# Width Scaling

All rows use independently mapped parameterized tops, the same Nangate45 library, and the same 1 ns virtual-clock constraints.

| Width | Inferred cells | Tree cells | Inferred area | Tree area | Inferred delay (ns) | Tree delay (ns) |
|---:|---:|---:|---:|---:|---:|---:|
| 8 | 30 | 19 | 30.058 | 17.822 | 0.2992 | 0.3066 |
| 16 | 61 | 54 | 59.052 | 51.072 | 0.4190 | 0.3634 |
| 32 | 134 | 115 | 132.468 | 106.400 | 0.4213 | 0.4222 |
| 64 | 267 | 231 | 262.542 | 221.578 | 0.6105 | 0.4954 |

The tree's RTL has logarithmic six-level reduction at 64 bits, but mapped delay is not monotonic purely by level count: library cell choices and Boolean restructuring dominate at 8 and 32 bits. At 64 bits the tree is both smaller and faster in this parameterized measurement.
