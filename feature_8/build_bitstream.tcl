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
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Check Synthesis Status
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "Synthesis failed!"
    exit 1
}

# Run Implementation and Generate Bitstream
puts "=== Running Implementation & Bitstream Generation ==="
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "Implementation failed!"
    exit 1
}

# Copy bitstream to root of feature_8
set IMPL_BIT [file join $SCRIPT_DIR "vivado_project" "rv32imf_btb_fpga.runs" "impl_1" "fpga_top_feature8.bit"]
set OUT_BIT  [file join $SCRIPT_DIR "fpga_top_feature8.bit"]
if {[file exists $IMPL_BIT]} {
    file copy -force $IMPL_BIT $OUT_BIT
    puts "=== Copied bitstream to $OUT_BIT ==="
}

puts "=== Bitstream Generation Successful! ==="
