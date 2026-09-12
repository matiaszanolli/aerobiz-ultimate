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

## State of play, 2026-09-12

**Done and shipping.** The game runs on the 32X, the Genesis ROM is still
byte-identical, and the SH2 runs C that is part of the shipping cartridge. The
world map is on the 32X layer, built from the ROM rather than a savestate, and
**it scales** -- U-035, the flagship effect, is measured and working.

**What the measurements changed.** Six findings redirected the plan, and every
one contradicted something this roadmap previously asserted:

| Finding | What it overturned |
|---|---|
| U-045: the 68000 is idle **69.5%** of gameplay; no AI or economy routine in the top 25; the LZ decompressor alone is **11.93%** | M5's premise. It was "AI and economy on the SH2, for responsiveness"; there is no queue to shorten. Rescoped to the hot path, and M8 no longer waits on it |
| U-003: H32 puts the Genesis and 32X layers at **1.25x different scales**, for a hardware reason (EDCLK is always the H40 clock) | §4.1 as written. The map screen must run H40, and only that screen |
| U-039/U-044: a comm-port round trip costs **~560 68000 cycles** flat, and the one offload that looked ideal is **never called** | The idea that per-call offload is the mechanism. Batching is |
| U-035: the zoom costs (source rows) x 320 dots, so vertical scale is free and the budget is **2.13 / 1.06 / 0.53** frames per blit at 1x / 2x / 4x | The worry that scaling might not fit at all. It fits from 2x in, on the master alone |
| U-046: decompression output goes to a **work-RAM scratch buffer**, not VRAM, and the 68000 costs **285 cycles per output byte** | Both of that item's stated premises. Transport is 2-3% of decompression, so the offload wins by a wide margin |
| U-093: the emulator modelled no SH2 cache and no memory latency at all | The idea that any SH2 timing here was a measurement. They were instruction counts |

**Critical path.** M4, and nothing on it is blocked any more. U-036's bug has
survived five hypotheses, but U-092 now matches frames by screen so the
plane-by-plane diff that should find it can actually be taken. Then the content
questions -- U-032, U-033, U-077.

**The result that reframes M8.** At 4x each map pixel is a 4x4 block: zooming
in reveals that there is nothing to reveal. The payoff has to come from
U-077's tiering -- airports and routes appearing as the map goes in -- and not
from more map pixels. That is the clearest evidence yet for the content
milestone, arrived at from the rendering side.

**The tooling is now part of the project.** U-093 turned PicoDrive into an
instrument: an SH2 cache and wait-state model validated to the cycle against
the manuals, the `RV` bit actually switching cartridge windows, and per-frame
screen fingerprints. All of it opt-in, because the permissive behaviours are
what every existing measurement depends on. It paid for itself immediately --
the SH2 slave had never enabled its cache, and every fetch of its idle spin was
an 8-word SDRAM burst.

**Honest state of the evidence.** Everything is PicoDrive; nothing has run on
real hardware -- see [HARDWARE_TESTS.md](HARDWARE_TESTS.md) for the seven
questions only a console can answer. What that caveat means has changed, so it
is worth restating precisely:

- **SH2 timings are now modelled and validated against the manuals** --
  `VRD_SH2_TIMING=1` on the interpreter core, exact to the cycle over a million
  accesses of each kind. That makes them *defensible*, not *confirmed*: they
  are what the documentation says the hardware does.
- **Three things remain genuinely unmodelled**, and are deliberately not
  guessed: whether `$880000-$9FFFFF` really goes away while `RV = 1`, whether
  a longword access to a 16-bit port is one bus cycle or two, and contention
  between the two SH2s and the 68000 on the cartridge bus. The last is why
  U-046's batching case rests on FM handover and the frame-buffer FIFO
  instead.
- **Divergence is handled rather than feared.** Any timing change still sends
  the demo down a different path, but U-092 matches frames by what is on
  screen, so two builds can be compared at the right frames instead of the
  same frame number.

---

## M1 -- Adapter bring-up

### U-001 -- Verify the milestone-1 cartridge actually boots [DONE]

All five acceptance criteria pass under the instrumented PicoDrive core: the
boot ROM accepts the security block, both SH2s hand-shake and leave the release
spin, MdMain runs, and bank 1 is selected.

It did not boot at first, and the three defects were all misreadings of the
manual rather than coding errors -- a truncated security block, MdMain placed
inside it, and the boot handshake on the wrong comm slot. HISTORY.md
(2026-09-08, M1 half reached) has each one; **PORT_ARCHITECTURE.md §5.1** has
the corrected conclusion, which is not the way the question was framed.

### U-004 -- Drop the retail donor requirement [DONE]

`tools/extract_mars_init.py` now reads the block from either a `.32x` image or
an assembly source carrying it as `dc.w` data. marsdev's
`examples/32x-skeleton/md_src/md_start.s` yields byte-identical output to
retail Virtua Racing Deluxe, and a full `make 32x-m1` built that way passes
U-001 unchanged. The block is still not committed here.

### U-002 -- Draw something on the 32X layer [DONE]

`make 32x-fbtest`: the 68000 sets packed-pixel mode, hands the VDP over with
`FM = 1`, and the SH2 paints the line table, palette and 224 lines from C
(`disasm/sh2/master/fb.c`). Five consecutive captured frames hash identically.

The test pattern is a two-axis gradient chosen so a wrong line table or stride
shows as shear rather than as something that merely looks odd, plus an
accidental ruler: the X ramp wraps at x = 256, which confirms the VDP really is
displaying a 320-pixel line.

**The frame-buffer facts this pinned down are now in PORT_ARCHITECTURE.md
§4.1**, where the rest of M4 can find them, rather than buried in a closed
roadmap item.

### U-003 -- Confirm Aerobiz's Genesis display mode [DONE, and resolved]

**Aerobiz runs H32** -- measured from the emulator's frame geometry, not read
out of a register table: H40 for the first 320 frames of TMSS and boot screens,
then 256x224 for the KOEI intro, the title and everything after. Manual 3.3
requires a 320-wide Genesis mode whenever the 32X layer is not blanked, so §4.1
as originally written could not work.

**Why it cannot be papered over.** In H32 the two layers sit at **1.25x
different scales** -- measured 95.6% pixel match for a nearest-neighbour
256->320 stretch, against 85.0% centred and 83.4% left-aligned. This is
hardware, not emulation: the cartridge slot carries EDCLK, always the H40
clock, which the 32X uses as its video clock, so H32 and H40 fill the same
on-screen width with different pixel counts (`pico/32x/draw.c:11-19`). In H40
the layers are **100.00% identical**. Full working in HISTORY.md (2026-09-12).

