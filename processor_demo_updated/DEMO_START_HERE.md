> Latest update: see [REQUESTED_CHANGES.md](REQUESTED_CHANGES.md) for final profiler timing, IF-PC terminal display, SW9 prediction bypass, and the comparison demo.

# Clear demo revision: read this first

This revision supersedes the older guide's hybrid-trace and dashboard descriptions.
The hardware pin fix remains D4. Firmware and the nine-stall cache contract are unchanged.

## Run

1. Rebuild from this folder: `vivado -mode batch -source board/build_vivado.tcl -tclargs 40`.
2. Review routed timing/DRC, generate a NEW bitstream and program it.
3. Set switches to 0x2032: SW13, SW5, SW4, SW1 on; all others off.
4. Run `python -m pip install -r requirements.txt`, then `python dashboard.py`.
5. Choose the actual COM port. Hold physical CPU reset, click Reset / Clear Run, then release physical reset after the dashboard has connected.
6. Read the first 256 consecutive active-cycle rows. The log explicitly reports complete/incomplete coverage. Pause Auto-Scroll freezes viewing only; computation and reception continue.
7. Wait for the 57 startup CHECK records and 100 packet proof pairs. Click Save log to preserve the displayed evidence.

## What is shown

Each trace row contains cycle, WB PC, decoded WB instruction and pipeline stall/activity flags. A bubble has no valid WB instruction. A stall can concern another pipeline stage; do not attribute all flags to the displayed WB instruction. Multiple active causes are listed. No missing cycles are fabricated.

The default RTL transmits EVERY active cycle 0 through 255. Beyond that window it still sends FP commit snapshots for counters/mirrors, but the dashboard hides those sampled rows. After the window ends, proof records and profiler results continue. Missing/reordered cycles are explicitly flagged. This is a short boot window, not a 285,000-cycle trace and not a trace of the later EMA loop.

Every packet now produces a permanent FPGA/host result row and a CPOP/integer reference row. Zbb/int diagnostic results are labeled accordingly. All startup CHECK records remain visible. The full session fits comfortably below the 10,000-line retention cap with the bounded view. Save log exports the visible log, not the hidden raw metadata stream.

SW12 still requests full hardware tracing, but the dashboard intentionally displays only the bounded window. Keep SW12 OFF for this demo. SW11 throttles all core ticks to 10 Hz: 285,000 ticks would take roughly eight hours. Keep SW11 OFF; use Pause Auto-Scroll for explanation. Reset/Clear only clears the host; physical CPU reset starts a new hardware run.

## Demonstration sequence

- 0x2032: flight, caches on, alpha 50/255. Show smoothing plus FPU and CPOP matching rows.
- 0x6032: profiler, caches on. After reset, look for TIMING rows: REV8_WINDOW=1, DCACHE_HIT_SERVICE=1, DCACHE_MISS_PENALTY=9, FMUL_WINDOW=4, FDIV_WINDOW=15, DIV_WINDOW=32. These are defined benchmark windows, not all instruction latencies in arbitrary contexts. The host compares known values only when trace metadata confirms cache-enabled profiler mode.
- 0xA032: conflict stress. The graph still uses EMA; show counters/integer comparisons, not a new graph. Cache stress accesses conflict in the same direct-mapped line.
- 0xE001: positive infinity from 1.0/0.0; look for FPU FPGA=7F800000 HOST=7F800000.
- 0xE003: NaN from 0.0/0.0; look for FPU FPGA=7FC00000 HOST=7FC00000. NaN/infinity graph points are gaps by design. Use the hex proof log.
- 0xE006: negative zero; result 80000000.
- 0xE00A: signed MAX versus unsigned MAXU: result 00000005, integer result FFFFFFFF.
- 0xE00B: CLZ(0) and CTZ(0) packed as 00200020; integer result is CPOP(FFFFFFFF)=32, hexadecimal 00000020.

Set switches BEFORE a fresh reset for every demonstration. Diagnostic values are fixed vectors with independent host expectations. CHECK rows demonstrate additional Zbb and FPU operations. These checks cover specified cases, not exhaustive ISA compliance.

In the user's screenshot SW=A000 selects stress mode with alpha seed zero. Alpha zero keeps the filter at its first sample, so a flat green line is expected. Use A032 for a useful nonzero-alpha stress example. The UI now labels the actual mode explicitly.

## Validation and limits

See reports/demo_revision_regression.log and reports/demo_window_validation.log. Functional UART simulation does not certify physical pin operation, GUI rendering or routed timing. A fresh Vivado run is required because RTL capture selection changed. The earlier PDF is an architectural reference; this note is authoritative for the revised trace and UI behavior.
