@echo off
REM ============================================================================
REM Batch Simulation Runner for Feature 5: RV32IMF Core with L1 D-Cache
REM Target: Vivado Simulator (50 MHz Standard Clocking)
REM ============================================================================

echo ============================================================================
echo   Running Feature 5 Simulation Suite (D-Cache Unit, Pipeline, Base, and UART)
echo ============================================================================

echo [1/4] Compiling Verilog source tree...
call xvlog -i "../modules" -f filelist.txt
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Compilation failed!
    exit /b %ERRORLEVEL%
)

echo [2/4] Simulating D-Cache Unit Testbench (tb_dcache)...
call xelab -top tb_dcache -snapshot snap_tb_dcache -debug typical
call xsim snap_tb_dcache -R -log sim_dcache.log

echo [3/5] Simulating Base Pipeline Testbench (tb_pipeline_base)...
call xelab -top tb_pipeline_base -snapshot snap_tb_base -debug typical
call xsim snap_tb_base -R -log sim_base.log

echo [4/5] Simulating Feature 5 Full Pipeline Testbench (tb_feature5_pipeline)...
call xelab -top tb_feature5_pipeline -snapshot snap_tb_feature5 -debug typical
call xsim snap_tb_feature5 -R -log sim_feature5.log

echo [5/5] Simulating UART Diagnostic Telemetry (tb_uart)...
call xelab -top tb_uart -snapshot snap_tb_uart -debug typical
call xsim snap_tb_uart -R -log sim_uart.log

echo ============================================================================
echo   Feature 5 Verification Complete!
echo ============================================================================