**Decision: convert the map screen alone to H40.** It is the screen whose
Genesis content M4 is replacing anyway, so it has the least to re-lay-out from
32 cells to 40, and it confines both the H40 switch and the backdrop change to
one place. Everything else stays H32 with the layer blanked. U-036 implements
it.

Two things stay open, both narrower than the original doubt and both on the
hardware list:

- **The backdrop.** With the layer on, the Genesis backdrop reads as
  transparent and every screen loses its background colour. `draw.c` flags the
  `/YS` signal -- which is what signals display of the background colour -- as
  "unclear" in H32, with possible "race conditions by the different video
  clocks". So this observation is the one to distrust, not the geometry.
- **The 4-pixel offset.** `draw.c` applies `H32_OFFSET 4` between the layers in
  H32. Scanning offsets against captured frames, the best match is at 0, so it
  is already inside the composite -- worth re-checking only if H32 compositing
  is ever relied on.

Neither affects the decision: the map screen goes H40, where neither applies.

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

The map is on the layer and scaling (U-030, U-031, U-035). What remains is the
screen it lives on (U-036), the things drawn over it (U-032, U-033), and
retiring the Genesis renderer it replaces (U-034).

### U-036 -- Switch the map screen to H40 [NO BUG; scoped and ready]

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

**Five hypotheses tested and eliminated.** `make 32x-h40map` reproduces the
corruption; the cause is still unfound, but the search space is much smaller.

| Ruled out | How |
|---|---|
| H40 itself | H40 alone renders correctly; corruption appears with the plane change in H32 |
| the `cmpi.w #$20` gate in `UpdateScrollDisplay` | patched the literal to `$40` so the routine runs again -- rendered frame **hashes identically**, before and after |
| vertical plane size | 64x32 and 64x64 produce **byte-identical frames**; only HSZ matters |
| horizontal scroll wrapping at 512 instead of 256 | hscroll is `(2,2)` in both stock and 64-cell builds, and reg 11 is `$00`, a single whole-screen value |
| the central address path | `ComputeMapCoordOffset` (`$000816`) and `CmdDMABatchWrite` (`$000876`) both read the register-16 shadow at `$10(a5)`, mask HSZ and scale the row stride by 1x/2x/4x -- they even trap on the prohibited HSZ=2 |

So the corruption tracks **HSZ = 64 alone**, while the engine's own central
write path handles HSZ correctly. Something outside that path is writing the
tilemap wrongly.

*Which plane is at fault is currently unestablished.* The attribution in an
earlier revision came from nametable tile counts read in the wrong byte order
(U-030 found PicoDrive stores VRAM and CRAM byte-swapped in savestates), so
those figures were meaningless. Redo it with `tools/extract_map.py`, which
renders a plane correctly and makes the answer visible rather than
statistical.

**Found, with U-092.** The cell-by-cell diff this was waiting for, taken at a
matched screen, and the answer is not corruption at all.

First, a confound that had to go. Comparing the stock build against the
64-cell build is worthless: at every matched screen the only differing VDP
register is **reg 12** (`$00` vs `$81`), i.e. H32 against H40, and that alone
makes 40-50% of pixels differ. Every earlier "the plane change breaks this
screen" reading was partly measuring the display mode. The controlled pair is
`32x-h40` against `32x-h40map` -- both H40, differing only in plane geometry.
Those two run **frame-locked, zero drift**, which makes the comparison direct.

With that control: frames 2250-2400 and 4230-4360 are **pixel-identical**, and
frames 400-660 differ in **every** frame. So the damage is confined, not
general. The screen is the KOEI logo, and the logo itself renders perfectly --
what appears is a block of stale colour in the right ~64 pixels.

The nametable says why, at plane A of the same frame:

| | cols 0-31 | cols 32-63 |
|---|---|---|
| `32x-h40` (32x128) | content, 112 cells written | *do not exist* |
| `32x-h40map` (64x64) | **byte-identical content** | **all `$0000`** |

**The engine writes the visible columns correctly. Nothing ever initialises
the new ones.** A cell of `$0000` is tile 0 at palette line 0, and tile 0
holds real graphics -- the tile area is 1,534 of 1,536 full -- so the block on
the right is a real tile shown through the wrong palette. The 32-cell plane
wrapped columns 0-63 into that space, which looked correct by accident; the
64-cell plane shows uninitialised nametable instead.

That also explains the "repeated glyphs tiled across the background" seen on
Regional Rankings: same cause, different stale contents.

**So the fix is initialisation, not arithmetic**, and the five eliminated
hypotheses were all eliminated correctly -- the engine's address path really
does handle HSZ properly. What is missing is a clear of the widened plane.
That is a much smaller job on the map screen alone, which is what U-003 already
decided, than it would have been globally.

**There is no engine bug. Both artifacts were the experiment's own setup.**

The routine is `ClearScreen` (`$0053BA`), which fills both planes through
GameCommand `$1A` with two hard-coded `pea ($0020).w` -- the fill width and
height in cells, literal 32. That is the "anything else assuming 32 cells" the
audit predicted, and it is why columns 32-63 are never written.

But widening its fill to 64 changed the rendering **not at all**, because
`$0000` and `$8000` are both **tile 0** -- and tile 0 is entirely blank, all 64
pixels transparent. So those columns were never showing garbage. They were
showing *through*.

What was behind them is the answer to the whole mystery. `32x-h40map` links
`32x_boot_h40.bin`, built with `-DH40PROBE=1`, which deliberately turns the 32X
layer on and paints **U-002's test gradient** into the frame buffer. The
32-cell plane wrapped an opaque backdrop tile over columns 256-319 and hid it;
the 64-cell plane leaves them transparent, so the gradient appears. The
coloured block is the test pattern, seen through the game.

Blanking the layer in both builds and repeating the comparison:

| | frames 400-660 |
|---|---|
| layer on (as before) | **0 of 261** identical |
| layer blanked | **170 of 261** identical |

and every remaining difference is confined to **columns 256-319 only**, where
the 64-cell build shows the VDP backdrop colour (black) and the 32-cell build
shows the wrapped backdrop tile (dark blue). A 64-pixel strip of the wrong
colour, not corruption.

Frames 2250-2400 and 4230-4360 were already pixel-identical with the layer on.
So on every screen sampled, **the engine renders 64-cell planes correctly.**
The "repeated glyphs tiled across the background, garbage in the lower half"
on Regional Rankings fits the same explanation -- a screen whose planes are
largely transparent, showing the gradient through.

