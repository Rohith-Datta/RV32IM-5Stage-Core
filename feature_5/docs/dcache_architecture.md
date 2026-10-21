# L1 Data Cache Architecture Specification

## Overview
The L1 Data Cache is a 2KB direct-mapped write-through cache designed for the RV32IMF 5-stage pipeline.

### Architectural Parameters
- **Capacity**: 2048 Bytes (2 KB)
- **Line Size**: 16 Bytes (4 words)
- **Set Count**: 128 cache lines
- **Policy**: Write-through with no-write-allocate on store misses
- **Hit Latency**: 1 clock cycle
