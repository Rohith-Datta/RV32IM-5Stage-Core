open_project [file normalize [file join [file dirname [info script]] "vivado_project/rv32m_multiplier_fpga.xpr"]]
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "Bitstream generation complete: [get_property STATUS [get_runs impl_1]]"
close_project
exit
