@echo off
REM ============================================================================
REM Batch Simulation Runner for Feature 4: RV32IMF IEEE 754 FPU
REM Target: Vivado Simulator (50 MHz Standard Clocking)
REM ============================================================================

echo ============================================================================
echo   Running Feature 4 Simulation Suite (FPU Unit, Pipeline, Base, and UART)
echo ============================================================================

echo [1/4] Compiling Verilog source tree...
call xvlog -i "../modules" -f filelist.txt
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Compilation failed!
    exit /b %ERRORLEVEL%
)

echo [2/4] Simulating FPU Unit Testbench (tb_fpu)...
call xelab -top tb_fpu -snapshot snap_tb_fpu -debug typical
call xsim snap_tb_fpu -R -log sim_fpu.log

echo [3/4] Simulating Feature 4 Full Pipeline Testbench (tb_feature4_pipeline)...
call xelab -top tb_feature4_pipeline -snapshot snap_tb_feature4 -debug typical
call xsim snap_tb_feature4 -R -log sim_feature4.log

echo [4/4] Simulating UART Diagnostic Telemetry (tb_uart)...
call xelab -top tb_uart -snapshot snap_tb_uart -debug typical
call xsim snap_tb_uart -R -log sim_uart.log

echo ============================================================================
echo   Feature 4 Verification Complete!
echo ============================================================================
