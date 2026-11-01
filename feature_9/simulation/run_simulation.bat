@echo off
REM ============================================================================
REM Batch Script to Run Feature 9 (Zbb) Simulations using Vivado xsim
REM ============================================================================

echo ============================================================
echo   Running Feature 9 Zbb Bit-Manipulation Simulations
echo ============================================================

where xvlog >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Vivado tools (xvlog, xelab, xsim) not found in PATH!
    echo Please run this from a Vivado Command Prompt or source settings64.bat.
    pause
    exit /b 1
)

echo.
echo [1/3] Simulating Direct Zbb Execution Unit (tb_zbb_unit)...
call xvlog -i ../modules -i ../modules/stages -i ../modules/pipeline -i ../modules/registers -i ../modules/fpga -i ../modules/uart -f filelist.txt ../testbench/tb_zbb_unit.v
if %errorlevel% neq 0 goto error
call xelab -top tb_zbb_unit -snapshot snap_tb_zbb_unit -debug typical
if %errorlevel% neq 0 goto error
call xsim snap_tb_zbb_unit -R -log sim_zbb_unit.log
if %errorlevel% neq 0 goto error

echo.
echo [2/3] Simulating Full 5-Stage RV32IMF Pipeline with Zbb...
call xvlog -i ../modules -i ../modules/stages -i ../modules/pipeline -i ../modules/registers -i ../modules/fpga -i ../modules/uart -f filelist.txt ../testbench/tb_feature9_pipeline.v
if %errorlevel% neq 0 goto error
call xelab -top tb_feature9_pipeline -snapshot snap_tb_feature9_pipeline -debug typical
if %errorlevel% neq 0 goto error
call xsim snap_tb_feature9_pipeline -R -log sim_feature9_pipeline.log
if %errorlevel% neq 0 goto error

echo.
echo [3/3] Simulating FPGA Top-Level with 115200 Baud UART Streaming...
call xvlog -i ../modules -i ../modules/stages -i ../modules/pipeline -i ../modules/registers -i ../modules/fpga -i ../modules/uart -f filelist.txt ../modules/fpga/seven_seg_controller.v ../modules/uart/uart_tx.v ../modules/fpga/fpga_top_feature9.v ../testbench/tb_fpga_top_feature9.v
if %errorlevel% neq 0 goto error
call xelab -top tb_fpga_top_feature9 -snapshot snap_tb_fpga_top_feature9 -debug typical
if %errorlevel% neq 0 goto error
call xsim snap_tb_fpga_top_feature9 -R -log sim_fpga_top_feature9.log
if %errorlevel% neq 0 goto error

echo.
echo ============================================================
echo   All Feature 9 Simulations Completed Successfully!
echo ============================================================
pause
exit /b 0

:error
echo.
echo [ERROR] Simulation failed! Check log files for details.
pause
exit /b 1
