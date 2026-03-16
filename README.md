# RV32IM SoC — Phase 2: Single-Cycle Implementation

A complete **RV32IM** processor and SoC implemented in SystemVerilog, targeting the **Digilent Arty A7-35T** (Xilinx Artix-7). Verified in simulation with 10/10 tests passing.

---

## Architecture

```
soc_top
├── riscv_core          Single-cycle RV32IM CPU
│   ├── pc_logic        Program counter + next-PC mux
│   ├── imem            Instruction memory (dual-port: fetch + .rodata)
│   ├── control         Main decode unit
│   ├── imm_gen         Immediate generator (I/S/B/U/J)
│   ├── regfile         32×32 register file
│   ├── alu             ALU (all RV32I ops)
│   ├── mul_div         M-extension (MUL/MULH/DIV/DIVU/REM/REMU)
│   ├── branch_unit     Branch comparator
│   ├── csr_regs        Machine-mode CSRs + trap handler
│   └── writeback       Write-back mux
├── bus_fabric          Address decoder + read-data mux
├── dmem                64 KB data SRAM (0x2000_0000)
├── gpio                4-out / 8-in GPIO with IRQ (0x4000_0000)
├── uart                8N1 UART 115200 baud with IRQ (0x4000_1000)
└── timer               64-bit mtime/mtimecmp timer (0x4000_2000)
```

## Memory Map

| Region | Base         | Size  | Description                    |
|--------|-------------|-------|--------------------------------|
| IMEM   | 0x0000_0000 | 64 KB | Instruction + .rodata (ROM)    |
| DMEM   | 0x2000_0000 | 64 KB | Data SRAM (stack, heap, .data) |
| GPIO   | 0x4000_0000 |  4 KB | LED outputs, button/switch in  |
| UART   | 0x4000_1000 |  4 KB | 8N1 serial, 115200 baud        |
| TIMER  | 0x4000_2000 |  4 KB | 64-bit mtime/mtimecmp          |
| CSRs   | 0x4000_3000 |  4 KB | (memory slot; CSRs via CSRRW)  |

## ISA Support

| Extension | Instructions |
|-----------|-------------|
| RV32I     | All (LUI, AUIPC, JAL, JALR, branches, loads, stores, ALU, FENCE) |
| RV32M     | MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU |
| Zicsr     | CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI |
| Trap      | ECALL, EBREAK, MRET, machine external/timer interrupts |

## CSRs Implemented

`mstatus`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, `cycle`, `cycleh`, `mhartid`

---

## Repository Structure

```
rtl/            RTL source (synthesisable)
  alu.sv            ALU
  branch_unit.sv    Branch comparator
  bus_fabric.sv     Address decoder + rdata mux
  control.sv        Decode / control signals
  csr_regs.sv       Machine-mode CSRs + trap logic
  dmem.sv           Data memory
  gpio.sv           GPIO peripheral
  imem.sv           Instruction memory (dual-port)
  imm_gen.sv        Immediate generator
  mul_div.sv        M-extension multiplier/divider
  pc_logic.sv       PC register + next-PC mux
  regfile.sv        Register file
  riscv_core.sv     Core top-level
  soc_top.sv        SoC top-level
  timer.sv          Timer peripheral
  uart.sv           UART peripheral
  writeback.sv      Write-back mux

tb/             Testbenches
  tb_alu.sv         ALU unit test
  tb_branch_unit.sv Branch unit test
  tb_csr_regs.sv    CSR + trap test
  tb_dmem.sv        Data memory test
  tb_gpio.sv        GPIO test
  tb_imem.sv        IMEM test
  tb_imm_gen.sv     Immediate generator test
  tb_mul_div.sv     M-extension test
  tb_pc_logic.sv    PC logic test
  tb_regfile.sv     Register file test
  tb_riscv_core.sv  Core integration test
  tb_timer.sv       Timer test
  tb_uart.sv        UART test
  tb_writeback.sv   Write-back test
  tb_phase2.sv      *** Phase 2 full-SoC verification (10 tests) ***

constraints/
  arty_a7.xdc       Pin assignments for Arty A7-35T

scripts/
  synth.tcl         Vivado batch synthesis + P&R script

firmware/
  crt0.S            Startup: stack init, .data copy, .bss zero
  link.ld           Linker script (IMEM=0x0, DMEM=0x2000_0000)
  hello.c           Hello World: banner, LED counter, button echo
  uart.h            UART driver (polling)
  gpio.h            GPIO driver
  Makefile          Build targets (requires riscv32-unknown-elf-gcc)
  bin2hex.py        Binary → $readmemh hex converter
  generate_imem.py  Generates imem_init.sv with firmware baked in
```

