# Run: vivado -mode batch -source board/build_vivado.tcl -tclargs 50
set project_root [file dirname [file dirname [file normalize [info script]]]]
cd $project_root
# Optional: -tclargs 40 (supported: 50, 40, 31.25, 25 MHz).
set system_mhz 50
if {[llength $argv]>0} {set system_mhz [lindex $argv 0]}
if {$system_mhz ni {50 40 31.25 25}} {error "Choose 50, 40, 31.25 or 25 MHz"}
set system_hz [expr {int(round($system_mhz*1000000))}]
set frequency_tag [string map {. p} $system_mhz]
set project_dir [file join build vivado_${frequency_tag}mhz]
set report_dir [file join build reports_${frequency_tag}mhz]
file mkdir $report_dir
create_project -force avionics $project_dir -part xc7a100tcsg324-1
set sources [glob integration/modules/*/*.v]
add_files $sources
add_files [glob board/*.v]
add_files avionics_demo.mem
set_property file_type {Memory Initialization Files} [get_files avionics_demo.mem]
set_property include_dirs [list [file normalize integration/modules/csr]] [current_fileset]
set_property verilog_define {SYNTHESIS} [current_fileset]
set_property top nexys_a7_top [current_fileset]
set_property generic "SYSTEM_CLOCK_HZ=$system_hz" [current_fileset]
add_files -fileset constrs_1 board/nexys_a7.xdc
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation did not complete: inspect impl_1/runme.log"}
open_run impl_1
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_drc -file [file join $report_dir drc.rpt]
# Timing reports must be reviewed before generating/programming a bitstream.

report_timing -max_paths 20 -file [file join $report_dir worst_paths.rpt]
report_timing -delay_type min -max_paths 20 -file [file join $report_dir worst_hold_paths.rpt]
report_clock_interaction -file [file join $report_dir clock_interaction.rpt]
report_cdc -file [file join $report_dir cdc.rpt]
set bad_setup [get_timing_paths -delay_type max -slack_lesser_than 0 -max_paths 1]
set bad_hold [get_timing_paths -delay_type min -slack_lesser_than 0 -max_paths 1]
if {[llength $bad_setup] || [llength $bad_hold]} {error "Timing violations remain; inspect $report_dir/timing_summary.rpt and worst_paths.rpt"}
