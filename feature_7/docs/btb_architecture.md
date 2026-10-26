# Static Branch Target Buffer (BTB) Architecture

## Overview
Direct-mapped 32-entry Branch Target Buffer operating in the Instruction Fetch (IF) stage.

### Storage Geometry
- **Entries**: 32
- **Valid Array**: 32 x 1 bit
- **Tag Array**: 32 x 25 bits (`PC[31:7]`)
- **Target Array**: 32 x 32 bits
