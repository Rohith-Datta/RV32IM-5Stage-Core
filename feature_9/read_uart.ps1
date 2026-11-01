# ============================================================================
# Script: read_uart.ps1
# Description: Feature 9 - Comprehensive Zbb Bit Manipulation Verification UART Monitor
# Target: Digilent Nexys A7-100T FPGA
# Baud Rate: 115200 8N1
# ============================================================================

param(
    [Parameter(Position=0)]
    [string]$Port = "",
    [Parameter(Position=1)]
    [int]$Baud = 115200
)

# Auto-detect COM port if not specified
if (-not $Port) {
    $ports = [System.IO.Ports.SerialPort]::GetPortNames()
    if ($ports.Count -eq 0) {
        Write-Host "[!] No active COM ports detected." -ForegroundColor Yellow
        Write-Host "    Please connect your Nexys A7 FPGA board via micro-USB." -ForegroundColor Gray
        exit
    }
    $Port = $ports[0]
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Feature 9: Zbb Bit-Manipulation UART Telemetry Receiver" -ForegroundColor Green
Write-Host " Connecting to $Port at $Baud baud (8N1)..." -ForegroundColor White
Write-Host " Press CPU_RESETN (Pin C12) on Nexys A7 to run verification." -ForegroundColor Yellow
Write-Host " Press BTNC (Pin N17) to re-transmit UART trace." -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

$serial = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$serial.ReadTimeout  = 3000
$serial.WriteTimeout = 1000
$serial.NewLine      = "`r`n"

try {
    $serial.Open()
    Write-Host "[*] Port $Port opened successfully. Waiting for Zbb telemetry..." -ForegroundColor Green
    
    while ($true) {
        try {
            $line = $serial.ReadLine()
            if ($line) {
                if ($line.StartsWith("=====")) {
                    Write-Host $line -ForegroundColor Cyan
                } elseif ($line.StartsWith("PC")) {
                    Write-Host $line -ForegroundColor Yellow
                } elseif ($line.Contains("Timing Violation Detected      : NO")) {
                    Write-Host $line -ForegroundColor Green
                } elseif ($line.Contains("Timing Violation Detected      : YES")) {
                    Write-Host $line -ForegroundColor Red
                } elseif ($line.StartsWith("Total Zbb")) {
                    Write-Host $line -ForegroundColor White
                } else {
                    Write-Host $line -ForegroundColor Gray
                }
            }
        } catch [System.TimeoutException] {
            # Idle timeout - keep listening
        }
    }
} catch {
    Write-Host "[!] Serial communication error: $_" -ForegroundColor Red
} finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
}
