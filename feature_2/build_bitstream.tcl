open_project [file normalize [file join [file dirname [info script]] "vivado_project/rv32m_multiplier_fpga.xpr"]]
update_compile_order -fileset sources_1
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
set_property incremental_checkpoint "" [get_runs synth_1]
catch { reset_run synth_1 }
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set run_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS: $run_status"
close_project
exit
