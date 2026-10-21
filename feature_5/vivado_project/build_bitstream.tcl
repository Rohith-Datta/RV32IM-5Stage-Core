open_project C:/CS2202L/RISCV/feature_5/vivado_project/rv32imf_dcache_fpga.xpr
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set run_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS: $run_status"
if {[string match "*write_bitstream Complete*" $run_status]} {
    puts "BITSTREAM GENERATION SUCCEEDED"
} else {
    puts "BITSTREAM GENERATION FAILED"
}
exit
