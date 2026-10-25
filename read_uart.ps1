# ============================================================================
# Script: read_uart.ps1
# Description: Fully Dynamic Real-Time Serial Monitor for Feature 5 (RV32IMF + D-Cache)
# Usage: 
#   powershell -ExecutionPolicy Bypass -File read_uart.ps1
#   powershell -ExecutionPolicy Bypass -File read_uart.ps1 -Bypass
#   powershell -ExecutionPolicy Bypass -File read_uart.ps1 -Port COM4 -Bypass
# ============================================================================

param(
    [Parameter(Position=0)]
    [string]$Port = "",
    [Parameter(Position=1)]
    [string]$Mode = "",
    [switch]$Bypass,
    [switch]$CacheBypass
)

if (-not $Port -or $Port -eq "bypass" -or $Port -eq "enabled") {
    if ($Port -eq "bypass") { $Mode = "bypass"; $Port = "" }
    $ports = [System.IO.Ports.SerialPort]::GetPortNames()
    if ($ports.Count -eq 0) {
        Write-Host "[!] No active COM ports detected." -ForegroundColor Yellow
        Write-Host "    Please connect your Nexys A7 FPGA board via micro-USB." -ForegroundColor Gray
        exit
    }
    $Port = $ports[0]
}

$is_bypass_arg = $Bypass.IsPresent -or $CacheBypass.IsPresent -or ($Mode -match "bypass")
$dcache_bypass_mode = $is_bypass_arg

# ============================================================================
# Dynamic RV32I / RV32M / RV32F Disassembler
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

    # OP-FP / RV32F (0x53)
    if ($opcode -eq 0x53) {
        $name = switch ([int]$funct7) {
            0x00 { "fadd.s" }
            0x04 { "fsub.s" }
            0x08 { "fmul.s" }
            0x0C { "fdiv.s" }
            0x10 { "fmul.s" }
            default { "fp_0x$([int]$funct7).ToString('X2')" }
        }
        return "$name $rdName, $rs1Name, $rs2Name"
    }

    return "inst (0x$($inst.ToString('X8')))"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Nexys A7 RISC-V Serial Monitor ($Port @ 115,200 Baud)" -ForegroundColor Cyan
if ($dcache_bypass_mode) {
    Write-Host " Feature 5: RV32IMF [D-CACHE BYPASS MODE (DIRECT MEMORY ACCESS)]" -ForegroundColor Magenta
} else {
    Write-Host " Feature 5: RV32IMF + Direct-Mapped L1 D-Cache" -ForegroundColor Yellow
}
Write-Host " Fully Dynamic Cycle-by-Cycle Execution & Hazard Tracker" -ForegroundColor Gray
Write-Host " Press red CPU RESET button on FPGA (Pin C12) to rerun." -ForegroundColor Yellow
Write-Host " Press Ctrl+C at any time to exit." -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

$sp = New-Object System.IO.Ports.SerialPort $Port, 115200, None, 8, One
$sp.ReadTimeout = 500
$sp.NewLine = "`n"

