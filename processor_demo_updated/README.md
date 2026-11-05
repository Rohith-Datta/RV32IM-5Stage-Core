> Latest update: see [REQUESTED_CHANGES.md](REQUESTED_CHANGES.md) for final profiler timing, IF-PC terminal display, SW9 prediction bypass, and the comparison demo.

> Start with **DEMO_START_HERE.md** for the updated bounded cycle window, proof log and switch sequence. Older hybrid-trace descriptions below are historical.

> **Audit revision, 4 November 2026:** A newly found SRA/SRAI signedness bug is fixed and covered by 1,920 additional ALU cases. Fresh functional regressions pass. The earlier successful 40 MHz Vivado run used the pre-fix RTL; rebuild this revision at 40 MHz and recheck timing before generating its bitstream. See `reports/VIVA_AUDIT_REVISION.md` and `docs/Processor_Architecture_Audit_and_Viva_Guide.pdf`. Dashboard validation, Zbb observation and trace labeling are also corrected and regression-tested. The Nexys A7 UART TX output is constrained to D4 (the FPGA-to-USB-UART path); rebuild the bitstream after this board-pin correction. Remaining ISA and observation limitations are explicitly documented. Earlier status notes below are historical.

# RISC-V avionics demo — RTL-tested integration

The project now includes the processor fixes, Nexys A7 board wrapper, UART hardware tracing, compiled firmware, live Python dashboard and reproducible verification. **RTL simulation passes; Vivado implementation, timing closure and a physical FPGA run remain unverified.** This is a demo-focused RNE implementation, not an assertion of exhaustive RV32F/IEEE-754 compliance.

## Quick start

1. Install RISC-V GCC/binutils, Icarus Verilog and Python 3.10+ with Tk support.
2. `python -m pip install -r requirements.txt`
3. `make -C firmware` — builds ELF, binary, disassembly and `avionics_demo.mem`. A compiled image is already included.
4. `python tools/run_tests.py` — directed core, FPU, integer, cache, UART, trace-transport and display regressions; board elaboration.
5. `python tests/run_modes.py` — slower four-mode plus eleven-seed regression. `python tests/verify_transcripts.py reports` validates its transcripts. The included final evidence is in `reports/final/`; validate it with `python tests/verify_transcripts.py reports/final`. NumPy is needed only to regenerate the supplied differential FPU vectors.
6. `python tools/run_board_tests.py` — full UART/clock-gate board simulation and consecutive verbose trace capture.
7. `python dashboard.py` — select the actual serial port, 115200 baud, 8N1. Reset/Clear clears host state; CPU_RESETN restarts the board.
8. From this directory: `vivado -mode batch -source board/build_vivado.tcl`. Top: `nexys_a7_top`. Device: `xc7a100tcsg324-1`. Review timing, utilization and DRC before generating a bitstream.

The program uses 64 KiB of unified synchronous RAM at address zero; stack top is `0x00010000`. The original ZIP is retained as `original_source.zip`. The earlier reviewed checkpoint is also retained in `checkpoints/`.

## Switches and modes

| Setting | Function |
|---|---|
| `0x2032` | Flight EMA, caches enabled, alpha = 50/255 |
| `0x0032` | Flight EMA; bypass accesses: 9 stall + 1 service cycles |
| `0x6032` | Latency profiler plus normal telemetry |
| `0xA032` | Nested loop and conflicting data-cache accesses |
| `0xE001` … `0xE00B` | Diagnostic vectors 1 … 11 |
| SW12 = 0 | Hybrid CSV plus sampled architectural events and FP commits |
| SW12 = 1 | Every active processor cycle is captured and sent over UART |
| SW11 = 1 | Whole processor/memory clock gated to at most ten ticks/s; UART and display remain running |
| SW10 = 1 | Display the software MMIO override; otherwise show IF PC |
| SW9 = 1 | Branch prediction bypass; SW9 = 0 preserves prediction ON |
| SW8 | Reserved |
| SW7:0 | Per-packet alpha or diagnostic seed |

All modes first execute **57 hardware self-checks** spanning the nine feature groups, then process exactly 100 telemetry packets, send `DEMO_COMPLETE`, and assert LED0. Diagnostic seeds are not needed to exercise the startup corner-case matrix. The processor clock stops after the completion flag is set.

A 10 Hz processor tick is not ten retired instructions/s: hazards and multicycle instructions also consume ticks. Reset between measured runs. Active-refill bypass selection is latched; a bypass store invalidates a stale cached line. The included toggle test covers these transitions, but arbitrary repeated live switching is not exhaustively verified.

## Real hardware tracing and bandwidth

`uart_trace_transport.v` captures WB PC, instruction, register bank/destination/data/validity, stall and exception events, D-cache refill progress, IF PC, physical LED outputs, switches and measured cache counters. It freezes the **entire processor and RAM clock** while transmitting a record. The UART/display keep running. Software CSV/CHECK lines are buffered and sent atomically, so traces cannot corrupt a CSV line.

Hybrid mode sends the first 64 selected stall/branch events and FP commits throughout the run. Verbose mode captures every active core cycle without dropping cycles. It is intentionally slow: 115200-baud 8N1 carries only 11,520 bytes/s, so a whole firmware run with hundreds of thousands of ASCII cycle records can take hours. Use hybrid mode for the practical live demo. Counter-based IPC/latency measures active processor cycles; it does **not** include wall-clock pauses for UART trace transport or human stepping.

