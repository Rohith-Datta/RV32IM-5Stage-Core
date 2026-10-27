# Bare-Metal C I-Cache Test Program Specification

## Overview
A lightweight C test (`icache.c`) compiled to 7 instructions across 2 cache lines.
- Total runtime: ~31 cycles (< 40 cycles approx)
- Return value: `a0 = 37 (0x0025)`
- Hit rate: 75.0%
