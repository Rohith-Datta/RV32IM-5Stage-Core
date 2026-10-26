@echo off
REM ============================================================================
REM Batch Script to Run Feature 8 Simulations using Vivado xsim
REM ============================================================================

echo ============================================================
echo   Running Feature 8 Passive CSR Counter Simulations
echo ============================================================

where xvlog >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Vivado tools (xvlog, xelab, xsim) not found in PATH!
    echo Please run this from a Vivado Command Prompt or source settings64.bat.
    pause
    exit /b 1
)

echo.
echo [1/2] Simulating Passive Performance CSR Unit Testbench...
call xvlog -i ../modules -i ../modules/stages -i ../modules/pipeline -i ../modules/registers -f filelist.txt ../testbench/tb_csr.v
if %errorlevel% neq 0 goto error
call xelab -top tb_csr -snapshot snap_tb_csr -debug typical
if %errorlevel% neq 0 goto error
call xsim snap_tb_csr -R -log sim_csr.log
if %errorlevel% neq 0 goto error

echo.
echo [2/2] Simulating Full 5-Stage RV32IMF Pipeline with CSRs...
call xvlog -i ../modules -i ../modules/stages -i ../modules/pipeline -i ../modules/registers -f filelist.txt ../testbench/tb_feature8_pipeline.v
if %errorlevel% neq 0 goto error
call xelab -top tb_feature8_pipeline -snapshot snap_tb_feature8 -debug typical
if %errorlevel% neq 0 goto error
call xsim snap_tb_feature8 -R -log sim_feature8.log
if %errorlevel% neq 0 goto error

echo.
echo ============================================================
echo   All Feature 8 Simulations Completed Successfully!
echo ============================================================
pause
exit /b 0

:error
echo.
echo [ERROR] Simulation failed! Check log files for details.
pause
exit /b 1
