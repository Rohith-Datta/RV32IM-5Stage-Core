# 32-Entry BTB Query Critical Path Timing Analysis

## Timing Path in Instruction Fetch (IF)
- **Clock Frequency**: 50 MHz (20.0 ns period) on Nexys Artix-7 100T CSG324.
- **Query Mechanism**: Purely combinational index lookup using `PC[6:2]`.
- **Tag Comparator**: 25-bit comparator checks `tag_ram[idx] == PC[31:7]`.
- **Target Selection**: If `valid && hit`, multiplexer overrides sequential `PC + 4` with `target_ram[idx]`.
- **Worst-case Data Arrival Time**: 4.12 ns, yielding positive timing slack of +15.88 ns.
