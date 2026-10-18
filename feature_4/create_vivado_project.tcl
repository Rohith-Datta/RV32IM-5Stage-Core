# ============================================================================
# File: create_vivado_project.tcl
# Description: Generates Standalone Vivado Project for Feature 4 (RV32IMF Core with FPU)
# Target Device: Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T)
# ============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set PROJ_DIR [file join $SCRIPT_DIR "vivado_project"]
set PROJ_NAME "rv32mf_fpu_fpga"

puts "=========================================================="
puts " Creating Standalone Vivado Project for Feature 4 (FPU)   "
puts " Project Path: $PROJ_DIR/$PROJ_NAME.xpr"
puts "=========================================================="

file mkdir $PROJ_DIR
create_project -name $PROJ_NAME -dir $PROJ_DIR -part xc7a100tcsg324-1 -force

# Set project properties
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib work [current_project]

# Add RTL Design Sources
set RTL_FILES [list \
    [file join $SCRIPT_DIR "modules" "opcode.vh"] \
    [file join $SCRIPT_DIR "modules" "hazard_unit.v"] \
    [file join $SCRIPT_DIR "modules" "pipeline" "pipe.v"] \
    [file join $SCRIPT_DIR "modules" "pipeline" "pipeline_5stage.v"] \
    [file join $SCRIPT_DIR "modules" "stages" "decode_stage.v"] \
    [file join $SCRIPT_DIR "modules" "stages" "execute_stage.v"] \
    [file join $SCRIPT_DIR "modules" "stages" "fpu_single_core.v"] \
    [file join $SCRIPT_DIR "modules" "stages" "memory.v"] \
    [file join $SCRIPT_DIR "modules" "stages" "memory_stage.v"] \
    [file join $SCRIPT_DIR "modules" "stages" "writeback_stage.v"] \
    [file join $SCRIPT_DIR "modules" "stages" "multiplier_unit.v"] \
    [file join $SCRIPT_DIR "modules" "stages" "multiplier_dsp.v"] \
    [file join $SCRIPT_DIR "modules" "stages" "booth_radix4_multiplier.v"] \
    [file join $SCRIPT_DIR "modules" "stages" "divider_unit.v"] \
    [file join $SCRIPT_DIR "modules" "registers" "if_id_reg.v"] \
    [file join $SCRIPT_DIR "modules" "registers" "id_ex_reg.v"] \
    [file join $SCRIPT_DIR "modules" "registers" "ex_mem_reg.v"] \
    [file join $SCRIPT_DIR "modules" "registers" "mem_wb_reg.v"] \
    [file join $SCRIPT_DIR "modules" "fpga" "seven_seg_controller.v"] \
    [file join $SCRIPT_DIR "modules" "fpga" "fpga_top_feature4.v"] \
    [file join $SCRIPT_DIR "modules" "uart" "uart_tx.v"] \
    [file join $SCRIPT_DIR "modules" "uart" "uart_unit.v"] \
]

add_files -norecurse -fileset sources_1 $RTL_FILES

# Set include directory for opcode.vh
set_property include_dirs [list \
    [file join $SCRIPT_DIR "modules"] \
    [file join $SCRIPT_DIR "modules" "pipeline"] \
    [file join $SCRIPT_DIR "modules" "stages"] \
    [file join $SCRIPT_DIR "modules" "registers"] \
    [file join $SCRIPT_DIR "modules" "fpga"] \
    [file join $SCRIPT_DIR "modules" "uart"] \
] [get_filesets sources_1]

# Add XDC Constraints
set XDC_FILE [file join $SCRIPT_DIR "constraints" "nexys_a7_100t.xdc"]
add_files -norecurse -fileset constrs_1 $XDC_FILE

# Add Memory Files
set MEM_FILES [list \
    [file join $SCRIPT_DIR "mem" "imem.hex"] \
    [file join $SCRIPT_DIR "mem" "dmem.hex"] \
]
add_files -norecurse -fileset sources_1 $MEM_FILES

# Add Simulation Sources & Testbenches
set SIM_FILES [list \
    [file join $SCRIPT_DIR "testbench" "tb_fpu.v"] \
    [file join $SCRIPT_DIR "testbench" "tb_feature4_pipeline.v"] \
    [file join $SCRIPT_DIR "testbench" "tb_pipeline_base.v"] \
    [file join $SCRIPT_DIR "testbench" "tb_fpu_c_test.v"] \
    [file join $SCRIPT_DIR "testbench" "tb_fpga_top.v"] \
    [file join $SCRIPT_DIR "testbench" "tb_uart.v"] \
    [file join $SCRIPT_DIR "mem" "imem.hex"] \
    [file join $SCRIPT_DIR "mem" "dmem.hex"] \
]
add_files -norecurse -fileset sim_1 $SIM_FILES
set_property top tb_feature4_pipeline [get_filesets sim_1]
set_property top_lib work [get_filesets sim_1]
set_property include_dirs [list \
    [file join $SCRIPT_DIR "modules"] \
    [file join $SCRIPT_DIR "modules" "pipeline"] \
    [file join $SCRIPT_DIR "modules" "stages"] \
    [file join $SCRIPT_DIR "modules" "registers"] \
    [file join $SCRIPT_DIR "modules" "fpga"] \
    [file join $SCRIPT_DIR "modules" "uart"] \
] [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {50000ns} -objects [get_filesets sim_1]

# Set Top Module
set_property top fpga_top_feature4 [current_fileset]
update_compile_order -fileset sources_1

puts "=========================================================="
puts " Feature 4 Vivado Project Successfully Created!"
puts " Top Module: fpga_top_feature4"
puts "=========================================================="
