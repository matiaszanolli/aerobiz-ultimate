# Aerobiz Ultimate -- History

What has actually happened, newest first. [ROADMAP.md](ROADMAP.md) is the other
half of this pair: it says what is next, this says what was done and -- more
usefully -- what we believed that turned out to be wrong.

Entries record evidence, not intentions. A claim here should name the file, the
manual section or the tool output that backs it.

---

## 2026-09-12

Nine commits, and the useful output was mostly negative results. Recorded here
because the beliefs they overturned were this project's own, written down with
more confidence than the evidence supported.

### The 32X layer works, and the display-mode question is settled

U-002: `make 32x-fbtest` paints the line table, palette and 224 lines from C on
the SH2. Five consecutive frames hash identically. Pinned down: line table is
256 words at the buffer head, packed-pixel lines are 160 words, palette is
`through:1 B:5 G:5 R:5`, `FM = 1` hands over the frame buffer *and* the 32X VDP
registers, an `FS` write lands only at the next V-Blank, and word writes
throughout because a byte write cannot store zero.

U-003 resolved by measurement. In H32 the Genesis and 32X layers sit at
**1.25x different scales** -- measured 95.6% pixel match for a nearest-neighbour
256->320 stretch against 85.0% centred and 83.4% left-aligned, with content
spanning 8-230 becoming 10-288. In H40 they are **100.00% identical** over the
5,077 non-backdrop pixels of a test frame.

**Believed wrong:** that this was emulator behaviour pending hardware. It is
physics -- `pico/32x/draw.c:11-19` explains that the cartridge slot carries
EDCLK, always the H40 clock, which the 32X uses as its video clock; H32 and H40
fill the same on-screen width with different pixel counts. Manual 3.3's "must
be 320-wide" means *officially unsupported*, not *broken*.

### M5's premise was false

U-039 measured the comm-port round trip at a flat **~560 68000 cycles**,
independent of payload -- 228 calls/frame whether the SH2 does a cheap divide
or an expensive one. U-044 then offloaded `UnsignedDivide`'s slow path
correctly (12,000 frames bit-identical in work RAM, VRAM, CRAM, VSRAM and
registers) and found it is **never called**: zero in 200,000 frames.

U-045 profiled properly, sampling the 68000 PC from the savestate once per
frame across a full 20-year demo game, 418,549 gameplay frames:

| | share |
|---|---|
| idle in `CmdWaitFrames` | 69.5% |
| graphics and decompression | 20.4% |
| everything else | 10.1% |

with the LZ decompressor at `$003F70-$004220` alone at **11.93%**, and **no AI
or economy routine in the top 25**.

**Believed wrong:** that the turn cycle is spent in AI and economy code, and
that offloading it would buy responsiveness. M5 was rescoped to the measured
hot path and M8's dependency on it removed.

**Believed wrong:** that picking an offload target by reading the code was
sound. `UnsignedDivide`'s slow path looked like the best candidate in the whole
math module -- pure, self-contained, comfortably above break-even -- and its
dynamic call count is zero.

### U-036 is unsolved, after five eliminated hypotheses

64-cell planes corrupt some screens. Ruled out: H40 itself (fine alone), the
`cmpi.w #$20` gate in `UpdateScrollDisplay` (patched, frame hashes identically),
vertical plane size (64x32 and 64x64 give byte-identical frames), horizontal
scroll wrapping (hscroll is `(2,2)` in both builds, reg 11 `$00`), and the
central address path (`ComputeMapCoordOffset` and `CmdDMABatchWrite` both scale
by the register-16 shadow and trap on the prohibited HSZ=2).

The engine turned out to be *more* parameterised than expected: plane geometry
is table-driven through `SetScrollQuadrant`, whose table at `$04737E` already
contains 64x64, and the BAT row stride is a variable at `$FFA77E`.

**Believed wrong, twice, both from a single frame:** that the plane change
rendered correctly (it was one lucky screen; Regional Rankings is corrupt), and
that the corruption was in plane A (that rested on byte-swapped nametable
reads and is withdrawn).

### The measurement traps cost more than the code

Three findings in this session came from *reading the instrument wrong*, and
all three are now in [KNOWN_ISSUES.md](KNOWN_ISSUES.md): savestates store VRAM,
CRAM and work RAM **byte-swapped**; debug reads return zero for `$A151xx`, so a
counter in a comm register cannot be distinguished from "never called"; and any
timing change makes the demo diverge, so **frames from two builds cannot be
compared at the same frame number**.

The last one is the expensive one. It has now caused a wrong conclusion three
times -- once via input timing in U-021, twice here -- and U-092 exists to fix
it properly.

### Also

