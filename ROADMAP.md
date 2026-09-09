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

### U-003 -- Confirm Aerobiz's Genesis display mode [OPEN]

Manual 3.3 requires the Genesis VDP to be at a 320-pixel-wide mode whenever the
32X layer is not blanked. Audit `SetDisplayMode` and the VDP register init table
at `$0002A0` to establish whether Aerobiz runs H40 or H32, and in which screens.
If any screen is H32, the world map plan in §4.1 needs rework. **Do this before
U-002 grows into real rendering work.**

---

## M2 -- Rebase the game to $900000

### U-010 -- Rewrite the 1,990 "safe" ROM literals [OPEN]

**Gated on U-022.** Not every ROM literal rebases to `ROM_BASE`: DMA source
addresses rebase to `$100000` instead, and nothing in the build catches the
mistake. See [PORT_ARCHITECTURE.md §2.1](PORT_ARCHITECTURE.md#a-second-rebase-constant-dma_base).

`tools/scan_rom_refs.py` classifies them. Rewrite each as `ROM_BASE+$xxxxxx`.
`make verify` must still report an MD5 match afterwards -- that proves no
encoding changed. Do it in reviewable batches, not one commit.

Forms in scope: `($imm).l` operands (1,075), `movea #imm` (831), `dbra` literal
targets (40), `dc.l` ROM pointers (31), `bsr.b` literal targets (12), one
`jmp $xxx(pc)`.

### U-011 -- Classify the 896 "review" literals [OPEN]

`tools/scan_rom_refs.py --list review`. Each is a `move`/`andi`/`addi`/`cmpi`/
`ori`/`mulu`/`subi` immediate that happens to fall in `$000200-$0FFFFF`. Most
are masks, counts and multipliers, not addresses. Classify against
`analysis/DATA_TABLES.md` and `analysis/FUNCTION_REFERENCE.md`.

**The Genesis byte-identical check cannot catch a mistake here.** Rewriting a
constant as `ROM_BASE+$xxxx` leaves the Genesis ROM unchanged and breaks only
the 32X build. Record the verdict and the evidence for each site.

### U-012 -- Get the game half to assemble at $900000 [OPEN]

Gated on U-010. `make 32x` currently fails on out-of-range branches, which is
exactly the unrebased literals showing up. Success is a 2 MB cartridge.

### U-013 -- Reach the title screen [OPEN]

The M2 acceptance test. Expect to find rebasing misses here; each one is a
literal the scanner did not classify or classified wrongly. Feed every finding
back into `tools/scan_rom_refs.py` so the tool gets better rather than the fixes
being one-offs.

---

## M3 -- Full game on 32X, layer blank

### U-020 -- Implement the `RV = 1` DMA window [OPEN, high risk]

**The design question is answered from the manuals; see
[PORT_ARCHITECTURE.md §2.1](PORT_ARCHITECTURE.md#21-genesis-vdp-dma-from-the-banked-game-image).
This item is now implementation plus one experiment, not research.**

Summary of what changed: the source register was never the constraint -- VDP
register 23 carries seven source bits (bits 23-17; `DMD0` doubles as bit 23),
which the game's own `andi.w #$7f` in `ConfigVDPDMA` confirms. The barrier is
that the adapter does not serve `$880000-$9FFFFF` to a VDP-mastered cycle, and
the `RV` bit at `$A15106` -- named "ROM to VRAM DMA" -- exists to solve exactly
this. Option 3 (relocate graphics to the fixed window) is dead for the same
reason, not for the range reason originally given.

Implementation, in order:

1. **Experiment first.** Determine whether `$880000-$9FFFFF` stays readable by
   the 68000 while `RV = 1`. The manual is silent. Write the answer into §5.3.
   The design does not depend on it -- the window runs from work RAM either way
   -- but it decides how much has to move.
2. **Relocate and grow the work-RAM stub.** Today: 10 bytes at `$FFF000`,
   boot-copied from `$000362`. Needed: set `RV = 1`, trigger, poll DMA-busy,
   clear `RV = 0`, all resident in RAM. Only six spare bytes before the A5 base
   at `$FFF010`, so pick a new home and make the hand-encoded
   `dc.w $4EB9,$00FF,$F000` in `ConfigVDPDMA` a dual-build divergence.
3. **Move the busy-wait inside the window.** The `l_0121c` poll after the
   `jsr $FFF000` currently runs from ROM. It must not.
4. **Clear `RV` in the reset path.** `VRES` with `RV = 1` prevents restart after
   power-off (docs/32x-technical-info.md:63).
5. **Measure the stall.** The SH2 blocks on cartridge reads for the window's
   duration. Our SH2 image runs from SDRAM, so the cost should be near zero --
   confirm it, and confirm no SH2 code path touches `$22000000` during a window.

Already satisfied, do not re-solve: interrupts are masked for the whole of
`ConfigVDPDMA` (`ori.w #$700, sr`), which meets the "no 68000 interrupts while
`RV = 1`" requirement (docs/32x-technical-info.md:103); and the DMA trigger
already runs from RAM.

One caveat to carry: `$001070`, `$002070` and `$003070` (4 bytes each) are
unreadable while `RV = 1` (docs/32x-technical-info.md:140). They sit in the boot
half, clear of the game image at `$100000`. Keep DMA-sourced data off them.

### U-022 -- Teach `scan_rom_refs.py` the `DMA_BASE` class [OPEN, blocks U-010]

A DMA source address is consumed while `RV = 1`, where the cartridge is visible
at its own offsets. It must be rebased to `$100000 + orig`, **not**
`ROM_BASE + orig`. Rewriting one to `ROM_BASE` keeps the Genesis ROM
byte-identical, assembles without complaint, encodes into register 23 cleanly,
and silently DMAs garbage -- rule 8's blind spot with no compensating signal.

The source is centralised, which makes this tractable: `CmdSetupDMA` stores it
to `$20(a5)` from the command block at `$16(a6)`. Trace back to every site that
builds such a block and classify those literals as `DMA_BASE` before U-010
rewrites anything.

**U-010 and U-011 must not start until this lands.**

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

### U-091 -- Emulator harness for automated boot tests [OPEN]

U-001 is manual. A headless run that asserts on comm-port state would make every
subsequent milestone cheaper to verify.
