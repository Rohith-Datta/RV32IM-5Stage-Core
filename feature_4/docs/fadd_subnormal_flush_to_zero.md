# Subnormal Number Handling and Flush-to-Zero (FTZ) Datapath

## Subnormal Operand Characteristics
Operands with exponent $E == 0$ and fraction $M \neq 0$ represent subnormals ($V = \pm 0.M \times 2^{-126}$).

### Hardware Mode Support
- **Default Mode**: Full subnormal denormalization and leading zero shifting.
- **FTZ High-Speed Mode**: If enabled via control register, subnormal inputs are treated as $\pm 0.0$ to eliminate multi-cycle alignment overhead.