**The five eliminated hypotheses were all correct, and so was the sixth.** The
engine was never at fault; the harness was. The lesson is the one U-092 was
built for and this item still managed to trip over: a build that paints a test
pattern into a layer is not a control for a change that alters what covers
that layer.

What this leaves for the real U-036, which is much less than it was:

- The extra 64 pixels need *something* -- but on the map screen the answer may
  be nothing at all. That is the screen where the 32X layer is meant to show
  through, so transparent Genesis columns are the desired state, not a defect.
  Decide it with U-034 when the map screen's framing is settled.
- Apply the geometry change to the map screen alone, rather than globally in
  `InitScrollModes` and `GameSetup2`, and re-run the controlled comparison
  **with the layer blanked**.
- Note the patch selects `$11` (64x64), not the `$01` (64x32) recorded above;
  harmless, since only HSZ matters, but the note was wrong.

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

**No longer blocks U-030.** It was placed before the map data path on the
reasoning that the renderer's geometry assumptions depend on it. Two findings
since say otherwise:

- **Plane B is the world map; plane A is the UI.** Established by rendering
  each plane out of a savestate with `tools/extract_map.py`: plane B is the
  world map plus the coloured panel frames, plane A is the report text and bar
  graphs. U-030 and U-031 replace *plane B*.
  *(An earlier revision cited tile-distribution counts here. Those were
  computed with the wrong byte order -- see U-030 -- and meant nothing. The
  conclusion survives because the rendered planes show it directly.)*
- Once the map is on the 32X layer, plane B goes blank on the Genesis side and
  its geometry stops mattering at all.

So U-030 and U-031 can proceed now. U-036 is still needed before the layer
goes live during play -- the plane A UI must fill 40 columns in H40 -- but it
gates the *switch-on*, not the renderer.

### U-030 -- Map data path to the SH2 [DONE]

`tools/extract_map.py` renders a Genesis plane out of a savestate and emits it
as raw 8bpp indices. It served its purpose -- proving the path and sizing the
asset -- and is superseded as a *source* by U-031's ROM extraction. Kept
because it is still the only way to see what the Genesis actually put on a
plane.

Findings, including the PicoDrive byte-swap trap, are in HISTORY.md
(2026-09-12, map on the layer).

### U-031 -- Packed-pixel map renderer on the SH2 master [DONE, one gap]

`make 32x-maptest` puts the world map on the 32X layer, read from cartridge
ROM by the SH2. The asset is built from `build/aerobiz.bin` by
`tools/make_map_asset.py` -- tiles decompress from **`$088CF8`** and the
nametable is implicit -- so a clean checkout reproduces it with no savestate.
`tools/lz_decompress.py` is a literal transcription of the game's decompressor
and is the specification for U-046.

Layout, at cartridge `$020000` (`$FF` padding in every other build, so it costs
nothing):

```
+$0000  256 words   palette, already BGR555
+$0200  224 x 320   packed pixels, one byte each
```

Rows are padded to the full 320 because manual 3.3 warns the VDP "mechanically
displays 320 pixels worth of data from the address specified per the line
table" -- a short row shows whatever follows it in DRAM. The map occupies the
left 256; the remaining 64 are index 0.

Full findings in HISTORY.md (2026-09-12, map on the layer).

**The one gap.** The 16-word map palette is a pinned constant, not derived: it
is not in the ROM raw in either byte order, nor inside any of the 1,289
compressed blocks reachable from the sources, so something builds it at
runtime that has not been traced. Worth closing if the map screen is ever
recoloured, and worth ignoring otherwise.

**Still to decide.** The map is 256 wide against the layer's 320. Filling the
extra 64 needs either map data that does not exist yet or a deliberate framing
decision -- see U-035, where the zoom makes the question concrete.

### U-037 -- Affine transform (rotate and scale) [DONE, in 32x-affine]

Prompted by the observation that many 32X games open with a transformed SEGA
logo, and worth having as a capability check in its own right: U-035's scaler
is axis-aligned, so nothing had ever exercised rotation.

**Rotation forfeits the line-table trick, and that is not a detail.** U-035 is
cheap because display lines share line-table slots, so the vertical axis costs
nothing. Once the source Y varies *along* a scanline, no two display lines hold
the same pixels; every one needs its own row. An affine frame is therefore
always the worst case, and worse than U-035's worst case because the inner loop
carries two bounds tests and a row multiply per pixel:

| | full screen |
|---|---|
| U-035, 1:1 axis-aligned | 2.13 frames |
| U-037, affine | **5.75 frames** |

That is ~10 fps full-screen, so affine is a *region* effect, not a screen
effect. A 128x128 area is 23% of the frame and lands near one frame; a masked
power-of-two source would cut the inner loop further by removing the bounds
tests and the multiply.

**Correct by construction, not by eye.** With the identity matrix the affine
path must reproduce the 1:1 blit exactly, and it does -- checksum `$8040EA91`
from both, and the 1:1 blit is itself already known identical to U-031's
straight copy. The rotation demo then runs from a 256-step Q15 sine table.

Open: the SEGA logo the idea came from is on screen as 48 tiles at plane A
rows 12-15, cols 14-25 (96x32 pixels), but its tiles are neither raw nor
contiguous in ROM, so it needs the same brute-force decompression hunt U-031
used for the map. Until then the demo transforms the world map, which proves
the path equally well and needs no new asset.

### U-032 -- Great-circle route arcs [DONE, in 32x-zoomtest]

A route is a great circle, and on this map that is a curve. The Genesis
renderer draws straight tile-granular lines; the SH2 draws the real thing,
per pixel, scaling with the zoom like U-077's markers.

**The projection had to be measured first.** A least-squares fit over 34
cities whose real positions are known independently:

| | | |
|---|---|---|
| `x = 0.5972 * lon + 35.13` | mean 3.5 px | max 7.7 |
| `y = -0.7854 * lat + 92.25` | mean 4.4 px | max 11.2 |

So it is equirectangular -- Mercator fits no better, 4.1 px against 4.4 -- at
about 215 px to a full turn, with a mid-Atlantic seam. The residual is
hand-drawn art, not projection error.

**Which is why arcs are anchored.** The projection alone would miss the city
markers by up to 8 px, so the curve is shifted to touch both endpoints exactly
and the discrepancy spread along it. Measured: **31 of 31 arcs terminate
within 3 px** of their destination.

**A cheap substitute was measured and rejected.** A quadratic Bezier through
the endpoints and the true spherical midpoint costs no inverse trig at all,
and its median deviation is only 1.8 px -- but the 90th percentile is 15.9 and
the worst case 87 (Baghdad to Los Angeles). Long routes need real spherical
interpolation, so the arc is a slerp with a table-driven `asin` and `atan2`.
Every city is inside 37 degrees of latitude, so `asin`'s ill-conditioned end
is never reached.

