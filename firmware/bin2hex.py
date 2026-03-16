#!/usr/bin/env python3
"""
bin2hex.py  -  Convert raw binary to Verilog $readmemh format
Step 20 — Hello World

Usage:
    python3 bin2hex.py input.bin output.hex

Output format:
    One 8-digit hex word per line, little-endian word assembly.
    Vivado and iverilog both accept this format with $readmemh.

    Example (3 bytes padded to 1 word):
        AABBCC00  → line: 00ccbbaa  (little-endian)
"""

import sys
import struct

def bin2hex(src: str, dst: str) -> None:
    with open(src, 'rb') as f:
        data = f.read()

    # Pad to 4-byte boundary
    remainder = len(data) % 4
    if remainder:
        data += b'\x00' * (4 - remainder)

    words = struct.unpack(f'<{len(data)//4}I', data)

    with open(dst, 'w') as f:
        for w in words:
            f.write(f'{w:08x}\n')

    print(f'Converted {src} → {dst}: {len(words)} words '
          f'({len(words)*4} bytes)')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f'Usage: {sys.argv[0]} input.bin output.hex')
        sys.exit(1)
    bin2hex(sys.argv[1], sys.argv[2])
