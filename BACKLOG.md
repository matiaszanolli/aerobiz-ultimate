# Aerobiz Ultimate -- Backlog

Task queue for the 32X port. Items are `U-nnn`. The inherited disassembly
backlog (`B-nnn`) lives in the upstream [aerobiz-disasm](../aerobiz-disasm/)
project and is not carried here -- that work is complete.

Milestones are defined in [PORT_ARCHITECTURE.md](PORT_ARCHITECTURE.md#6-milestones).

---

## M1 -- Adapter bring-up

### U-001 -- Verify the milestone-1 cartridge actually boots [OPEN, next]

`make 32x-m1` produces a 2 MB cartridge with a correct header, a verbatim Sega
initial program and a working SH2 image. **None of it has been run.** Load
`build/aerobiz-ultimate-m1.32x` in an emulator and confirm, in order:

1. The 32X boot ROM accepts the security block (no lock-out, no `SQER` in comm0).
2. Master writes `M_OK` to comm0 and slave writes `S_OK` to comm4.
3. Our 68K entry at `$8806BC` runs -- the two comm words get cleared.
4. Both SH2s leave their release spin and reach their idle loops.
5. Bank 1 is selected in `$A15104`.

Use an emulator with 32X debug visibility. Picodrive sources are in
`../32x-playground/third_party/picodrive`; Gens KMod is in
`../32x-playground/Gens_KMod_v0.7.3`.

**Resolves open question PORT_ARCHITECTURE.md §5.1** -- whether the boot ROM
accepts a security block whose hand-off target we did not choose, or whether it
checks fewer bytes than the block's full length. Our approach sidesteps the
question by placing our entry where the donor block already jumps, but that has
not been proven to work.

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

### U-020 -- Resolve Genesis VDP DMA from banked ROM [OPEN, highest risk]

The Genesis VDP DMA source register is 22 bits and cannot address `$900000`.
Aerobiz's graphics loaders (`LoadCompressedGfx`, `LoadScreenGfx`,
`CmdSetupDMA`, `VRAMBulkLoad`) DMA from ROM. Options, in order of preference:

1. `RV = 1` windows around each DMA, which maps the cartridge at `$000000` for
   the duration. Costs SH2 ROM access during the window (manual 3.2.1) -- but
   the SH2 runs from SDRAM, so it may not care. Measure the stall.
2. Stage through work RAM: 68K copies ROM to RAM, DMA from RAM. Costs RAM and
   time; Aerobiz has 64 KB total.
3. Move the graphics the DMA path needs into the fixed window at `$880000`,
   which *is* reachable... verify: the 22-bit source register reaches
   `$000000-$3FFFFF`, so `$880000` is out of range too. Likely a dead end --
   confirm before spending time on it.

**Read `docs/genesis-technical-bulletins.md` on the DMA source register width
before choosing.** This decides whether M3 is a week or a month.

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
