@echo off
rem ============================================================================
rem Launcher script to open Feature 1 (5-Stage RV32I Core) in Vivado GUI
rem ============================================================================
cd /d "%~dp0"
echo ==========================================================================
echo   Launching AMD Vivado for Feature 1: 5-Stage RV32I Core...
echo ==========================================================================

if exist "vivado_project\rv32i_5stage_core.xpr" (
    echo [*] Opening existing Vivado project: feature_1\vivado_project\rv32i_5stage_core.xpr
    start vivado "vivado_project\rv32i_5stage_core.xpr"
) else (
    echo [*] Generating Vivado project from create_vivado_project.tcl...
    call vivado -mode batch -source create_vivado_project.tcl
    start vivado "vivado_project\rv32i_5stage_core.xpr"
)
