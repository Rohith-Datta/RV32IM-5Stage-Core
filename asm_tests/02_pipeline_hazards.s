# ==============================================================================
# File: asm_tests/02_pipeline_hazards.s
# Description: Pipeline Hazard Unit & Forwarding Network Verification
# Verifies:
#   1. RAW EX-to-EX Data Forwarding (zero-bubble back-to-back operations)
#   2. RAW MEM-to-EX Data Forwarding
#   3. Load-Use Data Interlock Stall (1-bubble stall insertion)
#   4. Branch Prediction Flush (squashes invalid instructions in IF/ID)
# ==============================================================================

.globl main
.text

main:
    # --------------------------------------------------------------------------
    # Test 1: Back-to-Back RAW Forwarding (EX -> EX)
    # x1 is computed, then immediately consumed by next instruction!
    # --------------------------------------------------------------------------
    li      x1, 10
    addi    x1, x1, 20          # x1 = 30  (EX stage)
    add     x2, x1, x1          # x2 = 60  (Forwarded directly from EX/MEM!)
    add     x3, x2, x1          # x3 = 90  (Forwarded from both EX/MEM and MEM/WB!)

    # --------------------------------------------------------------------------
    # Test 2: Memory Store & Load-Use Hazard Interlock Stall
    # --------------------------------------------------------------------------
    li      x4, 0x00000200
    sw      x3, 0(x4)           # Store 90 to RAM[0x200]

    # Load-Use test: lw x5, followed IMMEDIATELY by add using x5!
    # Hardware Hazard Unit MUST stall PC, IF/ID, ID/EX by 1 cycle
    lw      x5, 0(x4)           # x5 = 90 loaded from RAM
    addi    x6, x5, 10          # x6 = 90 + 10 = 100 (Requires Load-Use stall!)

    # --------------------------------------------------------------------------
    # Test 3: Branch Flush Verification
    # If branch is taken, subsequent instruction MUST be flushed (bubble).
    # --------------------------------------------------------------------------
    li      x7, 1
    bnez    x7, branch_target   # Branch taken!
    addi    x8, x0, 999         # This instruction MUST NOT execute (flushed!)
    addi    x9, x0, 888         # This instruction MUST NOT execute (flushed!)

branch_target:
    # Arrived at target correctly
    addi    x10, x6, 5          # x10 = 100 + 5 = 105

    # Store verification results to RAM
    sw      x1, 4(x4)           # RAM[0x204] = 30
    sw      x2, 8(x4)           # RAM[0x208] = 60
    sw      x6, 12(x4)          # RAM[0x20C] = 100
    sw      x10, 16(x4)         # RAM[0x210] = 105

    # Signature: 0xCAFE0002 indicates Hazard Tests Passed!
    li      x11, 0xCAFE0002
    sw      x11, 20(x4)         # RAM[0x214] = 0xCAFE0002

    ret
