@echo off
REM ============================================================================
REM File: open_vivado.bat
REM Description: Opens the Standalone Vivado Project for Feature 6 (RV32IMF Core with L1 I-Cache)
REM Target Device: Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T)
REM ============================================================================

set SCRIPT_DIR=%~dp0
set PROJ_FILE=%SCRIPT_DIR%vivado_project\rv32imf_icache_fpga.xpr

if not exist "%PROJ_FILE%" (
    echo [*] Vivado project not found. Generating project from TCL script...
    vivado -mode batch -source "%SCRIPT_DIR%create_vivado_project.tcl" -nojournal -nolog
)

echo [*] Launching AMD Vivado with Feature 6 FPGA Project...
start "" vivado "%PROJ_FILE%"
