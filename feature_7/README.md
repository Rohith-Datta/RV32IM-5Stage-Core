# Feature 7: Branch Prediction (Static 32-Entry BTB)

## Objectives & Scope
Integration of a hardware **32-Entry Branch Target Buffer (BTB)** into the Fetch (IF) stage to eliminate the 2-cycle control hazard penalty on unconditional jumps and predicted-taken branches.

## Architectural Specifications
- **Table Capacity**: 32 entries (address-indexed with tag validation)
- **Entry Fields**:
  - `Valid Bit`: Indicates active cache entry
  - `Tag`: Instruction PC upper address bits
  - `Target PC`: Pre-computed target destination address
- **Static Prediction Policy**:
  - Unconditional jumps (`JAL`) always predicted taken
  - Conditional branches predicted using BTB hit status / static backwards-taken forward-not-taken heuristic
- **Pipeline Interconnect**:
  - **Fetch (IF)**: Searches BTB in parallel with instruction fetch; redirects PC on BTB hit
  - **Execute (EX)**: Resolves actual branch target and direction; updates or allocates BTB entry on misprediction and triggers 2-cycle recovery flush
