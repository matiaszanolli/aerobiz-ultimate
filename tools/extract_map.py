#!/usr/bin/env python3
"""Extract the Genesis world map from a PicoDrive savestate.

U-030. Plane B carries the world map (measured: 34 distinct tiles with no
dominant one, against plane A's 79% single filler tile). This reads the
nametable, the 4bpp tiles and CRAM out of a savestate and renders the visible
region, so the map can be checked against a captured frame before any of it is
handed to the SH2.

Usage: extract_map.py <state> <out.png> [--plane a|b] [--raw out.bin]
"""
import struct, sys, zlib

CHUNK_M68K, CHUNK_VRAM, CHUNK_CRAM, CHUNK_VIDEO = 1, 3, 5, 8

def chunks(path):
    d = open(path, 'rb').read()
    out, i = {}, 12
    while i + 5 <= len(d):
        cid = d[i]
        ln = struct.unpack('<I', d[i+1:i+5])[0]
        i += 5
        out.setdefault(cid, d[i:i+ln])
        i += ln
    return out

# PicoDrive stores VRAM and CRAM byte-swapped in savestates, the same way it
# stores 68K work RAM. Verified against the Genesis CRAM bit pattern: read
# little-endian, 16 of 16 entries match 0000bbb0ggg0rrr0; read big-endian, 4.
# So a logical byte at address a lives at index a^1, and a logical word is a
# little-endian read.
def vb(vram, a):
    """One VRAM byte at logical address a."""
    return vram[a ^ 1]

def vw(vram, a):
    """One VRAM word at logical (even) address a."""
    return struct.unpack('<H', vram[a:a+2])[0]

def cram_to_rgb(w):
    """Genesis CRAM: 0000 BBB0 GGG0 RRR0, three bits per channel."""
    r = (w >> 1) & 7
    g = (w >> 5) & 7
    b = (w >> 9) & 7
    return (r * 255 // 7, g * 255 // 7, b * 255 // 7)

def main():
    state, out_png = sys.argv[1], sys.argv[2]
    plane = 'b'
    raw_out = None
    if '--plane' in sys.argv:
        plane = sys.argv[sys.argv.index('--plane') + 1].lower()
    if '--raw' in sys.argv:
        raw_out = sys.argv[sys.argv.index('--raw') + 1]

    c = chunks(state)
    vram, cram, reg = c[CHUNK_VRAM], c[CHUNK_CRAM], c[CHUNK_VIDEO]

    base = (reg[4] & 0x07) << 13 if plane == 'b' else (reg[2] & 0x38) << 10
    hsz = {0: 32, 1: 64, 3: 128}[reg[16] & 3]
    stride = hsz * 2
    cols, rows = 32, 28                      # the visible area at H32
    print(f"plane {plane.upper()} base ${base:04X}, plane {hsz} cells wide, "
          f"reading {cols}x{rows} cells")

    pal = [cram_to_rgb(struct.unpack('<H', cram[i:i+2])[0])
           for i in range(0, min(len(cram), 128), 2)]

    W, H = cols * 8, rows * 8
    px = bytearray(W * H)                    # palette indices, 0-63
    for cy in range(rows):
        for cx in range(cols):
            e = vw(vram, base + cy*stride + cx*2)
            tile = e & 0x7FF
            hflip = (e >> 11) & 1
            vflip = (e >> 12) & 1
            palsel = (e >> 13) & 3
            src = tile * 32
            for y in range(8):
                sy = 7 - y if vflip else y
                for x in range(8):
                    sx = 7 - x if hflip else x
                    byte = vb(vram, src + sy*4 + (sx >> 1))
                    idx = (byte >> 4) if (sx & 1) == 0 else (byte & 0x0F)
                    px[(cy*8 + y) * W + cx*8 + x] = palsel*16 + idx

    if raw_out:
        open(raw_out, 'wb').write(bytes(px))
        print(f"wrote {raw_out}: {len(px)} bytes, {W}x{H} 8bpp indices")

    rgb = b''
    for y in range(H):
        rgb += b'\0'
        for x in range(W):
            i = px[y*W + x]
            rgb += bytes(pal[i] if i < len(pal) else (255, 0, 255))
    def ch(t, d):
        c_ = t + d
        return struct.pack('>I', len(d)) + c_ + struct.pack('>I', zlib.crc32(c_) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n'
           + ch(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
           + ch(b'IDAT', zlib.compress(rgb))
           + ch(b'IEND', b''))
    open(out_png, 'wb').write(png)
    print(f"wrote {out_png}: {W}x{H}")
    used = sorted(set(px))
    print(f"distinct palette indices used: {len(used)} -> {used}")

main()
