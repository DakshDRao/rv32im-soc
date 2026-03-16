## ============================================================
##  arty_a7.xdc  -  Arty A7 (XC7A35T-CSG324-1) Constraints
##  Project : Single-Cycle RV32IM SoC
##  Step    : 19 — Synthesis + Place & Route
##
##  Board reference: Digilent Arty A7-35T Master XDC
##  https://github.com/Digilent/digilent-xdc
## ============================================================

## ── Clock ────────────────────────────────────────────────────
## 100 MHz crystal oscillator — pin E3
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { clk }]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports { clk }]

## ── Reset ────────────────────────────────────────────────────
## BTN0 (RESET) — active-low in our design
## Using dedicated reset button on Arty A7 (PROG button is C2,
## but we use BTN0 = D9 as reset for user control)
set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports { rst_n }]

## ── LEDs ─────────────────────────────────────────────────────
## LD0 = H5  LD1 = J5  LD2 = T9  LD3 = T10
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { gpio_led[0] }]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { gpio_led[1] }]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { gpio_led[2] }]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { gpio_led[3] }]

## ── Buttons + Switches ──────────────────────────────────────
## Arty A7 has 4 buttons (BTN0-3) and 4 switches (SW0-3).
## BTN0=D9 is used for rst_n. That leaves 3 buttons + 4 switches = 7 inputs.
## We map 4 gpio_btn + 4 gpio_sw as follows (no pin conflicts):
##
##   gpio_btn[0] = BTN1 = C9
##   gpio_btn[1] = BTN2 = B9
##   gpio_btn[2] = BTN3 = B8
##   gpio_btn[3] = SW0  = A8  (switch used as 4th button input)
##   gpio_sw[0]  = SW1  = C11
##   gpio_sw[1]  = SW2  = C10
##   gpio_sw[2]  = SW3  = A10
##   gpio_sw[3]  = PMOD JA[0] = G13 (tie to GND on board if unused)
set_property -dict { PACKAGE_PIN C9  IOSTANDARD LVCMOS33 } [get_ports { gpio_btn[0] }]
set_property -dict { PACKAGE_PIN B9  IOSTANDARD LVCMOS33 } [get_ports { gpio_btn[1] }]
set_property -dict { PACKAGE_PIN B8  IOSTANDARD LVCMOS33 } [get_ports { gpio_btn[2] }]
set_property -dict { PACKAGE_PIN A8  IOSTANDARD LVCMOS33 } [get_ports { gpio_btn[3] }]

set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports { gpio_sw[0] }]
set_property -dict { PACKAGE_PIN C10 IOSTANDARD LVCMOS33 } [get_ports { gpio_sw[1] }]
set_property -dict { PACKAGE_PIN A10 IOSTANDARD LVCMOS33 } [get_ports { gpio_sw[2] }]
set_property -dict { PACKAGE_PIN G13 IOSTANDARD LVCMOS33 } [get_ports { gpio_sw[3] }]

## ── UART (USB via FT2232HQ) ──────────────────────────────────
## TX from FPGA → host : pin D10
## RX to   FPGA ← host : pin A9
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]
set_property -dict { PACKAGE_PIN A9  IOSTANDARD LVCMOS33 } [get_ports { uart_rx  }]

## ── Bitstream / Configuration ────────────────────────────────
set_property BITSTREAM.GENERAL.COMPRESS       TRUE   [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE      33     [current_design]
set_property CONFIG_VOLTAGE                   3.3    [current_design]
set_property CFGBVS                           VCCO   [current_design]

## ── Timing Exceptions ────────────────────────────────────────
## GPIO button/switch inputs are asynchronous — they pass through
## a 2-FF synchroniser inside gpio.sv, so timing constraints on
## the raw pads are not required.
set_false_path -from [get_ports { gpio_btn[*] gpio_sw[*] }]

## UART RX is asynchronous — 2-FF synchroniser inside uart.sv
set_false_path -from [get_ports { uart_rx }]

## Reset is asynchronous — 2-FF synchroniser inside soc_top
set_false_path -from [get_ports { rst_n }]
