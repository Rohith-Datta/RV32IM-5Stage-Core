# BTB Bare-Metal C Verification Notes

## Test Description (btb.c)
A clean 4-iteration accumulator loop verifying:
1. Cold compulsory miss on iteration 1 (2-cycle flush).
2. BTB hit on iterations 2 and 3 (0-cycle penalty).
3. Loop-exit misprediction on loop termination.
