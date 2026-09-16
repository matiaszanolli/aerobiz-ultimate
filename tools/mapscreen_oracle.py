#!/usr/bin/env python3
"""Per-frame oracle for the world map on the 32X layer -- U-034 stage 2.

Is what the 32X build shows exactly what the Genesis game would show?  The
builds diverge within seconds of a DEMO game (any timing change reseeds it), so
they cannot be compared frame against frame.  Instead each savestate of the 32X
run is turned into the stock picture for that same moment, and compared with
the frame the 32X run actually produced.

The stock picture is built from the state's own VRAM and CRAM, with one change.
LoadScreenGfx fills plane B's 32x22 map block with tile 0 where stock places the
map layout ($2001 + index), and whatever the game draws afterwards lands on the
same cells in both builds -- so a cell still at tile 0 is a map cell in stock.
That substitution is made per cell (the Quarterly Report keeps 509 map cells and
replaces 195) whenever the map is loaded (screen id 7), and also when the whole
block is blank, which is how it looks through a fade after the id has moved on.
The 704 map tiles are still uploaded in the 32X build, so the substituted cells
render exactly what stock renders.  Planes and sprites are composited in Genesis
priority order, and colours compared at the Genesis's 3 bits per channel.

Two properties of the harness, both measured:

  * a frame can already show a Genesis change its state holds only one tick
    later (a banner blink, a sprite removal), so state f+1 is accepted as well
    as state f -- never f-1, because a frame that matches the past is a lag,
    which is what this exists to catch;
  * PicoDrive composites H32 at 320 wide by stretching it (ROADMAP U-003), so
    an H32 frame cannot match a native render and is counted, not compared.

A comparison of black with black proves nothing, and the first version of this
check passed 301 frames of a build that had faded the game to black for good.
So the summary always says how many compared frames had the map lit.

Usage:
    mapscreen_oracle.py <state dir> <frame dump dir>      # summary + failures
    mapscreen_oracle.py <state dir> <frame dump dir> -v   # every frame

States are <frame, six digits>.state, as vrd_harness.save_script writes them.
Save at f and f+1 for each sampled frame.
"""
import glob
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_map import chunks, vb, vw          # noqa: E402
import vrd_harness                              # noqa: E402

SCREEN_ID = 0x9A1C              # analysis/RAM_MAP.md
SCREEN_WORLD = 7
MAP_COLS, MAP_ROWS = 32, 22
MAP_LAYOUT = 0x2001             # LoadScreenGfx's layout at $070198: tiles 1..704


def screen_id(state_chunks):
    ram = state_chunks[2]       # 68000 RAM, byte-swapped (KNOWN_ISSUES)
    return (ram[SCREEN_ID ^ 1] << 8) | ram[(SCREEN_ID + 1) ^ 1]


def planes(vram, reg, sid):
    """Both 28-row planes as nametable words, with stock's map cells restored."""
    width = {0: 32, 1: 64, 3: 128}[reg[16] & 3]
    out = {}
    for name, base in (("A", (reg[2] & 0x38) << 10), ("B", (reg[4] & 0x07) << 13)):
        out[name] = [[vw(vram, base + cy * width * 2 + cx * 2) for cx in range(32)]
                     for cy in range(28)]
    zero = [[(out["B"][cy][cx] & 0x7FF) == 0 for cx in range(MAP_COLS)]
            for cy in range(MAP_ROWS)]
    whole = all(all(r) for r in zero)
    restored = 0
    if sid == SCREEN_WORLD or whole:
        for cy in range(MAP_ROWS):
            for cx in range(MAP_COLS):
                if zero[cy][cx]:
                    out["B"][cy][cx] = MAP_LAYOUT + cy * MAP_COLS + cx
                    restored += 1
    return out, restored


def cell_pixel(vram, entry, x, y):
    """(colour index within the line, CRAM index, priority) of a plane pixel."""
    tile = entry & 0x7FF
    sx = 7 - (x & 7) if (entry >> 11) & 1 else x & 7
    sy = 7 - (y & 7) if (entry >> 12) & 1 else y & 7
    b = vb(vram, tile * 32 + sy * 4 + (sx >> 1))
    idx = (b >> 4) if (sx & 1) == 0 else (b & 15)
    return idx, ((entry >> 13) & 3) * 16 + idx, (entry >> 15) & 1


