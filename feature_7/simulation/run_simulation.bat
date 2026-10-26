@echo off
REM ============================================================================
REM Batch Script to Run Feature 7 Simulations using Vivado xsim
REM ============================================================================

echo ============================================================
echo   Running Feature 7 BTB Branch Predictor Simulations
echo ============================================================

where xvlog >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Vivado tools (xvlog, xelab, xsim) not found in PATH!
    echo Please run this from a Vivado Command Prompt or source settings64.bat.
    pause
    exit /b 1
)

echo.
echo [1/2] Simulating Static 32-Entry BTB Unit Testbench...
call xvlog -i ../modules -i ../modules/stages -i ../modules/pipeline -i ../modules/registers -f filelist.txt ../testbench/tb_btb.v
if %errorlevel% neq 0 goto error
call xelab -top tb_btb -snapshot snap_tb_btb -debug typical
if %errorlevel% neq 0 goto error
call xsim snap_tb_btb -R -log sim_btb.log
if %errorlevel% neq 0 goto error

echo.
echo [2/2] Simulating Full 5-Stage RV32IMF Pipeline with BTB...
call xvlog -i ../modules -i ../modules/stages -i ../modules/pipeline -i ../modules/registers -f filelist.txt ../testbench/tb_feature7_pipeline.v
if %errorlevel% neq 0 goto error
call xelab -top tb_feature7_pipeline -snapshot snap_tb_feature7 -debug typical
if %errorlevel% neq 0 goto error
call xsim snap_tb_feature7 -R -log sim_feature7.log
if %errorlevel% neq 0 goto error

echo.
echo ============================================================
echo   All Feature 7 Simulations Completed Successfully!
echo ============================================================
pause
exit /b 0

:error
echo.
echo [ERROR] Simulation failed! Check log files for details.
pause
exit /b 1