The dashboard decodes actual captured instruction bits and register aliases. Invalid WB slots remain explicitly marked `VALID=0`; no software PC estimates or invented stalls are printed. DREFILL reports the real 1–9 progress value; arbitration can repeat a progress value while waiting. Trace text is an extended observation format, not a byte-for-byte reproduction of the illustrative fictional trace in the original prompt. Memory store address/data annotations are not currently included in the UART record.

For offline RTL traces:

`vvp reports/firmware.vvp +SW=2032 +LOG=reports/run.log +TRACE`

The `.trace` companion file records real simulated WB/stall/branch observations. Without `+TRACE`, that offline trace is limited to the first 5,000 cycles. The physical hardware transport is tested separately by `tb_board_verbose` and `tb_board_full`.

## Protocol and host verification

The master prompt calls its CSV “9-field”, but enumerates **11 numeric fields**. The complete enumerated form is used:

`CSV,iter,sw,input_bits,output_bits,zbb_output,div_output,cycle,instret,dcache_misses,stalls,last_wb`

Every numeric field is eight hexadecimal digits. The stream also contains:

- `[CC=...]` hardware trace records, including SW/LED/IFPC and cache-counter metadata.
- `CHECK,name,actual,expected` startup self-test results; mismatches are failures.
- `PROFILE,name,cycles` measured latency results.
- `DEMO_COMPLETE` completion sentinel.

CHECK and PROFILE are explicit protocol extensions needed to expose the requested verification/profiling results. The original numeric CSV format is unchanged. The fixed CSV alone lacks cache-hit denominators and physical PC/LED state; the hardware trace metadata now supplies them. Gauges remain N/A until such metadata arrives. Hit rates are measured request statistics, including speculative instruction fetches, not rates inferred from retired-instruction counts.

Synthetic preview buttons are labelled as synthetic and are not hardware evidence. The host validates exact packet shape/order, independently computes diagnostic expected results and EMA rounding, reports failures honestly, and does not equate a sentinel with 100 verified packets.

## Measured profiler results

Assembly measurement windows are aligned to 16-byte instruction-cache lines. Back-to-back `csrr cycle` reads provide the baseline. Load measurements retain an explicit dependent instruction; the hit measurement subtracts that known dependency overhead, and the miss penalty is the difference between matched cold/hit windows.

| Observation | RTL-measured cycles |
|---|---:|
| Zbb REV8 | 1 |
| D-cache hit service | 1 |
| D-cache miss penalty | 9 |
| FMUL.S | 4 |
| FDIV.S | 15 |
| DIV | 32 |

Both L1 cold misses incur nine stall cycles plus one service cycle: ten cycles of stage occupancy. Four independent bypassed word accesses contribute 36 stall cycles (40 total occupancy cycles). Pipeline dependencies are separate from cache stage occupancy. Extra arbitration waits can increase elapsed latency. See `tests/check_profiles.py` for the numerical regression.

## Architectural interface changes

`rv32imf_core` still wraps `pipeline_5stage`. Internal register IDs and `wb_dest_reg` are now six bits: bit 5 selects FP storage, low five bits select the register. IDs 0–31 are x0–x31; 32–63 are f0–f31. Only x0 is hardwired to zero.

C00/C02 are cycle/instret; C03/C04/C05/C06 are D misses/I misses/stalls/branch mispredictions. C07 is branches, C08 the latest valid WB snapshot, C09 D hits and C0A I hits. FFLAGS/FRM/FCSR support read/replace/set/clear operations. Arithmetic validation here targets explicit RNE/FRM=0; other rounding modes and the complete RV32F instruction set are not comprehensively implemented or verified.

See `reports/REQUIREMENTS_REVIEW.md` for the change map, tested scope and remaining limitations. `reports/final_mode_results.log`, `reports/tb_board_full.log` and `reports/board_full_host_check.log` summarize final execution evidence.

## Vivado build-log follow-up

Read `reports/BUILD_LOG_REVIEW.md` for the latest corrections and the supplied build-log findings. The log reaches routing but does not establish final timing closure. Use this updated source for the next build. `EVENT` in UART records is the full 16-bit event mask; it was formerly mislabeled `FLAGS`. Pause Auto-Scroll permits manual log inspection; the terminal retains at most about 10,000 lines, and hybrid tracing samples the first 64 stall/flush events plus FP commits. Use verbose SW12 for consecutive cycle records.

## Timing optimization and frequency selection

The latest revision targets the FPU result-packing path and moves display logic onto the ungated system clock. Read `reports/TIMING_OPTIMIZATION.md` for the measured failing paths, changes, validation and limitations. No new Vivado timing closure is claimed.

Build the default 50 MHz target with `vivado -mode batch -source board/build_vivado.tcl -tclargs 50`. If setup timing still fails, use `-tclargs 40` (or `31.25` or `25`). The script adjusts the MMCM, UART, slow-step interval and LED hold time. Keep the board input-clock constraint at 100 MHz. Projects and reports are in `build/vivado_50mhz/` and `build/reports_50mhz/`, or the corresponding frequency-specific directories.

Run `python tools/run_timing_validation.py` for full board functional simulations at 50 and 40 MHz.
