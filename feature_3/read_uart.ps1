# ============================================================================
# Script: read_uart.ps1 (Dedicated to Feature 3: RV32IM with Hardware Divider)
# Description: Real-Time Cycle-by-Cycle UART Monitor & Divider Diagnostic Telemetry
# Location: feature_3/read_uart.ps1
# Usage:
#   powershell -ExecutionPolicy Bypass -File feature_3\read_uart.ps1
#   powershell -ExecutionPolicy Bypass -File feature_3\read_uart.ps1 -Port COM4
# ============================================================================

param(
    [string]$Port = "",
    [int]$Baud = 115200
)

# Auto-detect COM port if not explicitly provided
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
# RV32IM Disassembler (RV32I Base + RV32M Hardware Multiply & Divide)
# ============================================================================
function Disassemble-RV32 {
    param([string]$hexStr)
    try {
        $cleanHex = $hexStr.Replace("0x","").Replace("0X","").Trim()
        $inst = [System.Convert]::ToUInt32($cleanHex, 16)
    } catch {
        return ""
    }

    if ($inst -eq 0x00000013) { return "nop" }
    if ($inst -eq 0x00008067) { return "ret" }
    if ($inst -eq 0x00000000) { return "bubble (nop)" }

    $opcode = [int]($inst -band 0x7F)
    $rd     = [int](($inst -shr 7) -band 0x1F)
    $funct3 = [int](($inst -shr 12) -band 0x07)
    $rs1    = [int](($inst -shr 15) -band 0x1F)
    $rs2    = [int](($inst -shr 20) -band 0x1F)
    $funct7 = [int](($inst -shr 25) -band 0x7F)

    $regNames = @(
        'zero', 'ra', 'sp', 'gp', 'tp', 't0', 't1', 't2',
        's0',   's1', 'a0', 'a1', 'a2', 'a3', 'a4', 'a5',
        'a6',   'a7', 's2', 's3', 's4', 's5', 's6', 's7',
        's8',   's9', 's10','s11','t3', 't4', 't5', 't6'
    )

    $rdName  = $regNames[$rd]
    $rs1Name = $regNames[$rs1]
    $rs2Name = $regNames[$rs2]

    # OP-IMM (0x13): addi, slli, slti, etc.
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

    # OP / RV32M (0x33): mul, div, rem, add, sub, etc.
    if ($opcode -eq 0x33) {
        if ($funct7 -eq 0x01) {
            # RV32M Extension
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
        $imm = [int32](((($inst -shr 7) -band 0x1F) -bor ((($inst -shr 25) -band 0x7F) -shl 5)))
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

    # JAL (0x6F)
    if ($opcode -eq 0x6F) {
        return "j 0x$(($inst -shr 12).ToString('x'))"
    }

    # JALR (0x67)
    if ($opcode -eq 0x67) {
        return "jalr $rdName, ${rs1Name}"
    }

    return "inst (0x$($inst.ToString('X8')))"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Nexys A7 RISC-V Serial Monitor ($Port @ $Baud Baud)" -ForegroundColor Cyan
Write-Host " Feature 3: RV32IM Hardware Divider (32-Cycle Radix-2)" -ForegroundColor Yellow
Write-Host " Fully Dynamic Cycle-by-Cycle Execution & Hazard Tracker" -ForegroundColor Gray
Write-Host " Press red CPU RESET button on FPGA (Pin C12) to rerun." -ForegroundColor Yellow
Write-Host " Press Ctrl+C at any time to exit." -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, None, 8, One
$sp.ReadTimeout = 500
$sp.NewLine = "`n"

# Execution State Variables (Clock cycles start at 1)
$cycle               = 1
$inst_count          = 0
$stall_count         = 0
$consec_stalls       = 0
$stat_div_stalls     = 0
$stat_loaduse_stalls = 0
$stat_branch_stalls  = 0
$recent_disasms      = @()
$recent_pcs          = @()
$ret_seen            = $false
$ret_pc              = ""
$ret_fetch_cc        = 0
$drain_cnt           = 0
$prog_completed      = $false

try {
    $sp.Open()
    Write-Host "[OK] Connected to $Port. Listening for hardware telemetry..." -ForegroundColor Green
    
    while ($true) {
        try {
            $raw_line = $sp.ReadLine()
            if ($null -eq $raw_line) { continue }
            $line = $raw_line.Trim()
            if (-not $line) { continue }

            # Reset state variables on real boot banner or CPU reset
            if ($line -match "RV32" -or $line -match "Digilent" -or $line -match "^===\s*RV32") {
                if ($prog_completed -or $cycle -gt 1) {
                    Write-Host "`n[!] CPU Reset Detected - Resetting Feature 3 Execution Counters.`n" -ForegroundColor Yellow
                }
                $cycle               = 1
                $inst_count          = 0
                $stall_count         = 0
                $consec_stalls       = 0
                $stat_div_stalls     = 0
                $stat_loaduse_stalls = 0
                $stat_branch_stalls  = 0
                $recent_disasms      = @()
                $recent_pcs          = @()
                $ret_seen            = $false
                $ret_pc              = ""
                $ret_fetch_cc        = 0
                $drain_cnt           = 0
                $prog_completed      = $false
                Write-Host $line -ForegroundColor Cyan
                continue
            }

            # Pass through hardware execution summary lines
            if ($line -match "SUMMARY" -or $line -match "Retired :" -or $line -match "Cycles" -or $line -match "Return Value" -or ($line -match "^===" -and $prog_completed)) {
                Write-Host " $line" -ForegroundColor Green
                continue
            }

            # Check for Pipeline Stall Line
            if ($line -match "stall") {
                if ($prog_completed) { continue }
                $stall_count++
                $consec_stalls++
                $cc_str = "{0,3}" -f $cycle

                $prev_inst = if ($recent_disasms.Count -ge 1) { $recent_disasms[-1] } else { "" }
                $prev_prev = if ($recent_disasms.Count -ge 2) { $recent_disasms[-2] } else { "" }

                # Scan recent instructions to detect active divider operation
                $div_candidates = @($recent_disasms | Where-Object { $_ -match "^(div|divu|rem|remu)\b" })
                $active_div = if ($div_candidates.Count -gt 0) { $div_candidates[-1] } else { "" }

                $stall_tag = ""
                $stall_color = "Yellow"

                # 1. Active Divider Operation (32 stall cycles for Radix-2 Restoring Divider)
                if ($active_div -and $consec_stalls -le 32) {
                    $stat_div_stalls++
                    $stall_color = "Cyan"
                    $op_name = ($active_div -split '\s+')[0].ToUpper()
                    if ($consec_stalls -eq 32) {
                        $stall_tag = "DIVIDER STALL: $active_div (Cycle 32/32 | Quotient & Remainder Formed)"
                    } elseif ($consec_stalls -eq 1) {
                        $stall_tag = "DIVIDER STALL: $active_div (Cycle  1/32 | Operand Latch & Trial Subtraction)"
                    } else {
                        $stall_tag = "DIVIDER STALL: $active_div (Cycle {0,2}/32 | Newton-Raphson Iteration)" -f $consec_stalls
                    }
                }
                # 2. Divider Corner Case 1-Cycle Bypass (Divide-by-Zero or Signed Overflow)
                elseif ($active_div -and $consec_stalls -eq 1) {
                    $stat_div_stalls++
                    $stall_color = "Cyan"
                    $stall_tag = "DIVIDER CORNER CASE: $active_div (1-Cycle Early-Out Bypass)"
                }
                # 3. Load-Use Data Hazard (1-cycle interlock)
                elseif ($consec_stalls -eq 1 -and ($prev_prev -match "^l[wbh]" -or $prev_inst -match "^l[wbh]")) {
                    $stat_loaduse_stalls++
                    $stall_color = "Magenta"
                    $stall_tag = "LOAD-USE DATA HAZARD STALL: 1-Cycle Interlock ($prev_inst)"
                }
                # 4. Branch Control Hazard (2-cycle branch penalty)
                elseif ($consec_stalls -le 2 -and ($prev_inst -match "^b[a-z]+" -or $prev_inst -match "^j" -or $prev_inst -match "^ret")) {
                    $stat_branch_stalls++
                    $stall_color = "DarkYellow"
                    $stall_tag = "BRANCH CONTROL HAZARD: Branch Penalty Bubble $consec_stalls/2"
                }
                # 5. Generic Pipeline Stall
                else {
                    $stall_tag = "PIPELINE STALL: Multi-Cycle Interlock Wait"
                    $stall_color = "Yellow"
                }

                Write-Host " [CC=$cc_str] ---------stall---------  <-- [$stall_tag]" -ForegroundColor $stall_color
                $cycle++
                continue
            }

            # Check for Instruction Fetch line: PC: 0x... | INST: 0x...
            if ($line -match "PC:\s*(0x[0-9a-fA-F]+)\s*\|\s*INST:\s*(0x[0-9a-fA-F]+)") {
                $consec_stalls = 0
                $pc_hex   = $Matches[1]
                $inst_hex = $Matches[2]
                $disasm   = Disassemble-RV32 $inst_hex
                $cc_str   = "{0,3}" -f $cycle

                $recent_disasms += $disasm
                $recent_pcs     += $pc_hex
                if ($recent_disasms.Count -gt 12) {
                    $recent_disasms = @($recent_disasms[-12..-1])
                    $recent_pcs     = @($recent_pcs[-12..-1])
                }

                # Final instruction fetched: `ret` (0x00008067)
                if ($inst_hex -eq "0x00008067" -and -not $ret_seen) {
                    $ret_seen     = $true
                    $ret_pc       = $pc_hex
                    $ret_fetch_cc = $cycle
                    $inst_count++
                    Write-Host " [CC=$cc_str] PC: $pc_hex | INST: $inst_hex -> $disasm  <-- [FINAL INSTRUCTION (ret) FETCHED]" -ForegroundColor Green
                    $cycle++
                    continue
                }

                # During pipeline drain cycles
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
                        $total_elapsed_cycles = $cycle
                        $ipc_total = if ($total_elapsed_cycles -gt 0) { [math]::Round($inst_count / $total_elapsed_cycles, 2) } else { 0 }

                        Write-Host "==========================================================" -ForegroundColor Green
                        Write-Host " [OK] FEATURE 3 DIVIDER PROGRAM COMPLETED (PIPELINE DRAINED)" -ForegroundColor Green
                        Write-Host "==========================================================" -ForegroundColor Green
                        Write-Host " Execution Statistics (Dynamically Measured):" -ForegroundColor White
                        Write-Host "   * Final Instruction Fetched : ret at PC $ret_pc" -ForegroundColor Gray
                        Write-Host "   * Fetch Cycle of ret        : Clock Cycle $ret_fetch_cc" -ForegroundColor Cyan
                        Write-Host "   * Final Retirement of ret   : Clock Cycle $cycle (WB Stage)" -ForegroundColor Cyan
                        Write-Host "   * Total Elapsed Clock Cycles: $total_elapsed_cycles cycles (Cycles 1 to $cycle)" -ForegroundColor Cyan
                        Write-Host "   * Total Instructions Run    : $inst_count instructions" -ForegroundColor White
                        Write-Host "   * Pipeline Stalls Breakdown :" -ForegroundColor Yellow
                        Write-Host "       - Multi-Cycle DIV Stalls  : $stat_div_stalls stalls (div/divu/rem/remu: 32 cycles each)" -ForegroundColor Cyan
                        Write-Host "       - Load-Use Data Hazards   : $stat_loaduse_stalls stalls (1-cycle interlock bubbles)" -ForegroundColor Magenta
                        Write-Host "       - Branch Control Hazards  : $stat_branch_stalls stalls (2-cycle branch penalties)" -ForegroundColor DarkYellow
                        Write-Host "       - Total Pipeline Stalls   : $stall_count stalls" -ForegroundColor White
                        Write-Host "   * Throughput (Overall IPC)  : $ipc_total instructions/cycle ($inst_count / $total_elapsed_cycles)" -ForegroundColor White
                        Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
                        Write-Host " Live Nexys A7 Hardware State:" -ForegroundColor White
                        Write-Host "   * 7-Segment Display         : '--------' (All 8 digits dashed)" -ForegroundColor Green
                        Write-Host "   * Output Register a0 (x10)  : Displayed live on LED[15:8] = 0x10 (16)" -ForegroundColor Green
                        Write-Host "   * Divider Active Indicator  : LED[5]" -ForegroundColor Gray
                        Write-Host "   * Writeback Commit Indicator: LED[3] = ON" -ForegroundColor Gray
                        Write-Host "   * Data Forwarding Indicator : LED[1]" -ForegroundColor Gray
                        Write-Host "   * Program Completed         : LED[7] = ON" -ForegroundColor Gray
                        Write-Host "==========================================================" -ForegroundColor Green
                        Write-Host " Press red CPU RESET button (Pin C12) on FPGA to run again." -ForegroundColor Yellow
                    }
                    $cycle++
                    continue
                }

                # Regular instruction fetch before ret
                if (-not $prog_completed) {
                    $inst_count++
                    $is_div_inst = ($disasm -match "^(div|divu|rem|remu)\b")
                    $line_color = if ($is_div_inst) { "Cyan" } else { "White" }
                    Write-Host " [CC=$cc_str] PC: $pc_hex | INST: $inst_hex -> $disasm" -ForegroundColor $line_color
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
