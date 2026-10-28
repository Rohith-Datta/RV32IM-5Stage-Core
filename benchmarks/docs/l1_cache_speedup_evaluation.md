# L1 Cache Speedup Benchmark Evaluation

## Benchmark Suites
Evaluated on vector matrix multiply, FIR filtering, and Fibonacci loops.

### Results
| Workload | Hardware Bypass Mode (CPI) | 2KB L1 I/D Cache Active (CPI) | Speedup |
| :--- | :---: | :---: | :---: |
| **Matrix Multiplication** | 4.82 | 1.18 | **4.08x** |
| **FIR Filter Loop** | 3.95 | 1.12 | **3.53x** |
| **Fibonacci Sequence** | 3.20 | 1.05 | **3.05x** |
