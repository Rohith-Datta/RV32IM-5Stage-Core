# ============================================================================
# Script: read_uart.ps1 (Dedicated to Feature 4: RV32IMF with IEEE 754 FPU)
# Description: Real-Time Cycle-by-Cycle UART Monitor & FPU Diagnostic Telemetry
# Location: feature_4/read_uart.ps1
# Usage:
#   powershell -ExecutionPolicy Bypass -File feature_4\read_uart.ps1
#   powershell -ExecutionPolicy Bypass -File feature_4\read_uart.ps1 -Port COM5
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
# RV32IMF Disassembler (RV32I Base + RV32M Math + RV32F IEEE 754 Single FPU)
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
        $names = @('addi','slli','slti','sltiu','xori','sr','ori','andi')
        if ($funct3 -eq 0) {
            if ($rs1 -eq 0) { return "li $rdName, $imm" }
            return "addi $rdName, $rs1Name, $imm"
        }
        if ($funct3 -eq 5) {
            $is_sra = (($inst -shr 30) -band 1) -eq 1
            $shift_name = if ($is_sra) { "srai" } else { "srli" }
            $shamt = $imm -band 0x1F
            return "$shift_name $rdName, $rs1Name, $shamt"
        }
        return "$($names[$funct3]) $rdName, $rs1Name, $imm"
    }

    # OP / ARITHR (0x33): Base ALU & RV32M (mul, div, rem)
    if ($opcode -eq 0x33) {
        # RV32M Extension (funct7 == 0x01)
        if ($funct7 -eq 0x01) {
            $m_names = @('mul','mulh','mulhsu','mulhu','div','divu','rem','remu')
            return "$($m_names[$funct3]) $rdName, $rs1Name, $rs2Name"
        }
        if ($funct3 -eq 0) {
            if ($funct7 -eq 0x20) { return "sub $rdName, $rs1Name, $rs2Name" }
            return "add $rdName, $rs1Name, $rs2Name"
        }
        if ($funct3 -eq 5) {
            if ($funct7 -eq 0x20) { return "sra $rdName, $rs1Name, $rs2Name" }
            return "srl $rdName, $rs1Name, $rs2Name"
        }
        $names = @('add/sub','sll','slt','sltu','xor','srl/sra','or','and')
        return "$($names[$funct3]) $rdName, $rs1Name, $rs2Name"
    }

    # OP_FP / RV32F (0x53): IEEE 754 Single-Precision Floating-Point
    if ($opcode -eq 0x53) {
        $fpName = switch ($funct7) {
            0x00 { "fadd.s" }
            0x04 { "fsub.s" }
            0x08 { "fmul.s" }
            0x10 { "fmul.s" }
            0x0C { "fdiv.s" }
            0x2C { "fsqrt.s" }
            0x60 { "fcvt.w.s" }
            0x70 { "fmv.x.w" }
            0x50 {
                switch ($funct3) {
                    0 { "fle.s" }
                    1 { "flt.s" }
                    2 { "feq.s" }
                    default { "fcmp.s" }
                }
            }
            default { "fp_0x{0:X2}" -f $funct7 }
        }
        return "$fpName $rdName, $rs1Name, $rs2Name"
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

    # AUIPC (0x17)
    if ($opcode -eq 0x17) {
        return "auipc $rdName, 0x$(($inst -shr 12).ToString('x'))"
    }

    # JAL (0x6F)
    if ($opcode -eq 0x6F) {
        if ($rd -eq 0) { return "j" }
        return "jal $rdName"
    }

    # JALR (0x67)
    if ($opcode -eq 0x67) {
        return "jalr $rdName, ${rs1Name}"
    }

    return "inst (0x$($inst.ToString('X8')))"
}

# ============================================================================
# Main Serial Telemetry Loop
# ============================================================================
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Nexys A7 RV32IMF Real-Time FPU Serial Monitor ($Port @ $Baud Baud)" -ForegroundColor White
Write-Host " Tracking IEEE 754 Floating-Point Unit (Feature 4 Execution)" -ForegroundColor Cyan
Write-Host " Press red CPU RESET button on FPGA (Pin C12) to rerun." -ForegroundColor Yellow
Write-Host " Press Ctrl+C at any time to exit." -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Cyan

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, None, 8, One
$sp.ReadTimeout  = 500
$sp.NewLine      = "`n"

