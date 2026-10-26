@echo off
REM ============================================================================
REM Launch Vivado GUI for Feature 8 Project
REM ============================================================================

set SCRIPT_DIR=%~dp0
set PROJ_FILE=%SCRIPT_DIR%vivado_project\rv32imf_csr_fpga.xpr

if not exist "%PROJ_FILE%" (
    echo [INFO] Creating Vivado project...
    call vivado -mode batch -source "%SCRIPT_DIR%create_vivado_project.tcl"
)

echo [INFO] Opening Vivado GUI...
start vivado "%PROJ_FILE%"
