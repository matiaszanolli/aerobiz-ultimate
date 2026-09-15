#!/usr/bin/env python3
"""Build the SEGA-logo intro asset for the SH2, from the ROM.

The Genesis SEGA screen is drawn by InitGameGraphicsMode:

  * 50 raw 4bpp tiles at **$001D88**, loaded by CmdPlaceTile2 to tile $200.
  * A 12x4 name table at **$04771C**; each word indexes those tiles directly.
  * Palette line 0 at **$0476FC**.
  * Placed at tile (14,12), so pixel (112,96).

Decoding exactly that reproduces the Genesis frame: every palette index maps to
one captured colour, and nothing is drawn outside the 96x32 box (HISTORY,
2026-09-14). No capture is needed to build it.

The animation is precomputed here so the SH2 does no trigonometry and no
division: for every frame, the inverse affine matrix in Q16.16 and the screen
box it can touch. The last frames are the exact identity, and this script
checks that rasterising the final frame the way the SH2 does lands on the
Genesis logo pixel for pixel -- that is what makes the hand-off invisible.

Usage: make_sega_logo.py <rom> <out.h>
"""
import math, sys

TILES, NAMES, PAL = 0x001D88, 0x04771C, 0x0476FC
COLS, ROWS = 12, 4
W, H = COLS * 8, ROWS * 8                  # 96 x 32
DST_X, DST_Y = 112, 96                     # where the Genesis draws it
SCR_W, SCR_H = 320, 224

# The animation. Tune here; the SH2 only replays the table.
N_ANIM = 110                               # frames of motion, 60 per second
N_HOLD = 16                                # identity frames before the layer blanks
S0 = 0.06                                  # starting scale
TURNS = 2.0                                # turns unwound on the way in

# How PicoDrive displays Genesis colour levels, measured on this very screen
# (HISTORY 2026-09-14): 3-bit red/blue level -> 5-bit, green level -> 6-bit.
# The 32X side renders BGR555 as R5, G5 << 1, B5, so every green here is even
# and has an exact 32X equivalent. Matching them makes the hand-off seamless
# under emulation; on hardware the two DACs differ and the match is approximate.
RB5 = {0: 0, 5: 21, 6: 25, 7: 29}
G6 = {0: 0, 1: 12, 2: 20, 3: 28, 4: 34, 5: 42, 6: 50, 7: 58}


def word(rom, a):
    return (rom[a] << 8) | rom[a + 1]


