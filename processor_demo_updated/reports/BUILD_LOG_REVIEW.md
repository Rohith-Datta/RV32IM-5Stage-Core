# Vivado log review and follow-up revision

The supplied log is from Vivado 2025.2 targeting xc7a100tcsg324-1. Synthesis completed and implementation entered routing. The pasted log ends in Phase 5.1; it does not show a completed route, final timing results, or bitstream generation.

The intermediate routing report shows WNS -2.178 ns, TNS -580.047 ns, WHS -0.260 ns and THS -27.424 ns. These figures require the final routed timing report before judging hardware readiness. The route-initialization "45243 failed nets" message appears before actual routing and is not a final route failure.

## Corrections in this revision

- Moved I-cache payload-bank writes out of the asynchronous-reset FSM into synchronous write processes. This addresses Vivado's explicit reason for mapping these arrays to registers. Cache valid bits still reset; the 9-stall-cycle interface is preserved. Actual new resource inference must be confirmed in Vivado.
- Moved UART line-buffer writes out of the asynchronous-reset process. Resetting the buffer length and pending flags discards stale content. This addresses set/reset-priority and memory-inference warnings without resetting payload storage.
- Moved register-bank selection, FPU-operation selection, EX/WB validity and CSR bus declarations before their first use, avoiding implicit declarations and possible width ambiguity.
- Set BUFGCE SIM_DEVICE to 7SERIES, matching the target device and the tool's warning.
- Made the existing 16-bit trace event map explicit. IMPORTANT: the earlier conversational claim that the old concatenation was 19 bits was incorrect; flags[4] is one bit and the total was already 16. No dropped stall bits were established. The serialized mask was misleadingly labelled FLAGS; it is now EVENT. Bits 15/14/13/12/11/10/9 are aggregate stall/load-use/D-miss/I-miss/branch-flush/FPU-busy/integer-unit-busy. All event bits are retained when causes overlap; the text selects one cause, with cache waits ahead of arithmetic waits.
- Corrected the D-cache terminal colour match to recognize the actual emitted D-CACHE MISS / BYPASS WAIT text.
- Expanded the serial transport regression to check seven cause classifications, including simultaneous I-cache and FPU activity, and nine-step refill formatting.
- The Vivado script now checks implementation completion and emits worst-path, clock-interaction and CDC reports. It returns an error for negative setup/hold slack after routing. It still requires DRC/timing review before generating a bitstream.

## Remaining observations

Unconnected optional MMCM outputs, trimmed CSR bits, and unused ports can be normal optimization. RAM byte-write decomposition is an implementation choice, not proof of incorrect data writes. Setup/hold failures cannot be diagnosed or repaired reliably from intermediate summaries alone; use the new final reports. No clock frequency or instruction latency was changed to hide timing failures.

Normal hybrid trace captures the first 64 stall/flush events plus FP commits. Verbose SW12 captures every active core cycle; UART backpressure extends wall-clock time. The dashboard retains the most recent 10,000 terminal lines, trimming 199 older lines when the cap is exceeded. Pause Auto-Scroll allows manual inspection; this bounded widget is not a permanent full-run trace archive or an automatic per-miss timing checker.

## Evidence

See build_review_regression.log for the directed RTL, cache timing, serial, dashboard and board-elaboration checks, and build_review_board.log for the board trace/full-run simulation. Historical final_mode_results.log still documents the earlier full 15-configuration firmware matrix; this revision does not claim that entire matrix was rerun. The FPGA build must be repeated with the updated source.
