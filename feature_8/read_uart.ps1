# ============================================================================
# Script: read_uart.ps1
# Description: Feature 8 - Branch Target Buffer (BTB) Verification UART Monitor
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
Write-Host " Feature 8: BTB Verification UART Receiver" -ForegroundColor Green
Write-Host " Connecting to $Port at $Baud baud (8N1)..." -ForegroundColor White
Write-Host " Press CPU_RESETN (Pin C12) on Nexys A7 to run BTB test." -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

$serial = New-Object System.IO.Ports.SerialPort $Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One
$serial.ReadTimeout  = 3000
$serial.WriteTimeout = 1000
$serial.NewLine      = "`r`n"

try {
    $serial.Open()
    Write-Host "[*] Port $Port opened successfully. Waiting for BTB telemetry..." -ForegroundColor Green
    
    while ($true) {
        try {
            $line = $serial.ReadLine()
            if ($line) {
                if ($line.StartsWith("=====")) {
                    Write-Host $line -ForegroundColor Cyan
                } elseif ($line.StartsWith("CYC")) {
                    Write-Host $line -ForegroundColor Yellow
                } elseif ($line.Contains("MISPREDICT")) {
                    Write-Host $line -ForegroundColor Red
                } elseif ($line.Contains("PREDICTED CORRECTLY")) {
                    Write-Host $line -ForegroundColor Green
                } elseif ($line.Contains("PIPELINE FLUSH")) {
                    Write-Host $line -ForegroundColor Magenta
                } elseif ($line.Contains("Prediction accuracy")) {
                    Write-Host $line -ForegroundColor Green
                } else {
                    Write-Host $line
                }
            }
        } catch [System.TimeoutException] {
            # Continue waiting for reset or new run
        }
    }
} catch {
    Write-Host "[!] Serial Port Error: $_" -ForegroundColor Red
} finally {
    if ($serial -and $serial.IsOpen) {
        $serial.Close()
        Write-Host "[*] Closed port $Port." -ForegroundColor Gray
    }
}
