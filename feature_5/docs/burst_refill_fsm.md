# L1 Data Cache Burst Refill FSM

## State Machine Definition
1. **IDLE**: Tag check against index.
2. **MISS_START**: Assert stall request to hazard unit.
3. **BURST_WAIT**: 9-cycle burst refill reading 4 consecutive words from backing memory.
4. **REFILL_DONE**: Update tag and valid bit, deliver word to CPU load bus.