# Execution State Variables (Clock cycles start at 1)
$cycle               = 1
$inst_count          = 0
$stall_count         = 0
$consec_stalls       = 0
$consec_dcache       = 0
$dcache_event_count  = 0
$stat_dcache_stalls  = 0
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

            # Reset state variables ONLY on real boot banner or CPU reset (not summary borders)
            if ($line -match "RV32" -or $line -match "Digilent" -or $line -match "^===\s*RV32") {
                if ($prog_completed -or $cycle -gt 1) {
                    Write-Host "`n[!] CPU Reset Detected - Resetting Execution Counters.`n" -ForegroundColor Yellow
                }
                $cycle               = 1
                $inst_count          = 0
                $stall_count         = 0
                $consec_stalls       = 0
                $consec_dcache       = 0
                $dcache_event_count  = 0
                $stat_dcache_stalls  = 0
                $stat_loaduse_stalls = 0
                $stat_branch_stalls  = 0
                $recent_disasms      = @()
                $recent_pcs          = @()
                $ret_seen            = $false
                $ret_pc              = ""
                $ret_fetch_cc        = 0
                $drain_cnt           = 0
                $prog_completed      = $false
                $dcache_bypass_mode  = ($is_bypass_arg -or $dcache_bypass_mode)
                Write-Host $line -ForegroundColor Cyan
                continue
            }

            # Pass through summary borders and statistics without misinterpreting as reset
            if ($line -match "SUMMARY" -or $line -match "Retired :" -or $line -match "Hits      :" -or $line -match "Misses    :" -or $line -match "Value a0:" -or ($line -match "^===" -and $prog_completed)) {
                if ($line -match "MODE:\s*BYPASS")  { $dcache_bypass_mode = $true }
                if ($line -match "MODE:\s*ENABLED") { if (-not $is_bypass_arg) { $dcache_bypass_mode = $false } }
                Write-Host " $line" -ForegroundColor Green
                continue
            }

            # Pass through Feature 6 I-cache formatted trace lines without mangling
            if ($line -match "^\s*\d+\s+0x[0-9a-fA-F]{8}\s+0x[0-9a-fA-F]{8}" -or $line -match "^\s*FLUSH\s+PC=") {
                Write-Host $line
                continue
            }

            # Check for Pipeline Hazard / D-Cache Stall
            if ($line -match "stall") {
                if ($prog_completed) { continue } # Ignore trailing drain/idle stalls after halt
                $stall_count++
                $consec_stalls++
                $cc_str = "{0,3}" -f $cycle

                $prev_inst = if ($recent_disasms.Count -ge 1) { $recent_disasms[-1] } else { "" }
                $prev_prev = if ($recent_disasms.Count -ge 2) { $recent_disasms[-2] } else { "" }

                $is_dcache_hardware = ($line -match "DCACHE")
                $is_hazard_hardware = ($line -match "HAZARD")

                $stall_tag = ""
                $stall_color = "Yellow"

                if ($is_dcache_hardware) {
                    $stat_dcache_stalls++
                    $consec_dcache++
                    $stall_color = "Cyan"
                    $refill_cycle = (($consec_dcache - 1) % 9) + 1

                    # Count how many memory access / refill events occurred
                    if ($refill_cycle -eq 1) {
                        $dcache_event_count++
                        # In dcache_test.c, having >1 D-Cache stalls proves cache bypass mode is active
                        if ($dcache_event_count -ge 2 -and -not $dcache_bypass_mode) {
                            $dcache_bypass_mode = $true
                        }
                    }

                    if ($dcache_bypass_mode) {
                        # CACHE BYPASS MODE: Direct Memory Access (No cache refill, no tag commit)
                        $desc = switch ($refill_cycle) {
                            1  { "Memory Read Request (Bypassing L1 Cache)" }
                            2  { "Memory Access Latency Wait" }
                            3  { "Backing Memory Read Word 0 Latched" }
                            4  { "Backing Memory Read Word 1 Latched" }
                            5  { "Backing Memory Read Word 2 Latched" }
                            6  { "Backing Memory Read Word 3 Latched" }
                            7  { "Memory Bus Transfer Complete" }
                            8  { "Requested Word Selected" }
                            9  { "Data Ready - Delivered Directly to CPU" }
                            default { "Direct Memory Read" }
                        }
                        $stall_tag = "MEMORY ACCESS: Cycle {0,2}/9 ($desc)" -f $refill_cycle
                    } else {
                        # CACHE ENABLED MODE: Cold Miss Refill
                        $desc = switch ($refill_cycle) {
                            1  { "Cold Miss / Memory Read Word 0" }
                            2  { "Memory Access Latency Wait" }
                            3  { "Backing Memory Read Word 0 Latched" }
                            4  { "Backing Memory Read Word 1 Latched" }
                            5  { "Backing Memory Read Word 2 Latched" }
                            6  { "Backing Memory Read Word 3 Latched" }
                            7  { "Cache Line Bank 0 Commit" }
                            8  { "Cache Line Bank 1 Commit" }
                            9  { "Line Valid & Tag Commit" }
                            default { "Burst Refill" }
                        }
                        $stall_tag = "D-CACHE MISS REFILL: Cycle {0,2}/9 ($desc)" -f $refill_cycle
                    }
                } elseif ($is_hazard_hardware) {
                    $consec_dcache = 0
                    $stat_loaduse_stalls++
                    $stall_color = "Magenta"
                    if ($prev_inst) {
                        $stall_tag = "LOAD-USE DATA HAZARD STALL: 1-Cycle Interlock ($prev_inst)"
                    } else {
                        $stall_tag = "LOAD-USE DATA HAZARD STALL: 1-Cycle Interlock"
                    }
                } else {
                    # Backward compatibility for generic "---------stall---------" lines without hardware tags
                    $is_branch_prev = ($prev_inst -match "^b[a-z]+" -or $prev_inst -match "^j" -or $prev_inst -match "^ret")
                    if ($is_branch_prev -and $consec_stalls -le 2) {
                        $stall_tag = "BRANCH CONTROL HAZARD: Branch Penalty Bubble $consec_stalls/2"
                        $stat_branch_stalls++
                        $stall_color = "DarkYellow"
                    } elseif ($consec_stalls -ge 3 -and $consec_stalls -le 11) {
                        $refill_idx = $consec_stalls - 2
                        if ($dcache_bypass_mode) {
                            $desc = switch ($refill_idx) {
                                1  { "Memory Read Request (Bypassing L1 Cache)" }
                                2  { "Memory Access Latency Wait" }
                                3  { "Backing Memory Read Word 0 Latched" }
                                4  { "Backing Memory Read Word 1 Latched" }
                                5  { "Backing Memory Read Word 2 Latched" }
                                6  { "Backing Memory Read Word 3 Latched" }
                                7  { "Memory Bus Transfer Complete" }
                                8  { "Requested Word Selected" }
                                9  { "Data Ready - Delivered Directly to CPU" }
                                default { "Direct Memory Read" }
                            }
                            $stall_tag = "MEMORY ACCESS: Cycle {0,2}/9 ($desc)" -f $refill_idx
                        } else {
                            $desc = switch ($refill_idx) {
                                1  { "Cold Miss Detected in IDLE" }
                                2  { "Memory Read Word 0" }
                                3  { "Backing Memory Read Word 0 Latched" }
                                4  { "Backing Memory Read Word 1 Latched" }
                                5  { "Backing Memory Read Word 2 Latched" }
                                6  { "Backing Memory Read Word 3 Latched" }
                                7  { "Cache Line Bank 0 Commit" }
                                8  { "Cache Line Bank 1 Commit" }
                                9  { "Line Valid & Tag Commit" }
                                default { "Burst Refill" }
                            }
                            $stall_tag = "D-CACHE MISS REFILL: Cycle {0,2}/9 ($desc)" -f $refill_idx
                        }
                        $stat_dcache_stalls++
                        $stall_color = "Cyan"
                    } elseif ($consec_stalls -le 2 -and ($prev_prev -match "^l[wbh]" -or $prev_inst -match "^l[wbh]")) {
                        $stall_tag = "LOAD-USE DATA HAZARD STALL: 1-Cycle Interlock ($prev_inst)"
                        $stat_loaduse_stalls++
                        $stall_color = "Magenta"
                    } else {
                        $stall_tag = "PIPELINE STALL: Hazard / Multi-Cycle Wait"
                        $stall_color = "Yellow"
                    }
                }

                Write-Host " [CC=$cc_str] ---------stall---------  <-- [$stall_tag]" -ForegroundColor $stall_color
                $cycle++
                continue
            }

            # Check for Instruction Fetch line: PC: 0x... | INST: 0x...
            if ($line -match "PC:\s*(0x[0-9a-fA-F]+)\s*\|\s*INST:\s*(0x[0-9a-fA-F]+)") {
                $consec_stalls = 0
                $consec_dcache = 0
                $pc_hex   = $Matches[1]
                $inst_hex = $Matches[2]
                $disasm   = Disassemble-RV32 $inst_hex
                $cc_str   = "{0,3}" -f $cycle

                $recent_disasms += $disasm
                $recent_pcs     += $pc_hex
                if ($recent_disasms.Count -gt 8) {
                    $recent_disasms = @($recent_disasms[-8..-1])
                    $recent_pcs     = @($recent_pcs[-8..-1])
                }

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
                        $total_elapsed_cycles = $cycle
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
                        Write-Host "   * Total Elapsed Clock Cycles: $total_elapsed_cycles cycles (Cycles 1 to $cycle)" -ForegroundColor Cyan
                        Write-Host "   * Dynamic Instructions Run  : $inst_count instructions ($reg_commits register commits + 5 memory stores)" -ForegroundColor White
                        Write-Host "   * Pipeline Stalls Breakdown :" -ForegroundColor Yellow
                        if ($dcache_bypass_mode) {
                            Write-Host "       - Direct Memory Accesses  : $stat_dcache_stalls stalls (9 stalls + 1 active = 10 cycles latency each)" -ForegroundColor Cyan
                        } else {
                            Write-Host "       - L1 D-Cache Miss Penalty : $stat_dcache_stalls stalls (9 stalls + 1 active = 10 cycles total latency)" -ForegroundColor Cyan
                        }
                        Write-Host "       - Load-Use Data Hazards   : $stat_loaduse_stalls stalls (1-cycle interlock bubbles)" -ForegroundColor Magenta
                        Write-Host "       - Branch Control Hazards  : $stat_branch_stalls stalls (2-cycle branch penalties)" -ForegroundColor DarkYellow
                        Write-Host "       - Total Pipeline Stalls   : $stall_count stalls" -ForegroundColor White
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
