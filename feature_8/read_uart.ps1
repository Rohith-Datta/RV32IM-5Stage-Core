# ============================================================================
# Script: read_uart.ps1 (Dedicated to Feature 8: RV32IM with Hardware Performance Counters)
# Description: Real-Time Cycle-by-Cycle UART Monitor & CSR Telemetry Visualizer
# Location: feature_8/read_uart.ps1
# Usage:
#   powershell -ExecutionPolicy Bypass -File feature_8\read_uart.ps1
#   powershell -ExecutionPolicy Bypass -File feature_8\read_uart.ps1 -Port COM4
# ============================================================================

param(
    [Parameter(Position=0)]
    [string]$Port = "",
    [Parameter(Position=1)]
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
# RV32IM + CSR Disassembler
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

    # SYSTEM / CSR (0x73)
    if ($opcode -eq 0x73) {
        $csr = [int]($inst -shr 20)
        $csrName = switch ($csr) {
            0xC00 { "cycle" }
            0xC01 { "time" }
            0xC02 { "instret" }
            0xC80 { "cycleh" }
            0xC81 { "timeh" }
            0xC82 { "instreth" }
            default { "0x{0:X3}" -f $csr }
        }
        $names = @('ecall/ebreak','csrrw','csrrs','csrrc','res','csrrwi','csrrsi','csrrci')
        return "$($names[$funct3]) $rdName, $csrName, $rs1Name"
    }

    # OP-IMM (0x13)
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
            return "$shift_name $rdName, $rs1Name, $($imm -band 0x1F)"
        }
        return "$($names[$funct3]) $rdName, $rs1Name, $imm"
    }

    # OP / ARITHR (0x33)
    if ($opcode -eq 0x33) {
        if ($funct7 -eq 0x01) {
            $m_names = @('mul','mulh','mulhsu','mulhu','div','divu','rem','remu')
            return "$($m_names[$funct3]) $rdName, $rs1Name, $rs2Name"
        }
        if ($funct3 -eq 0) {
            return if ($funct7 -eq 0x20) { "sub $rdName, $rs1Name, $rs2Name" } else { "add $rdName, $rs1Name, $rs2Name" }
        }
        if ($funct3 -eq 5) {
            return if ($funct7 -eq 0x20) { "sra $rdName, $rs1Name, $rs2Name" } else { "srl $rdName, $rs1Name, $rs2Name" }
        }
        $names = @('add/sub','sll','slt','sltu','xor','srl/sra','or','and')
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

    # AUIPC (0x17)
    if ($opcode -eq 0x17) {
        return "auipc $rdName, 0x$(($inst -shr 12).ToString('x'))"
    }

    # JAL (0x6F)
    if ($opcode -eq 0x6F) {
        return if ($rd -eq 0) { "j" } else { "jal $rdName" }
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
Write-Host " Nexys A7 RV32IM Real-Time CSR Performance Counter Monitor ($Port @ $Baud Baud)" -ForegroundColor White
Write-Host " Tracking Hardware Cycle, Instret & Timer Counters (Feature 8)" -ForegroundColor Cyan
Write-Host " Press red CPU RESET button on FPGA (Pin C12) to rerun." -ForegroundColor Yellow
Write-Host " Press Ctrl+C at any time to exit." -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Cyan

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$sp.ReadTimeout  = 500
$sp.NewLine      = "`n"

$cycle           = 0
$inst_count      = 0
$stall_count     = 0

try {
    $sp.Open()
    Write-Host "[OK] Connected to $Port. Listening for hardware telemetry..." -ForegroundColor Green
    
    while ($true) {
        try {
            $raw_line = $sp.ReadLine()
            if ($null -eq $raw_line) { continue }
            $line = $raw_line.Trim()
            if (-not $line) { continue }

            if ($line -match "RV32" -or $line -match "^===") {
                Write-Host $line -ForegroundColor Cyan
                continue
            }

            if ($line -match "stall") {
                $stall_count++
                $cc_str = "{0,3}" -f $cycle
                Write-Host " [CC=$cc_str] ---------stall---------" -ForegroundColor Yellow
                $cycle++
                continue
            }

            if ($line -match "PC:\s*(0x[0-9a-fA-F]{8})\s*\|\s*INST:\s*(0x[0-9a-fA-F]{8})") {
                $pc_hex   = $matches[1]
                $inst_hex = $matches[2]
                $disasm   = Disassemble-RV32 $inst_hex
                $cc_str   = "{0,3}" -f $cycle
                $inst_count++
                Write-Host " [CC=$cc_str] PC: $pc_hex | INST: $inst_hex -> $disasm" -ForegroundColor White
                $cycle++
                continue
            }

            Write-Host " $line" -ForegroundColor Gray
        } catch [System.TimeoutException] {
        } catch {
            Write-Host "[!] Warning: $_" -ForegroundColor DarkYellow
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
