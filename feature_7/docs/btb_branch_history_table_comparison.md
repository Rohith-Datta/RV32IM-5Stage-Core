# Branch Target Buffer (BTB) Architecture Trade-Offs

## Branch Prediction Schemes Evaluation
On the 5-stage RISC-V core, branch resolution occurs in the Execute (EX) stage.

### Evaluated Configurations
1. **Direct-Mapped BTB (32 entries, target-only)**:
   - Hit latency: 0 penalty cycles.
   - Mispredict penalty: 2 penalty cycles (flushing IF/ID and ID/EX).
   - Resource cost: Minimal FPGA LUT footprint (< 150 LUTs).
2. **2-Bit Bimodal Saturating Counter (2BC)**:
   - Evaluated for loop-exit prediction stability.
   - Provides 88-92% accuracy on nested loops.