def sprites(vram, reg, width=256, height=224):
    """Topmost opaque sprite pixel at each screen position: (CRAM index, priority)."""
    sat = (reg[5] & 0x7F) << 9
    buf = {}
    index = 0
    for _ in range(80):
        e = sat + index * 8
        y = (vw(vram, e) & 0x3FF) - 128
        size = vw(vram, e + 2)
        attr = vw(vram, e + 4)
        x = (vw(vram, e + 6) & 0x1FF) - 128
        wc, hc = ((size >> 10) & 3) + 1, ((size >> 8) & 3) + 1
        tile, hflip, vflip = attr & 0x7FF, (attr >> 11) & 1, (attr >> 12) & 1
        line, pri = (attr >> 13) & 3, (attr >> 15) & 1
        for py in range(hc * 8):
            for px in range(wc * 8):
                sx, sy = x + px, y + py
                if not (0 <= sx < width and 0 <= sy < height) or (sx, sy) in buf:
                    continue
                tx = wc * 8 - 1 - px if hflip else px
                ty = hc * 8 - 1 - py if vflip else py
                t = tile + (tx >> 3) * hc + (ty >> 3)     # tiles run down columns
                b = vb(vram, t * 32 + (ty & 7) * 4 + ((tx & 7) >> 1))
                idx = (b >> 4) if (tx & 1) == 0 else (b & 15)
                if idx:
                    buf[(sx, sy)] = (line * 16 + idx, pri)
        index = size & 0x7F
        if index == 0:
            break
    return buf


def expected(path):
    """Stock's picture for this state, cols 0-255, as 3-bit (r, g, b) rows."""
    c = chunks(path)
    vram, reg = c[3], c[8]
    cram = [struct.unpack("<H", c[5][i:i + 2])[0] for i in range(0, 128, 2)]
    pl, restored = planes(vram, reg, screen_id(c))
    spr = sprites(vram, reg)
    backdrop = cram[reg[7] & 0x3F]
    rows = []
    for y in range(224):
        row = []
        for x in range(256):
            ia, ca, pa = cell_pixel(vram, pl["A"][y >> 3][x >> 3], x, y)
            ib, cb, pb = cell_pixel(vram, pl["B"][y >> 3][x >> 3], x, y)
            cs, ps = spr.get((x, y), (None, 0))
            layers = ((cs is not None and ps, cs), (ia and pa, ca), (ib and pb, cb),
                      (cs is not None and not ps, cs), (ia and not pa, ca),
                      (ib and not pb, cb))
            w = next((cram[col] for opaque, col in layers if opaque), backdrop)
            row.append(((w >> 1) & 7, (w >> 5) & 7, (w >> 9) & 7))
        rows.append(row)
    return rows, restored


def compare(states, dump):
    """One result per sampled frame: (frame, restored cells, differing pixels
    or None if not comparable, first difference, lit map samples)."""
    shots = vrd_harness.frames(dump)
    have = {int(os.path.basename(p)[:6]) for p in glob.glob(os.path.join(states, "*.state"))}
    results = []
    def path(n):
        return os.path.join(states, "%06d.state" % n)

    for f in sorted(have):
        # A state saved only as f-1's one-tick companion (f-1 sampled, f-2 not)
        # is not a sample of its own.  In a dense capture every frame is one.
        if f not in shots or (f - 1 in have and f - 2 not in have):
            continue
        r = shots[f]
        if not (chunks(path(f))[8][12] & 0x81) and int(r["width"]) == 320:
            results.append((f, 0, None, None, 0))
            continue
        img = vrd_harness.rgb565(os.path.join(dump, r["path"]), int(r["width"]), int(r["height"]))
        got = img.load()
        assert got is not None

        def mismatches(rows):
            return [(x, y) for y in range(224) for x in range(256)
                    if rows[y][x] != (got[x, y][0] >> 5, got[x, y][1] >> 5, got[x, y][2] >> 5)]

        exp, restored = expected(path(f))
        bad = mismatches(exp)
        if bad and f + 1 in have:
            exp_next, restored_next = expected(path(f + 1))
            bad_next = mismatches(exp_next)
            if not bad_next:
                exp, restored, bad = exp_next, restored_next, bad_next
        lit = sum(1 for y in range(0, 176, 4) for x in range(0, 256, 4) if exp[y][x] != (0, 0, 0))
        results.append((f, restored, len(bad), bad[0] if bad else None, lit))
    return results


def main(argv):
    verbose = "-v" in argv
    args = [a for a in argv if a != "-v"]
    results = compare(args[0], args[1])
    compared = [r for r in results if r[2] is not None]
    for f, restored, bad, first, lit in results:
        if verbose or bad:
            print("%6d  map cells restored %-4d  differing %-6s first %s"
                  % (f, restored, "-" if bad is None else bad, first))
    on_layer = [r for r in compared if r[1]]
    print("frames %d, compared %d, exact %d (H32, not comparable: %d); "
          "map on the layer in %d, lit in %d"
          % (len(results), len(compared), sum(1 for r in compared if r[2] == 0),
             len(results) - len(compared), len(on_layer),
             sum(1 for r in on_layer if r[4] > 100)))
    return 0 if all(r[2] == 0 for r in compared) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
