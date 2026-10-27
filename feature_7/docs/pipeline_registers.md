# Pipeline Prediction Metadata Propagation

## Register Forwarding
To prevent race conditions, the speculation decision travels synchronously with the instruction:
- `IF/ID`: registers `pred_taken` and `pred_target`.
- `ID/EX`: registers `if_id_pred_taken` and `if_id_pred_target`.
