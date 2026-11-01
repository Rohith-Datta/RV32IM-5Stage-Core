open_checkpoint C:/CS2202L/RISCV/feature_7/vivado_project/rv32imf_btb_fpga.runs/synth_1/fpga_top_feature7.dcp
read_xdc C:/CS2202L/RISCV/feature_7/constraints/nexys_a7_100t.xdc
opt_design
place_design
phys_opt_design
route_design
write_bitstream -force C:/CS2202L/RISCV/feature_7/fpga_top_feature7.bit
puts "=== BITSTREAM GENERATION COMPLETE ==="
