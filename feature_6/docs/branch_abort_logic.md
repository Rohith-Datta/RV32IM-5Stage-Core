# I-Cache Branch Abort & Flush Logic

## Flush Mechanism
When a branch or jump redirects in the EX stage (`flush_i == 1`), in-flight burst refills are safely terminated and the FSM immediately returns to `STATE_IDLE`.
