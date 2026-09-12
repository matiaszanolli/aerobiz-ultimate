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

Gated on U-003 (display mode) and M3.

---

## M5 -- AI and economy on the SH2

### U-040 -- RAM snapshot transport over DREQ FIFO [OPEN]
### U-041 -- Port quarterly processing to the SH2 [OPEN]
### U-042 -- Port the AI decision tree to the SH2 [OPEN]
### U-043 -- Split work across master and slave [OPEN]

Each ported routine keeps its 68K implementation selectable at assembly time so
results can be diffed against the original. Correctness first, speed second --
this code decides the outcome of the game.

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
