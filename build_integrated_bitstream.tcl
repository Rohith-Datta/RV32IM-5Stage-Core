# ============================================================================
# Vivado TCL Build Script: Full Synthesis, Implementation & Bitstream Generation
# Integrated RV32IMF+Zbb Full-System SoC for Nexys A7-100T
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_file [file normalize "$script_dir/integration/vivado_project/rv32imf_soc_integrated.xpr"]

puts "=========================================================================="
puts "  OPENING INTEGRATED VIVADO PROJECT: $proj_file"
puts "=========================================================================="
open_project $proj_file
update_compile_order -fileset sources_1

puts "=========================================================================="
puts "  RESETTING RUNS: CLEAN RE-SYNTHESIS & IMPLEMENTATION FROM SCRATCH"
puts "=========================================================================="
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
set_property incremental_checkpoint "" [get_runs synth_1]
catch { reset_run synth_1 }
catch { reset_run impl_1 }

puts "=========================================================================="
puts "  LAUNCHING SYNTHESIS (8 JOBS)"
puts "=========================================================================="
launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "=========================================================================="
puts "  SYNTHESIS STATUS: $synth_status"
puts "=========================================================================="

if {[string match "*Complete*" $synth_status]} {
    puts "=========================================================================="
    puts "  LAUNCHING IMPLEMENTATION & BITSTREAM GENERATION (8 JOBS)"
    puts "=========================================================================="
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    wait_on_run impl_1

    set run_status [get_property STATUS [get_runs impl_1]]
    puts "=========================================================================="
    puts "  IMPLEMENTATION STATUS: $run_status"
    puts "=========================================================================="

    set wns [get_property STATS.WNS [get_runs impl_1]]
    set tns [get_property STATS.TNS [get_runs impl_1]]
    set whs [get_property STATS.WHS [get_runs impl_1]]
    puts "  FINAL TIMING RESULTS: WNS = $wns ns | TNS = $tns ns | WHS = $whs ns"
    puts "=========================================================================="
} else {
    puts "ERROR: Synthesis did not complete successfully. Status: $synth_status"
}

close_project
exit
