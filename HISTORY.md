# Aerobiz Ultimate -- History

What has actually happened, newest first. [ROADMAP.md](ROADMAP.md) is the other
half of this pair: it says what is next, this says what was done and -- more
usefully -- what we believed that turned out to be wrong.

Entries record evidence, not intentions. A claim here should name the file, the
manual section or the tool output that backs it.

---

## 2026-09-09

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