Two bugs worth recording, both silent:

- **Longitude unwrapping needs a seed.** `atan2` returns -180..180 and the
  seam is mid-Atlantic, so the *first* sample has nothing to unwrap against
  and could land a turn away, dragging the arc across the world. Seeded from
  the start city's own map position.
- **A Q15 reciprocal overflows.** `1/sin(omega)` reaches ~16.7M for short
  routes and `sin * recip` exceeds the SH2's 32-bit long. It showed as wild
  lines out of the London cluster -- which is exactly where the shortest arcs
  are, and the clue that identified it. Written as a shift then a divide.

Open: the demo fans from London to all 31 other majors. Wiring it to the
player's actual routes is U-034's business, along with what happens to the
Genesis renderer it replaces.
### U-033 -- Per-pixel aircraft animation [OPEN]

### U-038 -- Aircraft scale with the map as they fly [OPEN]

Aircraft in flight should grow and shrink with the zoom rather than staying a
fixed size, so a plane reads as a thing at a place rather than a cursor over a
picture.

**U-077 found this is closer to free than it looks, and in fact hard to avoid.**
Overlays drawn into the frame buffer inherit the zoom automatically, because
display lines share line-table slots: anything written into a slot is repeated
by every line pointing at it. The airport markers already scale this way, and
it was not a feature that had to be built -- it was the behaviour that could
not be prevented without unsharing the slots and paying full price for the
vertical axis.

So the work is not "make them scale" but "make them scale *well*": a single
source sprite magnified 4x is a 4x4-blocky plane. Either accept that, matching
the map's own pixels, or carry two or three sprite sizes and switch on the
same threshold U-077 uses for the airport tiers. Decide it with U-033, since
both want the same sprite pipeline.
### U-034 -- Retire the Genesis-side map renderer [OPEN]

### U-035 -- Map scaling (zoom) [DONE, emulator; hardware pending]

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

`make 32x-zoomtest` builds it: the SH2 rasterizes the U-031 asset at a scale
factor and animates 1x -> 4x -> 1x until reset. Both predictions above held,
and the free axis is worth more than expected.

**The line-table trick works exactly as the manual implies.** A source row is
rasterized *once*, into the next free frame-buffer slot, and every display line
that lands on it just points another line-table entry at that slot. So the cost
of a frame is (distinct source rows) x 320 dots, and vertical magnification is
genuinely free. `sh2_zoom_rows` confirms it: 224, 112 and 56 rows rasterized at
1x, 2x and 4x.

**The measurement, 32 blits per level, V-Blanks as the clock:**

| Zoom | Source rows | Frames per blit | Effective rate |
|---|---|---|---|
| 1x | 224 | 2.13 | 28 fps |
| 2x | 112 | 1.06 | 56 fps |
| 4x | 56 | 0.53 | 60 fps (capped) |

Exactly linear in rows. So the answer to the open question is **no, a
full-screen 1:1 scale does not fit in one frame on one SH2** -- but that is the
one factor where scaling is the identity and the map can simply be copied, or
left alone. From 2x in, the effect is inside budget on the master alone, which
leaves U-043's slave assumption intact.

**Correctness.** At scale 1.0 the rasterizer's output is **100.00%
pixel-identical** to U-031's straight blit, compared frame against frame. The
zoom extremes are bounded by minimum run length -- source detail can lengthen a
run but never shorten it below the magnification factor -- which reads 1 at the
1:1 frame and exactly 4 at the deepest, so the clamps place the window where
they claim to.

**The clamp is the reason there are no per-pixel bounds tests.** The window is
placed so it always lies inside the source, which costs nothing because a step
of 1.0 makes the window exactly the source: it only forbids zooming *out* past
the whole map, which has nothing to show. Source is the full 320x224 asset
rather than the 256x176 world inside it, precisely so that 1.0 is the identity
and can be diffed against U-031.

**These are emulator numbers.** PicoDrive has no SH2 cache model -- `CCR` at
`$FFFFFE92` appears only in a comment in `pico/32x/sh2soc.c:16` -- and no SDRAM
latency model, so the figures are close to raw instruction counts. Real
hardware reads SDRAM 8-word-burst-fixed at 12 clocks per burst
(`docs/32x-hardware-manual.md:897`), which a cache-through fetch pays in full
for a single word. Enabling the cache ourselves changed the measurement by
literally zero, which is evidence about PicoDrive and not about the 32X. See
HARDWARE_TESTS.md item 6.

**Cache-on is now explicit anyway.** `docs/32x-hardware-manual.md:1359` has the
boot ROM ending with "Cache Clear / Cache ON", but nothing observable confirms
it ran and the downside of it not having run is severe, so `master_start` now
purges and enables `CCR` itself (`sh7604-hardware-manual.md` 8.2). It is
idempotent.

**A bug found on the way.** The SH2 interrupt handlers clobbered `r1` without
saving it. `RTE` restores only PC and SR, and `r1` is a scratch register gcc
uses freely, so with V interrupts enabled that was a rare timing-dependent
corruption of whatever C code was running -- invisible until something started
depending on the V handler. All five handlers now save what they touch.

Still open on this item:

- Panning. The centre is a compile-time constant; nothing drives it yet.
- The zoom is continuous here (`ZOOM_STEP` per frame). Whether the game should
  use continuous or a few discrete stops is still the U-077 question below.
- **The 256-vs-320 framing, now concrete.** At scale 1.0 the map leaves a
  64-pixel black pad on the right; zooming in past ~1.25x makes it disappear.
  So the options are visible rather than theoretical: frame the map at the
  scale where it fills the width, extend the source, or accept the pad as
  letterboxing. A decision for U-034, when the Genesis renderer retires and the
  map screen's layout is settled.
- **Zooming in reveals that there is nothing to reveal.** At 4x each source
  pixel is a 4x4 block; the map has no more detail to give. This is the
  clearest argument yet that the payoff comes from U-077's tiering -- airports
  and routes appearing as you go in -- rather than from more map pixels.

Was gated on U-003 (display mode) and M3; both are resolved.

**Contention with M5.** M4 and M5 both want SH2 time, and this is the real
scheduling question of the whole port. The natural split is master = renderer,
slave = AI and economy (U-043). U-035 has now measured its half: at 2x and in,
the renderer fits on the master with room to spare, so the split survives its
first test. U-041 still has to measure the other half.

---

## M5 -- SH2 offload of the measured hot path

