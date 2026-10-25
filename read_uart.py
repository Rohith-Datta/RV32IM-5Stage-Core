#!/usr/bin/env python3
# ==============================================================================
# File: read_uart.py
# Description: Real-Time Cross-Platform Serial Monitor for Nexys A7 RISC-V Core
# Baud Rate: 115,200 | 8-N-1 | Micro-USB FTDI Interface
# Supports: RV32I, RV32M, and RV32F (IEEE-754 FPU) Live Execution & Hazard Tracking
# ==============================================================================

import os
import sys
import time
import argparse

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("\n[!] 'pyserial' library not found.")
    print("    To install it, run: pip install pyserial")
    print("    Alternatively, on Windows you can use: powershell -ExecutionPolicy Bypass -File read_uart.ps1\n")
    sys.exit(1)

REG_NAMES = [
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
]

def disassemble(inst):
    if inst == 0x00000013: return "nop"
    if inst == 0x00008067: return "ret (Program Finished)"

    opcode = inst & 0x7F
    rd     = (inst >> 7) & 0x1F
    funct3 = (inst >> 12) & 0x7
    rs1    = (inst >> 15) & 0x1F
    rs2    = (inst >> 20) & 0x1F
    funct7 = (inst >> 25) & 0x7F

    rd_n  = REG_NAMES[rd]
    rs1_n = REG_NAMES[rs1]
    rs2_n = REG_NAMES[rs2]

    # OP-IMM (0x13)
    if opcode == 0x13:
        imm = (inst >> 20)
        if imm >= 2048: imm -= 4096
        if funct3 == 0:
            if rs1 == 0: return f"li {rd_n}, {imm}"
            if imm == 0: return f"mv {rd_n}, {rs1_n}"
            return f"addi {rd_n}, {rs1_n}, {imm}"
        names = ['addi', 'slli', 'slti', 'sltiu', 'xori', 'srli', 'ori', 'andi']
        return f"{names[funct3]} {rd_n}, {rs1_n}, {imm}"

    # OP / RV32M (0x33)
    if opcode == 0x33:
        if funct7 == 0x01:
            mnames = ['mul', 'mulh', 'mulhsu', 'mulhu', 'div', 'divu', 'rem', 'remu']
            return f"{mnames[funct3]} {rd_n}, {rs1_n}, {rs2_n}"
        if funct3 == 0:
            return f"sub {rd_n}, {rs1_n}, {rs2_n}" if funct7 == 0x20 else f"add {rd_n}, {rs1_n}, {rs2_n}"
        names = ['add', 'sll', 'slt', 'sltu', 'xor', 'srl', 'or', 'and']
        return f"{names[funct3]} {rd_n}, {rs1_n}, {rs2_n}"

    # OP-FP / RV32F (0x53)
    if opcode == 0x53:
        fp_names = {0x00: "fadd.s", 0x04: "fsub.s", 0x08: "fmul.s", 0x0C: "fdiv.s"}
        name = fp_names.get(funct7, f"fp_op(f7={funct7:#x})")
        return f"{name} {rd_n}, {rs1_n}, {rs2_n}"

    # LOAD (0x03)
    if opcode == 0x03:
        imm = (inst >> 20)
        if imm >= 2048: imm -= 4096
        names = ['lb', 'lh', 'lw', 'res', 'lbu', 'lhu']
        return f"{names[funct3]} {rd_n}, {imm}({rs1_n})"

    # STORE (0x23)
    if opcode == 0x23:
        imm = ((inst >> 7) & 0x1F) | (((inst >> 25) & 0x7F) << 5)
        if imm >= 2048: imm -= 4096
        names = ['sb', 'sh', 'sw']
        return f"{names[funct3]} {rs2_n}, {imm}({rs1_n})"

    # BRANCH (0x63)
    if opcode == 0x63:
        names = ['beq', 'bne', 'res', 'res', 'blt', 'bge', 'bltu', 'bgeu']
        return f"{names[funct3]} {rs1_n}, {rs2_n}"

    # LUI (0x37)
    if opcode == 0x37:
        return f"lui {rd_n}, 0x{(inst >> 12):x}"

    return f"inst (0x{inst:08x})"

