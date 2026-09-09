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

### U-011 -- Classify the 896 "review" literals [OPEN]

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

### U-013 -- Reach the title screen [OPEN, blocked on U-020]

The game boots and runs on 32X. Running the cartridge and the Genesis build in
the same emulator and diffing work RAM from `$FFF010`, they agree to within 17
of 4,080 bytes after 900 frames, and the survivors are per-frame counters and
dispatch flags around `$FFF011-$FFF03C` -- where two runs that are not
cycle-locked would differ anyway, since the 32X spends its first frames in
adapter bring-up.

Getting there needed one fix beyond rebasing: the jump table's slots are
vector-indexed, not packed, so every interrupt was jumping into padding. Work
RAM divergence went from 41 bytes to 2 when that was corrected.

We can now see the screen (U-091), and it is **black**. Every pixel, at every
frame sampled. The Genesis reference at the same frames shows the KOEI intro
and then the title attract sequence.

That is the expected shape of the remaining failure, not a new one: the game
logic runs, and nothing reaches VRAM or CRAM because the graphics loaders DMA
from ROM and the `RV` window is not implemented. A failed palette DMA alone
gives an all-black screen whatever is in VRAM. **Blocked on U-020**, which is
the M3 gate, so this is M3 work rather than M2 work.

---

## M3 -- Full game on 32X, layer blank

### U-020 -- Implement the 32X DMA stub: `RV` window and source translation [OPEN, high risk]

**Design settled from the manuals and the sources; see
[PORT_ARCHITECTURE.md §2.1](PORT_ARCHITECTURE.md). This is implementation plus
one experiment.** It absorbs what was filed separately as U-022.

The source register was never the constraint -- VDP register 23 carries seven
source bits, which the game's own `andi.w #$7f` confirms. The barrier is that
the adapter does not serve `$880000-$9FFFFF` to a VDP-mastered cycle, and the
`RV` bit at `$A15106`, named "ROM to VRAM DMA", exists to solve exactly that.

One routine does the whole job, in free work RAM, reached by repointing the six
bytes of `dc.w $4EB9,$00FF,$F000` in `ConfigVDPDMA` under `ifne ROM_BASE`. That
patch is size-neutral, which it must be.

1. **Experiment first.** Is `$880000-$9FFFFF` still readable by the 68000 while
   `RV = 1`? The manual is silent. Write the answer into §5.3. The design does
   not depend on it -- the stub is RAM-resident either way -- but it decides how
   much else has to move.
2. **Place the stub.** `$FFFC80-$FFFFFF` measures free (~896 bytes): the A5 work
   area tops out at `$FFFC80` and nothing in the shared sources references above
   `$FFFC74`. Confirm dynamically before relying on it. Install from the boot
   half, after the initial program's 64 KB work-RAM clear.
3. **Translate the source.** `if (src & $F00000) == $900000: src -= $800000`,
   then reprogram VDP registers 21-23. Work-RAM sources fail the test, pass
   through untouched, and need no `RV` window -- the same test decides both.
4. **Window, trigger, wait, close.** Raise `RV`, write the staged command word
   from `$42(a5)`/`$44(a5)`, poll DMA-busy, lower `RV`. The poll currently runs
   from ROM at `l_0121c` and must move inside.
5. **Clear `RV` in the reset path.** `VRES` with `RV = 1` prevents restart after
   power-off (docs/32x-technical-info.md:63).
6. **Measure the stall.** The SH2 blocks on cartridge reads for the window.
   Our image runs from SDRAM, so this should be near zero -- confirm it, and
   confirm no SH2 path touches `$22000000` during a window.

Already satisfied, do not re-solve: interrupts are masked across the whole of
`ConfigVDPDMA` (`ori.w #$700, sr`), meeting the "no 68000 interrupts while
`RV = 1`" requirement (docs/32x-technical-info.md:103); and the trigger already
runs from RAM.

Carry this caveat: `$001070`, `$002070` and `$003070` (4 bytes each) are
unreadable while `RV = 1` (docs/32x-technical-info.md:140). They sit in the boot
half, clear of the game image at `$100000`.

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

### U-021 -- Full playthrough on 32X [OPEN]

Scenario select through a completed game, save and load, against the Genesis
build as the behavioural reference.

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
