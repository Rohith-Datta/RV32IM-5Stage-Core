# Validation of the requested update

Firmware rebuilt using GCC 13.2.0 for RV32IMF + Zicsr + Zbb. The ELF, binary,
disassembly and root memory initialization image are included and correspond
to the updated source. Icarus Verilog 12.0 was used for functional simulation.

- 14 RTL regressions passed, including the new prediction-bypass test.
- 29 dashboard tests passed.
- Nine firmware configurations passed strict independent host verification,
  including flight, profiler, cache bypass, stress and diagnostic operation.
- Full board/UART profiler runs passed in both settings: 100 telemetry packets,
  all 57 hardware checks, six correct timing windows after packet 99, 256
  consecutive IF-PC terminal rows, completion sentinel and LED0 observed.
- Late profiler entry also produced all six windows and correct packet results;
  the changed-switch run was correctly excluded from comparison history.

## Measured comparison

| Workload | Prediction | Active cycles | Retired instructions | IPC |
| --- | --- | ---: | ---: | ---: |
| Flight | ON | 287,423 | 243,649 | 0.847702 |
| Flight | BYPASS | 353,185 | 243,649 | 0.689862 |
| Profiler (board/UART) | ON | 288,068 | 243,929 | 0.846776 |
| Profiler (board/UART) | BYPASS | 353,830 | 243,929 | 0.689396 |

The profiler board run uses 65,762 more active cycles with bypass. Timing windows
are REV8=1, D-cache miss penalty=9, D-cache hit service=1, FMUL=4, FDIV=15,
DIV=32 in both prediction settings. Totals are sampled before final reporting;
UART transport clock-gating pauses are excluded. Firmware UART work is included.

These are functional simulation results, not measurements from a physical FPGA.
Vivado synthesis/place/route and board programming were not available here.
Rebuild the bitstream using the included memory image and check timing before
programming. Historical reports elsewhere in the archive are not new evidence.

See `rtl_regression.log`, `dashboard_tests.log`, `board_validation.log`,
`strict_host_validation.log` and the associated UART/dashboard transcripts here.
