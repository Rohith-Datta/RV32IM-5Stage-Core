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
Write-Host " Single Switch Program Selection:" -ForegroundColor Yellow
Write-Host "   SW[4] = 0 (Down) : Runs Bare-Metal C Program (zbb.c) -> 7-Seg: 00180018" -ForegroundColor Yellow
Write-Host "   SW[4] = 1 (Up)   : Runs Synthetic Benchmark          -> 7-Seg: 00180022" -ForegroundColor Yellow
Write-Host " Dynamic Controls:" -ForegroundColor Gray
Write-Host "   Flip SW[4]       : Dynamically switches program and streams UART" -ForegroundColor Gray
Write-Host "   Press BTNC (N17) : Re-runs currently selected program & streams UART" -ForegroundColor Gray
Write-Host "   Press CPU_RESETN : Full hardware reset (Pin C12)" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

$serial = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$serial.ReadTimeout  = 500
$serial.WriteTimeout = 500

try {
    $serial.Open()
    Write-Host "[*] Port $Port opened successfully. Listening for telemetry..." -ForegroundColor Green
    
    while ($true) {
        try {
            $data = $serial.ReadExisting()
            if ($data.Length -gt 0) {
                Write-Host -NoNewline $data
            } else {
                Start-Sleep -Milliseconds 20
            }
        } catch [System.TimeoutException] {
            # Idle
        }
    }
} catch {
    Write-Host "[!] Serial communication error: $_" -ForegroundColor Red
} finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
}
