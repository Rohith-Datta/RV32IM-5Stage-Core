@echo off
REM ============================================================================
REM Batch Simulation Runner for Feature 6: RV32IMF Core with L1 Harvard Caches
REM Target: Vivado Simulator (50 MHz Standard Clocking)
REM ============================================================================

echo ============================================================================
echo   Running Feature 6 Simulation Suite (I-Cache Unit, Pipeline, Base, and UART)
echo ============================================================================

echo [1/5] Compiling Verilog source tree...
call xvlog -i "../modules" -f filelist.txt
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Compilation failed!
    exit /b %ERRORLEVEL%
)

echo [2/5] Simulating I-Cache Unit Testbench (tb_icache)...
call xelab -top tb_icache -snapshot snap_tb_icache -debug typical
call xsim snap_tb_icache -R -log sim_icache.log

echo [3/5] Simulating Base Pipeline Testbench (tb_pipeline_base)...
call xelab -top tb_pipeline_base -snapshot snap_tb_base -debug typical
call xsim snap_tb_base -R -log sim_base.log

echo [4/5] Simulating Feature 6 Harvard Pipeline Testbench (tb_feature6_pipeline)...
call xelab -top tb_feature6_pipeline -snapshot snap_tb_feature6 -debug typical
call xsim snap_tb_feature6 -R -log sim_feature6.log

echo [5/5] Simulating UART Diagnostic Telemetry (tb_uart)...
call xelab -top tb_uart -snapshot snap_tb_uart -debug typical
call xsim snap_tb_uart -R -log sim_uart.log

echo ============================================================================
echo   Feature 6 Verification Complete!
echo ============================================================================
