# ============================================================================
# Vivado TCL Project Generation Script for Integrated RV32IMF+Zbb SoC
# Target Device: Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T Board)
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
cd $script_dir

set proj_name "rv32imf_soc_integrated"
set proj_dir  [file normalize "$script_dir/integration/vivado_project"]
set part_num  "xc7a100tcsg324-1"

puts "=========================================================================="
puts "  CREATING INTEGRATED VIVADO PROJECT: $proj_name for $part_num"
puts "  Directory: $proj_dir"
puts "=========================================================================="

file mkdir $proj_dir

create_project $proj_name $proj_dir -part $part_num -force

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib work [current_project]

# Gather RTL files
set rtl_files [glob -nocomplain [file normalize "$script_dir/integration/modules/**/*.v"]]
add_files -norecurse -fileset sources_1 $rtl_files

# Add header
set vh_file [file normalize "$script_dir/integration/modules/opcode.vh"]
if {[file exists $vh_file]} {
    add_files -norecurse -fileset sources_1 $vh_file
    set_property file_type "Verilog Header" [get_files $vh_file]
}

# Add constraints
set xdc_file [file normalize "$script_dir/integration/constraints/nexys_a7_100t.xdc"]
if {[file exists $xdc_file]} {
    add_files -norecurse -fileset constrs_1 $xdc_file
}

# Add testbenches
set tb_files [glob -nocomplain [file normalize "$script_dir/integration/testbench/*.v"]]
if {[llength $tb_files] > 0} {
    add_files -norecurse -fileset sim_1 $tb_files
}

# Add hex memory initialization files
set hex_files [glob -nocomplain [file normalize "$script_dir/integration/**/*.hex"]]
if {[llength $hex_files] > 0} {
    add_files -norecurse -fileset sources_1 $hex_files
    add_files -norecurse -fileset sim_1 $hex_files
}

# Include directories
set inc_dirs [list \
    [file normalize "$script_dir/integration/modules"] \
    [file normalize "$script_dir/integration/modules/core"] \
    [file normalize "$script_dir/integration/modules/stages"] \
    [file normalize "$script_dir/integration/modules/registers"] \
    [file normalize "$script_dir/integration/modules/arith"] \
    [file normalize "$script_dir/integration/modules/cache"] \
    [file normalize "$script_dir/integration/modules/hazard"] \
    [file normalize "$script_dir/integration/modules/fpga"] \
]
set_property include_dirs $inc_dirs [current_fileset]
set_property include_dirs $inc_dirs [get_filesets sim_1]

# Set Top Module
set_property top fpga_top_integrated [current_fileset]
set_property top tb_fpga_top_integrated [get_filesets sim_1]

puts "=========================================================================="
puts "  INTEGRATED VIVADO PROJECT CREATED SUCCESSFULLY!"
puts "  Open in Vivado: $proj_dir/$proj_name.xpr"
puts "=========================================================================="
close_project