- `m3-full-game-32x` tagged and pushed.
- SH2 C toolchain closed (U-090) -- not merely available but shipping, two C
  files in `build/aerobiz-ultimate.32x`.
- M8 written up with measured content ceilings: 32 major airports (a full
  32-bit region bitmask), 57 secondary, 53 aircraft with 16 visible per era
  through sliding windows, 4 scenarios, 7 regions.
- `tools/extract_map.py` renders a Genesis plane out of a savestate; the world
  map comes out at 256x224 with 24 distinct palette indices.
- `HARDWARE_TESTS.md` added -- five questions only a real 32X can answer.

---

## 2026-09-11 (U-021)

### A full game, a save and a load, on the 32X

The 32X now plays Aerobiz Supersonic end to end. Both builds were driven from
power-on by one input script and compared.

**A turn cycle.** Scenario 1 (*The Dawn of the Jet Age*), skill level 1, one
human airline based in Berlin plus three CPU airlines. The setup screens, the
opening news events, the in-turn command bar and the system menu were all
reached and worked. 90,000 frames, no 68000 exception on either build.

**Save and load.** The system menu's *Save* writes 16,384 bytes to cartridge
SRAM at `$200000-$203FFF` -- on the 32X exactly as on the Genesis. Booting the
32X build again with that SRAM restored, the title screen's CONTINUE lists the
save ("Berlin MAN Berlin ... 1955 APR") and resumes into the running game, with
no exception. This is the 32X reading back a save the 32X itself wrote.

`docs/32x-technical-info.md:83` is why this works unchanged: "The RV bit is
irrelevant when reading and writing to the SRAM". The save address is built as
`addi.l #$00200003,d0` in `PackSaveState`, which is outside the ROM window and
so is correctly left alone by the rebaser.

**The end of the game.** The player-count screen has a DEMO entry that gives all
four airlines to the CPU, so a whole 20-year game runs with no input at all.
Both builds played one to completion and returned to the attract loop -- the
Genesis at frame 433,515, the 32X at 295,736 -- and the last 9,000 frames of
each have the same structure (static runs of 246, 246, 246, 120, 129, 130
frames). 900,000 frames each: **zero 68000 exceptions on both**.

### The long AI game is not an equivalence test, and the control proves it

The two DEMO games ran to different lengths, which looks damning until the
control is run. Shifting the setup presses by a few frames and replaying:

| input shift | Genesis ends at | 32X ends at |
|---|---|---|
| +0 | 433,515 | 295,736 |
| +3 | 184,626 | 264,259 |
| +4 | 172,286 | 306,457 |
| +5 | 272,618 | 163,716 |
| +6 | 310,546 | 268,080 |
| +7 | 293,335 | 228,608 |

**One frame** changes the Genesis build's own 20-year game by a factor of two
and a half. The 32X spread is the same. The adapter's few frames of bring-up
therefore reseed the game all by themselves, and no comparison of two long AI
games between the builds can mean anything. This is worth stating plainly
because the first reading of that table -- "the 32X ends 138,000 frames early"
-- would have sent the next day into chasing a bug that is not there.

### What the builds were actually compared on

With **no input at all**, both builds run their own attract loop, so nothing can
be reseeded. After 300,000 frames (about 83 minutes) the 68000 work RAM differs
in **64 bytes of 65,536**:

- 53 bytes are ROM pointers holding exactly Genesis + `$900000`, which is the
  correct value on the 32X;
- 5 bytes are dead stack below the pointer, where the U-020 DMA thunk runs its
  window body;
- 6 bytes remain: `$FF1401`, `$FFA785`, `$FFA789`, `$FFF08F`, `$FFF097` and
  `$FFFBF3`, the last being a counter one ahead.

That is 0.009% of work RAM unaccounted for, over a run in which the game
executed its own code for an hour and a quarter of wall-clock gameplay.

### Notes for the next session

- **libretro button numbering is not Genesis button numbering.** START is id 3
  (mask `8`); Genesis A, B and C are libretro Y, B and A -- masks `2`, `1` and
  `256`. `retro_pico_map` in PicoDrive's `platform/libretro/libretro.c:3039`.
- **The game's own encoding is different again**: the byte at `$FFFC08` uses
  bit 5 (`$20`) for C, which is what `BrowseMapPages` tests when it confirms a
  save slot. The disassembly comment there calls `$20` "Right d-pad"; that
  annotation is wrong, and following it cost an hour of pressing the wrong
  button at the save-slot browser.
- **Screens ignore input until the previous message is dismissed**, and the
  first press on a screen is usually consumed doing that. A single press
  reading as "no response" usually means one press short, not a hang.
