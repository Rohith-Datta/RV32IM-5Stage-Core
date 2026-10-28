# L1 I-Cache 10-Cycle Memory Burst Refill FSM

## State Machine Definition
The 2KB L1 Instruction Cache manages cache misses through a dedicated 4-state Mealy FSM.

### States
1. `IDLE / LOOKUP`: Evaluates `tag_match && valid` in 1 clock cycle.
2. `MISS_INIT`: Latches missed PC, halts core IF stage, and issues memory burst request.
3. `BURST_REFILL`: Iterates through cycles 1 to 10 streaming 16 bytes (4 words) from memory.
4. `LINE_UPDATE`: Writes tag and valid bits, routes fetched word directly to IF/ID register.
