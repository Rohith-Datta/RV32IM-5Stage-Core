## ============================================================================
## File: nexys_a7_100t.xdc
## Description: Physical Constraints File for 5-Stage RV32I Processor (Feature 1)
## Target Device: Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T Board)
## ============================================================================

## ----------------------------------------------------------------------------
## 100 MHz Master Oscillator Clock & 50 MHz Derived Core Clock
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk_100mhz }];
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports { clk_100mhz }];
create_generated_clock -name clk_50mhz -source [get_ports clk_100mhz] -divide_by 2 [get_pins -hier -filter {NAME =~ *clk_50mhz_reg/Q}]

## ----------------------------------------------------------------------------
## Reset Button (CPU_RESETN - Red Pushbutton, Active-Low)
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { cpu_resetn }];

## ----------------------------------------------------------------------------
## Center Pushbutton (btnc - Manual Single-Step Clock)
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { btnc }];

## ----------------------------------------------------------------------------
## Slide Switches
## sw[0]: Mode select (0 = Normal Run, 1 = Manual Single-Step via btnc)
## sw[1]: Speed select (0 = 50 MHz core speed, 1 = 1 Hz slow visual clock)
## sw[2]: Display select (0 = PC Address, 1 = 32-bit Instruction Machine Code)
## sw[3]: UART mode (0 = MMIO printf, 1 = Auto-Telemetry Stream)
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { sw[0] }];
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { sw[1] }];
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { sw[2] }];
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports { sw[3] }];

## ----------------------------------------------------------------------------
## 8-Digit Seven-Segment Display (Directly ABOVE the 16 LEDs)
## Displays the 32-bit Fetch PC Address (imem_addr / pc_if[31:0])
## ----------------------------------------------------------------------------
## Anodes (Active-Low Digit Select)
set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports { an[0] }]; # AN0 (Rightmost)
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { an[1] }]; # AN1
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { an[2] }]; # AN2
set_property -dict { PACKAGE_PIN J14   IOSTANDARD LVCMOS33 } [get_ports { an[3] }]; # AN3
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { an[4] }]; # AN4
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { an[5] }]; # AN5
set_property -dict { PACKAGE_PIN K2    IOSTANDARD LVCMOS33 } [get_ports { an[6] }]; # AN6
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { an[7] }]; # AN7 (Leftmost)

## Cathodes (Active-Low Segments A through G)
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { seg[0] }]; # CA
set_property -dict { PACKAGE_PIN R10   IOSTANDARD LVCMOS33 } [get_ports { seg[1] }]; # CB
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { seg[2] }]; # CC
set_property -dict { PACKAGE_PIN K13   IOSTANDARD LVCMOS33 } [get_ports { seg[3] }]; # CD
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { seg[4] }]; # CE
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports { seg[5] }]; # CF
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { seg[6] }]; # CG
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { dp }];     # DP (Decimal point)

## ----------------------------------------------------------------------------
## 16 User LEDs
## LED[0] : DATA HAZARD DETECTED! (Lights up on Load-Use Hazard Stall)
## LED[1] : DATA FORWARDING ACTIVE! (Lights up when operand bypass occurs)
## LED[2] : BRANCH FLUSH! (Lights up on branch redirection)
## LED[3] : WRITEBACK COMMIT (Lights up when instruction commits to RegFile)
## LED[5:4] : Forward A Code
## LED[7:6] : Forward B Code
## LED[15:8]: Committed Result Low Byte (wb_data[7:0])
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { led[0]  }]; # HAZARD LED
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { led[1]  }]; # FORWARDING LED
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { led[2]  }]; # FLUSH LED
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { led[3]  }]; # RETIRE LED
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { led[4]  }]; # fwd_a[0]
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { led[5]  }]; # fwd_a[1]
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { led[6]  }]; # fwd_b[0]
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { led[7]  }]; # fwd_b[1]
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { led[8]  }]; # wb_data[0]
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { led[9]  }]; # wb_data[1]
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { led[10] }]; # wb_data[2]
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { led[11] }]; # wb_data[3]
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { led[12] }]; # wb_data[4]
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { led[13] }]; # wb_data[5]
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { led[14] }]; # wb_data[6]
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { led[15] }]; # wb_data[7] (Far Left LED)

## ----------------------------------------------------------------------------
## USB-RS232 Serial Interface (FTDI FT2232HQ)
## ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]; # FPGA Transmit (TXD) to FTDI
set_property -dict { PACKAGE_PIN C4    IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]; # FPGA Receive (RXD) from FTDI

## ----------------------------------------------------------------------------
## Configuration and Voltage
## ----------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
