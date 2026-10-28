# IEEE 754 Round to Nearest Even (RNE) Tie-Breaking Datapath

## Mathematical Basis
When a floating-point intermediate result falls equidistant between two representable numbers:
$$\text{Tie Condition} = G \land \overline{R} \land \overline{S}$$

### Hardware Implementation
- Round Up if $G \land (R \lor S)$ (greater than half-way).
- Round Up if $G \land \overline{R} \land \overline{S} \land M_0$ (exact tie, round to even LSB).
- Leaves LSB unchanged if $M_0 == 0$, guaranteeing zero long-term statistical bias.
