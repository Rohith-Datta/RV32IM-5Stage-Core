# I-Cache Tag Comparison Unit

## Address Breakdown
- `addr[1:0]`: Byte offset (ignored)
- `addr[3:2]`: Word offset within line (selects word 0..3)
- `addr[10:4]`: 7-bit Cache Line Index (128 lines)
- `addr[31:11]`: 21-bit Tag
