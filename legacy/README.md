# legacy/

Early drafts kept for reference only. They are not part of the build, do not
compile, and are superseded by the v1.0.0 RTL:

| File | Original location | Superseded by |
|---|---|---|
| `pc_32bit.sv` | `rtl/pc.sv` | PC logic in `rtl/if/fetch_unit.sv` |
| `pc_64bit.sv` | `rtl/pc/pc.sv` | PC logic in `rtl/if/fetch_unit.sv` |
| `or_gate_root.sv` | `./or_gate.sv` | `rtl/ex/alu/alu_modules/or_gate.sv` |

Safe to delete once the project is under version control.
