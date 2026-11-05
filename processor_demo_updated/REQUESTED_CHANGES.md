# Profiler, fetch PC and branch-prediction switch update

## Use the updated project

Use this folder as the Vivado source project and run the included dashboard.py.
The firmware memory image must match these sources. Rebuild and program the FPGA:
changing Python alone does not enable SW9 or the new end-of-run records.

1. Start the dashboard and connect before resetting the board.
2. Keep SW12 (verbose) and SW11 (10 Hz stepping) OFF for a practical demo.
3. Set `0x6032` for profiler mode, caches ON, prediction ON; reset the board.
4. After packet 99, six measured timing records appear, followed by the final
   profiler timing summary and run totals. The host retains earlier timing
   records too, so old compatible logs also get a summary at completion.
5. For the comparison, clear the dashboard, turn SW9 ON (`0x6232`), and reset
   the board. Keep every other switch unchanged. The second completion shows
   both cycle counts, both IPC values, extra cycles with bypass, and IPC gain.
   Either run order works. Keep the same dashboard process and input source;
   Clear preserves the comparison pair while clearing the current run.

| Switch / setting | Meaning |
| --- | --- |
| SW9 OFF | Branch prediction ON; original behavior |
| SW9 ON | Branch prediction BYPASS; fetch PC+4 until EX resolves a branch/jump |
| SW8 | Still reserved |
| `0x2032` / `0x2232` | Flight mode with prediction ON / BYPASS |
| `0x6032` / `0x6232` | Profiler mode with prediction ON / BYPASS |

Set switches before resetting and leave them unchanged for comparable runs.
The firmware detects configuration changes observed during packet polling and
at the final sample; do not flick switches between polls. Hardware prediction
metadata is captured with each instruction, and EX recovery remains active in
both modes. The BTB continues training during bypass; reset gives each measured
run the same cold starting state.

## What changed

- Profiler measurements are collected on the first packet executed in profiler
  mode (including entering that mode after packet zero), buffered, and sent
  after all 100 packets. The dashboard also repeats them at completion.
- Terminal trace rows use **IF PC** from the same hardware snapshot. Instruction
  decoding is explicitly labelled **WB instruction**, since it belongs to a
  different pipeline stage. Legacy traces without IFPC show "unavailable";
  the dashboard never substitutes WB PC as an IF address. The existing raw
  UART format remains compatible: raw `PC:` is WB; `IFPC=` is fetch.
- SW9 is wired through the board, core and pipeline to fetch. Bypass masks both
  the predicted next PC and prediction metadata while preserving redirects.
- Firmware emits `RUN_STATS,SW,CYCLES,INSTRET,CHANGED` (eight-digit hex fields).
  Cycles and retired instructions are sampled immediately before final reports.
  These are active-core totals from reset, including startup checks, workload,
  and software UART overhead. Hardware UART clock-gating pauses do not count.
  IPC is measured retired instructions divided by measured cycles. It is not
  wall-clock throughput or a claim that every program benefits equally.
- The dashboard compares only complete, passing runs with the same source and
  switch word except SW9. Measurements are shown as received, not forced to
  indicate an improvement. A fresh process starts a fresh comparison history.

## Build and validate

```sh
make -C firmware
python tools/run_tests.py
REPORT_PREFIX=reports/requested_changes python tests/run_modes.py vvp 2032 2232 6032 6232 0032 0232 a032 a232 e203
python tests/check_profiles.py reports/requested_changes/uart_6032.log
vvp reports/firmware.vvp +SW=2032 +SW_CYCLE=120000 +SW_LATER=6032 +LOG=reports/requested_changes/late_profiler_uart.log
python tools/run_requested_validation.py
python tools/verify_requested_results.py
```

`run_requested_validation.py` executes full board/UART simulations for the two
profiler switch settings and validates actual received records and final order.
All new validation evidence is under `reports/requested_changes/`; older reports
and architecture documents are retained as historical reference.

In Vivado, use `board/nexys_a7_top.v` as top and include the rebuilt
`avionics_demo.mem`. The existing `board/build_vivado.tcl` performs synthesis,
routing and timing checks. Generate and program the bitstream after successful
timing/DRC review. Simulation does not establish physical-board timing closure.
