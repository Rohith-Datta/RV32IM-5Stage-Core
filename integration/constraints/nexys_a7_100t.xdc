## ============================================================================
## File: nexys_a7_100t.xdc
## Board: Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T-1CSG324C)
## Project: RV32IMF + Zbb + BTB + Caches + CSR Full-System Processor SoC
## ============================================================================

## Clock signal (100 MHz onboard oscillator & 50 MHz Derived Core Clock)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk_100mhz }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk_100mhz }];
create_generated_clock -name clk_50mhz -source [get_ports clk_100mhz] -divide_by 2 [get_pins -hier -filter {NAME =~ *clk_50mhz_reg*/Q}]

## CPU Reset Button (Active-low red pushbutton, Pin C12)
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { cpu_resetn }];

## Center Pushbutton (btnc, Pin N17)
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { btnc }];

## Slide Switches (sw[15:0])
## sw[15:14] = Mode (00=Flight Telemetry, 01=Cycle Profiler, 10=BTB/Cache Stress, 11=Diagnostic Fault)
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 } [get_ports { sw[15] }];
set_property -dict { PACKAGE_PIN U11   IOSTANDARD LVCMOS33 } [get_ports { sw[14] }];
## sw[13]    = L1 Cache Enable (1=Caches Active, 0=Caches Bypassed with 10c stall)
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { sw[13] }];
## sw[12]    = Verbose Cycle-by-Cycle Trace Mode (1=Pure Trace, 0=Hybrid CSV+Trace)
set_property -dict { PACKAGE_PIN H6    IOSTANDARD LVCMOS33 } [get_ports { sw[12] }];
## sw[11]    = Execution Clock Throttle (0=50 MHz full speed, 1=10 Hz human step rate)
set_property -dict { PACKAGE_PIN T13   IOSTANDARD LVCMOS33 } [get_ports { sw[11] }];
## sw[10]    = 7-Segment Display Select (0=Live PC, 1=Committed WB Data)
set_property -dict { PACKAGE_PIN R16   IOSTANDARD LVCMOS33 } [get_ports { sw[10] }];
## sw[9:8]   = Reserved (LVCMOS18 on Nexys A7 Bank 35)
set_property -dict { PACKAGE_PIN U8    IOSTANDARD LVCMOS18 } [get_ports { sw[9]  }];
set_property -dict { PACKAGE_PIN T8    IOSTANDARD LVCMOS18 } [get_ports { sw[8]  }];
## sw[7:0]   = Dynamic Input Seed / Fault Vector
set_property -dict { PACKAGE_PIN R13   IOSTANDARD LVCMOS33 } [get_ports { sw[7]  }];
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports { sw[6]  }];
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports { sw[5]  }];
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { sw[4]  }];
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports { sw[3]  }];
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { sw[2]  }];
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { sw[1]  }];
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { sw[0]  }];

## 8-Digit Seven-Segment Display (Directly above LEDs)
## Cathodes: seg[6:0] = {CA, CB, CC, CD, CE, CF, CG}
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { seg[0] }]; # CA
set_property -dict { PACKAGE_PIN R10   IOSTANDARD LVCMOS33 } [get_ports { seg[1] }]; # CB
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { seg[2] }]; # CC
set_property -dict { PACKAGE_PIN K13   IOSTANDARD LVCMOS33 } [get_ports { seg[3] }]; # CD
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { seg[4] }]; # CE
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports { seg[5] }]; # CF
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { seg[6] }]; # CG
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { dp }];     # DP

## Anodes: an[7:0]
set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports { an[0] }];
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { an[1] }];
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { an[2] }];
set_property -dict { PACKAGE_PIN J14   IOSTANDARD LVCMOS33 } [get_ports { an[3] }];
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { an[4] }];
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { an[5] }];
set_property -dict { PACKAGE_PIN K2    IOSTANDARD LVCMOS33 } [get_ports { an[6] }];
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { an[7] }];

## Discrete 16 LEDs: Architectural Status Indicators with 20ms pulse-stretchers
## LED[15]: Pipeline Stall
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { led[15] }];
## LED[14]: Load-Use Data Hazard
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { led[14] }];
## LED[13]: D-Cache Miss Refill (10 cycles)
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { led[13] }];
## LED[12]: I-Cache Miss Refill
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { led[12] }];
## LED[11]: BTB Mispredict Flush
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { led[11] }];
## LED[10]: FPU Unit Busy
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { led[10] }];
## LED[9] : Multiplier / Divider Busy
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { led[9]  }];
## LED[8] : Instruction Writeback Commit
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { led[8]  }];
## LED[7] : FPU Exception: Invalid Operation (NV, NaN)
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { led[7]  }];
## LED[6] : FPU / Div Exception: Divide-by-Zero (DZ)
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { led[6]  }];
## LED[5] : FPU Exception: Overflow (OF)
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { led[5]  }];
## LED[4] : FPU Exception: Underflow (UF)
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { led[4]  }];
## LED[3] : FPU Exception: Inexact / RNE Round (NX)
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { led[3]  }];
## LED[2] : Zbb Bit-Manipulation Unit Active
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { led[2]  }];
## LED[1] : UART TX Active (Flickers on transmit)
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { led[1]  }];
## LED[0] : Demo Complete Status (Latches ON at halt)
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { led[0]  }];

## USB-UART Interface (FTDI FT2232HQ)
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]; # FPGA Transmit (TXD) to FTDI
set_property -dict { PACKAGE_PIN C4    IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]; # FPGA Receive (RXD) from FTDI

## Configuration Voltage & SPI Options
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
