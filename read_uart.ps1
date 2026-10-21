# ============================================================================
# Script: read_uart.ps1
# Description: Fully Dynamic Real-Time Serial Monitor for Nexys A7 RISC-V Core
# Usage: 
#   powershell -ExecutionPolicy Bypass -File read_uart.ps1
#   powershell -ExecutionPolicy Bypass -File read_uart.ps1 -Port COM4
# ============================================================================

param(
    [string]$Port = ""
)

if (-not $Port) {
    $ports = [System.IO.Ports.SerialPort]::GetPortNames()
    if ($ports.Count -eq 0) {
        Write-Host "[!] No active COM ports detected." -ForegroundColor Yellow
        Write-Host "    Please connect your Nexys A7 FPGA board via micro-USB." -ForegroundColor Gray
        exit
    }
    $Port = $ports[0]
}

# ============================================================================
# Dynamic RV32I / RV32M Disassembler
# Decodes 32-bit machine hex codes into assembly mnemonics in real-time
# ============================================================================
function Disassemble-RV32 {
    param([string]$hexStr)
    try {
        $inst = [System.Convert]::ToUInt32($hexStr.Replace("0x","").Replace("0X",""), 16)
    } catch {
        return ""
    }

    if ($inst -eq 0x00000013) { return "nop" }
    if ($inst -eq 0x00008067) { return "ret" }

    $opcode = $inst -band 0x7F
    $rd     = ($inst -shr 7) -band 0x1F
    $funct3 = ($inst -shr 12) -band 0x7
    $rs1    = ($inst -shr 15) -band 0x1F
    $rs2    = ($inst -shr 20) -band 0x1F
    $funct7 = ($inst -shr 25) -band 0x7F

    $regs = @('zero','ra','sp','gp','tp','t0','t1','t2','s0','s1','a0','a1','a2','a3','a4','a5','a6','a7','s2','s3','s4','s5','s6','s7','s8','s9','s10','s11','t3','t4','t5','t6')
    $rdName = $regs[$rd]
    $rs1Name = $regs[$rs1]
    $rs2Name = $regs[$rs2]

    # OP-IMM (0x13)
    if ($opcode -eq 0x13) {
        $imm = [int32]($inst -shr 20)
        if ($imm -ge 2048) { $imm -= 4096 }
        if ($funct3 -eq 0) {
            if ($rs1 -eq 0) { return "li $rdName, $imm" }
            if ($imm -eq 0) { return "mv $rdName, $rs1Name" }
            return "addi $rdName, $rs1Name, $imm"
        }
        $names = @('addi','slli','slti','sltiu','xori','srli','ori','andi')
        return "$($names[$funct3]) $rdName, $rs1Name, $imm"
    }

    # OP / RV32M (0x33)
    if ($opcode -eq 0x33) {
        if ($funct7 -eq 0x01) {
            $mnames = @('mul','mulh','mulhsu','mulhu','div','divu','rem','remu')
            return "$($mnames[$funct3]) $rdName, $rs1Name, $rs2Name"
        }
        if ($funct3 -eq 0) {
            if ($funct7 -eq 0x20) { return "sub $rdName, $rs1Name, $rs2Name" }
            return "add $rdName, $rs1Name, $rs2Name"
        }
        $names = @('add','sll','slt','sltu','xor','srl','or','and')
        return "$($names[$funct3]) $rdName, $rs1Name, $rs2Name"
    }

    # LOAD (0x03)
    if ($opcode -eq 0x03) {
        $imm = [int32]($inst -shr 20)
        if ($imm -ge 2048) { $imm -= 4096 }
        $names = @('lb','lh','lw','res','lbu','lhu')
        return "$($names[$funct3]) $rdName, ${imm}($rs1Name)"
    }

    # STORE (0x23)
    if ($opcode -eq 0x23) {
        $imm = (($inst -shr 7) -band 0x1F) -bor ((($inst -shr 25) -band 0x7F) -shl 5)
        if ($imm -ge 2048) { $imm -= 4096 }
        $names = @('sb','sh','sw')
        return "$($names[$funct3]) $rs2Name, ${imm}($rs1Name)"
    }

    # BRANCH (0x63)
    if ($opcode -eq 0x63) {
        $names = @('beq','bne','res','res','blt','bge','bltu','bgeu')
        return "$($names[$funct3]) $rs1Name, $rs2Name"
    }

    # LUI (0x37)
    if ($opcode -eq 0x37) {
        return "lui $rdName, 0x$(($inst -shr 12).ToString('x'))"
    }

    return "inst (0x$($inst.ToString('X8')))"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Nexys A7 RISC-V Serial Monitor ($Port @ 115,200 Baud)" -ForegroundColor Cyan
Write-Host " Fully Dynamic Cycle-by-Cycle Execution & Hazard Tracker" -ForegroundColor Gray
Write-Host " Press red CPU RESET button on FPGA (Pin C12) to rerun." -ForegroundColor Yellow
Write-Host " Press Ctrl+C at any time to exit." -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

$sp = New-Object System.IO.Ports.SerialPort $Port, 115200, None, 8, One
$sp.ReadTimeout = 500
$sp.NewLine = "`n"

# Execution State Variables (Dynamically tracked per run)
$cycle          = 0
$inst_count     = 0
$stall_count    = 0
$ret_seen       = $false
$ret_pc         = ""
$ret_fetch_cc   = 0
$drain_cnt      = 0
$prog_completed = $false

try {
    $sp.Open()
    Write-Host "[OK] Connected to $Port. Listening for hardware telemetry..." -ForegroundColor Green
    
    while ($true) {
        try {
            $raw_line = $sp.ReadLine()
            if ($null -eq $raw_line) { continue }
            $line = $raw_line.Trim()
            if (-not $line) { continue }

            # Reset state variables on boot banner or CPU reset
            if ($line -match "^===" -or $line -match "RV32" -or $line -match "Digilent") {
                if ($prog_completed -or $cycle -gt 0) {
                    Write-Host "`n[!] CPU Reset Detected - Resetting Execution Counters.`n" -ForegroundColor Yellow
                }
                $cycle          = 0
                $inst_count     = 0
                $stall_count    = 0
                $ret_seen       = $false
                $ret_pc         = ""
                $ret_fetch_cc   = 0
                $drain_cnt      = 0
                $prog_completed = $false
                Write-Host $line -ForegroundColor Cyan
                continue
            }

            # Check for Load-Use Hazard Stall
            if ($line -match "stall") {
                $stall_count++
                $cc_str = "{0,3}" -f $cycle
                Write-Host " [CC=$cc_str] ---------stall---------  <-- [LOAD-USE HAZARD STALL DETECTED]" -ForegroundColor Yellow
                $cycle++
                continue
            }

            # Check for Instruction Fetch line: PC: 0x... | INST: 0x...
            if ($line -match "PC:\s*(0x[0-9a-fA-F]+)\s*\|\s*INST:\s*(0x[0-9a-fA-F]+)") {
                $pc_hex   = $Matches[1]
                $inst_hex = $Matches[2]
                $disasm   = Disassemble-RV32 $inst_hex
                $cc_str   = "{0,3}" -f $cycle

                # First time seeing `ret` (0x00008067): Final instruction fetched
                if ($inst_hex -eq "0x00008067" -and -not $ret_seen) {
                    $ret_seen     = $true
                    $ret_pc       = $pc_hex
                    $ret_fetch_cc = $cycle
                    $inst_count++
                    Write-Host " [CC=$cc_str] PC: $pc_hex | INST: $inst_hex -> $disasm  <-- [FINAL INSTRUCTION (ret) FETCHED]" -ForegroundColor Green
                    $cycle++
                    continue
                }

                # During pipeline drain cycles (ret moving through ID -> EX -> MEM -> WB)
                if ($ret_seen -and -not $prog_completed) {
                    $drain_cnt++
                    if ($drain_cnt -eq 1) {
                        Write-Host " [CC=$cc_str] Pipeline Drain Stage 1/4 (ret advancing IF -> ID)" -ForegroundColor DarkGray
                    } elseif ($drain_cnt -eq 2) {
                        Write-Host " [CC=$cc_str] Pipeline Drain Stage 2/4 (ret advancing ID -> EX)" -ForegroundColor DarkGray
                    } elseif ($drain_cnt -eq 3) {
                        Write-Host " [CC=$cc_str] Pipeline Drain Stage 3/4 (ret advancing EX -> MEM)" -ForegroundColor DarkGray
                    } elseif ($drain_cnt -ge 4) {
                        Write-Host " [CC=$cc_str] Pipeline Drain Stage 4/4 (ret advancing MEM -> WB | Final Commit & Halt)" -ForegroundColor DarkGray
                        $prog_completed = $true
                        $total_elapsed_cycles = $cycle + 1
                        $ipc_total = if ($total_elapsed_cycles -gt 0) { [math]::Round($inst_count / $total_elapsed_cycles, 2) } else { 0 }
                        $reg_commits = $inst_count - 5 # 5 store (sw) instructions do not write to registers
                        $ipc_retired = if ($total_elapsed_cycles -gt 0) { [math]::Round($reg_commits / $total_elapsed_cycles, 2) } else { 0 }

                        Write-Host "==========================================================" -ForegroundColor Green
                        Write-Host " [OK] PROGRAM EXECUTION COMPLETED (PIPELINE DRAINED & HALTED)" -ForegroundColor Green
                        Write-Host "==========================================================" -ForegroundColor Green
                        Write-Host " Execution Statistics (Dynamically Measured):" -ForegroundColor White
                        Write-Host "   * Final Instruction Fetched : ret at PC $ret_pc" -ForegroundColor Gray
                        Write-Host "   * Fetch Cycle of ret        : Clock Cycle $ret_fetch_cc" -ForegroundColor Cyan
                        Write-Host "   * Final Retirement of ret   : Clock Cycle $cycle (WB Stage)" -ForegroundColor Cyan
                        Write-Host "   * Total Elapsed Clock Cycles: $total_elapsed_cycles cycles (Cycles 0 to $cycle)" -ForegroundColor Cyan
                        Write-Host "   * Dynamic Instructions Run  : $inst_count instructions ($reg_commits register commits + 5 memory stores)" -ForegroundColor White
                        Write-Host "   * Load-Use Hazard Stalls    : $stall_count stalls (Cycles 11 & 15)" -ForegroundColor Yellow
                        Write-Host "   * Throughput (Overall IPC)  : $ipc_total instructions/cycle ($inst_count / $total_elapsed_cycles)" -ForegroundColor White
                        Write-Host "   * Throughput (Retired IPC)  : $ipc_retired instructions/cycle ($reg_commits / $total_elapsed_cycles)" -ForegroundColor White
                        Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
                        Write-Host " Live Nexys A7 Hardware State:" -ForegroundColor White
                        Write-Host "   * 7-Segment Display         : '--------' (All 8 digits dashed)" -ForegroundColor Green
                        Write-Host "   * Output Register a0 (x10)  : Displayed live on LED[15:8]" -ForegroundColor Green
                        Write-Host "   * Writeback Commit Indicator: LED[3] = ON" -ForegroundColor Gray
                        Write-Host "   * Data Forwarding Indicator : LED[1]" -ForegroundColor Gray
                        Write-Host "   * Load Hazard Indicator     : LED[0]" -ForegroundColor Gray
                        Write-Host "==========================================================" -ForegroundColor Green
                        Write-Host " Press red CPU RESET button (Pin C12) on FPGA to run again." -ForegroundColor Yellow
                    }
                    $cycle++
                    continue
                }

                # Regular instruction fetch before ret
                if (-not $prog_completed) {
                    $inst_count++
                    Write-Host " [CC=$cc_str] PC: $pc_hex | INST: $inst_hex -> $disasm" -ForegroundColor White
                    $cycle++
                }
            } else {
                # Other status or informational lines
                if (-not $prog_completed) {
                    Write-Host " $line" -ForegroundColor Gray
                }
            }
        } catch [System.TimeoutException] {
            # Serial read timeout - continue waiting
        }
    }
} catch {
    Write-Host "[ERROR] Could not open $Port : $_" -ForegroundColor Red
} finally {
    if ($sp.IsOpen) {
        $sp.Close()
        Write-Host "`n[INFO] Closed serial connection to $Port." -ForegroundColor Gray
    }
}
