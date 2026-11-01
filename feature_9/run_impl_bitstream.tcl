open_checkpoint C:/CS2202L/RISCV/feature_9/vivado_project/rv32imf_zbb_fpga.runs/synth_1/fpga_top_feature9.dcp
read_xdc C:/CS2202L/RISCV/feature_9/constraints/nexys_a7_100t.xdc
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file C:/CS2202L/RISCV/feature_9/timing_summary.rpt
write_bitstream -force C:/CS2202L/RISCV/feature_9/fpga_top_feature9.bit
puts "=== BITSTREAM GENERATION COMPLETE ==="
