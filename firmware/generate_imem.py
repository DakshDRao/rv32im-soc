#!/usr/bin/env python3
"""
generate_imem.py  -  Generate imem_init.sv with firmware baked in
Step 20 — Hello World

Usage:
    python3 generate_imem.py hello.hex imem_init.sv

Reads a word-addressed hex file (one 8-digit word per line, little-endian)
and writes a complete imem.sv with every word assigned explicitly in the
initial block. This bypasses Vivado's unreliable $readmemh for LUTRAMs.
"""

import sys

def generate(hex_file: str, out_file: str, depth: int = 16384) -> None:
    # Read hex words
    words = []
    with open(hex_file) as f:
        for line in f:
            line = line.strip()
            if line:
                words.append(int(line, 16))

    if len(words) > depth:
        print(f"Warning: hex file has {len(words)} words, truncating to {depth}")
        words = words[:depth]

    print(f"Read {len(words)} words from {hex_file}")

    # Find last non-NOP word so we don't emit 64K lines for a small binary
    NOP = 0x00000013
    last_nonzero = len(words) - 1
    while last_nonzero > 0 and words[last_nonzero] in (NOP, 0):
        last_nonzero -= 1
    emit_count = last_nonzero + 1

    addr_bits = depth.bit_length() - 1  # log2(depth)

    lines = []
    lines.append("// ============================================================")
    lines.append("//  imem_init.sv  -  Instruction Memory with firmware baked in")
    lines.append(f"//  Generated from: {hex_file}")
    lines.append(f"//  Words emitted: {emit_count} / {depth}")
    lines.append("//  DO NOT EDIT — regenerate with generate_imem.py")
    lines.append("// ============================================================")
    lines.append("")
    lines.append(f"module imem #(")
    lines.append(f"    parameter int    DEPTH     = {depth},")
    lines.append(f"    parameter int    ADDR_BITS = {addr_bits},")
    lines.append(f"    parameter string MEM_FILE  = \"\"")
    lines.append(f")(")
    lines.append(f"    input  logic        clk,")
    lines.append(f"    // Port 1: instruction fetch")
    lines.append(f"    input  logic [31:0] addr,")
    lines.append(f"    output logic [31:0] instr,")
    lines.append(f"    // Port 2: data read (.rodata access via bus_fabric)")
    lines.append(f"    input  logic [31:0] daddr,")
    lines.append(f"    input  logic [2:0]  dfunct3,")
    lines.append(f"    output logic [31:0] ddata")
    lines.append(f");")
    lines.append("")
    lines.append(f"logic [31:0] mem [0:{depth-1}];")
    lines.append("")
    lines.append("initial begin")
    lines.append(f"    integer i;")
    lines.append(f"    for (i = 0; i < {depth}; i = i + 1)")
    lines.append(f"        mem[i] = 32'h00000013;  // NOP fill")
    lines.append("")

    # Emit explicit assignments for non-NOP words
    for i, w in enumerate(words[:emit_count]):
        if w != NOP:
            lines.append(f"    mem[{i}] = 32'h{w:08x};")

    lines.append("end")
    lines.append("")
    lines.append("assign instr = mem[addr[ADDR_BITS+1:2]];")
    lines.append("")
    lines.append("// Port 2: data read with byte/halfword/word decode")
    lines.append("logic [31:0] raw_word;")
    lines.append("logic [1:0]  byte_off;")
    lines.append("assign raw_word = mem[daddr[ADDR_BITS+1:2]];")
    lines.append("assign byte_off = daddr[1:0];")
    lines.append("always_comb begin : ddata_mux")
    lines.append("    unique casez (dfunct3)")
    lines.append("        3'b000: ddata = {{24{raw_word[byte_off*8+7]}}, raw_word[byte_off*8+:8]};")
    lines.append("        3'b001: ddata = {{16{raw_word[byte_off[1]*16+15]}}, raw_word[byte_off[1]*16+:16]};")
    lines.append("        3'b010: ddata = raw_word;")
    lines.append("        3'b100: ddata = {24'h0, raw_word[byte_off*8+:8]};")
    lines.append("        3'b101: ddata = {16'h0, raw_word[byte_off[1]*16+:16]};")
    lines.append("        default: ddata = raw_word;")
    lines.append("    endcase")
    lines.append("end")
    lines.append("")
    lines.append("endmodule")
    lines.append("")

    with open(out_file, 'w') as f:
        f.write('\n'.join(lines))

    print(f"Written {out_file} ({emit_count} explicit assignments)")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} input.hex output_imem.sv [depth]")
        sys.exit(1)
    depth = int(sys.argv[3]) if len(sys.argv) > 3 else 16384
    generate(sys.argv[1], sys.argv[2], depth)