$cycle               = 0
$inst_count          = 0
$stall_count         = 0
$consec_stalls       = 0
$stat_fpu_stalls     = 0
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
    Write-Host "[OK] Connected to $Port. Listening for Feature 4 hardware telemetry..." -ForegroundColor Green
    
    while ($true) {
        try {
            $raw_line = $sp.ReadLine()
            if ($null -eq $raw_line) { continue }
            $line = $raw_line.Trim()
            if (-not $line) { continue }

            # Reset state variables on real boot banner or CPU reset
            if ($line -match "RV32" -or $line -match "Digilent" -or $line -match "^===\s*RV32") {
                if ($prog_completed -or $cycle -gt 0) {
                    Write-Host "`n[!] CPU Reset Detected - Resetting Feature 4 Execution Counters.`n" -ForegroundColor Yellow
                }
                $cycle               = 0
                $inst_count          = 0
                $stall_count         = 0
                $consec_stalls       = 0
                $stat_fpu_stalls     = 0
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
            if ($line -match "SUMMARY" -or $line -match "Retired :" -or $line -match "Retired" -or $line -match "Cycles" -or $line -match "FPU Stall" -or $line -match "Return Value" -or ($line -match "^===" -and $prog_completed)) {
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

                # Scan recent instructions to detect active FPU or Divider operation
                $fpu_candidates = @($recent_disasms | Where-Object { $_ -match "^f(add|sub|mul|div|sqrt)\.s" })
                $active_fpu = if ($fpu_candidates.Count -gt 0) { $fpu_candidates[-1] } else { "" }

                $div_candidates = @($recent_disasms | Where-Object { $_ -match "^(div|divu|rem|remu)\b" })
                $active_div = if ($div_candidates.Count -gt 0) { $div_candidates[-1] } else { "" }

                $stall_tag = ""
                $stall_color = "Yellow"

                # 1. Load-Use Data Hazard (1-cycle interlock when load was in EX and dependent inst in ID)
                if ($consec_stalls -eq 1 -and ($prev_prev -match "^l[wbh]" -or $prev_inst -match "^l[wbh]")) {
                    $stat_loaduse_stalls++
                    $stall_color = "Magenta"
                    $stall_tag = if ($prev_inst -match "^f") {
                        "LOAD-USE DATA HAZARD STALL: FPU Operand Interlock ($prev_inst)"
                    } else {
                        "LOAD-USE DATA HAZARD STALL: 1-Cycle Interlock ($prev_inst)"
                    }
                }
                # 2. Active FPU Division (14 stall cycles, 15 cycles total latency)
                elseif ($active_fpu -and $active_fpu -match "^fdiv\.s") {
                    $stat_fpu_stalls++
                    $stall_color = "Cyan"
                    $stall_tag = "FPU DIVISION STALL: $active_fpu (Stall {0,2}/14 | Latency: 15 Cycles - Radix-4 Restoring Divider)" -f $consec_stalls
                }
                # 3. Active FPU Add / Sub (4 stall cycles, 5 cycles total latency)
                elseif ($active_fpu -and ($active_fpu -match "^fadd\.s" -or $active_fpu -match "^fsub\.s") -and $consec_stalls -le 4) {
                    $stat_fpu_stalls++
                    $stall_color = "Cyan"
                    $stall_tag = "FPU ARITHMETIC STALL: $active_fpu (Stall {0,2}/4 | Latency: 5 Cycles - Pipeline)" -f $consec_stalls
                }
                # 4. Active FPU Multiply (3 stall cycles, 4 cycles total latency)
                elseif ($active_fpu -and $active_fpu -match "^fmul\.s" -and $consec_stalls -le 3) {
                    $stat_fpu_stalls++
                    $stall_color = "Cyan"
                    $stall_tag = "FPU MULTIPLY STALL: $active_fpu (Stall {0,2}/3 | Latency: 4 Cycles - DSP Multiplier)" -f $consec_stalls
                }
                # 5. Active Hardware Integer Divider (31-cycle serial radix-2 division)
                elseif ($active_div -and $consec_stalls -le 31) {
                    $stall_color = "Cyan"
                    $stall_tag = "HARDWARE DIVIDER STALL: $active_div (Cycle {0,2}/31 - Radix-2 Serial Divider)" -f $consec_stalls
                }
                # 6. Branch Control Hazard (2-cycle flush penalty)
                elseif ($consec_stalls -le 2 -and ($prev_inst -match "^b[a-z]+" -or $prev_inst -match "^j" -or $prev_inst -match "^ret")) {
                    $stat_branch_stalls++
                    $stall_color = "DarkYellow"
                    $stall_tag = "BRANCH CONTROL HAZARD: Branch Penalty Bubble $consec_stalls/2"
                }
                # 7. Generic FPU or Pipeline Execution Stall
                elseif ($active_fpu) {
                    $stat_fpu_stalls++
                    $stall_color = "Cyan"
                    $stall_tag = "FPU EXECUTION STALL: $active_fpu (Cycle {0,2})" -f $consec_stalls
                }
                else {
                    $stall_color = "Yellow"
                    $stall_tag = "PIPELINE STALL: Multi-Cycle Interlock Wait"
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
                    $recent_disasms = $recent_disasms[-12..-1]
                    $recent_pcs     = $recent_pcs[-12..-1]
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
                        Write-Host " [CC=$cc_str] Pipeline Drain Stage 1/5 (ret advancing IF -> ID)" -ForegroundColor DarkGray
                    } elseif ($drain_cnt -eq 2) {
                        Write-Host " [CC=$cc_str] Pipeline Drain Stage 2/5 (ret advancing ID -> EX)" -ForegroundColor DarkGray
                    } elseif ($drain_cnt -eq 3) {
                        Write-Host " [CC=$cc_str] Pipeline Drain Stage 3/5 (ret advancing EX -> MEM)" -ForegroundColor DarkGray
                    } elseif ($drain_cnt -eq 4) {
                        Write-Host " [CC=$cc_str] Pipeline Drain Stage 4/5 (ret advancing MEM -> WB | Retirement)" -ForegroundColor DarkGray
                    } elseif ($drain_cnt -ge 5) {
                        Write-Host " [CC=$cc_str] Pipeline Drain Stage 5/5 (Core Freeze & Latch Hardware Summary)" -ForegroundColor DarkGray
                        $prog_completed = $true
                        $total_elapsed_cycles = $cycle + 1
                        $ipc_total = if ($total_elapsed_cycles -gt 0) { [math]::Round($inst_count / $total_elapsed_cycles, 2) } else { 0 }

                        Write-Host "==========================================================" -ForegroundColor Green
                        Write-Host " [OK] FEATURE 4 FPU PROGRAM COMPLETED (PIPELINE DRAINED)" -ForegroundColor Green
                        Write-Host "==========================================================" -ForegroundColor Green
                        Write-Host " Execution Statistics (Dynamically Measured):" -ForegroundColor White
                        Write-Host "   * Final Instruction Fetched : ret at PC $ret_pc" -ForegroundColor Gray
                        Write-Host "   * Fetch Cycle of ret        : Clock Cycle $ret_fetch_cc" -ForegroundColor Cyan
                        Write-Host "   * Final Retirement of ret   : Clock Cycle $cycle (WB Stage)" -ForegroundColor Cyan
                        Write-Host "   * Total Elapsed Clock Cycles: $total_elapsed_cycles cycles" -ForegroundColor Cyan
                        Write-Host "   * Total Instructions Run    : $inst_count instructions" -ForegroundColor White
                        Write-Host "   * Pipeline Stalls Breakdown :" -ForegroundColor Yellow
                        Write-Host "       - Multi-Cycle FPU Stalls  : $stat_fpu_stalls stalls (fadd/fsub/fmul/fdiv)" -ForegroundColor Cyan
                        Write-Host "       - Load-Use Data Hazards   : $stat_loaduse_stalls stalls (1-cycle interlock)" -ForegroundColor Magenta
                        Write-Host "       - Branch Control Hazards  : $stat_branch_stalls stalls (2-cycle flushes)" -ForegroundColor DarkYellow
                        Write-Host "       - Total Pipeline Stalls   : $stall_count stalls" -ForegroundColor White
                        Write-Host "   * Throughput (Overall IPC)  : $ipc_total instructions/cycle" -ForegroundColor White
                        Write-Host "==========================================================" -ForegroundColor Green
                        Write-Host " Press red CPU RESET button (Pin C12) on FPGA to run again." -ForegroundColor Yellow
                    }
                    $cycle++
                    continue
                }

                # Regular instruction fetch before ret
                if (-not $prog_completed) {
                    $inst_count++
                    $is_fpu_inst = ($disasm -match "^f(add|sub|mul|div)\.s")
                    $line_color = if ($is_fpu_inst) { "Cyan" } else { "White" }
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
            # Timeout waiting for next byte/line - keep waiting
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
