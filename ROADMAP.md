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

### U-002 -- Draw something on the 32X layer [OPEN]

Extend the SH2 master to fill the frame buffer and enable packed pixel mode, so
the layer is visibly alive. Exercises the line table format (256 words at the
page head -- manual 3.3), the palette, the `FM` handover and the frame buffer
swap. Watch for the byte-write-zero trap in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

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

### U-040 -- RAM snapshot transport over DREQ FIFO [OPEN]
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
| Aircraft (per scenario) | 16 | **hard 16** -- `plane_type` packs two classes as nibbles | route slot `+$02`; `SortAircraftByMetric` `$00C540` fills `$C0` = 16x12 |
| Scenarios | 4 | selector is bounds-tested 0..3 in two places | `$FF0002`; `BuildAircraftAttrTable` `$00C68A`, `HandleEventCallback` |
| Regions | 7 | 7 -- fixed-size parallel tables | `RegionBitmaskTable` `$05ECDC`, `CharTypeRangeTable` `$05ECBC` |

Each scenario shows a **sliding 16-wide window** into the 53-entry aircraft
pool, with the window starts held in `RegionAircraftIndex` (`$05ECF8`) =
`{0, 12, 26, 37}`. The windows overlap, which is how an aircraft stays
available across eras. This is the single most useful structural fact for M8:
**adding an era is cheap (a new window start plus new pool entries); adding a
17th aircraft to an existing era is not (it changes the save format).**

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
16. Independent of U-070..U-072 -- the cheapest visible win in M8.

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
