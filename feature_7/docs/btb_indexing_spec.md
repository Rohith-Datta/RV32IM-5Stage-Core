# BTB Indexing & Tag Comparison

## Address Mapping
- Word-aligned instruction PC has `PC[1:0] == 2'b00`.
- **Index**: `PC[6:2]` (5 bits, selects entry 0 to 31).
- **Tag**: `PC[31:7]` (25 bits, stored in tag array).
