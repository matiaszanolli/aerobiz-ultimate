#!/usr/bin/env python3
"""Build the 32X map asset from a Genesis savestate.  U-031.

Emits one blob laid out exactly as the SH2 wants to consume it, so the blit is
a straight copy with no unpacking:

    +$0000  256 words  32X palette, BGR555 (through:1 B:5 G:5 R:5)
    +$0200  224 * 320  packed-pixel rows, one byte per pixel

Rows are padded to the full 320 the VDP displays. Manual 3.3: "VDP mechanically
displays 320 pixels worth of data from the address specified per the line
table", so a short row would show whatever follows it in DRAM.

Usage: make_map_asset.py <state> <out.bin> [--plane a|b]
"""
import struct, sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from extract_map import chunks, vb, vw, CHUNK_VRAM, CHUNK_CRAM, CHUNK_VIDEO

SRC_W, SRC_H = 256, 224
DST_W = 320

def main():
    state, out = sys.argv[1], sys.argv[2]
    plane = sys.argv[sys.argv.index('--plane') + 1].lower() if '--plane' in sys.argv else 'b'

    c = chunks(state)
    vram, cram, reg = c[CHUNK_VRAM], c[CHUNK_CRAM], c[CHUNK_VIDEO]
    base = (reg[4] & 0x07) << 13 if plane == 'b' else (reg[2] & 0x38) << 10
    stride = {0: 32, 1: 64, 3: 128}[reg[16] & 3] * 2

    # Genesis CRAM is BGR333, three bits per channel; the 32X palette is BGR555.
    # (v << 2) | (v >> 1) spreads 0-7 across 0-31 hitting both endpoints.
    pal = bytearray(512)
    for i in range(64):
        w = struct.unpack('<H', cram[i*2:i*2+2])[0]
        r3, g3, b3 = (w >> 1) & 7, (w >> 5) & 7, (w >> 9) & 7
        r5, g5, b5 = ((r3 << 2) | (r3 >> 1)), ((g3 << 2) | (g3 >> 1)), ((b3 << 2) | (b3 >> 1))
        struct.pack_into('>H', pal, i*2, (b5 << 10) | (g5 << 5) | r5)

    px = bytearray(DST_W * SRC_H)          # zero-filled: index 0 in the pad
    for cy in range(SRC_H // 8):
        for cx in range(SRC_W // 8):
            e = vw(vram, base + cy*stride + cx*2)
            tile, hflip, vflip, palsel = e & 0x7FF, (e >> 11) & 1, (e >> 12) & 1, (e >> 13) & 3
            src = tile * 32
            for y in range(8):
                sy = 7 - y if vflip else y
                row = (cy*8 + y) * DST_W + cx*8
                for x in range(8):
                    sx = 7 - x if hflip else x
                    byte = vb(vram, src + sy*4 + (sx >> 1))
                    idx = (byte >> 4) if (sx & 1) == 0 else (byte & 0x0F)
                    px[row + x] = palsel*16 + idx

    open(out, 'wb').write(bytes(pal) + bytes(px))
    print(f"wrote {out}: {512 + len(px)} bytes "
          f"(512 palette + {SRC_H}x{DST_W} pixels, map {SRC_W} wide, rest index 0)")

main()
