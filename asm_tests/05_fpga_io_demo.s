# ==============================================================================
# File: asm_tests/05_fpga_io_demo.s
# Description: Interactive Board I/O & Visual Counter for Nexys A7 FPGA Demo
# Writes incremental patterns to register file so LEDs and 7-Segment display
# show visual progression during hardware demonstration
# ==============================================================================

.globl main
.text

main:
    li      x1, 0x00000200      # x1 = Base RAM Address
    li      x2, 0               # x2 = Visual pattern counter (0 to 255)
    li      x3, 10              # Number of cycles to run in simulation

demo_loop:
    # 1. Update pattern
    addi    x2, x2, 1           # Increment counter

    # 2. Store to RAM (Observable via memory bus and LEDs[15:8])
    sw      x2, 0(x1)

    # 3. Software Delay Loop (for visual human pacing on FPGA)
    li      x4, 5               # Delay count (small for simulation, adjust for hardware)
delay:
    addi    x4, x4, -1
    bnez    x4, delay

    # 4. Loop condition
    addi    x3, x3, -1
    bnez    x3, demo_loop

    # Store signature when demo loop finishes
    li      x5, 0xCAFE0005
    sw      x5, 4(x1)

    ret
