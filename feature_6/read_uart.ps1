# ============================================================================
# Script: read_uart.ps1 (Dedicated to Feature 6: RV32IMF with L1 Instruction Cache)
# Description: Real-Time Cycle-by-Cycle UART Monitor & L1 I-Cache Telemetry Visualizer
# Location: feature_6/read_uart.ps1
# Usage:
#   powershell -ExecutionPolicy Bypass -File feature_6\read_uart.ps1
#   powershell -ExecutionPolicy Bypass -File feature_6\read_uart.ps1 -Port COM4
#   powershell -ExecutionPolicy Bypass -File feature_6\read_uart.ps1 -Port COM4 -Bypass
# ============================================================================

param(
    [Parameter(Position=0)]
    [string]$Port = "",
    [Parameter(Position=1)]
    [int]$Baud = 115200,
    [switch]$Bypass
)

# Auto-detect COM port if not explicitly provided
if (-not $Port -or $Port -eq "bypass" -or $Port -eq "enabled") {
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
            if ($imm -eq 0) { return "mv $rdName, $rs1Name" }
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
Write-Host " Nexys A7 RV32IMF Real-Time I-Cache Monitor ($Port @ $Baud Baud)" -ForegroundColor White
Write-Host " Tracking 2KB Direct-Mapped L1 Instruction Cache (Feature 6)" -ForegroundColor Cyan
Write-Host " Mode Control: SW[0]=0 (I-Cache Normal) | SW[0]=1 (I-Cache Bypass)" -ForegroundColor White
Write-Host " Press red CPU RESET button on FPGA (Pin C12) or BTNC to run." -ForegroundColor Yellow
Write-Host " Press Ctrl+C at any time to exit." -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Cyan

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$sp.ReadTimeout  = 500
$sp.NewLine      = "`n"

$total_hits     = 0
$total_misses   = 0
$total_stalls   = 0
$inst_count     = 0

try {
    $sp.Open()
    Write-Host "[OK] Connected to $Port. Listening for hardware telemetry..." -ForegroundColor Green
    
    while ($true) {
        try {
            $raw_line = $sp.ReadLine()
            if ($null -eq $raw_line) { continue }
            $line = $raw_line.Trim()
            if (-not $line) { continue }

            # 1. Reset counters on new benchmark / trace start
            if ($line -match "^===\s*I-CACHE" -or $line -match "I-CACHE TRACE \(MODE:") {
                $total_hits   = 0
                $total_misses = 0
                $total_stalls = 0
                $inst_count   = 0
                Write-Host "`n$line" -ForegroundColor Cyan
                continue
            }

            # 2. Header and border lines
            if ($line -match "^===" -or $line -match "^---" -or $line -match "CYC\s+PC\s+INSTR\s+STATUS") {
                Write-Host $line -ForegroundColor DarkGray
                continue
            }

            # 3. Formatted I-Cache Row from icache_uart_printer:
            # Pattern: <cyc> <pc> <inst> <status>
            if ($line -match "^\s*(\d+)\s+(0x[0-9a-fA-F]{8})\s+(0x[0-9a-fA-F]{8})\s*(.*)$") {
                $cyc      = $matches[1]
                $pc_hex   = $matches[2]
                $inst_hex = $matches[3]
                $status   = $matches[4].Trim()
                $disasm   = Disassemble-RV32 $inst_hex

                $color = "White"
                if ($status -match "HIT") {
                    $color = "Green"
                    $total_hits++
                    $inst_count++
                } elseif ($status -match "MISS") {
                    $color = "Red"
                    $total_misses++
                    $total_stalls++
                } elseif ($status -match "FETCHED") {
                    $color = "Cyan"
                    $inst_count++
                } elseif ($status -match "STALL") {
                    $color = "Yellow"
                    $total_stalls++
                }

                $disasm_fmt = "{0,-16}" -f $disasm
                $status_fmt = "{0,-18}" -f $status
                Write-Host ("     {0,4}   {1}   {2}   {3}   {4}" -f $cyc, $pc_hex, $inst_hex, $disasm_fmt, $status_fmt) -ForegroundColor $color
                continue
            }

            # 4. Formatted Flush Row from icache_uart_printer:
            if ($line -match "^\s*FLUSH\s+PC=(0x[0-9a-fA-F]{8})\s*(.*)$") {
                $pc_hex = $matches[1]
                $desc   = $matches[2]
                Write-Host ("          FLUSH   PC={0}   {1}" -f $pc_hex, $desc) -ForegroundColor Magenta
                continue
            }

            # 5. Summary and Comparison Table lines
            if ($line -match "EXECUTION SUMMARY" -or $line -match "SIDE-BY-SIDE" -or $line -match "Total Cycles" -or $line -match "Instructions Run" -or $line -match "I-Cache Hits" -or $line -match "I-Cache Misses" -or $line -match "Hit Rate" -or $line -match "Average CPI" -or $line -match "Metric\s+Enabled") {
                Write-Host " $line" -ForegroundColor Green
                continue
            }

            # 6. Standard telemetry lines (PC: 0x... | INST: 0x...)
            if ($line -match "PC:\s*(0x[0-9a-fA-F]{8})\s*\|\s*INST:\s*(0x[0-9a-fA-F]{8})") {
                $pc_hex   = $matches[1]
                $inst_hex = $matches[2]
                $disasm   = Disassemble-RV32 $inst_hex
                Write-Host (" [PC: {0} | INST: {1}] -> {2}" -f $pc_hex, $inst_hex, $disasm) -ForegroundColor White
                continue
            }

            # 7. Hardware Stall tags
            if ($line -match "stall") {
                Write-Host " [STALL] $line" -ForegroundColor Yellow
                continue
            }

            # Default pass-through
            Write-Host " $line" -ForegroundColor Gray

        } catch [System.TimeoutException] {
            # Expected when waiting for characters
        } catch {
            Write-Host "[!] Serial Read Warning: $_" -ForegroundColor DarkYellow
        }
    }
} catch {
    Write-Host "`n[!] Serial Connection Error: $_" -ForegroundColor Red
} finally {
    if ($sp -and $sp.IsOpen) {
        $sp.Close()
        Write-Host "`n[INFO] Closed serial connection to $Port." -ForegroundColor Yellow
    }
}
