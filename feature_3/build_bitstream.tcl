open_project [file normalize [file join [file dirname [info script]] "vivado_project/rv32m_divider_fpga.xpr"]]
update_compile_order -fileset sources_1
catch { reset_run synth_1 }
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set run_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS: $run_status"
close_project
exit
