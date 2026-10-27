# Branch Misprediction Resolution in EX Stage

## Detection Logic
Asserted when actual branch outcome differs from speculation:
`mispredict = (actual_taken != pred_taken) || (actual_taken && (actual_target != pred_target))`

Recovery flushes IF/ID and ID/EX with a 2-cycle penalty.
