$modules = Get-ChildItem -Path "C:/CS2202L/RISCV/feature_9/modules" -Recurse -Filter "*.v" | ForEach-Object { $_.FullName.Replace('\', '/') }
$tb = "C:/CS2202L/RISCV/feature_9/testbench/tb_fpga_top_feature9.v"
Set-Location "C:/CS2202L/RISCV/feature_9/simulation"
& xvlog -i "C:/CS2202L/RISCV/feature_9/modules" -i "C:/CS2202L/RISCV/feature_9/modules/fpga" @modules $tb
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& xelab -top tb_fpga_top_feature9 -snapshot sim_fpga_top
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& xsim sim_fpga_top -R
