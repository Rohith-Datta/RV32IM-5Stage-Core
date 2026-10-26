# ============================================================================
# File: build_bitstream.tcl
# Description: Automated Synthesis, Implementation, and Bitstream Generation
# Target: Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
# ============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set PROJ_FILE [file join $SCRIPT_DIR "vivado_project" "rv32imf_btb_fpga.xpr"]

if {![file exists $PROJ_FILE]} {
    puts "Project does not exist. Creating project first..."
    source [file join $SCRIPT_DIR "create_vivado_project.tcl"]
} else {
    open_project $PROJ_FILE
}

# Run Synthesis
puts "=== Running Synthesis ==="
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check Synthesis Status
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "Synthesis failed!"
    exit 1
}

# Run Implementation and Generate Bitstream
puts "=== Running Implementation & Bitstream Generation ==="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "Implementation failed!"
    exit 1
}

puts "=== Bitstream Generation Successful! ==="