**Rescoped 2026-09-12 by U-045.** This milestone was "AI and economy on the
SH2", justified as flagship responsiveness. The profile says that premise is
false: over a full 20-year demo game the 68000 is **idle 69.5% of the time**,
and **not one AI or economy routine appears in the top 25**. There is nothing
to win there.

What is actually hot is graphics -- 20.4% of gameplay frames, over half of it
in one routine, the LZ decompressor at `$003F70-$004220`. So the milestone
keeps its purpose (move work the 68000 cannot afford onto the SH2) and changes
its target.

**And the size of the prize is now measured, not inferred.** The 68000 spends
**285 cycles per output byte** decompressing, so the largest block in the game
costs 62 frames on its own -- which is where the 74-76 frame quarter-boundary
stall comes from. Transport back across the frame buffer costs 2-3% of that.
U-046 is the whole milestone in practice; U-041 and U-042 have no measured
benefit and U-043 is a scheduling question, not a workload.


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
the frontend (**since upstreamed into `../32x-playground` as
`VRD_FRAME_FINGERPRINT`, where the PC is one column of several -- see
U-093**).

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

### U-046 -- Offload LZ decompression to the SH2 [DONE, in the shipping build]

The measured hot spot: **11.93% of all gameplay frames**, 3.4x the next item,
and the bulk of the 74-76 frame stalls at each quarter boundary. Those stalls
are screen loading, not thinking.

It suits the SH2 unusually well. The input is compressed data in cartridge
ROM, which the SH2 can read directly at `$22000000`; the work is bit-serial
and branch-heavy, which is what a 32-bit RISC is for; and it is *batch* work,
so it clears U-039's ~560-cycle break-even by a wide margin instead of
straddling it the way a single divide did.

**The arithmetic is done, and two of its premises were wrong.**

*Wrong premise 1: "decompressed tiles go to VRAM".* They do not. The signature
is `LZ_Decompress(dest, src)` with the arguments on the stack, and **66 of the
92 static call sites decompress to one shared work-RAM scratch buffer at
`$FF1804`**; 6 more go to `$FF899C`. The recurring pattern is

```
DisplaySetup(...)
LZ_Decompress(src_rom, $FF1804)
VRAMBulkLoad(tile, count, $FF1804, ...)     ; DMA scratch -> VRAM
```

so the buffer is pure staging and nothing else reads it. That opens a path the
original framing had ruled out: the SH2 decompresses into the frame buffer and
the 68000 either copies to `$FF1804` (safe) or points the existing DMA at the
frame buffer instead (cheaper, but needs the VDP to DMA from `$840000`, which
is unverified).

*Wrong premise 2: that the copy might eat the saving.* It cannot come close.
`make 32x-lzprobe` runs the real routine over eight real blocks spanning the
measured size distribution and lets the harness supply the clock:

| | |
|---|---|
| Rate | **285 cycles per output byte** (448 bytes/frame), from the slope between 300 and 1,200 frames so the boot offset cancels |
| Median block, 1,952 bytes | 4.35 frames |
| Largest block, 27,872 bytes | **62 frames** |

**This is independently corroborated.** U-045 measured the quarter-boundary
stalls at 74-76 frames by PC sampling; the largest block alone accounts for 62
of them. Two measurements taken different ways agreeing on the stall is the
strongest evidence in this item.

285 cycles/byte is 6-10x a typical 68000 LZSS, and the code says why: a
`jsr (a4)` with a `pea`-pushed argument for **every bit read**, and the control
byte re-fetched from absolute long `$FFA78C` on every bit. Against that, a
68000 copy out of the frame buffer costs 6-8 clocks per word access (manual
4.1: 2-4 wait on a 4-clock cycle), so **transport is 2-3% of decompression**.
The offload wins on arithmetic by a wide margin.

**Size distribution**, from decompressing all 46 distinct sources reachable
from the call sites: min 192, median 1,952, mean 4,560, max 27,872 bytes.

