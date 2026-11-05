# Timing-driven revision

## Evidence from the supplied routed report

Final WNS is -3.722 ns; TNS -836.123 ns; 446 setup-failing endpoints. Hold WNS is +0.016 ns with zero failing hold endpoints. The earlier console estimates were slightly different; the complete report is the source of these numbers.

The 50 MHz group has 157 failing endpoints and WNS -3.722 ns. The ten worst listed paths end at FPU fmul_final_res registers. The worst has 23.631 ns data delay, 39 logic levels (including 19 CARRY4 cells), and 14.893 ns routing delay.

Another 289 endpoints fail from pll_clock50 to sys_clk_pin (50 MHz to the 100 MHz display controller). WNS there is -3.450 ns. A representative path runs from ID/EX register selection through event logic to display stretch-counter enables, with 12.700 ns data delay against a 10 ns requirement.

## Implemented changes

1. Replaced the generic floating-point packer's serial MSB-priority search with a six-level binary search. Bounded exponent/shift calculations replace 32-bit integers, rounding increments only the required 25 significand bits, and discarded-bit detection uses a shift/mask plus reduction instead of 64 conditional comparisons. Existing FMUL/FDIV state counts and RNE results are preserved. This targets the actual worst listed arithmetic path without adding a pipeline cycle or imposing a false/multicycle timing exception.
2. Clocked the display controller from the ungated MMCM system clock, alongside the UART. Its register paths are now in the related system-clock domain, with a 20 ns nominal requirement at 50 MHz instead of the former 10 ns display capture requirement. The processor still uses a gated derivative; display scanning continues during UART backpressure and after program completion. LED stretch duration is derived from CLOCK_HZ to remain 20 ms.
3. Added SYSTEM_CLOCK_HZ selection for 50, 40, 31.25 or 25 MHz. The MMCM divide ratio, UART divisor, 10 Hz slow-step interval and display hold duration follow the selected frequency. The physical input-clock XDC remains 100 MHz. A simulation MMCM model supports fallback frequencies.
4. Each frequency now has its own Vivado project/report directory, allowing comparison without overwriting a different-frequency build. The script still stops for failed setup/hold timing and never generates a bitstream automatically.

## Build commands (from the extracted project)

    vivado -mode batch -source board/build_vivado.tcl -tclargs 50
    vivado -mode batch -source board/build_vivado.tcl -tclargs 40

Try the optimized 50 MHz build to determine whether it closes timing. Use 40 MHz as the next fallback; 31.25 and 25 are also accepted. At 40 MHz the cycle budget is 25 ns; at 25 MHz it is 40 ns. The old same-clock path suggests a nominal period near 23.722 ns, or 42.15 MHz, but this is only an estimate from the old routed design and excludes the old display-crossing problem. It is not an achieved maximum-frequency result.

Project paths: build/vivado_50mhz/avionics.xpr and build/vivado_40mhz/avionics.xpr. Reports: build/reports_50mhz/ and build/reports_40mhz/. The 31.25 MHz directory uses 31p25mhz. Inspect timing_summary.rpt, worst_paths.rpt, worst_hold_paths.rpt and drc.rpt before programming.

## Verification and limits

- timing_revision_tests.log: integration, 2,784 differential FPU vectors, directed FPU result/flag cases, integer edges, nine-stall-cycle caches, UART/trace transport, display, dashboard and board elaboration.
- pack_equivalence.log: 20,000 randomized magnitude/exponent/sign/sticky comparisons against the previous packer, including exception bits.
- timing_profiler_run.log and timing_profiler_results.log: 100 packets, 57 startup self-tests, and unchanged profiler windows (REV8=1, cache hit=1, miss penalty=9, FMUL=4, FDIV=15, DIV=32).
- timing_board_results.log and timing_board_* logs: complete 100-packet board/UART simulations at 50 and 40 MHz with host verification. Serial transfer is accelerated in those board testbenches; these are functional checks, not measured physical runtime.
- yosys_timing_revision.log: process-lowering and structural checks; generic cell counts are not FPGA utilization or timing signoff.

Vivado is unavailable in this workspace. No new routed WNS/Fmax is claimed, and hardware testing remains pending. Lower frequency improves setup budget but does not guarantee hold timing or eliminate other implementation problems; rerun the full routed checks for the selected frequency. Earlier timing reports describe prior revisions.
