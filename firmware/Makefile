## ============================================================
##  Makefile  -  RV32IM SoC Firmware
##  Step 20 — Hello World
##
##  Targets:
##    make          → build hello.elf + hello.hex
##    make clean    → remove build artefacts
##    make dump     → disassemble for inspection
##    make size     → show section sizes
##
##  Requirements:
##    riscv32-unknown-elf-gcc  (or riscv64 with -march=rv32im)
## ============================================================

CROSS   := riscv32-unknown-elf
CC      := $(CROSS)-gcc
OBJCOPY := $(CROSS)-objcopy
OBJDUMP := $(CROSS)-objdump
SIZE    := $(CROSS)-size

## ── Compiler flags ───────────────────────────────────────────
ARCH    := rv32im_zicsr
ABI     := ilp32
CFLAGS  := -march=$(ARCH) -mabi=$(ABI)   \
            -O2                           \
            -ffreestanding                \
            -fno-builtin                  \
            -Wall -Wextra                 \
            -nostdlib                     \
            -nostartfiles                 \
            -T link.ld

## ── Sources ──────────────────────────────────────────────────
SRCS    := crt0.S hello.c

## ── Outputs ──────────────────────────────────────────────────
TARGET  := hello

## ── Rules ────────────────────────────────────────────────────
.PHONY: all clean dump size

all: $(TARGET).hex

## Link ELF
$(TARGET).elf: $(SRCS) link.ld
	$(CC) $(CFLAGS) -o $@ $(SRCS)

## Binary → hex (verilog readmemh format)
## objcopy -O verilog produces one byte per line (not what we want).
## We use a Python helper to produce word-addressed 8-hex-digit lines.
$(TARGET).hex: $(TARGET).elf
	$(OBJCOPY) -O binary $< $(TARGET).bin
	python3 bin2hex.py $(TARGET).bin $@
	@echo ""
	@echo "=== $(TARGET).hex ready ==="
	@echo "Word count: $$(wc -l < $@) instructions"
	@echo ""
	@echo "Next step: run Vivado synthesis with IMEM_FILE=$@"
	@echo "  vivado -mode batch -source ../synth.tcl -tclargs $$(pwd)/$(TARGET).hex"

## Disassembly
dump: $(TARGET).elf
	$(OBJDUMP) -d -M numeric $< | less

## Size report
size: $(TARGET).elf
	$(SIZE) $<

clean:
	rm -f $(TARGET).elf $(TARGET).bin $(TARGET).hex
