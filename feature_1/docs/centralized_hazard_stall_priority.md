# Centralized Pipeline Hazard Unit Stall Prioritization

## Priority Ordering
When multi-cycle hardware units simultaneously request pipeline control:
1. **Branch Mispredict Flush (Highest)**: Clears IF/ID and ID/EX stages immediately.
2. **I-Cache Burst Refill Stall**: Stalls IF stage until 16-byte refill completes.
3. **D-Cache Store/Load Miss Stall**: Freezes IF, ID, and EX stages.
4. **Newton Raphson Method Divider Stall**: Freezes pipeline for 32 clock cycles.
5. **Load-Use Data Hazard Stall**: 1-cycle bubble insertion.
