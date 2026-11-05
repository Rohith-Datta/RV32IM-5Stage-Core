# Viva audit revision - 4 November 2026

## Corrections

- ALU SRA/SRAI: compute the signed shift before the unsigned result mux.
- Dashboard: require 57 unique independently expected checks and 100 sequential packets; validate raw inputs, normal and stress integer results; synchronize diagnostic/flight EMA reference state; clear stale readouts; synthetic runs remain unverified.
- Zbb observer: qualify supported opcode/function encodings to avoid false ADDI activity.
- Trace reason: require aggregate stall before labeling a D-cache miss as a wait.

The UART output pin was also corrected in `board/nexys_a7.xdc`: the FPGA TX signal now uses D4 (`uart_rxd_out`), the Nexys A7 FPGA-to-USB-UART path. The old C4 (`uart_txd_in`) pin is the USB-UART-to-FPGA direction. Rebuild and rerun timing after this pin correction. No cache/FPU latency, firmware image or timing exception was changed.

## Verification

Full regression passes, including 1,920 ALU vectors (85 failures before, zero after), 24 observer cases, eight trace cases and 20 headless dashboard tests. Fresh board simulations at 40 and 50 MHz each produce 100 packets and 57 checks with zero host failures. Fifteen stored final-mode transcripts pass the stricter parser. Firmware rebuild is byte-identical.

No physical FPGA or local Vivado run was possible. The user's 40 MHz timing pass belongs to pre-fix RTL. From this project root run:

```
vivado -mode batch -source board/build_vivado.tcl -tclargs 40
```

Review timing/DRC, then generate a new bitstream. Simulation at 50 MHz does not establish physical timing closure. Remaining ISA, serial-protocol and observation limitations are detailed in the guide. Passing scoped tests is not an error-free or full ISA-compliance guarantee.
