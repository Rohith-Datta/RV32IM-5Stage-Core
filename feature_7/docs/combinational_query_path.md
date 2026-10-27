# BTB Query Path (IF Stage)

## Timing
Parallel tag check during instruction fetch.
- `pred_hit = valid_array[index] && (tag_array[index] == fetch_tag)`
- `pred_taken = pred_hit`
- `pred_target = pred_hit ? target_array[index] : (fetch_pc + 4)`
