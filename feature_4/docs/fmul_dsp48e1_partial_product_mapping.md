# DSP48E1 Cascaded Multiplier Mapping for 24x24 FMUL

## FPGA Implementation
On Xilinx Artix-7 100T CSG324:
- DSP Slice 0 computes: $A[16:0] \times B[23:0]$ (17x24 unsigned).
- DSP Slice 1 computes: $A[23:17] \times B[23:0]$ shifted by 17 bits.
- Internal dedicated carry chains perform the sum with sub-nanosecond delay.