---

## Quick Start

### Prerequisites
- Vivado 2020.1+ (or 2025.2 as tested)
- `riscv32-unknown-elf-gcc` toolchain
- Digilent Arty A7-35T board

### 1 — Build Firmware

```bash
cd firmware

# For simulation (fast delays: CLK_HZ=100kHz equivalent)
make SIM=1
# Or manually:
riscv32-unknown-elf-gcc -march=rv32im -mabi=ilp32 -O2 \
  -ffreestanding -fno-builtin -nostdlib -nostartfiles \
  -DCLK_HZ=100000 -T link.ld -o hello_sim.elf crt0.S hello.c
riscv32-unknown-elf-objcopy -O binary hello_sim.elf hello_sim.bin
python3 bin2hex.py hello_sim.bin hello_sim.hex

# For real board (CLK_HZ=100MHz)
make
```

### 2 — Generate IMEM Init File

```bash
cd ..   # back to repo root
python3 firmware/generate_imem.py firmware/hello_sim.hex imem_init.sv
# (sim) or
python3 firmware/generate_imem.py firmware/hello.hex imem_init.sv
# (board)
```

### 3 — Simulate (Vivado XSim)

In Vivado, add all `rtl/*.sv` sources, replace `imem.sv` with `imem_init.sv`, add `tb/tb_phase2.sv` as simulation top. Set runtime to `400ms` and run.

Expected output:
```
PASSED: 10 / 10    FAILED: 0 / 10
*** PHASE 2 COMPLETE ***
```

### 4 — Synthesise & Program Board

```bash
vivado -mode batch -source scripts/synth.tcl
# Programs Arty A7 via Vivado Hardware Manager
```

Connect a serial terminal at **115200 8N1** to see:
```
========================================
  Hello from RV32IM SoC!
  Arty A7 (XC7A35T)  |  100 MHz
  ISA: RV32IM + CSRs + Traps
========================================
```

---

## Verification Results

All 10 Phase 2 tests pass in simulation:

| # | Test                        | Result |
|---|-----------------------------|--------|
| 1 | Reset & Boot                | ✅ PASS |
| 2 | Core Execution (PC moves)   | ✅ PASS |
| 3 | GPIO Initialisation         | ✅ PASS |
| 4 | IMEM Data Read (.rodata)    | ✅ PASS |
| 5 | UART TX Banner              | ✅ PASS |
| 6 | LED Binary Counter          | ✅ PASS |
| 7 | CSR Cycle Counter           | ✅ PASS |
| 8 | LED Counter Wrap (0xF→0x0)  | ✅ PASS |
| 9 | Button Echo                 | ✅ PASS |
|10 | UART RX Loopback            | ✅ PASS |

---

## Target Device

| Parameter   | Value              |
|-------------|-------------------|
| FPGA        | XC7A35T-CSG324-1  |
| Board       | Digilent Arty A7  |
| Clock       | 100 MHz           |
| Tool        | Vivado 2025.2     |

---

## What's Next — Phase 3

Phase 3 will transform this into a **5-stage pipeline** (IF → ID → EX → MEM → WB) with:
- Pipeline registers between all stages
- Data hazard detection + stalling
- EX/MEM and MEM/WB forwarding paths
- Branch resolution in EX stage
- Performance counters (IPC measurement)

The SoC infrastructure (bus fabric, peripherals, firmware) will remain unchanged — only `riscv_core.sv` changes.
