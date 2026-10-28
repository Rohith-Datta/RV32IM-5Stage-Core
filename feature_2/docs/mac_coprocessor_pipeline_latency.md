# 64-Bit Neural Network MAC Execution Latency and Throughput

## Performance Profile
- **Single Instruction Latency**: 1 clock cycle.
- **Consecutive MAC Throughput**: 1.0 IPC.
- **Register Hazard Forwarding**: Dedicated bypass routes ALU/MAC results directly into next-cycle MAC inputs.
- **FPGA Resource Footprint**: 2 DSP48E1 slices, 64 flip-flops, 112 LUTs.