- Frame hashes cannot be compared across the builds at all: the Genesis build
  reports H32 as 256 pixels wide and the 32X composites at 320. Compare 68000
  work RAM, which is width-independent.

---

## 2026-09-11 (later)

### START crashed the 32X; 50 addresses hidden in untranslated dc.w blocks

Reported symptom: the title screen is reached but the game resets on START.
It was not a reset. With an exception hook in the 68000 core (`execute_exception`
in PicoDrive's `cpu/fame/famec.c`, the one point every exception passes through)
the 32X run took exactly one exception and the Genesis run took none:

    EXC vect=11 at=000d64 newPC=88023c sp=ffef8e

Vector 11 is line-F, and `$000D64` is `GameCommand` -- the game's central
dispatcher, its most-called function -- at its *Genesis* address. The 68000 had
jumped to `$000D64` instead of `$900D64`, which under ADEN is unmapped, so it
executed garbage and trapped. The exception handler chain then re-entered the
game, which looks exactly like a reset.

Two sources, two classes, both invisible to `tools/scan_rom_refs.py`:

- **Upper-case mnemonics.** `INSTR` matched `[a-z]` only, so the nine modules
  transcribed in upper case were never even seen as instructions.
  `MOVEA.L #$00000D64,A2` in `WeightedAverage.asm` was one of two sites.
- **Hand-encoded instructions inside untranslated `dc.w` blocks.** Where the
  disassembly could not translate a block it emitted one word per line, so a
  call reads `dc.w $4eb9` / `dc.w $0000` / `dc.w $0d64`. `HAND_ENCODED` needs
  all three words on one line with the opcode first, which never happens there.
  50 sites: 31 `jsr`, 14 `movea.l`, 5 `pea`, in 5 files.

`RunScenarioMenu.asm` holds 34 of the 50 -- the screen START leads to, which is
why nothing before START ever touched them.

### Verifying a class `make verify` cannot see

Ground rule 8 applies in full here: rewriting these keeps the Genesis ROM
byte-identical whatever the bytes meant, so an MD5 match proves nothing about
whether a word was really an opcode. The evidence used instead was a linear
capstone decode of each enclosing block, located in the ROM by matching its
whole byte sequence: all 50 candidate opcodes land on an instruction boundary,
and a word that merely *looks* like an opcode inside data does not. Widening the
opcode set from the 22 forms first tried to all 27 address-operand forms found
the same 50 sites, and the section data files -- 2,697 lines of graphics -- yield
none.

The rebase itself is `dc.l ROM_BASE+$xxxxxx` in place of the two operand words:
the same four bytes on Genesis, the rebased address on 32X. Afterwards the 32X
game image differs from the Genesis ROM only in rebased pointers, plus the one
deliberate six-byte U-020 DMA thunk swap at `$001216`.

### What the 32X now does

Same 30,000-frame input script into both builds, START on the title screen and
A every 400 frames: no exception in either, and both walk the same path into a
running game. At frame 20,000 the 68000 work RAM differs in 79 bytes of 65,536.
74 of them are dead stack below the pointer -- the DMA thunk runs its window
body there -- four are stored ROM pointers holding exactly Genesis + `$900000`,
which is the correct value, and one is a counter two ahead. The route map
renders identically on both.

`scan_rom_refs.py` now reports zero `safe` sites outstanding. The 901 remaining
are the `review` class (U-011), unchanged.

### The input mask was wrong all along

The earlier "START tapped from frame 300" evidence was not START. In libretro
`RETRO_DEVICE_ID_JOYPAD_START` is 3, so the mask is `8`; the scripts used `0x80`,
which is RIGHT. The 4,500-frame agreement recorded above stands, but it never
exercised START, and that is why this crash survived a run that looked thorough.
A frontend that cannot press the button you think it is pressing produces
confident, wrong evidence.

Two smaller traps in the same session, both of which produced silent empty
measurements rather than errors: `VRD_INPUT_SCRIPT` must contain exactly
`max_frames` rows, so a short run against a long script aborts before the core
starts -- which is how a "positive control" for the exception hook came back
empty; and `grep` treats `famec.c` as binary because it is ISO-8859, so a search
for `exception` in it returns nothing at all unless `-a` is passed.

---

## 2026-09-11

### The game runs on the 32X

M2 complete in the sense that matters: the 32X build's video output is
indistinguishable from the Genesis build's. At frame 2550 VRAM differs in 2
bytes of 65536, CRAM in 1 of 128, VSRAM and all 64 VDP registers not at all.
Driven by the same recorded input for 4,500 frames, the frames-with-content
runs match exactly, five frames apart for adapter bring-up, and captured frames
are pixel-identical.

The cause was a class nothing had looked for: **pointer values stored in ROM
data**. Rebasing rewrites addresses that appear in *code*. These are addresses
that appear in *data* -- the load site is rebased, the pointer it reads is not.
On 32X a raw address lands in the boot half's `$FF` padding, which is why VRAM
filled with `$FF` and palette lines read `$0EEE`: that is `$FFFF` masked into
the Genesis 9-bit colour format. Both symptoms were visible for days and neither
pointed at the cause.

No data-side heuristic finds them. The pointer feeding `DecompressVDPTiles` sits
at `$0AF190`, mid-line, in bytes that are otherwise compressed graphics; nothing
distinguishes it from the graphics around it. What finds them is the *code*:

- every `move/movea.l (ROM_BASE+$X).l` proves that offset X holds a pointer, and
  all 260 such sites load a value that is itself a ROM address -- a 100% hit
  rate, which is what made the rule trustworthy rather than plausible;
- a rebased literal used as a base address, followed by a run of even ROM
  addresses, is a table indexed at runtime -- 98 of them, 4,192 entries.

567 pointers in total, each batch verified byte-identical.

Two refinements were needed, both found by chasing a single wrong colour -- the
sky was white -- down to the pointer at `$07702E`: runs must extend *backwards*
from the base, because the code takes the address of the middle of that table;
and a pointer can straddle two `dc.w` lines once an earlier pass has split the
line that held it, so address-contiguous lines must be merged before rewriting.

### A measurement error worth recording

Several conclusions in the middle of this were drawn from an emulator run whose
ROM did not exist. `make clean` had removed it, only the Genesis target was
rebuilt, and the frontend's "Failed to open ROM" went to a stream I was
filtering. Empty output read exactly like "the 32X performs no DMA and never
touches the VDP", which is a dramatic finding and was entirely an artefact.

The tell was available and I missed it: the same run reported *nothing at all*,
not even the startup lines the Genesis run printed. A comparison that produces a
striking asymmetry deserves a check that both sides ran, before the asymmetry is
interpreted.

### Instrumenting the emulator was the thing that worked

Four hypotheses were eliminated by argument and measurement over two days and
none was the cause. What resolved it in one step was hooking PicoDrive: report
the 68000 PC whenever `$FFFF` reaches the VDP. One line of output --
`FFPORT +1 a=c00000 d=ffff pc=90433e` -- named the routine, its caller named the
pointer, and the pointer named the class.

The hooks are kept as a patch rather than committed to that repository, which is
otherwise untouched.

---

## 2026-09-09

### Retraction: the RV probe answered nothing

PicoDrive does not emulate the `RV` bit. `pico/32x/memory.c:2358` -- "c0: don't
need to care about RV - not emulated" -- and :2481, "we take the easy way and
don't unmap ROM, so that we can avoid handling the RV bit", with the
`m68k_map_unmap(0x000000, 0x3fffff)` left commented out.

So the probe result recorded earlier today -- both cartridge windows reading
identically with `RV` set and clear -- was measuring a mapping that never
changed. It is not evidence for anything. §5.3 is open again, and the `RV`
window is unverifiable on this emulator: U-020 can be shown not to break
anything, and cannot be shown to work.

Confirmed independently: building the thunk so that it never translates gives
byte-for-byte the same VRAM as building it so that it always does. Under
PicoDrive the translation is a no-op in both directions.

The lesson is narrower than "check the emulator". The probe was well designed
for the question and the result was internally consistent -- both windows equal,
the cartridge visible at its own offsets, exactly what a working `RV` would
produce. A negative control was missing: read the same addresses with `RV`
never set. That would have shown the same answer and exposed the test as inert.

### Hypothesis (2), the VRAM fill, is disproved

`ConfigVDPColors` uses mode `$9780`, a VRAM fill, which writes a pattern without
reading ROM -- a candidate for filling VRAM with `$FF` that would survive every
pointer fix. It is not the cause: the fill value at `$28(a5)` reads `$0000` in
both builds at frame 1450.

Also worth recording from that comparison: the savestate work-RAM chunk is
word-byte-swapped, so `ff 00 7a ef` is `$00FFEF7A`. The 32X's DMA source at that
moment decodes to `$00973780` -- correctly rebased, in the bank window -- so the
pointer feeding DMA is right and the fetch still yields `$FF`.


### The display fault is unrebased pointers, and savestates proved it

Comparing PicoDrive savestates turned out to be the instrument we needed, and it
needed no core changes: the format is chunked (id byte, 4-byte little-endian
length, data), so VRAM, CRAM and VSRAM can be lifted straight out and compared
between the two builds. Both states are the same size even though only one has
32X sections, so the parse is the same for each.

At frame 1450: VRAM differs in 61,132 of 65,536 bytes, CRAM in 31 of 128, VSRAM
in none. 32X VRAM is **54,328 bytes of `$FF`** where the Genesis build holds
52,325 bytes of zero, and palette line 0 reads `$0EEE` throughout -- which is
`$FFFF` masked into the Genesis 9-bit colour format. Reads from unmapped
cartridge space, filling both VRAM and CRAM. The white block was a white palette
over `$FF` tiles.

So the rebasing is still incomplete, and a fourth hidden class turned up: 32-bit
ROM pointers emitted as two consecutive `dc.w` words. 1,290 of them, in tables
the disassembly labels as pointer tables. Rebased, byte-identical, and it
changed nothing on the failing path -- because the tables are not line-aligned.
`GraphicSequencePtrs` spans `$048D18-$048D2B` and its first entry shares a line
with the graphics data before it, so a line-oriented rule converts four of five.

Worth recording as a pattern, since it is now three for three: every time the
scanner has been wrong it has been wrong by *omission*, and the omission has
never been visible from inside the tool. It took the assembler for the
PC-relative class, and the emulator for this one. The count is not the
deliverable; the evidence that nothing is left is.


### U-020 is done, and it was not what was blanking the screen

The thunk is implemented and exercised -- 616 entries over 3,000 frames, 31 of
them on the cartridge path -- and the display is unchanged with and without it.
Necessary work, wrong suspect.

`make 32x-rvprobe` answers §5.3 at emulator level: under PicoDrive both
cartridge windows read identically with `RV = 0` and `RV = 1`, while the
cartridge is simultaneously visible at its own offsets. The manual says neither
thing, so the thunk keeps its windowed sequence in RAM anyway.

Two earlier claims in this file were wrong and are corrected:

- **"896 bytes free at the top of work RAM" is false.** Painting
  `$FFFC80-$FFFFFF` and running the game overwrote all 896 bytes; painting
  `$FFE000-$FFEFFF` overwrote all 4096. The figure came from scanning literal
  displacements and missed runtime-indexed writes. It was flagged as
  unconfirmed when recorded; this is the confirmation, and it is negative. The
  thunk runs from below the stack pointer instead, which needs no free region.
- **"The game never DMAs from ROM" is false**, though it was never written down
  as such. A 900-frame sample showed every DMA sourced from work RAM and nearly
  led to abandoning U-020. Over 3,000 frames, 31 transfers use the cartridge
  path. The first ROM-sourced DMA simply happens late.

### `make verify` had been vacuous

Neither ROM depended on the sources it includes: `$(GENESIS_ROM)` listed only
`aerobiz.asm`, `$(GAME_HALF)` only `ultimate_game.asm`, while all 818 shared
modules and sections arrive through includes. Editing a module rebuilt nothing,
so `make verify` re-checked the previous binary and reported MATCH for the
wrong reason.

Every per-batch verification during the U-010 rebasing was in that state and
proved nothing. The end state is sound -- the run after the jump-table fix was
a `make clean` rebuild, and so are the ones since -- but the confidence claimed
at the time was not earned. Worth remembering how the failure presented: not as
a wrong answer, but as a right answer arriving too easily.

It cost real debugging time the same day. A DMA change appeared to do nothing;
the built image still contained the previous build's `jsr`.

### The screen is not black, and the cause is still open

Counting non-black pixels per frame rather than sampling two frames changes the
picture. Over 1,500 frames:

| Build | frames with content |
|---|---|
| Genesis | 20-320, 390-660, 667-829, 843-1106, 1320-1499 |
| 32X | 24-324, 1398-1499 |

The 32X renders the boot screen **identically** -- same non-zero pixel count,
four frames later for adapter bring-up -- then loses everything from the first
game screen on. At frame 1450 the Genesis shows the blue trademark screen and
the 32X shows a white block on black: the signature of tiles fetched from
something that reads as `$FF`.

Ruled out by measurement, not argument: the DMA window (implemented, exercised,
no change); H32 (forcing every mode write to H40 changes the content runs not at
all); the 32X layer covering the Genesis one (`$A15180` reads `$8000` --
blanked -- throughout); the review literals (of 896, only 19 are long-sized and
`>= $10000`, and every one is a money value or the `$30000` DMA mask); and game
state (all 64 KB of work RAM differs from the Genesis build in 308 bytes at
frame 500, no run longer than 16).

So work RAM is right and what reaches the VDP is wrong. The instrument we lack
is a VRAM/CRAM comparison: PicoDrive's debugger exposes the 68000 bus and SH2
registers, not VDP memory. That is the next thing to build.

---

## 2026-09-08

### We can see the screen now, and it is black

U-091 done, U-003 answered, U-013 diagnosed and handed to M3.

The harness needed no new code, only a rebuild: the checked-in
`profiling_frontend` in `../32x-playground` is older than its own source and has
no video capture, so it accepted `VRD_VIDEO_DUMP_DIR` and silently wrote
nothing. Rebuilt from the same source into a scratch directory -- that
repository is untouched -- it dumps RGB565 frames.

**The 32X output is black. Every pixel, every frame sampled.** The Genesis
reference at the same frames shows the KOEI intro text and then the title
attract sequence with clouds and an aircraft.

This is the failure we predicted rather than a new one. The game logic runs --
work RAM tracks the Genesis build to 17 bytes in 4 KB over 900 frames -- and
nothing reaches VRAM or CRAM, because the graphics loaders DMA from ROM and the
`RV` window is not implemented. A failed palette DMA on its own produces an
all-black screen whatever VRAM holds. U-013 is therefore blocked on U-020 and
belongs to M3.

### Aerobiz runs H32, and §4.1 has a problem

Measured rather than read out of the register table, by logging the emulator's
frame geometry across 3,000 frames of the Genesis build:

| Frames | Mode |
|---|---|
| 0-320 | H40, 320x224 -- TMSS and boot |
| 321 onward | **H32, 256x224** -- KOEI intro, title, and on |

Manual 3.3 requires a 320-wide Genesis mode whenever the 32X layer is not
blanked, and the game is at 256 essentially always. So the world map cannot sit
on the 32X layer with the Genesis planes in front as §4.1 describes. Moving the
game to H40 means 40 tiles per line where every screen is laid out for 32 --
not a flag flip. This is a design decision to take before U-030, and it is
exactly what U-003 existed to surface.

Found by accident, which is worth noting: the harness's capture path hard-codes
320x224 and rejects anything else, so the Genesis frames were being dropped
with no message. Chasing the missing frames answered the open question.

### M2: the rebased game assembles, boots and runs on the 32X

U-010 and U-012 done, U-013 all but confirmed. 3,001 literals rebased in five
batches, each verified byte-identical, by `scan_rom_refs.py --rewrite`.

The measured figure of 2,886 that this file already records as a correction of
an earlier guess was itself wrong. Three classes were invisible to the scanner:

| Missed | Count | Why |
|---|---|---|
| hand-encoded `dc.w $4EB9,$hi,$lo` | 971 | the address is split across two words |
| multi-value `dc.l` lines | 35 | only the first longword per line was matched |
| PC-relative `$xxx(pc)`, `dbne`, `dbeq` | 24 | not modelled |

True inventory: 3,872. The 971 were the dangerous ones -- `jsr` targets that
would each have called into unmapped `$000xxx`.

Two things fell out that are worth more than the count:

**The image layout is provably intact.** The 32X game half is byte-for-byte the
same length as the Genesis image and differs in 5,793 bytes, every one an
isolated single byte where an address high byte went `$0X` to `$9X`. Not one
contiguous run of two. That is the direct evidence for the size-neutrality
constraint recorded earlier the same day, and the cheapest test we have that
rebasing has not shifted anything.

**Every 68000 interrupt was jumping into padding.** The boot ROM's vector table
is fixed and each vector targets its own slot in the cartridge jump table at
`$200 + (vector - 1) * 6`. Ours packed the sixteen entries we use end to end, so
V-Blank sat at `$25A` -- vector 16's slot -- while the boot ROM jumped to
`$2AE`. Read back live rather than inferred: `$000078` holds `$8802AE`. M1 never
caught it because MdMain masks interrupts and idles.

The differential method is what found it, and is worth keeping: run the 32X
cartridge and the Genesis build in the same emulator, diff work RAM. Before the
fix, 41 of 512 bytes differed, with the 32X side holding zeros exactly where the
Genesis build had V-Blank dispatch flags. After, 2 of 512 -- one of them a
stored ROM pointer reading `$94xxxx` against `$04xxxx`, which is correct
rebasing rather than divergence.

A caution recorded because it nearly misled: `$FF0006` is documented in
RAM_MAP.md as incrementing each MainLoop iteration, and it reads zero on 32X.
It also reads zero on the Genesis build, so it is not the liveness signal the
map describes and proves nothing either way.

Still not *seen*. The prebuilt `profiling_frontend` is older than its own
source and has no video capture, so it accepts `VRD_VIDEO_DUMP_DIR` and writes
nothing. "Reaches the title screen" is inference from work RAM until the
harness can produce a frame; U-091 is raised to blocking.

### The rebasing mechanism was never actually wired up

`ROM_BASE` is the whole dual-build design (PORT_ARCHITECTURE.md §3), and it did
not exist. It was undefined for the Genesis target -- CLAUDE.md's source table
claimed `disasm/aerobiz.asm` set it to 0, and it did not -- and it appeared zero
times in the shared sources. U-010 could not have started.

It is now `equ $00000000` in `disasm/aerobiz.asm`, with one literal converted as
a worked template (`movea.l #ROM_BASE+$000D64,a3` in `VRAMBulkLoad`). `make
verify` still matches, which is the part that matters: it confirms
`#ROM_BASE+$000D64` encodes identically to `#$00000D64` under `-no-opt`, the
encoding hazard KNOWN_ISSUES.md warns about.

### The 32X image must keep the Genesis layout byte for byte

A constraint the design implied but never stated, and it is the kind that bites
silently. Rebased expressions carry the *Genesis* offsets, so inserting a single
byte into a shared source moves everything after it while every literal keeps
naming the old offset. The Genesis build stays byte-identical throughout,
because `ROM_BASE` is zero there and its own literals shift with it.

So 32X-only changes to shared code must be size-neutral, and target-specific
behaviour has to live in the boot half or in work RAM. `$FFFC80-$FFFFFF`
measures free for the latter -- the A5 work area tops out at offset `$C70`
(`$FFFC80`), nothing in the shared sources references above `$FFFC74`, and the
stack grows down from `$FFF000`. About 896 bytes, by reference scan; not yet
confirmed dynamically.

### `DMA_BASE` was the wrong fix, and is dropped

Filed this morning as U-022 and gating U-010; closed the same day as superseded.

The plan was to classify every literal that becomes a DMA source and rebase it
to cartridge offset `$100000 + orig` rather than `ROM_BASE + orig`. It does not
work. A pointer to graphics data is not necessarily used only for DMA -- the
68000 may dereference the same value, and a CPU read needs `$900000`, because
`$100000` is unmapped while `RV = 0`. One value cannot be both, and a literal is
only safe to rebase that way if it feeds DMA and nothing else. That cannot be
established by pattern matching: sources reach `CmdSetupDMA` as `GameCommand`
command 5's third longword, and callers pass them through wrappers
(`VRAMBulkLoad` forwards `$10(a6)` in a register), so it is an interprocedural
dataflow problem.

Translating at the sink removes the question. `ConfigVDPDMA` is the only code in
the game that programs a memory-to-VRAM DMA source -- `ConfigVDPColors` uses
mode `$9780` (VRAM fill) and `ConfigVDPScroll` `$97C0` (VRAM copy, source is a
VRAM address), and neither writes a bus address to registers 21-23. One
conditional subtract there, and every literal rebases uniformly to `ROM_BASE`.

This also collapses U-020 and U-022 into one change, and hands it a hook that
costs nothing: the hand-encoded `dc.w $4EB9,$00FF,$F000` in `ConfigVDPDMA` is
already a six-byte `jsr` into RAM. Repointing it at a larger stub is
size-neutral, and the stub has to be RAM-resident for the `RV` window anyway.

Recording the shape of the mistake, since it is the second of its kind today: in
both cases the instinct was to fix the *data* -- 2,886 literals, then a subset of
them -- when the cheaper fix was one place in the *code*.

### M1 half reached: the 32X cartridge boots and idles

`U-001` closed. `build/aerobiz-ultimate-m1.32x` runs 600 frames under the
instrumented PicoDrive libretro core in
`../32x-playground/tools/libretro-profiling`, with all five acceptance criteria
met: security accepted (`ADEN = 1`, no lock-out), `M_OK`/`S_OK` seen and
cleared, both SH2s out of their release spin and into their idle loops, bank 1
selected in `$A15104`.

M1's other half -- something visible on the 32X layer -- is `U-002` and is not
done, so M1 is not finished.

It did not boot on the first attempt. Three defects, each a wrong belief rather
than a slip:

| Believed | Actually |
|---|---|
| The Sega initial program is 228 bytes, ending at the `jmp (a0)` near `$4C0` | It is **1040 bytes, `$3F0-$7FF`**. That `jmp` is internal: the block has just set `ADEN = 1`, so it relocates itself into the fixed window to keep running |
| `$6BC` is the application entry the donor block jumps to | `$6BC` is the block's own **work-RAM clear loop**. We were assembling MdMain on top of it. The entry is `$800`, reached by fall-through |
| Manual 5.1's "comm 4" means comm register 4, `$A15128` | It is a **byte offset**: the slave's `S_OK` lands at `$A15124`. The 68000 waited forever on a word nothing writes |

The block ends with `bra.b $800` on both paths and carries its verdict in the
carry flag, which is why the manual's own sample listing places `bcs _error`
immediately after `.include icd_mars.prg`. Retail Virtua Racing Deluxe at `$800`
is literally `65 28` -- `bcs.b`. MdMain now opens with that check.

Two build defects surfaced alongside: the M1 cartridge inherited MdMain's
`jmp (GameEntryPoint).l` into a game half it does not carry (now behind a
`MILESTONE1` idle), and the boot half did not depend on its own includes, so
edits to `md_main.asm` did not trigger a rebuild.

### Retail donor no longer required

`U-004`. `tools/extract_mars_init.py` reads the initial program from either a
`.32x` image or an assembly source carrying it as `dc.w` data. marsdev's
`examples/32x-skeleton/md_src/md_start.s` produces byte-identical output to
retail Virtua Racing Deluxe, and a full `make 32x-m1` built that way passes
`U-001` unchanged. The block is still not committed to this repository.

Worth recording precisely, because the manual is often paraphrased wrongly: the
*headers* (vectors, MD/32X header, jump table, MARS user header) are fully
documented and we author them ourselves. The *initial program* is not -- manual
5.2 references it only as a Sega-supplied `icd_mars.prg` that "cannot be
modified or omitted". What changed is the source we read it from, not whether
we need it.

### The M3 DMA gate resolved from the manuals

`U-020` moved from research to implementation; the analysis is
[PORT_ARCHITECTURE.md §2.1](PORT_ARCHITECTURE.md). The conclusion (use `RV = 1`
windows) survived, but the reason it was resting on did not:

- **The DMA source register was never the constraint.** VDP register 23 carries
  seven source bits, not six -- with `DMD1 = 0`, `DMD0` doubles as source
  address bit 23. The manual shows it incidentally (work-RAM DMA from `$FF0000`
  is register 23 = `$7F` "with `DMD0 = 1`",
  genesis-technical-bulletins.md:1492), and Aerobiz's own `ConfigVDPDMA` masks
  with `andi.w #$7f`. `$900000` encodes fine.
- **The adapter's decode is the constraint**, and the evidence is that
  `$A15106` bit 0 is named "RV: ROM to VRAM DMA". A bit whose only job is
  exposing the cartridge for ROM-to-VRAM DMA would be pointless if the high
  windows already worked. Inference, not a manual statement -- flagged as such.
- **One choke point, not four.** The DMA source is centralised through
  `$20(a5)`; a sweep of all shared sources finds three immediate DMA-register
  writes, two of them fill/copy with no memory source.
- Three of the four `RV = 1` constraints are already satisfied by existing code
  (interrupts masked across `ConfigVDPDMA`, trigger already in a work-RAM stub).

This also moved risk *earlier*: a DMA source address is consumed while
`RV = 1`, where the cartridge is visible at its own offsets, so it rebases to
`$100000 + orig`, not `ROM_BASE + orig`. Rewriting one to `ROM_BASE` leaves the
Genesis ROM byte-identical, assembles cleanly, encodes into register 23 without
complaint and silently DMAs garbage. Filed as `U-022`, gating `U-010`/`U-011`.

### Two open questions closed

- **§5.1, security block extent and patchability.** Resolved by `U-001` above,
  and not as framed: nothing about the block is per-cartridge. Retail VR Deluxe
  and marsdev agree byte for byte across all 1040 bytes and diverge only at
  `$800`.
- **§5.4, SH2 C toolchain.** marsdev is installed at `/mnt/data/src/marsdev` and
  carries `sh-elf-gcc` 15.1.0. Nothing needs building.

### M0: fork builds the Genesis ROM byte-identical

Commit `09c4d3f`. Forked from the byte-identical preservation disassembly in
[aerobiz-disasm](../aerobiz-disasm/); `make verify` reports MD5
`1269f44e846a88a2de945de082428b39`. That check runs on every build and is the
regression oracle for every change to shared sources.

Design of record set in [PORT_ARCHITECTURE.md](PORT_ARCHITECTURE.md): the game
image sits at cartridge `$100000` and is selected as bank 1 at `$900000`, so
rebasing collapses to one constant; the boot half lives in the fixed window at
`$880000` so it stays addressable whatever the bank register holds.

### Rebasing cost measured, after an estimate that was wrong by 6x

A grep put the rebasing job at ~330 sites. `tools/scan_rom_refs.py` put it at
**2,886**: 1,990 mechanically safe and 896 needing human review. The grep had
missed the `($imm).l` operand form entirely -- 1,075 sites on its own.

The 896 matter more than the 1,990, and they are the reason for ground rule 8:
an `andi #$0FFF` mask rewritten as `ROM_BASE+$0FFF` leaves the Genesis ROM
byte-identical while breaking only the 32X build. The regression oracle has
exactly one blind spot and that is it.

This is also why the project prefers a re-runnable tool to a number in a
document.
