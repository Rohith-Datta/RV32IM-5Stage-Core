@echo off
rem ============================================================================
rem Root launcher script forwarding to feature_1 Vivado project
rem ============================================================================
cd /d "%~dp0\feature_1"
call open_vivado.bat