**Batch, do not call per block.** Decided on three grounds, strongest first:
FM handover is a mutual stall ("SH2 and 68000 wait together until access
authorization returns", manual:737), so one rendezvous per batch beats one per
block; the frame-buffer write FIFO costs 3 clocks per word unfilled against 5
filled and the manual assumes "continuous accessing without an Idle Cycle"
(4.1), so sustained runs are cheaper per word; and RPC amortisation, which at
~560 cycles against a 1,952-byte median is already comfortable and is
therefore the weakest reason, not the strongest. The intuitive argument --
cartridge bus contention -- is the one that **cannot be measured on
PicoDrive**, so it is not counted. The interface should take a job list, not a
job.

Where batching actually applies: the call sites interleave
`DisplaySetup / decompress / VRAMBulkLoad` one block at a time, so they do not
batch naturally. The place they cluster is the quarter-boundary stall, which
is also the user-visible one. Target those sites, not all 92.

**The decompressor is built and measured.** `disasm/sh2/master/lz.c`,
transcribed from `tools/lz_decompress.py` and so at one remove from the 68000
itself, kept in that shape so the three can be diffed. `make 32x-lztest` runs
it on the world map's tiles.

**Correct, by checksum rather than by eye.** A wrong decompressor produces
plausible bytes, so "22,528 bytes came out" proves nothing. The SH2's FNV-1a
over its whole output is **`0x3640A33D`**, which is what the Python reference
computes independently.

**And it is fast.** Measured on the U-093 timing core with the cache and wait
states modelled, 16 decompressions bracketed by the V-Blank counter:

| | 68000 | SH2 (wait=min) | SH2 (wait=max) |
|---|---|---|---|
| Cycles per output byte | 285.5 | **59.7** | 60.7 |
| Bytes per frame | 448 | **6,437** | 6,324 |
| Largest block (27,872 B) | 62.2 frames | **4.4** | 4.4 |
| Median block (1,952 B) | 4.4 frames | **0.3** | 0.3 |

**14.1-14.4x faster in wall clock**, 4.7-4.8x fewer cycles on a CPU running 3x
the clock. The min/max wait spread is only 2%, because the workload is
cache-resident at a 99.99% hit rate -- so for once the unmodelled parts of the
timing barely matter. Turning the timing model off entirely moves it by 10%,
which is the honest bound on how much this depends on U-093's model at all.

Two things make the comparison conservative rather than flattering: the 68000
figure does not include modelled cartridge wait states (0-5 per manual 4.1),
which would make it slower, and the benchmark's misses sit close to the
compulsory minimum (2,335 per iteration against ~1,920 unavoidable), so
repeating the same block is not warming the cache in a way real use would not.

**So the 74-76 frame quarter-boundary stall becomes about 5 frames.** That is
the whole of M5's value, and it is now a measured number rather than a hope.

**It is wired into the game and it works.** `disasm/32x/sh2_lz.asm` is a
size-neutral swap for `LZ_Decompress`'s first eight bytes under
`ifne ROM_BASE` -- eight bytes for eight, patching the routine rather than its
92 call sites, so one edit covers every screen load. It falls back to the stock
68000 code if the SH2 does not answer within a bounded wait: a slow screen load
beats a hung one.

Transport goes through the 32X frame buffer, the only memory both CPUs can
reach -- the SH2 cannot touch 68000 work RAM and the 68000 cannot touch SDRAM.
The shipping build leaves the frame buffer entirely unused (the layer is
blanked, M3), so `$012000` onward is free scratch, past the line table and the
224 displayed lines.

**Measured against a baseline built from the previous commit**, 12,000 frames
each, compared with U-092 because the two builds diverge by construction:

| | |
|---|---|
| Shared screens | **2,247 of 2,273** (98.9%) |
| Frames at matched screens | **31 of 31 bit-identical**, across two samples |
| Frame drift | **-198** -- the patched build runs *ahead* |
| Cartridge size | unchanged, 2,097,152 bytes |
| Genesis ROM | byte-identical |

The 198 frames are the point, and they corroborate the prediction from a
different direction: quarter boundaries recur about every 4,000 frames
(U-045), so 12,000 frames covers roughly three of them, and 198 / 3 is about
66 frames saved each -- which is the 74-76 frame stall becoming about five.

Why it is not larger: the game is frame-locked and the 68000 is idle 69.5% of
the time, so a faster decompressor does not raise the frame rate. It only
shortens the stalls. That is the whole of the user-visible effect and it is
what M5 was for.

**The caveat from the first write-up of this item is closed, and it was the
tool.** The matcher reported the shared screens visited in different orders at
12,000 frames. Chasing it: its order test compared the two full run sequences
elementwise, which can never succeed, because screens recur constantly -- 1,050
of them over 12,000 frames -- and a single extra transient run in either build
shifts everything after it.

Replaced with an inversion count on first occurrences, which gives **7
inversions in 2,247 shared screens**, all among states held for fewer than 20
frames. Filtered to screens a player would call a screen (`--min-run=20`):
**zero inversions**. Both builds visit every stable screen in the same order,
and the residual inversions are transitions reached at different sub-frame
points, which is what a timing change does.

Still open:

- **Batching**, per the interface note above: a job list, not a job. The
  handshake is currently one round trip per block, which the measurement says
  is affordable but which FM handover makes worth amortising.
- **RV interlock.** The SH2 now reads cartridge ROM through the *cached*
  alias while the 68000 raises `RV` to DMA from ROM, and an SH2 cartridge
  access while `RV = 1` stalls until it clears
  (`docs/32x-hardware-manual.md:281`). U-093 counts those. **This is a real
  interaction now, not a hypothetical**, and it is the next thing to measure.
- The scratch region assumes the 32X layer stays blanked. M4 turns it on, and
  the two uses of the frame buffer will have to be reconciled.

### U-047 -- Fluidity in the complex UI screens [OPEN, measure before building]

Reported symptom: screens with a lot of moving parts -- the aircraft dealer is
the example -- feel sluggish in a way the simpler screens do not.

**This may already be fixed, and that has to be checked before anything is
built.** U-045 found the 68000 idle 69.5% of gameplay with no AI or economy
routine in the top 25, so sluggishness is unlikely to be computation. What is
hot is graphics, over half of it the LZ decompressor -- and U-046 has just made
that 14x faster, cutting screen-load stalls from ~70 frames to ~5. A screen
that felt slow because it was reloading tiles may simply not any more.

Method, in order:
1. Reproduce it. Drive the demo to the dealer screen and use the U-092
   fingerprint to find the frames; a stall shows as a run of frames where the
   screen hash does not change.
2. Compare against the pre-U-046 baseline at the same screen.
3. Only if a stall survives, profile it with the PC sampler and find out what
   it is actually doing.

The trap to avoid is the one M5 already fell into once: assuming the slow thing
is the thing that looks expensive.

### U-041 -- Port quarterly processing to the SH2 [OPEN, no measured benefit]
### U-042 -- Port the AI decision tree to the SH2 [OPEN, no measured benefit]
### U-043 -- Split work across master and slave [OPEN]

Kept, not deleted, but nothing should start on U-041 or U-042 until there is a
measurement that justifies it. U-045 found no AI or economy routine in the top
25; the nearest were `$01E226`/`$01E22E`/`$01E232` in the `MulDiv` /
`WeightedAverage` cluster at about 0.5% between them. Re-profile after M8
lands -- more cities and routes multiply exactly these loops, and the answer
may change -- but today porting them would be work with no user-visible
result.

Each ported routine keeps its 68K implementation selectable at assembly time so
results can be diffed against the original. Correctness first, speed second.

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

### U-063 -- Better text and fonts [OPEN]

The game's text is Genesis 4bpp tiles at one cell per character, which caps
the font at 8x8 in 15 colours and makes proportional spacing impossible. On
the 32X layer a glyph is just pixels, so a proportional font, anti-aliasing
against the panel colour, and mixed sizes all become available.

The catch is where text lives. U-003 decided the 32X layer is for the map
screen alone, and every other screen keeps its Genesis planes -- so text drawn
on the layer only helps screens that have been converted. Sequencing question
for U-034, not a free win.

Worth measuring first: how many distinct glyph cells the UI actually uses, and
whether the win is legibility (a better font at the same size) or density
(more text per screen). Those pull in different directions on a 320x224 display.

### U-064 -- Better dialogs [OPEN]

The yes/no and confirmation dialogs are the most-touched UI in the game and
the least considered. Cheap improvements that do not need the 32X layer:
consistent button placement, a default highlighted option, and cancel on B.

Check first whether the dialogs share one routine or are open-coded per site.
If they share one, this is a small change with broad effect; if they do not,
it is a refactor first, and the count of sites decides whether it is worth it.

---

## M8 -- Content expansion

The project goal, stated 2026-09-11: **Aerobiz Ultimate should be the successor
the series never received** -- more scenarios, more events, more aircraft and
more airports. Not an unbounded amount; enough that scaling the map is worth
doing -- "scaling" meaning the zoom effect of U-035, not a bigger world. The
causality runs that way round: the map zoom is the flagship visual, and the
content has to be dense enough that zooming into it shows the player something.

M8 was sequenced after M5 on the reasoning that the content expansion
multiplies the AI and economy loops, so that work should move to the SH2
first. **U-045 retired that argument**: those loops are not hot -- the 68000 is
idle 69.5% of the time and no AI or economy routine reaches the top 25. There
is no queue to get out of the way of.

**M8's real dependency is M4**, and specifically U-035's zoom and U-077's
tiering: more airports are only worth adding to a map that can show them. M5
is no longer a prerequisite. It is worth re-profiling *after* M8 lands, since
more cities and routes multiply exactly the loops that are quiet today.

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

### U-081 -- Retire the subcontinent views [OPEN, design decision first]

The game divides the world into seven regions -- Europe, Africa, the Middle
East, Southeast Asia, Oceania, North America, South America -- and scopes much
of the UI to one at a time. The proposal is to drop that and let the player
work with one continuous world, navigated by U-035's zoom and U-077's tiering
rather than by choosing a region from a menu.

**The argument that prompted it is worth keeping.** Rejecting an interactive
globe (U-082) because "it hides half the world" is not a coherent objection
from a design that already hides five sevenths of it. Either the whole world is
visible and navigable, or the paging is fine and so is the globe. Choosing the
first is a real decision, not a tidy-up.

**But two premises need correcting before anyone plans around them.**

*It was never a RAM constraint.* The per-city arrays already cover all 89
cities at once in 68000 work RAM -- `city_data` at `$FFBA80` is 89 x 4 entries
(712 bytes) and `char_stat_tab` at `$FF1298` is 89 x 4. The game holds
whole-world state today and pages the *presentation*. So nothing has to be
freed to do this; it is UI work.

*And the 32X does not add RAM the 68000 can use.* The 256 KB of SDRAM sits on
the SH2 bus and the 68000 cannot address it at all -- its map has the frame
buffer at `$840000`, the cartridge windows, and the same 64 KB of work RAM as
before. For anything the 68000 owns, the budget is unchanged. This matters far
beyond this item: **M8's "more airports" depends on it**, which is exactly why
U-071 and U-072 exist.

There is a way round it, and it reopens an argument U-045 closed. U-045 killed
the *performance* case for moving game state to the SH2 -- there is no queue to
shorten. Capacity is a different case: state that lives in SDRAM is state that
does not compete for the 64 KB. If M8 runs out of work RAM, U-041 and U-043
come back for a reason that has nothing to do with speed.

What actually has to be replaced:

| Today | Notes |
|---|---|
| `RegionBitmaskTable` (`$05ECDC`) | 7 longwords, and they partition **exactly the 32 majors** -- 7+2+3+7+3+7+3. The 57 secondaries have no region at all, which is quiet evidence that the scheme was already straining |
| `RegionNamePtrs` (`$05EC84`) | 14 strings, long and short forms of the seven |
| `RegionAircraftIndex` (`$05ECF8`) | availability by era **and region** -- this one is game design, not UI, and has to survive in some form |

Order of work: U-034 first, since retiring the Genesis map renderer is what
makes zoom-and-pan the primary navigation; then the region-scoped screens one
at a time, with U-092 confirming each still shows what it used to.

### U-082 -- Interactive globe [OPEN, set-piece not primary]

Measured as affordable rather than assumed. A globe with a vertical axis has a
property that makes it much cheaper than per-pixel inverse trig suggests:
**each screen row is a single line of latitude**, so latitude costs one `asin`
per row, and along a row longitude is `asin(x / r_row)` with `r_row` constant
-- a shared table indexed by a multiply. **Rotation is an additive offset to
longitude**, so spinning costs nothing extra.

That puts the inner loop near U-037's affine loop, measured at 5.75 frames
full-screen, and a globe covers only a disc -- 55% of the frame at full height.
Call it **~4 frames, 12-15 fps**, better for a smaller globe. Two things
already favour it: the map is equirectangular, which is a globe texture, and it
is **256 pixels wide, a power of two**, so longitude wrap is a mask.

Against it: arcs need far-side occlusion, labels distort at the limb, and half
the network is hidden -- which is only an objection if U-081 lands. Sequence it
after U-081 either way: if the whole world becomes the navigation model, the
globe is a set-piece within it, not a competitor to it.

### U-079 -- Bring scenario 4 in line with what actually happened [OPEN]

Aerobiz Supersonic's last scenario was set in the game's own future, and that
future is now thirty years of recorded history. Its assumptions about which
cities matter, which routes open and which political events fire can be
replaced with what happened, which costs no new engine capability -- it is data
in the per-scenario blocks at `$05F26A`+ and the event tables U-075 covers.

The judgement call to make explicitly rather than drift into: how much realism
serves the game. Aerobiz is a boardgame about competition, not a simulator, so
an event that is historically right but strategically inert is worse than the
invented one it replaces. Prefer changes that alter the map of opportunity.

Depends on U-075 for the event format.

### U-080 -- Scenario 5, starting fifteen years on [OPEN]

A fifth scenario picking up where the fourth leaves off. The natural shape for
the successor this project is trying to be: the existing four are a historical
sweep that stops short of the present, and one more closes the gap.

Mechanically this is U-074 -- a window start in `RegionAircraftIndex`, a
per-scenario data block, and the 0..3 bounds tests widened -- so the engine
work is shared and only the content is new. It is also the scenario that most
wants M8's other items: a later start implies the aircraft of that era
(U-073, U-078) and airports that did not matter in 1955 (U-076).

Sequence it last among the content items. It is the one that best demonstrates
the point of the project, which also makes it the one with the most to gain
from everything else landing first.

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

### U-077 -- Draw secondary airports only when zoomed in [DONE, in 32x-zoomtest]

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

**Built, and the prediction held: no new data was needed.** The coordinate
table is at Genesis **`$05E948`**, two bytes per city -- x then y in map
pixels, which is exactly the space the rasterizer works in. `DrawRouteLines`
(`$0098D2`) reads it the same way to place route endpoints, which is how it
was found.

Verified rather than eyeballed: at 1:1 **all 32 majors land on their exact
table coordinates** in the rendered frame, and **zero secondaries are drawn**.
Past the threshold the secondaries appear and then vanish again on the way
out -- yellow pixels are present only in the deepest third of the zoom cycle.

**The open question is answered: a discrete threshold, not a fade.** One
comparison against the scale, `step <= FP_ONE / 2`, so secondaries appear once
a source pixel covers at least two dots. At this resolution a pin either reads
or it does not; there is no intermediate size worth crossfading to, and the
pop is hidden by the zoom motion itself.

**A constraint discovered in the building, which U-032 and U-033 inherit.**
Markers scale with the map rather than holding a constant size on screen, and
that is forced by the line-table trick rather than chosen: display lines that
share a slot share its pixels, so anything drawn into a slot is repeated by
every line pointing at it. Constant-size overlays would mean giving each
display line its own row and paying full price for the vertical axis -- which
is precisely the cost U-035 avoids. Route arcs and aircraft sprites will scale
too.

Still open: the threshold is a renderer-side constant as the design note asks,
but U-070's `CITY_MAJOR_COUNT` does not exist yet, so `CITY_MAJOR` is defined
in `fb.c` and must move when it does.

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

### U-090 -- Build or install an SH2 C toolchain [DONE]

`sh-elf-gcc` 13.2.0 is on `PATH` with a big-endian SH2 multilib
(`/usr/lib/gcc/sh-elf/13/m2/libgcc.a`); marsdev also carries 15.1.0. Nothing
needed building.

More to the point it is now **in use and proven**, not merely available: the
SH2 command dispatcher and the frame buffer test are both C
(`disasm/sh2/master/rpc.c`, `fb.c`), compiled `-m2 -mb -O2 -ffreestanding` and
linked against libgcc for `__udivsi3`, with `.bss` bounds exported from
`sh2.lds` and cleared by `master_start` before any C runs. That code ships in
`build/aerobiz-ultimate.32x`.

### U-092 -- Screen-matched comparison harness [DONE]

Three times a change made the demo diverge, putting two builds on different
screens at the same frame number and making frame-to-frame comparison
meaningless. It caused two wrong conclusions in one session.

Fixed in two halves. The frontend gained `VRD_FRAME_FINGERPRINT=<csv>`: one row
per frame with the 68000 PC and hashes of VRAM, CRAM, VSRAM and the VDP
registers, all from a single `retro_serialize` into a reusable buffer. VRAM and
CRAM identify a screen -- the loaded tile set and palette change when the
screen changes and hold still while it is displayed. `tools/match_screens.py`
then pairs frames showing the same screen.

**Choosing the key is the part that matters**, and the default is not always
right. `--key=both` (VRAM + CRAM) is the most specific. `--key=cram` is the one
to use when the change under test rewrites VRAM itself -- a plane-geometry or
display-mode change moves the nametable, so a VRAM key matches nothing and
reports "these builds never show the same screen", which is true and useless.

Validated on the case it was built for. Stock 32X build against the H40 build,
3,000 frames each:

| | |
|---|---|
| Distinct screens | 56 in each |
| Shared (`--key=cram`) | **56 of 56** |
| Screen order | agrees |
| Frame drift | constant **+7** |

So frame 2315 in the stock build is frame 2322 in the H40 build, same screen,
100 frames long. **This unblocks U-036.**

It also reproduces a number that was previously measured by hand: the Genesis
build against the 32X build drifts +0 to +6 frames, which is U-013's "offset by
five frames of adapter bring-up", now derived automatically.

### U-093 -- Make PicoDrive the instrument this project needs [DONE]

U-046 stalled on a number the emulator could not produce, so the emulator got
the work instead. All of it in `../32x-playground`, all of it **opt-in**: the
permissive behaviours are what every existing measurement and every other game
depends on, and a silent shift would invalidate them.

| Env | What it adds |
|---|---|
| `VRD_SH2_TIMING=1` | SH2 wait states (32x manual 4.1) and a timing-only SH7604 cache (sh7604 section 8) |
| `VRD_SH2_TIMING_WAIT` | `min`/`max`/`mid` within the manual's ranges, so results are quoted as a range |
| `VRD_RV_EMULATION=1` | the `RV` bit actually switching the cartridge windows |
| `VRD_FRAME_FINGERPRINT` | per-frame screen identity (U-092) |
| `VRD_RAM_TRACE` | one 68000 RAM value per frame |

Two cores are now built by `build_cores.sh`, because they cannot share an
object tree -- the Makefile has no dependency on `use_sh2drc`, so switching it
reuses stale objects. `picodrive_libretro.so` is the DRC core for long
profiling runs; `picodrive_libretro_timing.so` is the interpreter core and the
only one where the timing model works, since the recompiler keeps the live
cycle count packed in SR around a memory call. The model **refuses to enable**
under the DRC rather than silently ignoring every wait state.

**Validated, not asserted.** `make 32x-timingtest` makes a known number of
accesses of one kind; measured by slope between two iteration counts so fixed
overhead cancels. Over 1,000,000 accesses each:

| Access | Measured | From the manual |
|---|---|---|
| cache-through SDRAM longword read | **11.0000** | 12-clock burst − 1 |
| frame buffer word write | **2.0000** | 2 + 1 wait − 1 |
| cache-through cart ROM longword read | **7.0000** | 2 + 6 wait − 1 |

**What it found immediately.** The SH2 slave had never enabled its cache, so
every fetch of its two-instruction idle spin was an 8-word SDRAM burst: 139.4M
wait cycles against the master's 19.3M, for a CPU doing nothing. Fixed; now
472,472, a 295x reduction.

**`RV` is no longer unverifiable-in-principle, only unverified-on-hardware.**
Upstream stores the bit and acts on nothing, leaving both cartridge windows
readable where hardware offers one. With it enforced, the Aerobiz 32X build ran
3,000 frames through **233 mapping changes** with **100 of 100 captured frames
identical** to the baseline -- so the U-020 DMA thunk works against the
documented model. The transition counter exists because "no change" and "never
fired" look identical otherwise.

What is still out of reach, and stated so it is not forgotten: whether hardware
really unmaps `$880000` while `RV` is set, whether a longword access to a
16-bit port is one bus cycle or two, and contention between the two SH2s and
the 68000 on the cartridge bus. HARDWARE_TESTS items 6 and 7.

### U-091 -- Emulator harness for automated boot tests [DONE]

`../32x-playground/tools/libretro-profiling` had everything needed except a
usable binary: the checked-in `profiling_frontend` is older than its own source
and has no video capture, so it accepted `VRD_VIDEO_DUMP_DIR` and silently
wrote nothing. Rebuilding from the same source
(`cc -O2 -o frontend profiling_frontend.c -ldl`) gives working RGB565 frame
dumps.

**The "nothing in that repository was modified" policy recorded here is
superseded by U-093.** It was right while we were only borrowing a tool; it
stopped being right once the tool was the thing standing between us and a
measurement. The frontend and the PicoDrive core are now modified there
deliberately, and the local patch file that used to hold our changes is
deleted rather than maintained as a second copy.

Still worth doing there: the capture path hard-codes 320x224 and rejects
anything else, which silently drops every Genesis-mode frame. Relaxing it to
accept the reported geometry is what produced the H32 answer in U-003, and it
is still carried as a local edit rather than upstreamed.

U-001 is manual. A headless run that asserts on comm-port state would make every
subsequent milestone cheaper to verify.
