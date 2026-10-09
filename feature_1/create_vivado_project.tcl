# ============================================================================
# Vivado TCL Project Generation Script for Feature 1
# Project: RV32I 5-Stage Core with 8-Digit Display & Hazard/Forwarding LEDs
# Target Device: Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T Board)
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
cd $script_dir

set proj_name "rv32i_5stage_core"
set proj_dir  [file normalize "$script_dir/vivado_project"]
set part_num  "xc7a100tcsg324-1"

puts "=========================================================================="
puts "  CREATING VIVADO PROJECT: $proj_name for $part_num"
puts "  Directory: $proj_dir"
puts "=========================================================================="

# 1. Create project
create_project $proj_name $proj_dir -part $part_num -force

# Set project properties
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib work [current_project]

# 2. Add RTL Design Sources
set rtl_files [list \
    [file normalize "$script_dir/modules/opcode.vh"] \
    [file normalize "$script_dir/modules/hazard_unit.v"] \
    [file normalize "$script_dir/modules/pipeline/pipe.v"] \
    [file normalize "$script_dir/modules/pipeline/pipeline_5stage.v"] \
    [file normalize "$script_dir/modules/stages/decode_stage.v"] \
    [file normalize "$script_dir/modules/stages/execute_stage.v"] \
    [file normalize "$script_dir/modules/stages/memory.v"] \
    [file normalize "$script_dir/modules/stages/memory_stage.v"] \
    [file normalize "$script_dir/modules/stages/writeback_stage.v"] \
    [file normalize "$script_dir/modules/registers/if_id_reg.v"] \
    [file normalize "$script_dir/modules/registers/id_ex_reg.v"] \
    [file normalize "$script_dir/modules/registers/ex_mem_reg.v"] \
    [file normalize "$script_dir/modules/registers/mem_wb_reg.v"] \
    [file normalize "$script_dir/modules/fpga/seven_seg_controller.v"] \
    [file normalize "$script_dir/modules/fpga/fpga_top_feature1.v"] \
    [file normalize "$script_dir/modules/uart/uart_tx.v"] \
    [file normalize "$script_dir/modules/uart/uart_unit.v"] \
]

add_files -norecurse -fileset sources_1 $rtl_files
set_property file_type "Verilog Header" [get_files [file normalize "$script_dir/modules/opcode.vh"]]

# Set include directories
set_property include_dirs [list \
    [file normalize "$script_dir/modules"] \
    [file normalize "$script_dir/modules/pipeline"] \
    [file normalize "$script_dir/modules/stages"] \
    [file normalize "$script_dir/modules/registers"] \
    [file normalize "$script_dir/modules/fpga"] \
    [file normalize "$script_dir/modules/uart"] \
] [current_fileset]

# Set Top Module for Synthesis / Implementation
set_property top fpga_top_feature1 [current_fileset]
update_compile_order -fileset sources_1

# 3. Add Constraints (.xdc)
set xdc_file [file normalize "$script_dir/constraints/nexys_a7_100t.xdc"]
if {[file exists $xdc_file]} {
    add_files -norecurse -fileset constrs_1 $xdc_file
    set_property target_constrs_file $xdc_file [current_fileset -constrset]
    puts "\[+\] Added constraints file: $xdc_file"
}

# 4. Add Simulation Sources & Testbenches
set sim_files [list \
    [file normalize "$script_dir/testbench/tb_pipeline_base.v"] \
    [file normalize "$script_dir/testbench/tb_feature1_pipeline.v"] \
    [file normalize "$script_dir/testbench/tb_hazard.v"] \
    [file normalize "$script_dir/testbench/tb_uart.v"] \
    [file normalize "$script_dir/mem/imem.hex"] \
    [file normalize "$script_dir/mem/dmem.hex"] \
]

add_files -norecurse -fileset sim_1 $sim_files
set_property top tb_pipeline_base [get_filesets sim_1]
set_property top_lib work [get_filesets sim_1]
set_property include_dirs [list \
    [file normalize "$script_dir/modules"] \
    [file normalize "$script_dir/modules/pipeline"] \
    [file normalize "$script_dir/modules/stages"] \
    [file normalize "$script_dir/modules/registers"] \
    [file normalize "$script_dir/modules/fpga"] \
    [file normalize "$script_dir/modules/uart"] \
] [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {15000ns} -objects [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "=========================================================================="
puts "  PROJECT CREATED SUCCESSFULLY!"
puts "  Project Location: [file normalize "$proj_dir/$proj_name.xpr"]"
puts "  Synthesis Top   : fpga_top_feature1"
puts "  Simulation Top  : tb_pipeline_base"
puts "=========================================================================="
