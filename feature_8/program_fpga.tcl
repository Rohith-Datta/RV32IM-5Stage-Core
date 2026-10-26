# ============================================================================
# File: program_fpga.tcl
# Description: Programs Digilent Nexys A7-100T via Vivado Hardware Manager
# ============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set BIT_FILE [file join $SCRIPT_DIR "vivado_project" "rv32imf_csr_fpga.runs" "impl_1" "fpga_top_feature8.bit"]

if {![file exists $BIT_FILE]} {
    puts "Error: Bitstream not found at $BIT_FILE"
    puts "Please run build_bitstream.tcl first."
    exit 1
}

puts "Opening Hardware Manager..."
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set DEVICE [lindex [get_hw_devices xc7a100t_*] 0]
current_hw_device $DEVICE
refresh_hw_device -update_hw_probes false $DEVICE

puts "Programming device with: $BIT_FILE"
set_property PROGRAM.FILE $BIT_FILE $DEVICE
program_hw_devices $DEVICE
refresh_hw_device $DEVICE

puts "=== Device programmed successfully! ==="
disconnect_hw_server
close_hw_manager