def decode(rom):
    names = [word(rom, NAMES + 2 * i) for i in range(COLS * ROWS)]
    img = [0] * (W * H)
    for k, n in enumerate(names):
        tile = rom[TILES + 32 * (n & 0x7FF):TILES + 32 * (n & 0x7FF) + 32]
        tx, ty = (k % COLS) * 8, (k // COLS) * 8
        for y in range(8):
            for x in range(8):
                b = tile[y * 4 + x // 2]
                img[(ty + y) * W + tx + x] = (b >> 4) & 15 if x % 2 == 0 else b & 15
    return img


def palette(rom, used):
    out = [0] * 16
    for i in sorted(used):
        w = word(rom, PAL + 2 * i)
        r, g, b = (w >> 1) & 7, (w >> 5) & 7, (w >> 9) & 7
        if r not in RB5 or b not in RB5 or g not in G6:
            sys.exit(f"palette index {i} (${w:04X}) uses a level with no measured display value")
        out[i] = (RB5[b] << 10) | ((G6[g] >> 1) << 5) | RB5[r]   # opaque: priority bit clear
    return out


def frames():
    cx, cy, sx, sy = DST_X + W / 2, DST_Y + H / 2, W / 2, H / 2
    out = []
    for f in range(N_ANIM + N_HOLD):
        if f >= N_ANIM - 1:
            s, a = 1.0, 0.0
        else:
            e = 1.0 - (1.0 - f / (N_ANIM - 1)) ** 3
            s, a = S0 ** (1.0 - e), TURNS * 2 * math.pi * (1.0 - e)
        c, sn = math.cos(a), math.sin(a)
        xs, ys = [], []
        for px, py in ((0, 0), (W, 0), (W, H), (0, H)):
            dx, dy = px - sx, py - sy
            xs.append(cx + s * (c * dx - sn * dy)); ys.append(cy + s * (sn * dx + c * dy))
        x0 = max(0, int(math.floor(min(xs))) - 1) & ~1
        x1 = min(SCR_W, (int(math.ceil(max(xs))) + 2) & ~1)
        y0 = max(0, int(math.floor(min(ys))) - 1)
        y1 = min(SCR_H, int(math.ceil(max(ys))) + 1)
        ddx, ddy = x0 + 0.5 - cx, y0 + 0.5 - cy
        u0 = sx + (c * ddx + sn * ddy) / s
        v0 = sy + (-sn * ddx + c * ddy) / s
        q = lambda v: int(round(v * 65536))
        out.append(((q(u0), q(v0), q(c / s), q(-sn / s), q(sn / s), q(c / s)), (x0, y0, x1, y1)))
    return out


def raster(img, m, box):
    """The SH2's inner loops, in Python, for the self-check."""
    screen = {}
    u0, v0, dudx, dvdx, dudy, dvdy = m
    x0, y0, x1, y1 = box
    ul, vl = u0, v0
    for y in range(y0, y1):
        u, v = ul, vl
        for x in range(x0, x1):
            su, sv = u >> 16, v >> 16
            screen[(x, y)] = img[sv * W + su] if 0 <= su < W and 0 <= sv < H else 0
            u += dudx; v += dvdx
        ul += dudy; vl += dvdy
    return screen


def main():
    rom = open(sys.argv[1], 'rb').read()
    img = decode(rom)
    used = set(img)
    pal = palette(rom, used)
    anim = frames()

    last = raster(img, *anim[-1])
    for (x, y), idx in last.items():
        want = img[(y - DST_Y) * W + (x - DST_X)] if DST_X <= x < DST_X + W and DST_Y <= y < DST_Y + H else 0
        if idx != want:
            sys.exit(f"final frame is not the identity at ({x},{y}): {idx} != {want}")
    if not all(DST_X <= x < DST_X + W and DST_Y <= y < DST_Y + H for x in range(anim[-1][1][0], anim[-1][1][2])
               for y in range(anim[-1][1][1], anim[-1][1][3]) if last[(x, y)]):
        sys.exit("final frame draws outside the logo box")
    for m, (x0, y0, x1, y1) in anim:
        if x0 & 1 or x1 & 1 or not (0 <= x0 <= x1 <= SCR_W and 0 <= y0 <= y1 <= SCR_H):
            sys.exit(f"bad box {x0},{y0},{x1},{y1}")
        if any(not -2**31 <= v < 2**31 for v in m):
            sys.exit("a Q16.16 value does not fit a 32-bit long")

    L = ["/* Generated by tools/make_sega_logo.py from the ROM. Do not edit. */",
         "#ifndef SEGA_LOGO_H", "#define SEGA_LOGO_H", "",
         f"#define SEGA_W       {W}u", f"#define SEGA_H       {H}u",
         f"#define SEGA_FRAMES  {len(anim)}u",
         f"#define SEGA_IDENTITY {N_ANIM - 1}u   /* first identity frame */", "",
         f"/* palette indices, {W}x{H}; indices used: {sorted(used)} */",
         f"static const unsigned char sega_logo[{W * H}] = {{"]
    for r in range(H):
        L.append("    " + ",".join(str(v) for v in img[r * W:(r + 1) * W]) + ",")
    L += ["};", "", "/* 32X BGR555, priority bit clear */",
          "static const unsigned short sega_pal[16] = {",
          "    " + ",".join(f"0x{p:04X}" for p in pal), "};", "",
          "/* per frame: u0, v0 at the box's first pixel centre, dudx, dvdx, dudy, dvdy -- Q16.16 */",
          "static const long sega_anim[SEGA_FRAMES][6] = {"]
    for m, _ in anim:
        L.append("    {" + ",".join(f"{v}L" for v in m) + "},")
    L += ["};", "", "/* per frame: x0, y0, x1, y1 -- x even, x1 and y1 exclusive */",
          "static const unsigned short sega_box[SEGA_FRAMES][4] = {"]
    for _, b in anim:
        L.append("    {" + ",".join(str(v) for v in b) + "},")
    L += ["};", "", "#endif", ""]
    open(sys.argv[2], 'w').write("\n".join(L))
    print(f"{sys.argv[2]}: {W}x{H} logo, {len(used)} colours, {len(anim)} frames; final frame verified identity")


if __name__ == '__main__':
    main()
