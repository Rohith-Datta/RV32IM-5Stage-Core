# ============================================================================
# File: program_fpga.tcl
# Description: Connects to Hardware Server and Programs Nexys A7-100T FPGA
#              with the Feature 5 Bitstream (fpga_top_feature5.bit)
# ============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set BIT_FILE [file normalize [file join $SCRIPT_DIR "vivado_project/rv32imf_dcache_fpga.runs/impl_1/fpga_top_feature5.bit"]]

if {![file exists $BIT_FILE]} {
    puts "[-] Error: Bitstream file not found at:"
    puts "    $BIT_FILE"
    puts "    Please generate the bitstream first using: vivado -mode batch -source build_bitstream.tcl"
    exit 1
}

puts "=========================================================="
puts " Connecting to Hardware Server and Programming Nexys A7"
puts " Target Bitstream: $BIT_FILE"
puts "=========================================================="

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set devices [get_hw_devices]
if {[llength $devices] == 0} {
    puts "[-] Error: No hardware device detected on JTAG chain."
    puts "    Please check:"
    puts "    1. Digilent Nexys A7 USB cable is plugged in."
    puts "    2. Board power switch is turned ON."
    disconnect_hw_server
    close_hw_manager
    exit 1
}

set dev [lindex $devices 0]
puts "[*] Detected Target FPGA Device: $dev"
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

puts "[*] Programming bitstream to $dev..."
set_property PROGRAM.FILE $BIT_FILE $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "=========================================================="
puts "[+] FPGA PROGRAMMING COMPLETED SUCCESSFULLY!"
puts "=========================================================="

close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
