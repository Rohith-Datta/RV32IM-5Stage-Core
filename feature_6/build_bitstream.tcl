open_project [file normalize [file join [file dirname [info script]] "vivado_project/rv32imf_icache_fpga.xpr"]]
update_compile_order -fileset sources_1
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
set_property incremental_checkpoint "" [get_runs synth_1]
catch { reset_run synth_1 }
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set run_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS: $run_status"
set bit_src [file normalize [file join [file dirname [info script]] "vivado_project/rv32imf_icache_fpga.runs/impl_1/fpga_top_feature6.bit"]]
set bit_dst [file normalize [file join [file dirname [info script]] "fpga_top_feature6.bit"]]
if {[file exists $bit_src]} {
    file copy -force $bit_src $bit_dst
    puts "BITSTREAM_COPIED: $bit_dst"
}
close_project
exit