def auto_detect_port():
    ports = list(serial.tools.list_ports.comports())
    if not ports:
        return None

    # Filter out internal/virtual ports
    candidates = []
    for p in ports:
        dev = p.device.lower()
        if "debug-console" in dev or "bluetooth" in dev or "wlan" in dev:
            continue
        candidates.append(p)

    # 1. Look for Digilent / FTDI / USB Serial explicitly
    for p in candidates:
        desc = (p.description or "").lower()
        hwid = (p.hwid or "").lower()
        dev  = p.device.lower()
        if any(k in desc or k in hwid or k in dev for k in ["digilent", "ftdi", "usbserial", "ttyusb", "com"]):
            return p.device

    # 2. Return first real candidate if available
    return candidates[0].device if candidates else None

def main():
    parser = argparse.ArgumentParser(description="Nexys A7 UART Live Execution Monitor (115200 Baud)")
    parser.add_argument("-p", "--port", default=None, help="Serial port (e.g., COM3, COM4, /dev/ttyUSB0)")
    parser.add_argument("-b", "--baud", type=int, default=115200, help="Baud rate (default: 115200)")
    args = parser.parse_args()

    port = args.port or auto_detect_port()

    print("====================================================================")
    print("      Nexys A7 RV32IMF Real-Time Serial Monitor @ 115,200 Baud      ")
    print("====================================================================")

    if not port:
        print("[!] No active serial COM port detected.")
        print("    1. Plug your Digilent Nexys A7 FPGA into PC via micro-USB.")
        print("    2. Make sure the board power switch is turned ON.")
        print("    3. If on Windows, check Device Manager -> Ports (COM & LPT).")
        sys.exit(1)

    print(f"[*] Connecting to: {port} at {args.baud} baud (8-N-1)...")
    try:
        ser = serial.Serial(port, args.baud, timeout=0.5)
    except Exception as e:
        print(f"[!] Failed to open port '{port}': {e}")
        print("    If using another program (PuTTY / TeraTerm), close it first.")
        sys.exit(1)

    print(f"[+] Connected successfully! Waiting for FPGA telemetry stream...")
    print("    -> Press the red CPU_RESET pushbutton on Nexys A7 (Pin C12) to reset.")
    print("    -> Press Ctrl+C at any time to exit.\n")
    print("-" * 68)

    cycle = 0
    instructions = 0
    stalls = 0

    try:
        while True:
            line_bytes = ser.readline()
            if not line_bytes:
                continue

            line = line_bytes.decode('ascii', errors='replace').strip()
            if not line:
                continue

            cycle += 1

            # Hazard Stall line
            if "stall" in line.lower():
                stalls += 1
                print(f"[Cycle {cycle:4d}] >>> PIPELINE HAZARD STALL (Hardware Interlock Hold)")
                continue

            # Standard Fetch Telemetry: "PC: 0x00000000 | INST: 0x3FC000B7"
            if "PC:" in line and "INST:" in line:
                instructions += 1
                try:
                    parts = line.split("|")
                    pc_str = parts[0].split(":")[1].strip()
                    inst_str = parts[1].split(":")[1].strip()
                    inst_val = int(inst_str, 16)
                    dis = disassemble(inst_val)
                    print(f"[Cycle {cycle:4d}] PC: {pc_str} | INST: {inst_str}  -->  {dis}")
                    if inst_val == 0x00008067:
                        print("\n" + "=" * 68)
                        print(" [SUCCESS] Program Finished (ret instruction committed)!")
                        print(f" Summary: {instructions} instructions, {stalls} stalls, total {cycle} cycles.")
                        print("=" * 68 + "\n")
                except Exception:
                    print(f"[Cycle {cycle:4d}] {line}")
            else:
                # Banner or arbitrary string
                print(line)

    except KeyboardInterrupt:
        print("\n[*] Exiting UART monitor...")
    finally:
        ser.close()

if __name__ == "__main__":
    main()
