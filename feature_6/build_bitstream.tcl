open_project [file normalize [file join [file dirname [info script]] "vivado_project/rv32imf_icache_fpga.xpr"]]
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "=========================================================="
puts " Bitstream generation complete: $impl_status"
puts "=========================================================="
if { [string first "ERROR" $impl_status] != -1 } {
    exit 1
}
close_project
exit 0
