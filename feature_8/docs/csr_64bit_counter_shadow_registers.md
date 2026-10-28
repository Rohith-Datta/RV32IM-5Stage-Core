# 64-Bit Performance Counter Shadow Register Architecture

## Counter Encodings
- `cycle` (`0xC00`) & `cycleh` (`0xC80`): 64-bit elapsed clock cycle count.
- `time` (`0xC01`) & `timeh` (`0xC81`): 64-bit real-time timer ticks.
- `instret` (`0xC02`) & `instreth` (`0xC82`): 64-bit retired instruction count.

### Atomicity & Shadow Latching
To prevent reading inconsistent high/low words during an atomic 32-bit rollover, reading `cycle` latches `cycleh` into a shadow register for an atomic two-instruction read sequence.
