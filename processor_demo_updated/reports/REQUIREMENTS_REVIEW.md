# Master specification review and delivery status

The original top is `rv32imf_core`, with `u_pipeline: pipeline_5stage`. The new physical board top is `nexys_a7_top`. This package implements and simulates the demo integration; FPGA implementation and physical operation remain unverified.

## Original signal mapping and implemented connections

| Required observation | Actual source / implementation |
|---|---|
| IF PC | `rv32imf_core.pc_if`; internal `u_pipeline.if_pc` |
| WB PC/data/write | `pc_wb`, `wb_data`, `wb_reg_write` |
| WB destination | `wb_dest_reg`; widened to six bits for integer/FP banks |
| Retirement validity | internal `u_pipeline.wb_valid`; exported `retire_o` |
| Aggregate stall | `hazard_stall` |
| Load-use | original `u_pipeline.u_hazard_unit.load_use_hazard`; exported valid-qualified `load_use_o` |
| D-cache refill | `u_pipeline.u_dcache.state`, `refill_cnt`, `dcache_stall` |
| I-cache refill | `u_pipeline.u_icache.state`, `refill_cnt`, `icache_stall` |
| Branch resolution | `btb_mispredict`, `ex_redirect_pc` |
| FPU/divider | `fpu_busy`, `div_busy`; operation exception events added as `fp_flags_o` |
| Zbb | decoded EX activity exported as `zbb_active_o` |
| MMIO | new MEM-stage `mmio_*` interface; bypasses both caches and backing-RAM arbitration |

## Implemented corrections and integration

- Separate integer/FP register banks, writable f0, six-bit register IDs through forwarding/hazards/WB, compiler-required conversions/moves/sign injection, and WB snooping during held ID/EX stalls.
- Both L1 caches have **9 stalled cycles + 1 service cycle = 10 stage occupancy cycles** under granted synchronous memory service. I-cache already used this timing; D-cache refill and bypass store completion now use the same nine-stall convention. Bus contention can add waiting. Direct tests cover all four word offsets and both cached/bypass paths; four independent bypass accesses accumulate **36 stalls**, not 40.
- Cache responses honor granted bus requests. Active refill mode is latched; bypass stores write once and invalidate stale cached data. Hit counters count accepted accesses.
- Firmware reads real CSR counters. There are no synthetic refill-print loops or `40u` CSR multipliers to retain. Hardware DREFILL records progress 1 through 9; firmware documents the 36u four-access stall budget. No software printing is presented as a real-time cache observation.
- FPU RNE rounding, subnormal/underflow handling and exception events; fflags/frm/fcsr read/replace/set/clear. Validation is scoped to implemented demo operations and RNE, not complete RV32F or all rounding modes.
- Corrected counter map, valid WB snapshot and accepted branch updates/flushes; real integer divide-zero and multiply activity LEDs.
- 64 KiB synchronous unified program/data RAM; MMIO routing ahead of caches; 100-to-50 MHz clock generation; safe whole-core/RAM clock gating; UART at 115200 baud; display scan/LED drivers and official Digilent pin constraints.
- Lossless per-active-cycle hardware trace through clock backpressure; atomic software lines; hybrid sampled events plus FP commits; real switch/LED/IF-PC/cache-counter metadata. UART transmission runs while the core is paused.
- Bare-metal startup/linker and compiled firmware with 57 startup self-checks in every mode, four operating modes, eleven diagnostic seeds, isolated six-window profiler and 100 packets per completed run.
- Host serial selection, bounded input queue, partial-line assembly, stale-source isolation, exact packet checks, independently calculated diagnostic/EMA expectations, actual cache gauges and metadata mirrors, and instruction disassembly from captured bits.

## Specification clarifications and remaining limits

| Item | Delivered interpretation / limit |
|---|---|
| Cache timing correction | Nine stall cycles and ten total occupancy cycles for both L1 caches; extra arbitration waits are separate. |
| “9-field” CSV | The specification enumerates eleven numeric fields; all eleven are retained. |
| CHECK / PROFILE | Explicit protocol extensions report measured self-tests/profiler results. |
| UART cycle tracing | Real captured cycles, with the processor paused during serial transport. Full verbose runs may take hours; hybrid is practical for demonstration. |
| Verbose validation | Consecutive 32-cycle prefix tested; full 100-packet board run uses hybrid mode. |
| Trace wording | Extended actual-state format, not the fictional example verbatim. No store address/data annotation in UART records. |
| Slow mode | At most ten active processor ticks per second, not ten retired instructions per second. |
| SW10 | Software MMIO display override; otherwise IF PC. Resolves conflicting display descriptions. |
| Performance rates | Measured cache/IPC statistics; no predetermined hit-rate or IPC claims. UART wall time is excluded from active-cycle counters. |
| ISA compliance | Demo-focused implemented subset/RNE validation, not exhaustive ISA/IEEE-754 certification. |
| FPGA readiness | Vivado synthesis/place/route/timing/DRC and physical programming have not been run. The included script prepares these steps. |
| GUI | Eight headless logic tests; visual desktop inspection not performed. |

## Reproducible evidence

- `regression_final.log`: core integration, 12 directed FPU cases, 2,784 differential FPU vectors, 16 integer edge cases, cache timing/bypass/toggle, UART, trace transport, display and dashboard tests; board elaboration.
- `final_mode_results.log` and `final/uart_*.log`: final corrected timing, four operating configurations and eleven diagnostic seeds, each with 57 self-checks and 100 packets.
- `transcript_verification.log`: independent host verification of final transcripts.
- `profiler_final.log`: expected measured windows REV8=1, D-hit=1, D-miss penalty=9, FMUL=4, FDIV=15, DIV=32.
- `tb_board_verbose.log`: consecutive real cycle trace capture through UART.
- `tb_board_full.log`, `board_full_uart.log`, `board_full_host_check.log`: complete board-level RTL serial run, completion and simulated LED output, checked through the host parser.

`yosys_check.log` and `yosys_trace.log` report zero structural problems after process lowering; this is not FPGA synthesis/timing signoff. The earlier whole-board Yosys attempt did not complete and provides no signoff.

Earlier logs/checkpoint files document development and may contain superseded timing. Only the final paths listed above describe the nine-stall-cycle revision. The original master specification is preserved unchanged as `MASTER_SPEC.md`; this user's timing correction takes precedence.

Pin assignments originate from the included Digilent Nexys-A7-100T master XDC; SW8/SW9 retain LVCMOS18. `rtl_changes.patch` compares the original processor RTL with this revision.
