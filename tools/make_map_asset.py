#!/usr/bin/env python3
"""Build the 32X world-map asset from the ROM.  U-031.

No savestate. The map is reproducible from `build/aerobiz.bin` alone:

  * Tiles live compressed at **$088CF8** and decompress to exactly 22,528
    bytes -- 704 tiles, verified byte-for-byte against VRAM.
  * The nametable needs no data. Plane B rows 0-21 are tiles 1..704 laid out
    **in sequence**, attribute $2000, so the map is a linear 256x176 bitmap.
    Rows 22-27 are a single repeated tile ($21E1 = tile 481), the ocean band
    under it.

  * The palette is **$07677E**, 16 raw Genesis CRAM words: LoadScreenGfx hands
    it to DisplaySetup for palette line 1 just before placing the map, and the
    live CRAM on the world-map screen equals it word for word.

The palette used to be a pinned constant, on the belief that it was not in the
ROM. It is; the constant had been captured mid-fade, one FadePalette step down
on every channel ($0864 -> $0642), and a search for those values could never
find the table. See HISTORY 2026-09-16.

Output layout, which is exactly what the SH2 writes:

    +$0000  256 words  32X palette, BGR555
    +$0200  224 * 320  packed pixels, one byte each

Usage: make_map_asset.py <rom> <out.bin>
"""
import struct, sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from lz_decompress import decompress

MAP_TILES_ADDR = 0x088CF8
MAP_PALETTE_ADDR = 0x07677E          # LoadScreenGfx -> DisplaySetup, line 1
MAP_TILE_COUNT = 704
MAP_COLS, MAP_ROWS = 32, 22          # the linear region, tiles 1..704
FILL_TILE = 481                      # $21E1, the band under it
PAL_LINE = 1                         # attribute $2000
SRC_W, SRC_H, DST_W = 256, 224, 320


def main():
    rom = open(sys.argv[1], 'rb').read()
    out = sys.argv[2]

    tiles = decompress(rom, MAP_TILES_ADDR)
    if len(tiles) != MAP_TILE_COUNT * 32:
        raise SystemExit(f"expected {MAP_TILE_COUNT*32} bytes of tiles, got {len(tiles)}")

    # 32X palette: BGR333 -> BGR555, (v << 2) | (v >> 1) hits both endpoints.
    pal = bytearray(512)
    palette = struct.unpack_from('>16H', rom, MAP_PALETTE_ADDR)
    for i, w in enumerate(palette):
        r3, g3, b3 = (w >> 1) & 7, (w >> 5) & 7, (w >> 9) & 7
        r5, g5, b5 = (r3 << 2) | (r3 >> 1), (g3 << 2) | (g3 >> 1), (b3 << 2) | (b3 >> 1)
        struct.pack_into('>H', pal, (PAL_LINE * 16 + i) * 2, (b5 << 10) | (g5 << 5) | r5)

    def blit(tile_index, cx, cy, px):
        src = (tile_index - 1) * 32
        for y in range(8):
            row = (cy * 8 + y) * DST_W + cx * 8
            for x in range(8):
                b = tiles[src + y * 4 + (x >> 1)]
                idx = (b >> 4) if (x & 1) == 0 else (b & 0x0F)
                px[row + x] = PAL_LINE * 16 + idx

    px = bytearray(DST_W * SRC_H)            # index 0 in the pad to the right
    for cy in range(MAP_ROWS):
        for cx in range(MAP_COLS):
            blit(cy * MAP_COLS + cx + 1, cx, cy, px)
    for cy in range(MAP_ROWS, SRC_H // 8):
        for cx in range(MAP_COLS):
            blit(FILL_TILE, cx, cy, px)

    open(out, 'wb').write(bytes(pal) + bytes(px))
    print(f"wrote {out}: {512 + len(px)} bytes, from ROM ${MAP_TILES_ADDR:06X} "
          f"({MAP_TILE_COUNT} tiles, {SRC_W}x{SRC_H}, {DST_W}-wide rows)")


if __name__ == '__main__':
    main()
