# Aerobiz Ultimate -- Roadmap

What is next for the 32X port. Items are `U-nnn`, grouped by milestone;
milestones are defined in
[PORT_ARCHITECTURE.md](PORT_ARCHITECTURE.md#6-milestones).

[HISTORY.md](HISTORY.md) is the companion to this file: what has already been
done, and which earlier beliefs turned out to be wrong. When an item closes,
move its findings there rather than leaving them here.

The inherited disassembly backlog (`B-nnn`) lives in the upstream
[aerobiz-disasm](../aerobiz-disasm/) project and is not carried here -- that
work is complete.

---

## M1 -- Adapter bring-up

### U-001 -- Verify the milestone-1 cartridge actually boots [DONE]

Run under the instrumented PicoDrive libretro core in
`../32x-playground/tools/libretro-profiling` (`profiling_frontend
--debug-script`), 600 frames. All five acceptance criteria pass:

| # | Criterion | Observed |
|---|---|---|
| 1 | Boot ROM accepts the security block | `$A15101` = `$83`, `ADEN = 1`, no lock-out, comm0 clean |
| 2 | Master `M_OK` / slave `S_OK` | seen at `$A15120` and `$A15124`, then cleared |
| 3 | Our 68K entry runs | both comm words cleared by MdMain |
| 4 | Both SH2s leave the release spin | master PC `$0600029C` = `main_loop`, slave PC `$06000332` = `slave_loop` |
| 5 | Bank 1 selected | `$A15104` = `$0001` |

It did not boot at first. Three real defects, all now fixed:

1. **The security block was truncated to 228 bytes.** It is 1040 (`$3F0-$7FF`).
   `extract_mars_init.py` stopped at the `jmp (a0)` near `$4C0`, taking that for
   the application hand-off. It is not -- it is the block relocating itself into
   the fixed window after setting `ADEN = 1`. Everything past `$4D4` was `$FF`
   in our cartridge, so the block called into padding and the 68000 died inside
   the first frame.
2. **MdMain was placed at `$8806BC`, inside the block**, on top of its work-RAM
   clear loop. The real entry is `$800`, where the block falls through with its
   verdict in the carry flag -- hence the `bcs` that the manual's sample listing
   puts as the first application instruction. MdMain now starts with it.
3. **The boot handshake used the wrong comm slot.** Manual 5.1's "comm 0, 4, 8"
   are byte offsets, not comm-register indices: the slave's `S_OK` lands at
   `$A15124`, not `$A15128`. The 68000 waited forever on a word nothing writes.
   `MARS_COMM_MOK` / `MARS_COMM_SOK` now name the two slots explicitly on both
   the 68000 and SH2 sides.

Two build defects found on the way: the M1 cartridge inherited MdMain's
`jmp (GameEntryPoint).l` into a game half it does not carry (there is now a
`MILESTONE1` idle), and the boot half did not depend on its own includes, so
edits to `md_main.asm` or `mars_header.asm` did not trigger a rebuild.

**Resolves PORT_ARCHITECTURE.md §5.1**, and not the way it was framed -- see
that entry.

### U-004 -- Drop the retail donor requirement [DONE]

`tools/extract_mars_init.py` now reads the block from either a `.32x` image or
an assembly source carrying it as `dc.w` data. marsdev's
`examples/32x-skeleton/md_src/md_start.s` yields byte-identical output to
retail Virtua Racing Deluxe, and a full `make 32x-m1` built that way passes
U-001 unchanged. The block is still not committed here.

### U-002 -- Draw something on the 32X layer [DONE]

`make 32x-fbtest` builds a cartridge whose 68000 sets packed-pixel mode, hands
the VDP to the SH2 with `FM = 1`, asks it to paint, and parks. The SH2 fills
the line table, the palette and 224 lines of pixels from C
(`disasm/sh2/master/fb.c`). The layer comes up and holds a steady image --
five consecutive captured frames hash identically.

The test pattern is a two-axis gradient, red along X and green along Y,
chosen so that a wrong line table or a wrong stride shows up as shear or noise
rather than as something that merely looks odd. It also carries an accidental
ruler: the X ramp is masked to 16 bands of 16 pixels, so it wraps at x = 256,
and seeing that wrap confirms the VDP really is displaying a 320-pixel line.

What this pins down for the rest of M4:

- Line table is 256 words at the head of the buffer; in packed-pixel mode a
  line is 160 words, so pixel data starts at word 256 and line *n* is at
  `256 + n * 160` (manual 3.3).
- Palette word is `through:1 B:5 G:5 R:5` (manual, "Color Palette").
- `FM = 1` hands the frame buffer *and* the 32X VDP registers to the SH2, so
  the bitmap mode register has to be written by the 68000 first, while it
  still owns them.
- An `FS` write only takes effect at the next V Blank (manual :1059), and only
  the back buffer is writable -- so painting both buffers in turn is what
  makes the image independent of which side the VDP happens to be showing.
- Word writes throughout. A byte write to the frame buffer cannot store zero
  ([KNOWN_ISSUES.md](KNOWN_ISSUES.md)), which would have punched holes in any
  pattern containing palette index 0.

### U-003 -- Confirm Aerobiz's Genesis display mode [DONE, and it is a problem]

**Aerobiz runs H32.** Measured, not read out of the register table: the
emulator's own frame geometry over 3,000 frames of the Genesis build.

| Frames | Mode |
|---|---|
| 0-320 | H40, 320x224 -- TMSS and boot screens |
| 321 onward | **H32, 256x224** -- the KOEI intro, title and everything after |

Manual 3.3 requires the Genesis VDP to be in a 320-wide mode whenever the 32X
layer is not blanked. The game spends essentially all of its time at 256.

So §4.1 as written does not work: the world map cannot go on the 32X layer with
the Genesis planes in front while the game is in H32. Either the game moves to
H40 -- which is 40 tiles per line against the 32 every screen is laid out for,
so not a flag flip -- or the 32X layer is used only on screens converted to H40.
Resolve this before U-030 starts; it is a design decision, not a bug.

#### Resolved by measurement, 2026-09-12: convert the map screen only

`make 32x-layeron` builds the real game with the 32X layer live behind it
(packed pixel, `PRI = 0`, the §4.1 arrangement) and the U-002 gradient painted
underneath. What happens is not a catastrophe and not usable either.

**Nothing breaks.** The game runs, stays legible, and composites the way §4.1
wants -- Genesis planes in front, the 32X layer showing through wherever the
Genesis pixel is transparent.

**But the two layers are at different scales.** With the 32X active the
compositor always emits 320, and PicoDrive fills it by stretching the H32
output 1.25x. Measured on frame 1799 against the Genesis build's own 256-wide
frame:

| Hypothesis | Pixel match |
|---|---|
| nearest-neighbour stretch 256 -> 320 | **95.6%** |
| centred with 32-pixel borders | 85.0% |
| left-aligned, no scaling | 83.4% |

and the content spans confirm it: columns 8-230 in the Genesis frame, 10-288
in the composite, which is 8 and 230 multiplied by exactly 1.25.

So while the game is in H32, **one Genesis pixel is 1.25 32X pixels** and the
two layers cannot be registered against each other. A 32X-drawn map with
Genesis-drawn pins, labels or route lines on top of it would not line up, and
no amount of care in the renderer fixes that. In H40 they are 1:1 -- visible
in the frame-250 capture, where the SEGA logo sits unstretched over the
gradient.

Also observed, and a reason not to enable the layer globally: with the layer
on, the Genesis backdrop reads as transparent, so **every screen loses its
background colour** to the 32X layer.

**Decision: option (b), and specifically the map screen alone.** That is the
screen whose Genesis content M4 is replacing anyway, so it has the least to
re-lay-out from 32 tiles to 40, and it confines the H40 switch -- and the
backdrop change -- to one place. The rest of the game stays H32 with the layer
blanked, exactly as it is today.

**How far to trust this.** The stretch is not an emulator shortcut. PicoDrive
models a specific hardware mechanism, and says so in `pico/32x/draw.c:11-19`:

> 32X officially doesn't support H32 mode. However, it does work since the
> cartridge slot carries the EDCLK signal which is always H40 clock and is
> used as video clock by the 32X. The H32 MD image is overlaid with the 320 px
> 32X image which has the same on-screen width.

That is the whole explanation. H32 and H40 fill the same visible width; H32
just uses fewer, wider pixels; the 32X always clocks video at H40 off EDCLK.
So 256 MD pixels landing on 320 32X pixels is physics, not emulation, and the
1.25x scale mismatch would be there on a real console. Manual 3.3's "must be
320-wide" turns out to mean *officially unsupported*, not *broken*.

Worth noting the core is FAME/C here (`fm68k_emulate`), not Musashi -- but the
68000 core is irrelevant to this question either way; the compositing is
PicoDrive's own 32X code.

Two things are still genuinely open, both narrower than the original doubt:

- **The backdrop.** The same comment says the `/YS` signal, which is what
  signals display of the background colour, is of "unclear" handling in H32
  and "might lead to glitches due to race conditions by the different video
  clocks". Our observation that the Genesis backdrop goes transparent is
  exactly that path, so it is the finding to distrust -- not the geometry.
- **The 4-pixel offset.** `draw.c` applies `H32_OFFSET 4` between the MD and
  32X layers in H32. Scanning offsets against the captured frames, the best
  match is at 0, so it is already inside the composite rather than a residual
  shift -- but it is a hardware detail worth re-checking if H32 compositing is
  ever relied on.

Neither affects the decision: the map screen goes H40, where none of this
applies.

---

## M2 -- Rebase the game to $900000

### U-010 -- Rewrite the safe ROM literals [DONE]

3,001 rebased as `ROM_BASE+$xxxxxx`, in five batches, each verified
byte-identical. `scan_rom_refs.py --rewrite` did the work, so the tool that
finds a site is the tool that fixes it.

The starting figure of 1,990 was wrong, in three ways the scanner could not
see:

| Missed class | Count | Why |
|---|---|---|
| hand-encoded `dc.w $4EB9,$hi,$lo` | 971 | address split across two words; invisible to every regex |
| multi-value `dc.l` lines | 35 | only the first longword on a line was matched |
| PC-relative `$xxx(pc)` / `$xxx(pc,Rn)` | 22 | not modelled at all |
| `dbne` / `dbeq` | 2 | only `dbra`/`dbf` were listed, and the conditional pattern anchors on `b` |

The 971 mattered most: they are `jsr` targets, and left alone every one would
have called into unmapped `$000xxx`. They are now real mnemonics --
`jsr (ROM_BASE+$000D64).l` -- which also removes 971 hand-encoded instructions,
per ground rule 4.

The true inventory was 3,872, not 2,886. `disasm/sections/header.asm` is
excluded: its vector table is inert on 32X.

Two further classes surfaced only when START was first pressed (see
[HISTORY.md](HISTORY.md)), both of them blind spots in the scanner rather than
in the source:

| Missed class | Count | Why |
|---|---|---|
| upper-case mnemonics | 2 | `INSTR` matched `[a-z]` only, so nine modules were never seen as instructions |
| hand-encoded instructions in untranslated `dc.w` blocks | 50 | one word per line, so no three-word pattern can match |

`--rewrite-dcw-code` handles the second: the two operand words become one
`dc.l ROM_BASE+$xxxxxx`, the same four bytes on Genesis. `make verify` cannot
see this class, so each site is confirmed by decoding its enclosing block
linearly with capstone -- a word that only looks like an opcode inside data does
not land on an instruction boundary. All 50 do.

`scan_rom_refs.py` now reports **zero** `safe` sites outstanding.

### U-011 -- Classify the 901 "review" literals [OPEN]

`tools/scan_rom_refs.py --list review`. Each is a `move`/`andi`/`addi`/`cmpi`/
`ori`/`mulu`/`subi` immediate that happens to fall in `$000200-$0FFFFF`. Most
are masks, counts and multipliers, not addresses. Classify against
`analysis/DATA_TABLES.md` and `analysis/FUNCTION_REFERENCE.md`.

**The Genesis byte-identical check cannot catch a mistake here.** Rewriting a
constant as `ROM_BASE+$xxxx` leaves the Genesis ROM unchanged and breaks only
the 32X build. Record the verdict and the evidence for each site.

### U-012 -- Get the game half to assemble at $900000 [DONE]

Fell out of U-010: once the PC-relative literals were rebased, `make 32x`
assembles a full 2 MB cartridge.

The layout check that matters: the game half is byte-for-byte the same length
as the Genesis image and differs in 5,793 bytes, **every one an isolated single
byte** where an address high byte went `$0X` to `$9X`. No runs, so nothing
shifted -- which is the property the whole rebasing scheme depends on. Roughly
3,000 of those are the literal rebases; the rest are symbolic references that
`org ROM_BASE` moved on their own.

### U-013 -- Reach the title screen [DONE]

**The 32X build renders identically to the Genesis build.** At frame 2550, and
frame-for-frame through 4,500 frames driven by the same recorded input:

| | differing |
|---|---|
| VRAM | 2 of 65536 bytes |
| CRAM | 1 of 128 |
| VSRAM | 0 of 128 |
| VDP registers | 0 of 64 |
| work RAM | 60 of 65536 |

Frames-with-content runs match exactly, offset by five frames of adapter
bring-up.

The cause was never a literal in the source. It was pointer **values stored in
ROM data**: the code that loads them was rebased, the pointer it read was not,
and on 32X a raw address lands in the boot half's `$FF` padding -- which is why
VRAM filled with `$FF` and palettes came out `$0EEE`, that being `$FFFF` masked
into the Genesis 9-bit colour format.

No data-side heuristic can find these -- a pointer sits mid-line in compressed
graphics and looks like graphics. The code is the evidence, so both new passes
read the code:

- `--rewrite-indirect`: every `move/movea.l (ROM_BASE+$X).l` proves offset X
  holds a pointer. All 260 such sites load a value that is itself a ROM address.
- `--rewrite-tables`: a rebased literal used as a base, followed by a run of
  even ROM addresses, is a table indexed at runtime. Runs extend both
  directions, since the code may take the address of a table's middle.

567 pointers rebased in total, every batch byte-identical on the Genesis side.

---

## M3 -- Full game on 32X, layer blank

### U-020 -- Implement the 32X DMA stub: `RV` window and source translation [DONE]

`disasm/32x/dma_stub.asm`, reached by swapping the six bytes of
ConfigVDPDMA's `jsr $FFF000` for a `jsr` to a fixed address in the boot half.
Translates a bank-window source to the same bytes' cartridge offset, reprograms
VDP registers 21-23, and runs the windowed sequence from below the stack
pointer. A work-RAM source takes neither and hands off to the game's own
trigger stub.

`make 32x-rvprobe` does **not** answer §5.3 after all: PicoDrive does not
implement the `RV` bit (`pico/32x/memory.c:2358`, :2481), so the probe was
observing a mapping that never changed. The window is unverifiable on this
emulator -- the thunk demonstrably breaks nothing, and cannot be shown to work.
Keep the probe; it will answer the question on hardware.

Exercised: 616 thunk entries over 3,000 frames, 31 of them on the cartridge
path. **None in the first 900 frames** -- an earlier sample over that range
concluded the game never DMAs from ROM, which was wrong.

**This did not fix the display.** U-020 was necessary but is not what is
blanking the screen; see U-013.

### U-022 -- Teach `scan_rom_refs.py` the `DMA_BASE` class [CLOSED, superseded]

Dropped in favour of translating at the sink (U-020 step 3). Kept here because
the reasoning matters: rebasing a literal to cartridge offset `$100000` is only
correct if that literal feeds DMA **and nothing else**. The same pointer is
often dereferenced by the 68000 too, which needs `$900000`; one value cannot be
both. Identifying the DMA-only ones would need interprocedural dataflow, since
callers pass sources through wrappers, and getting it wrong fails silently.

Translating in `ConfigVDPDMA` -- the only code in the game that programs a
memory-to-VRAM DMA source -- makes the question disappear. **U-010 is no longer
gated.**

### U-021 -- Full playthrough on 32X [DONE]

Scenario select, a turn cycle, save, load and the end of the game all run on the
32X. Evidence in [HISTORY.md](HISTORY.md); the short version:

| what | result |
|---|---|
| setup, turn cycle, save (90,000 frames) | 0 exceptions on either build |
| complete 20-year DEMO game (900,000 frames) | 0 exceptions on either build; both reach the ending and return to attract |
| save | 16,384 bytes written to cartridge SRAM `$200000-$203FFF` by both builds |
| load | the 32X boots its own save, CONTINUE lists it and resumes the game |
| no-input equivalence, 300,000 frames | work RAM differs in 64 of 65,536 bytes: 53 rebased pointers, 5 dead stack, 6 unexplained |

SRAM needs no port work. `docs/32x-technical-info.md:83` says the `RV` bit is
irrelevant to SRAM, and `PackSaveState` builds the address as
`addi.l #$00200003,d0` -- outside the ROM window, so the rebaser leaves it alone.

**Do not compare two long AI games between the builds.** The outcome is
chaotically sensitive to input timing: shifting the setup presses by one frame
changes the *Genesis* build's own game length from 433,515 frames to 172,286, so
the adapter's few frames of bring-up reseed the game by itself. Use a no-input
run, or a short horizon with identical input.

Frame hashes cannot be compared across builds either: the Genesis build reports
H32 as 256 wide and the 32X composites at 320. Compare 68000 work RAM, which is
width-independent.

---

## M4 -- World map on the 32X layer

### U-036 -- Switch the map screen to H40 [SCOPED]

The gate U-003 landed on. The map screen has to run 40 tiles per line for its
Genesis overlay to register against a 32X-drawn map; every other screen stays
H32 with the layer blanked.

`make 32x-h40` forces H40 once per frame from the V-Blank trampoline in the
boot half -- no shared-code change -- with the layer on underneath. It answers
both questions.

**H40 gives exact registration.** Comparing the composite against the Genesis
build's own 256-wide frame 1799, over the 5,077 non-backdrop pixels in columns
0-255: **100.00% identical**. Not approximately 1:1 -- pixel for pixel, no
stretch and no offset. Nothing else about the game's rendering breaks.

**The extra 64 pixels wrap.** Columns 256-319 are **100.00%** identical to
columns 0-63. VDP register 16 reads `$10`: VSZ = 64 cells, HSZ = **32** cells,
so the plane is 256 pixels wide and H40 simply shows it twice.

**Widening it is far cheaper than "re-lay-out the screen".** The engine already
treats the BAT row stride as a variable, not a constant: `$FFA77E` holds it
(`$0020` = 32 cells at runtime), `SetScrollQuadrant` writes it, and
`UpdateScrollRegisters`, `CalcScrollBarPos` and `DrawCharInfoPanel` all
multiply by it rather than by a literal. So the change is:

| Step | Detail |
|---|---|
| VDP register 16 | `$10` -> `$11` (HSZ 32 -> 64 cells) |
| `$FFA77E` | 32 -> 64, for the screen that runs H40 |
| VRAM | nametable per plane 4,096 -> 8,192 bytes; needs a budget check |
| `UpdateScrollDisplay` | has a literal `cmpi.w #$20` against the stride |
| audit | anything else assuming 32 cells |

**The VRAM budget, measured -- H40 costs nothing.** The layout is identical on
every screen sampled through a demo game (frames 12,000 to 36,000):

| | |
|---|---|
| Tiles | `$0000-$BFFF`, last non-zero byte `$BFDA` -- **1,534 of 1,536 tiles used** |
| Plane A | `$C000` |
| Plane B | `$E000` |
| Sprites | `$F800` |
| HScroll | `$FC00` |
| Register 16 | `$30` -- **V 128 cells, H 32 cells** |

The tile area is full, so the earlier worry was that widening the planes would
need VRAM that does not exist. It does not, because the planes are **already
8,192 bytes each**: 32 x 128 cells and 64 x 64 cells are the same size. The
change is register 16 `$30` -> `$11` and nothing moves.

Nor does the vertical loss matter for display. A 224-line screen is 28 rows,
and the vertical scroll is **zero in every state sampled** -- the game does not
scroll these planes vertically at all -- so 64 rows is more than twice what is
ever shown.

**The real risk is the off-screen rows.** Plane A holds real tilemap data out
to row 91 and plane B to row 78, far past the 28 that are displayed; on the
sampled screens plane A rows 0-28 are a uniform filler tile while rows 40+
carry varied content with tile indices up to `$7FA`. Something is being kept
there. Reshaping to 64 x 64 cuts that off-screen area from rows 28-127 down to
rows 28-63, so 100 spare rows become 36. Before changing register 16, find out
whether the game stages tilemaps in those rows -- the VDP's VRAM-copy DMA makes
it plausible -- or whether they are simply stale.

Worth noting plane B's nominal 128 rows already run into the sprite table at
`$F800`, so only 96 of them are usable today. The declared plane size is
already larger than what the game can really use, which is mild evidence that
the off-screen rows are slack rather than a design.

**And the engine already supports 64 x 64.** `SetScrollQuadrant` (`$005518`)
takes two quadrant indices, looks up a byte in a table at `$04737E`, and issues
it as `$9000 | value` through `GameCommand` -- which is a **VDP register 16
write**, `$8000 | (16 << 8)`. It then sets `$FFA77E` and `$FFA77C` to the
matching cell dimensions. So plane geometry is table-driven and already changes
at runtime. The table:

| | d3=0 | d3=1 | d3=2 | d3=3 |
|---|---|---|---|---|
| **d2=0** | -- | `$01` 64x32 | -- | `$03` 128x32 |
| **d2=1** | `$10` 32x64 | **`$11` 64x64** | -- | -- |
| **d2=2** | -- | -- | -- | -- |
| **d2=3** | `$30` 32x128 | -- | -- | -- |

The game runs `(3,0)` -> `$30`, 32 x 128. What U-036 wants is `(1,1)` -> `$11`,
**64 x 64** -- already present, already wired, same 8,192 bytes. `$FFA77E` is
the horizontal size in cells and `$FFA77C` the vertical, both derived as
`index * 32 + 32`, which is why the drawing code multiplies by `$FFA77E`
instead of by a literal.

That reduces the plane half of U-036 to selecting a different quadrant mode on
the map screen, and makes the off-screen-row worry much smaller: 64 x 64 is a
configuration the engine already knows how to produce.

**Tried it: two thirds work.** `make 32x-h40map` selects 64x32 instead of
32x128 and forces H40. The plane change is a **12-byte, size-neutral** edit at
the only two sites that request 32x128 -- `InitScrollModes` and `GameSetup2` --
because the push *order* is what picks the table entry:

```
    pea ($0003).w / clr.l -(a7)   ->  d2=3 d3=0  ->  $30  32x128   6 bytes
    clr.l -(a7)   / pea ($0001).w ->  d2=0 d3=1  ->  $01  64x32    6 bytes
```

Diffing the two game halves confirms exactly 12 bytes changed, in two runs of
six, and the Genesis ROM stays byte-identical. 64x32 is 4,096 bytes per plane
-- it *halves* the VRAM the planes use rather than costing any.

| Build | Result |
|---|---|
| forced H40 only | **Renders correctly.** Clean, unstretched, full-width world map |
| 64x32 plane only | **Depends on the screen.** Quarterly Report is indistinguishable from stock; Regional Rankings is corrupted -- repeated glyphs tiled across the background, garbage in the lower half |
| both together | Same corruption as the plane change alone |

So **H40 is innocent** and the plane geometry is the whole problem. An earlier
revision of this section said the plane change rendered correctly; that came
from looking at one lucky screen, and is wrong. Cropping the corrupt frame
shows the damage is inside columns 0-255, not in the eight columns H40 adds.

**The `cmpi.w #$20` gate is not the cause.** `UpdateScrollDisplay` only applies
scroll offsets when `$FFA77E` is 32, so at 64 it silently does nothing -- an
obvious suspect. Patching the literal to `$40` changed the rendered frame
**not at all**: the before and after frames hash identically. Hypothesis dead,
patch reverted.

What is left is that some tilemap writers use the variable stride `$FFA77E`
and others assume 32. That matches the symptom exactly -- content written at
32 cells per row but read back at 64 lands at half the row and alternating
column halves, which is what the tiled-glyph pattern looks like. A census
finds 28 sites multiplying by 64 bytes and 118 by 32, so this is a search for
the specific writers, not a one-line fix.

**The useful conclusion is about scope, not the bug.** The screens that break
are ranking and status screens; the map-bearing screens survive. This
experiment changed the geometry **globally**, in `InitScrollModes` and
`GameSetup2`, which was never the plan -- U-003 already decided the map screen
alone should go H40. The result confirms that decision is not merely
preferable but **required**: the engine does not handle 64-cell planes
everywhere.

Next step is therefore not to hunt all 28 sites. It is to set the geometry on
entry to the map screen and restore it on exit -- the pattern
`RunWorldMapAnimation` already uses around its own animation -- so only that
screen ever sees 64 cells, and only the writers it uses need to be correct.

**A methodological trap worth recording.** Changing the display mode makes the
demo diverge: at frame 20,000 the H40 build was showing the world map while
stock was on the Quarterly Report. Same input, different screen. This is the
same class as the input-timing sensitivity in U-021, now with a second cause,
and it means **frames from different builds cannot be compared at the same
frame number.** Compare screens, or compare 68000 work RAM.

Still open: what breaks in the H40 + 64x32 combination, the literal
`cmpi.w #$20` in `UpdateScrollDisplay`, and the backdrop going transparent with
the layer on (U-003; item 3 in [HARDWARE_TESTS.md](HARDWARE_TESTS.md)).

Do this before U-030: the data path is shaped by what the renderer is allowed
to assume about geometry.

### U-030 -- Map data path to the SH2 [OPEN]
### U-031 -- Packed-pixel map renderer on the SH2 master [OPEN]
### U-032 -- Great-circle route arcs [OPEN]
### U-033 -- Per-pixel aircraft animation [OPEN]
### U-034 -- Retire the Genesis-side map renderer [OPEN]

### U-035 -- Map scaling (zoom) [OPEN]

The flagship effect, and the reason M8's content density matters: a world map
the player can zoom into, with U-077 revealing the 57 secondary airports as it
goes in. The 32X has **no hardware scaler** -- the "enhanced
scaling and rotation" in `docs/32x-introduction-and-system-features.md:45` is
overview prose, not a register. Scaling is SH2 software rasterization into the
frame buffer, with one large exception in our favour.

**Vertical scale is nearly free.** The frame buffer begins with a 256-word line
table; each word holds the address of that display line's pixel data
(`docs/32x-hardware-manual.md:1204`). Repeating or skipping line-table entries
repeats or drops source lines at no pixel cost, so the Y axis scales by
rewriting 256 words per frame.

**Horizontal scale is not.** Line-table addresses are word units, which in
packed-pixel mode means 2-dot granularity; the `SFT` bit recovers 1-dot
positioning (`docs/32x-hardware-manual.md:1238`) -- but that is *panning*, not
scaling. X scaling has to be a per-pixel SH2 inner loop.

Two constraints to design against, both already in KNOWN_ISSUES: byte writes to
the frame buffer cannot write zero (`docs/32x-hardware-manual.md:1162`), and
`SFT` is ignored when the low byte of the line-table base address is `$FF`
(`docs/32x-technical-info.md:156`).

Unverified: whether a full-screen X scale fits in one frame on one SH2. That is
a measurement to make early, because the answer decides the master/slave split
below.

Gated on U-003 (display mode) and M3.

**Contention with M5.** M4 and M5 both want SH2 time, and this is the real
scheduling question of the whole port. The natural split is master = renderer,
slave = AI and economy (U-043), but it is an assumption until U-035 and U-041
have measured budgets. Neither milestone should assume it owns both CPUs.

---

## M5 -- AI and economy on the SH2

### U-039 -- Comm-port RPC and the break-even measurement [DONE]

The first slice: a real 68000 -> SH2 -> 68000 round trip, wired end to end and
diffed against the 68000's own answer. `make 32x-sh2probe` builds it; it parks
instead of starting the game and leaves its results at `$FFFD00`.

Subject: unsigned 32/32 division. It is the largest piece of genuinely pure
arithmetic in the game -- two longwords in, two out, no work RAM, no ROM
tables -- so it crosses the comm ports without needing any of the state
transport U-040 still has to solve.

**It works.** All 16 test vectors match Aerobiz's own `UnsignedDivide`
(`$03E0C6`) exactly, covering all three of its paths: the `DIVU.W` fast path,
the two-step path taken when the quotient exceeds 16 bits, and the
shift-subtract path taken when the divisor reaches `$10000`. PING returns its
sentinel, the dispatcher's own call counter reads 17 for 17 requests, zero
timeouts, and the round trip is a steady 5 poll iterations.

**The cost, measured rather than derived from timing tables.** Four batches of
20,000 calls each, sampled every 10 frames from outside; the frame at which a
counter saturates is the duration.

| Work per call | 68000 in place | Over the comm ports |
|---|---|---|
| Shift-subtract path (divisor >= `$10000`) | 136.6 calls/frame | **228.2** |
| `DIVU.W` fast path | **443.4 calls/frame** | 228.2 |

The offload rate is *identical* in both rows. The division never costs the SH2
anything measurable; the round trip is the entire price, and it is a flat
ceiling of about 228 calls per frame -- roughly **560 68000 cycles per call**
at ~128,000 cycles/frame.

That single number is what M5 needs: **work smaller than ~560 cycles loses
money over the comm ports; work larger than that wins.** A 32-bit divide sits
right on the line, which is why it wins by 1.67x in its expensive form and
loses by 1.94x in its cheap one. Per-call RPC is therefore not the mechanism
for U-041 and U-042 -- batching is, which is exactly what U-040 is for.

Three things this does *not* establish, and none should be quietly assumed:

- It is PicoDrive, not hardware. The core detects the SH2's comm-port spin
  (`poll_addr=0x20`) and may answer more promptly than a real SH2 would, so
  228 calls/frame is an **upper bound** on the transport.
- It is synchronous: the 68000 spins in a poll loop doing nothing. The real
  M5 win is overlap -- hand off, keep working, collect later -- which this
  measures nothing about.
- It says nothing about SH2 compute speed, because compute never became the
  bottleneck.

Also established, and reusable: the SH2 C toolchain path. The dispatcher is C
(`disasm/sh2/master/rpc.c`), compiled `-m2 -mb` and linked against libgcc for
`__udivsi3`, with `.bss` bounds now exported from `sh2.lds` and cleared by
`master_start` before any C runs. U-041 and U-042 are large enough that they
were always going to be C; this proves the route before they depend on it.

### U-044 -- Offload UnsignedDivide's slow path [DONE, and inert]

The first real math moved into the shipping 32X build, and the first useful
negative result.

`UnsignedDivide` (`$03E0C6`) already branches on exactly the right predicate:
`cmpi.l #$10000,d1 / bcc UDiv_Full32` splits a single `DIVU.W` (~200 cycles)
from a 16-iteration shift-subtract (~900). U-039 measured the comm round trip
at ~560, so the slow half is worth offloading and the fast half is not. The
32X build therefore replaces the first six bytes of `UDiv_Full32` with
`jmp (MARS_SH2_UDIV).l` under `ifne ROM_BASE` -- six bytes for six, the same
size-neutral swap `ConfigVDPDMA` already uses -- and leaves the fast path
entirely on the 68000.

**Correct.** With and without the offload, 12,000 frames of identical input
produce bit-identical 68000 work RAM, VRAM, CRAM, VSRAM *and* register file.
`make verify` still MATCHes; the Genesis ROM never sees the patch.

**And never once used.** The SH2 dispatcher's own call counter reads zero
after 200,000 frames, spanning the attract loop and a full DEMO game. Aerobiz
never divides by anything `>= $10000`. The expensive path exists in the ROM
and does not execute.

So the mechanism is proven end to end in the shipping build and buys nothing.
Both halves of that are worth having written down:

- The **pattern** is now validated and reusable -- fixed thunk address in the
  fixed window (`$880A00`, beside the DMA thunk at `$880900`), size-neutral
  `ifne ROM_BASE` patch in shared code, comm-port RPC with interrupts masked
  for the call, and a bounded wait that falls back to the stock 68000
  algorithm so a stalled SH2 cannot wedge the game.
- The **lesson** is that picking an offload target by reading the code is
  guessing. This one looked like the single best candidate in the whole math
  module -- pure, self-contained, comfortably above break-even -- and its call
  count is zero. Nothing further should be ported before it is profiled.

Kept rather than reverted: it costs nothing on a branch that is never taken,
it is the only validated instance of the mechanism, and M8's larger economies
may yet reach it.

### U-045 -- Profile what the game actually computes [DONE]

**Aerobiz is not CPU-bound on game logic, and M5 as scoped would buy nothing.**

Method: sample the 68000 PC once per emulated frame and attribute it to a
function. The PC is reachable from outside only through the savestate --
`CHUNK_M68K` (id 1) carries it as a **little-endian** longword at offset
`$40` -- so the frontend serialises into a reusable buffer each frame and
reads that field. 426,000 frames cost 70 seconds. The addition is kept as
`tools/profiling-frontend-pc-sampler.patch` against the upstream
`profiling_frontend.c`; nothing in `../32x-playground` was modified.

Symbol attribution comes from the `N bytes | $xxxxxx-$yyyyyy` header line each
module carries -- 752 of them have one.

Result over a complete 20-year DEMO game, 418,549 gameplay frames:

| | frames | share |
|---|---|---|
| Idle in `CmdWaitFrames` | 290,959 | 69.5% |
| Graphics and decompression | 85,473 | 20.4% |
| Everything else | 42,117 | 10.1% |

and the ranking inside that:

| share | routine |
|---|---|
| 11.93% | the LZ decompressor at `$003F70-$004220` |
| 3.50% | `CmdSetupSprite` |
| 2.88% | `FadePalette` |
| 2.36% | `$00268E` -- the Z80 sound driver region |
| 1.34% | `$FFF008` -- the boot-copied VDP register stub |
| 1.16% | `BulkCopyVDP` |

**Not one AI or economy routine appears anywhere in the top 25.** The nearest
candidates are `$01E226/$01E22E/$01E232`, inside the `MulDiv`/`WeightedAverage`
cluster, at about 0.5% between them.

The user-visible stalls are real but they are not what M5 targets: bursts of
non-idle frames recur roughly every 4,000 frames -- the quarter boundary --
and the longest run 74-76 frames, about 1.25 seconds. Their content is
decompression plus VDP traffic. They are **screen loading**, not thinking.

Two limits on this, stated rather than buried:

- The sample is always taken at the same point in the frame, immediately
  after `retro_run` returns. A frame-synced main loop that finishes its work
  and then waits will be caught waiting, so the 69.5% idle figure is
  **biased high** and should be read as "there is a lot of headroom", not as
  a precise duty cycle. The *ranking among working routines* does not depend
  on the sampling phase, and that is what the conclusion rests on.
- PicoDrive timing, not hardware.

The instrument trap worth remembering: PicoDrive's debug read serves RAM but
returns zero for the `$A151xx` I/O range, so a counter parked in a comm
register is indistinguishable from "never called" -- and `$FF0006`, which
`analysis/RAM_MAP.md` calls a per-iteration frame counter, is cleared in
practice and sits at 1 for the whole game. Both cost a false start here.

### U-040 -- RAM snapshot transport over DREQ FIFO [OPEN]

Now has a target to beat: it must move enough state per transfer that the
per-call cost measured in U-039 is amortised well below 560 cycles per unit of
work.

### U-041 -- Port quarterly processing to the SH2 [OPEN]
### U-042 -- Port the AI decision tree to the SH2 [OPEN]
### U-043 -- Split work across master and slave [OPEN]

Each ported routine keeps its 68K implementation selectable at assembly time so
results can be diffed against the original. Correctness first, speed second --
this code decides the outcome of the game.

M5 is also the prerequisite for M8. The content expansion multiplies exactly
the loop counts this milestone offloads, so the AI and economy move to the SH2
before the world grows, not after.

---

## M6 -- PWM audio

### U-050 -- PWM init and a test tone [OPEN]
### U-051 -- PCM streaming from ROM via DMA channel 1 [OPEN]
### U-052 -- Music and SFX asset pipeline [OPEN]

Note manual 5.3: whichever SH2 drives PWM cannot use auto-request DMA.

---

## M7 -- High-colour art and transitions

### U-060 -- Art conversion pipeline [OPEN]
### U-061 -- Title and city art on the 32X layer [OPEN]
### U-062 -- Fades and wipes as 32X palette operations [OPEN]

---

## M8 -- Content expansion

The project goal, stated 2026-09-11: **Aerobiz Ultimate should be the successor
the series never received** -- more scenarios, more events, more aircraft and
more airports. Not an unbounded amount; enough that scaling the map is worth
doing -- "scaling" meaning the zoom effect of U-035, not a bigger world. The
causality runs that way round: the map zoom is the flagship visual, and the
content has to be dense enough that zooming into it shows the player something.

M8 is sequenced **after M5**, deliberately. The turn cycle already spends its
time in 68000 AI and economy code that iterates per-city and per-route arrays;
every axis below multiplies those loop counts. Moving that work to the SH2
first means the content work lands on a machine that can afford it, and it
avoids porting code twice. Nothing in M8 should start until U-041 and U-042
close.

### What the format actually allows

Measured 2026-09-11 against `build/aerobiz.bin` and the assembly sources; every
number below is re-derivable with the command in the last column.

| Axis | Today | Ceiling in the current format | Evidence |
|---|---|---|---|
| Airports (major) | 32 | **hard 32** -- one longword bitmask per region | `RegionBitmaskTable` `$05ECDC` |
| Airports (secondary) | 57 | byte index, `$FF` = empty; no ceiling below 255 | `CharTypeRangeTable` `$05ECBC` second ranges |
| Aircraft (pool) | 53 | none -- ROM table, freely extendable | `AircraftStatsByRegion` `$05EDD0`, 12-byte entries |
| Aircraft (per era) | 16 | 16 as built; 32 reachable without growing the route slot -- see U-078 | route slot `+$02`; fleet table `$FFB9E8`; `SortAircraftByMetric` `$00C540` |
| Scenarios | 4 | selector is bounds-tested 0..3 in two places | `$FF0002`; `BuildAircraftAttrTable` `$00C68A`, `HandleEventCallback` |
| Regions | 7 | 7 -- fixed-size parallel tables | `RegionBitmaskTable` `$05ECDC`, `CharTypeRangeTable` `$05ECBC` |

Each scenario shows a **sliding 16-wide window** into the 53-entry aircraft
pool, with the window starts held in `RegionAircraftIndex` (`$05ECF8`) =
`{0, 12, 26, 37}`. The windows overlap, which is how an aircraft stays
available across eras. Adding an era is therefore cheap -- a new window start
plus new pool entries. Going past 16 *within* an era is not free, but it is
cheaper than it first looks: U-078 shows the route slot can stay 20 bytes, and
the cost lands on the fleet table and the save instead.

### The airport tier already exists

The 89 airports are **not** a flat list. They are two tiers, encoded as index
order, and the split is exactly the one U-077 needs:

| Tier | Indices | Count | Per region (0..6) |
|---|---|---|---|
| Major | 0-31 | 32 | 7, 2, 3, 7, 3, 7, 3 |
| Secondary | 32-88 | 57 | 17, 5, 5, 10, 6, 9, 5 |

Cities 0-31 are London, Paris, Frankfurt, Amsterdam, Rome, Berlin, Moscow,
Cairo, Tunis, Tehran, Baghdad, New Delhi, Tokyo, Beijing, Seoul, Hong Kong,
Singapore, Bangkok, Manila, Sydney, Perth, Auckland, Washington, New York,
Chicago, Los Angeles, Dallas, Atlanta, Vancouver, Mexico City, Sao Paulo,
Havana -- the hub-tier cities. 32-88 are the secondaries, Manchester through
Santiago.

`CharTypeRangeTable` (`$05ECBC`) holds both ranges per region as
`[base1, size1, base2, size2]`. `RegionBitmaskTable` (`$05ECDC`) holds one
longword per region whose set bits are exactly that region's major-city
indices; the seven masks partition bits 0-31 with **none spare**. Both tables
have 10+ callers each, so this is core, not incidental.

Two consequences, and they pull in opposite directions:

- **Adding secondary airports is cheaper than a flat reading suggests.** Index
  32 and above lives outside the region bitmask entirely, so the cost is the
  `#$59` sweep, work RAM and the save -- not a format change.
- **A 33rd major airport is hard-blocked.** The longword is full. Promoting a
  city to hub tier means widening `RegionBitmaskTable` to a quad or a bit
  array, and touching every one of its callers. Prefer adding secondaries.

### Space available

| Region | Size | Used | Free |
|---|---|---|---|
| Cart `$000000-$07FFFF` -> `$880000` fixed window | 512 KB | to `$01036F` | ~507 KB, always addressable |
| Cart `$080000-$0FFFFF` (bank 0 upper) | 512 KB | nothing | 512 KB, needs a bank switch |
| Cart `$100000-$1FFFFF` -> `$900000` game bank | 1 MB | 646,825 non-fill bytes | ~400 KB in-bank |

Content is not constrained by ROM. The cartridge can also grow past 2 MB --
`$A15104` selects a 1 MB bank and only bank 1 is spoken for.

The two budgets that *are* tight:

- **68000 work RAM, 64 KB.** Per-city arrays are fixed-stride and packed
  against their neighbours (`city_data` at `$FFBA80` is 89 x 4 x 2 = 712 bytes;
  the char-stat descriptor table at `$FF1298` is 89 x 4 = 356). Growing the
  city count moves every array above it.
- **Cartridge SRAM, 8 KB odd-addressed** (`$200001-$203FFF`). The save block is
  read as `$2000` stride-2 bytes from `$200003 + slot * $2000`
  (`LoadAllGameData` `$00CA3E`). More cities and more routes both grow the
  save; the slot layout has to be re-planned before, not after.

### The real cost of more airports

89 is not a constant anywhere. It is the literal `#$59`, compared inline at
**41 sites across 31 files**, and 39 files reference the `city_data` base
`$FFBA80` directly. Any change to the city count is a mechanical sweep of all
of them plus a work-RAM relayout -- the same shape of job as U-010/U-013, and
the same blind spot applies: `make verify` cannot see a wrong one, because
these sites are identical in both builds.

Prerequisite: introduce a `CITY_COUNT` equate and convert all 41 sites to it
under `make verify`, *before* changing its value. That is U-070.

### Items

### U-070 -- Replace the 41 hard-coded `#$59` city-count literals with an equate [OPEN]

Pure refactor, value unchanged, `make verify` must still MATCH. This is the
gate for every other airport item and is worth doing on its own -- it converts
an unmeasurable sweep into a one-line change.

### U-071 -- Relocatable work-RAM layout for per-city arrays [OPEN]

Replace the fixed bases (`$FFBA80`, `$FF1298`, `$FF05C4`, ...) with equates
derived from `CITY_COUNT`. Needed before the count can move. Depends on U-070.

### U-072 -- Re-plan the SRAM save layout for a larger world [OPEN]

Establish what a save costs per city and per route slot, and whether the
existing slot count survives. Versioned save header so old saves are detected
rather than misread. Depends on U-071.

### U-073 -- Extend the aircraft pool [OPEN]

Append entries to `AircraftStatsByRegion`, `AircraftModelPtrs` and the
`AircraftModels` string pool. No format change while each scenario still shows
16. Independent of U-070..U-072 -- the cheapest visible win in M8, and the
prerequisite for U-078.

### U-078 -- Double the aircraft available per era, 16 -> 32 [OPEN]

Target: up to 32 aircraft per era, **not** necessarily 32 in every era. The
early scenarios should stay sparse -- 1955 did not have thirty airliners worth
choosing between, and a half-empty list is the honest depiction.

That last point changes the mechanism as much as the number does. Today an era
is a fixed 16-wide sliding window into the pool, with the starts in
`RegionAircraftIndex` (`$05ECF8`) = `{0, 12, 26, 37}`. Variable fill means the
window needs a length as well as a start: a parallel 4-byte count table beside
`$05ECF8`, and the loops bounded by it instead of by a literal 16.

**Where the 16 actually lives.** Not in one place, and not where the aircraft
tables are:

| Site | Now | At 32 |
|---|---|---|
| `plane_type`, route slot `+$02` | two 4-bit nibbles | two 5-bit fields |
| Fleet table `$FFB9E8` | 4 players x 16 x 2 = 128 B | 256 B, stride `$20` -> `$40` |
| Fleet table save | 64 B at `$FF02A8` | 128 B |
| `SortAircraftByMetric` buffers | `$C0` = 16x12, `$20` flags | 384 B, 64 B |
| Aircraft pool | 53 entries | ~70-90 |

`$FFB9E8` is the per-player fleet, confirmed by `SumStatBytes` (`$010492`):
`lsl.w #$5` for the player stride, `d2*2` for the slot, `cmpi.w #$10` for the
bound. 37 files reference the base; the stride shift `#$5 -> #$6` has to be
found at every one of them.

**The route slot does not have to grow.** `plane_type` needs 10 bits for two
5-bit classes and only has 8 -- but `frequency` at `+$03` is capped at 14
(`cmpi.b #$e` in `RunAIMainLoop.asm:260` and `EvaluateNegotiation.asm:44`), so
its high nibble is spare. Packing the two classes across the `+$02`/`+$03` pair
gives 12 bits where 10 are needed, and **the route slot stays 20 bytes with its
saved 12-byte prefix unchanged.** That removes the single largest save-format
risk in M8.

*Verify before relying on it:* two range checks cap `frequency` at 14, but
nothing yet proves no site writes the high nibble of `+$03`. This is a ground
rule 8 class risk -- the sites are identical in both builds, so `make verify`
is blind to getting it wrong. Audit every write to `+$03` first.

The save still grows, because the fleet table doubles. That is one block rather
than a per-route change, so it belongs to U-072's versioned save header.

**Relocation is not the obstacle.** Both tables are boxed in -- `$FFB9E8` has 24
bytes of slack before `city_data` at `$FFBA80`, and `SortAircraftByMetric`'s
destination `$FFA6B8` has 2 bytes before `$FFA77A` -- so both must move. Given
how completely the cartridge is mapped, moving them is bookkeeping, not risk;
this is the same relayout U-071 already has to do, and the two should be done
together rather than twice.

Depends on U-071 (relayout), U-072 (save format) and U-073 (pool). Not on
U-070, which is airports.

### U-074 -- Additional scenarios / eras [OPEN]

A new era needs a window start in `RegionAircraftIndex`, a per-scenario data
block (the `$0164`-byte blocks at `$05F26A`+ are per-scenario variants), and
the 0..3 bounds tests widened. Depends on U-073.

### U-075 -- Additional events [OPEN]

Scope not yet measured: the event tables (`EventNamePtrs` `$047D7C`,
`UnpackEventRecord`, `HandleEventCallback`) need the same inventory treatment
the aircraft tables just received before this item can be estimated.

### U-076 -- More airports [OPEN]

The headline item, and last on purpose. Depends on U-070, U-071, U-072, and on
M4: at H32 on a Genesis tilemap there is nowhere to put more pins legibly, and
the answer to that is U-035's zoom plus U-077's tiering rather than a smaller
pin. More airports and the map zoom justify each other, so neither is worth
shipping alone.

Add secondary airports (index >= 32), not major ones -- see the tier section
above. The major tier is full at 32 and widening it is a much larger job than
the airports themselves are worth.

### U-077 -- Draw secondary airports only when zoomed in [OPEN]

Level of detail on the map: zoomed out shows the 32 major airports, zooming in
reveals the 57 secondaries. This is what keeps the map readable as U-076 grows
the world, and it is the other half of why U-035's zoom is worth building.

The pleasant surprise is that **no new data is needed**. The tier is already
the index: `city_index < 32` is the major tier, and the existing
`RegionBitmaskTable` already enumerates exactly those per region. The LOD test
is a comparison, not a lookup, and it costs nothing in ROM, work RAM or the
save.

Design note: the threshold should be a renderer-side constant, not a second
copy of the number 32. If U-070 introduces `CITY_COUNT`, this wants
`CITY_MAJOR_COUNT` alongside it, and the two must stay consistent with the
bitmask width.

Open question, to answer with U-035: whether the zoom is continuous or a small
number of discrete steps. Discrete steps make LOD a clean switch; continuous
zoom needs a fade or a pop threshold, and pins popping in mid-zoom looks worse
than it sounds. Decide this before the renderer is written, not after.

### Corrections found while measuring this

- `analysis/GAME_PHASE_FLOW.md` describes `LoadAllGameData` as streaming
  scenario data from ROM and LZ-decompressing it. It does neither: it reads the
  **save state from cartridge SRAM**. The module's own header comment is right.
- `analysis/DATA_TABLES.md` describes `RegionAircraftIndex` as region-indexed
  and `AircraftStatsByRegion` as "16 entries per category". The index is the
  **scenario** (`$FF0002`), and the table is 53 entries with overlapping
  16-wide windows.
- `analysis/DATA_TABLES.md` calls `RegionNamePtrs` "14 entries, one per game
  region". There are **7** regions; the 14 pointers are 7 long plus 7 short
  name forms, the same doubling as `CityNamePtrs` (2 x 89 = 178).

These are analysis-doc errors, not code errors, and are left recorded here
rather than silently patched.

---

## Infrastructure

### U-090 -- Build or install an SH2 C toolchain [OPEN]

Only `sh-elf-as`, `sh-elf-ld`, `sh-elf-objcopy` and `sh-elf-nm` are present;
there is no `sh-elf-gcc`. The SH2 renderer and the AI port are both large enough
that assembly-only would be a poor trade. marsdev or crosstool-ng `sh-elf`.

Not urgent -- M1 and M2 need no SH2 C -- but it blocks M4 and M5.

### U-091 -- Emulator harness for automated boot tests [DONE]

`../32x-playground/tools/libretro-profiling` had everything needed except a
usable binary: the checked-in `profiling_frontend` is older than its own source
and has no video capture, so it accepted `VRD_VIDEO_DUMP_DIR` and silently
wrote nothing. Rebuilding from the same source
(`cc -O2 -o frontend profiling_frontend.c -ldl`) gives working RGB565 frame
dumps. Nothing in that repository was modified; the build goes to a scratch
directory.

One patch is worth upstreaming there: the capture path hard-codes 320x224 and
rejects anything else, which silently drops every Genesis-mode frame. Relaxing
it to accept the reported geometry is what produced the H32 answer in U-003.

U-001 is manual. A headless run that asserts on comm-port state would make every
subsequent milestone cheaper to verify.
