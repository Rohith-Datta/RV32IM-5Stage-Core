# IEEE 754 Floating-Point Adder and Subtractor (FADD / FSUB) Architecture

## Pipeline Overview
The FADD/FSUB execution pipeline operates as a 2-stage synchronized execution unit integrated into the central core pipeline.

### Stage 1: Operand Unpack & Exponent Alignment
1. **Unpack & Hidden Bit Insertion**: Insert explicit leading bit `1.M` for normal numbers or `0.M` for zero/subnormals.
2. **Exponent Difference**: $\Delta E = E_A - E_B$.
3. **Mantissa Alignment Shifter**: Shift smaller mantissa right by $|\Delta E|$ bits, retaining Guard ($G$), Round ($R$), and Sticky ($S$) bits.

### Stage 2: 25-Bit Adder & Normalization
1. **Effective Operation**: Determine whether addition or subtraction is required:
   $$\text{EffOp} = \text{is\_sub} \oplus S_A \oplus S_B$$
2. **25-bit Adder/Subtractor**: Computes aligned sum or difference.
3. **Leading Zero Detector (LZD)**: 25-bit priority encoder detects normalization shift distance.
4. **Rounding Logic**: Evaluates RNE rounding based on $G$, $R$, and $S$ bits:
   $$\text{RoundUp} = G \land (R \lor S \lor M_0)$$
5. **Output Packing**: Reassembles 32-bit IEEE 754 float result and generates exception flags (`NV`, `OF`, `UF`, `NX`).
