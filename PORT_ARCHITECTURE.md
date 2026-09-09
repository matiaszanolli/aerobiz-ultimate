# Aerobiz Ultimate -- 32X Port Architecture

Design document for porting *Aerobiz Supersonic* (Sega Genesis, KOEI 1994) to the
Sega 32X. Derived from the byte-identical Genesis disassembly in
[aerobiz-disasm](../aerobiz-disasm/) and the Sega 32X hardware manuals in `docs/`.

**Every address and register in this document is cited to a manual section.**
Nothing here is inferred. See Ground Rule 1 in [CLAUDE.md](CLAUDE.md).

---

## 1. What the 32X actually gives us

The 32X is *additive*. It does not replace the Genesis. After boot:

- The 68000 keeps running and keeps driving the Genesis VDP (planes A/B, sprites).
- Two SH2s @ ~23 MHz run from 256 KB of SDRAM, with 4 KB cache each.
- A 32X VDP composites a **bitmap layer** either in front of or behind the
  Genesis layer, per-pixel, via the palette priority bit.
- PWM gives 2-channel 11-bit PCM audio alongside the YM2612/PSG.

Sources: `docs/32x-hardware-manual.md` ch. 1-2.

Consequences for this port:

| We keep | We add |
|---------|--------|
| All 68K game logic, menus, text, save format | SH2 co-processing for AI + economy |
| Genesis VDP planes for UI chrome and text | 32X bitmap layer for the world map and art |
| Z80 + YM2612 driver (initially) | PWM streaming audio |

The Genesis VDP is still the *only* source of hardware text/tiles -- the 32X layer
has **no sprites and no tilemap**, only a linear framebuffer with a hardware
horizontal shift. UI text stays on the Genesis side.

---

## 2. The memory-map problem (and its solution)

### The problem

On a 32X cartridge with the adapter enabled (`ADEN = 1`), the 68000 no longer sees
the cartridge at `$000000`. Per `docs/32x-hardware-manual.md` §3.5:

| 68000 address | Cartridge ROM offset |
|---------------|----------------------|
| `$880000-$8FFFFF` | `$000000-$07FFFF` (fixed, 512 KB) |
| `$900000-$9FFFFF` | one of four 1 MB banks, selected by the Bank Set Register |

Aerobiz is 1 MB and addresses its own code and data at `$000000-$0FFFFF`
throughout. Both facts have to be reconciled:

1. The game does not fit in the 512 KB fixed window.
2. Every absolute reference in the game is off by the new base.

Virtua Racing Deluxe confirms the real-world pattern -- its exception vectors all
read `$00880832`, i.e. its 68K code is linked at `$88xxxx`.

### The solution: bank 1 hosts the game, unmodified and contiguous

The Bank Set Register at **`$A15104`** (`docs/32x-hardware-manual.md` §3.2.1)
selects which 1 MB of cartridge appears at `$900000`:

| BK1 | BK0 | `$900000-$9FFFFF` shows cartridge |
|-----|-----|-----------------------------------|
| 0 | 0 | `$000000-$0FFFFF` (initial value) |
| 0 | 1 | `$100000-$1FFFFF` |
| 1 | 0 | `$200000-$2FFFFF` |
| 1 | 1 | `$300000-$3FFFFF` |

So we place the **entire 1 MB Aerobiz image at cartridge offset `$100000`** and
select bank 1. The whole game is then linearly addressable at `$900000-$9FFFFF`
with no split, no overlay collision with the 32X header, and no per-access banking.

Rebasing the game is therefore a single constant: **`+$900000`**.

### 2.1 Genesis VDP DMA from the banked game image

Aerobiz's graphics loaders DMA straight from ROM, and the game image lives at
`$900000`. Two separate questions were tangled together here; they have
different answers.

**The DMA source register is not the problem.** It is commonly described as 22
bits. It is not. VDP register 21 holds source bits 8-1, register 22 holds bits
16-9, and register 23 holds bits 23-17 -- seven bits, because when `DMD1 = 0`
(memory-to-VRAM) the `DMD0` bit doubles as source address bit 23. The manual
shows this directly: work-RAM-to-VRAM DMA, whose source is `$FF0000`, is
specified as register 23 = `$7F` with "`DMD0 = 1`"
(genesis-technical-bulletins.md:1492) -- `DMD0` is set precisely because
`$FF0000` has bit 23 set. Aerobiz's own `ConfigVDPDMA` agrees: it masks the
computed register-23 value with `andi.w #$7f`
([ConfigVDPDMA.asm:46](disasm/modules/68k/vdp/ConfigVDPDMA.asm#L46)), keeping
seven bits, not six. So the register encodes `$900000` perfectly well
(`$900000 >> 1 = $480000` -> register 23 = `$48`, `DMD1 = 0`).

**The adapter's address decode is the problem.** The reason a VDP-mastered DMA
cannot fetch from `$880000-$9FFFFF` is not encoding but that the 32X does not
serve those windows to the VDP. The manual never states this outright, but the
hardware carries its own proof: bit 0 of the DREQ control register at
`$A15106` is named **"RV: ROM to VRAM DMA"**, and setting it maps the cartridge
into `$000100-$3FFFFF` (32x-hardware-manual.md:237, 432-436). A dedicated bit
whose only purpose is to make the cartridge visible for ROM-to-VRAM DMA would
be pointless if the high windows already worked. Treat the decode claim as a
strong inference to be confirmed by U-020, not as a manual citation.

**Consequence: `RV = 1` windows are the intended mechanism, not a workaround.**
With `RV = 1` the cartridge appears at its own offsets, so the game image at
cartridge `$100000` is DMA-able at `$100000-$1FFFFF` -- comfortably inside the
source register's reach either way.

Four constraints follow, three of them already satisfied by the existing code:

| Constraint | Source | Status |
|---|---|---|
| All 68000 interrupts prohibited while `RV = 1` | 32x-technical-info.md:103 | Already met -- `ConfigVDPDMA` opens with `ori.w #$700, sr` |
| DMA trigger must not execute from cartridge | inferred from :237-238 | Already met -- the trigger is a boot-copied stub at `$FFF000` |
| SH2 cartridge reads stall until `RV = 0` | 32x-hardware-manual.md:281 | Harmless -- the SH2 image runs from SDRAM; it must simply not touch `$22000000` during a window |
| 12 bytes unreadable while `RV = 1`: `$001070`, `$002070`, `$003070` (4 each) | 32x-technical-info.md:140 | Falls in the boot half, not the game image at `$100000`. Keep DMA-sourced data off those offsets |

`VRES` while `RV = 1` prevents restart after power-off
(32x-technical-info.md:63) -- the reset handler must check and clear `RV`.

**One choke point, not four.** The backlog named four loaders, but the DMA
source is centralised: `CmdSetupDMA` stores it to `$20(a5)` from the command
block at `$16(a6)`, and `ConfigVDPDMA` is the only code that programs registers
21-23 from it. A grep for immediate DMA-register writes across all shared
sources finds three, two of which are fill/copy modes with no memory source.
The `RV` window therefore has exactly one implementation site.

The work-RAM stub must grow: today it is 10 bytes (two staged control-port
writes plus `rts`, boot-copied from `$000362`), but the DMA-busy poll that
follows the `jsr $FFF000` currently executes from ROM and has to move inside
the window. `$FFF000-$FFF00F` has only six spare bytes before the A5 base at
`$FFF010`, so the 32X build needs a relocated, larger stub -- a dual-build
divergence, since moving it changes the hand-encoded `dc.w $4EB9,$00FF,$F000`
in shared code.

### A second rebase constant: `DMA_BASE`

This changes M2, not just M3. A DMA source address is consumed under `RV = 1`,
where the cartridge is visible at its own offsets -- so it must be rebased to
**cartridge offset `$100000 + orig`**, not `ROM_BASE + orig` (`$900000`). Two
different constants for what looks like one kind of literal.

This is the rule-8 blind spot in its sharpest form: a DMA source rewritten to
`ROM_BASE` leaves the Genesis ROM byte-identical, assembles cleanly, encodes
into register 23 without complaint, and silently DMAs garbage. `make verify`
cannot see it and neither can the assembler. `tools/scan_rom_refs.py` does not
model this class yet; U-010 and U-011 must not run until it does.

### Cartridge layout

```
cart $000000-$0000FF   68K exception vectors            -> also $880000 (fixed window)
cart $000100-$0001FF   MD / 32X ROM header ("SEGA 32X")
cart $000200-$0003BF   68K jump table (6-byte JMPs)     (32X convention, §3.1)
cart $0003C0-$0003EF   MARS user header (SH2 load spec) (§5.1)
cart $0003F0-$0004D3   Sega initial program + security  (§5.2, verbatim, not in git)
cart $000500-$00FFFF   Aerobiz Ultimate 68K glue        -> $880500  (always mapped)
cart $010000-$07FFFF   SH2 program image + new assets   -> $890000  (always mapped)
cart $080000-$0FFFFF   spare (reachable via bank 0)
cart $100000-$1FFFFF   Aerobiz game image, org $900000  -> bank 1
```

Total ROM: 2 MB. The glue and SH2 image live inside the *fixed* window on purpose
-- they stay addressable no matter which bank is selected.

### Rebasing cost (measured by `tools/scan_rom_refs.py`)

Because the disassembly is complete, all control flow between functions is
already symbolic and relocates for free. What does not relocate is every place
a ROM address appears as a bare literal:

| Reference kind | Count | Class |
|----------------|-------|-------|
| `jsr` / `bsr.w` / `jsr (d16,PC)` call sites | 3,696 | already labels -- relocate for free |
| Local `bra.s` / `beq.s` and other PC-relative branches | all | position independent |
| `$00FFxxxx` RAM, `$00Axxxxx` I/O, `$00Cxxxxx` VDP | many | unchanged on 32X |
| `($000xxxxx).l` absolute-long operands | 1,075 | safe |
| `movea #imm` ROM immediates | 831 | safe |
| `dbra dN,$xxxx` literal targets | 40 | safe |
| `dc.l $000xxxxx` pointers in data tables | 31 | safe |
| `bsr.b $xxxx` literal targets | 12 | safe |
| `jmp $xxx(pc)` literal target | 1 | safe |
| **safe subtotal** | **1,990** | |
| `move #imm` in ROM range | 414 | review |
| `andi #imm` in ROM range | 253 | review |
| `addi #imm` in ROM range | 122 | review |
| `cmpi` / `ori` / `mulu` / `subi` `#imm` | 107 | review |
| **review subtotal** | **896** | |
| **Total literal sites** | **2,886** | |

Run `python3 tools/scan_rom_refs.py` to regenerate this table, and
`tools/scan_rom_refs.py --list review` to walk the ambiguous set.

An earlier estimate in this document said ~330. That was wrong: it counted only
`movea.l #` immediates and `dc.l` pointers and missed the `($x).l` operand and
bare-branch forms entirely. The numbers above are measured, not estimated.

The mechanical fix is to rewrite each site as `ROM_BASE+$xxxxxx`, which
collapses back to the original literal when `ROM_BASE` is 0. The byte-identical
Genesis build then proves the rewrite changed no encodings.

**But that check does not catch every error.** A literal like `#$00001000` may
be a ROM address or may be a plain count; rewriting a count to `ROM_BASE+$1000`
leaves the Genesis build byte-identical while silently breaking the 32X build.
So the rewrite is split, and the tool enforces the split:

- **safe** -- the operand is an address by construction: an address-register
  load, `pea`/`lea`, any `($imm).l` operand, or a branch/loop target. These can
  be rewritten mechanically.
- **review** -- the literal sits where either an address or a plain number is
  plausible. Most of these are almost certainly *not* addresses: an
  `andi #$0FFF` is a bit mask and a `mulu #$0258` is a multiplier that merely
  happen to fall inside the ROM's numeric range. Each must be classified by
  hand against `analysis/DATA_TABLES.md` and `analysis/FUNCTION_REFERENCE.md`.
  Rewriting one of these wrongly is invisible to the Genesis check.

This split is the substance of milestone M2.

---

## 3. Dual-target build

The tree builds **two** ROMs from **one** set of game sources:

| Target | Output | Purpose |
|--------|--------|---------|
| `make genesis` | `build/aerobiz.bin` | Byte-identical original. **Regression oracle.** |
| `make 32x` | `build/aerobiz-ultimate.32x` | The port. |

`make verify` must keep reporting an MD5 match against the original ROM.
Any change to shared game sources that breaks the Genesis build is a bug in that
change -- this is the project's primary correctness guarantee and it is not
negotiable. It is why the "keep the Genesis build" option was chosen over a clean
break.

Mechanism: `ROM_BASE` is `$000000` for the Genesis target and `$900000` for the
32X target. Shared sources reference ROM addresses through `ROM_BASE`, never as
bare literals.

---

## 4. Feature architecture

### 4.1 World map on the 32X layer

The world map is the centrepiece of Aerobiz and the best fit for the 32X bitmap
layer. Today it is Genesis tiles, so routes are drawn at tile granularity and
aircraft animate in tile-sized steps (`AnimateFlightPaths`, `DrawRouteLines`,
`DrawRoutePair` in `disasm/modules/68k/graphics/`).

Target design:

- Map rendered into the 32X framebuffer in **packed-pixel mode** (8 bpp, 256
  colours from a 32,768-colour palette). Packed pixel is chosen over direct
  colour because 320x224 direct colour needs 143,360 bytes and the framebuffer is
  only 128 KB (1 Mbit) per page -- packed pixel fits at 71,680 bytes and leaves
  room for double buffering.
- SH2 master draws great-circle route arcs and per-pixel aircraft positions.
- Genesis planes keep all UI chrome, panels and text **in front** of the 32X layer
  via the palette priority bit.
- Hardware horizontal scroll (Screen Shift Control) for map panning.

### 4.2 AI and economy on the SH2

The between-turn pause is the least "fluid" part of the game. `GameLogic1`
(`$0213B6`) and `GameLogic2` (`$02947A`) run turn/route processing and the AI
decision tree on a 7.67 MHz 68000. Moving that to a 23 MHz SH2 -- ideally
split across master and slave -- is the largest real responsiveness win.

Approach: the 68K ships a snapshot of the relevant RAM tables to SDRAM via DREQ
FIFO, raises a command interrupt, and polls a communication port while continuing
to render. The SH2 writes results back and the 68K applies them. The existing
documentation in `analysis/DATA_STRUCTURES.md` and `analysis/RAM_MAP.md` gives
the exact table layouts this needs.

This is deliberately *incremental*: each offloaded routine keeps its 68K
implementation, selectable at assembly time, so results can be diffed against
the original for correctness.

### 4.3 PWM audio

Self-contained and low-risk to game logic. Master or slave SH2 streams PCM from
ROM to the PWM FIFO via DMA channel 1. Note the manual's restriction (§5.3): a
CPU that drives PWM cannot also use auto-request DMA.

### 4.4 High-colour art and transitions

Title screens, city art, aircraft art and cutscenes rendered on the 32X layer in
direct colour or packed pixel. Fades and wipes (`FadePalette`, `DiagonalWipe`,
`AnimateScrollWipe`) become 32X palette or framebuffer operations at full frame
rate instead of Genesis CRAM tricks.

---

## 5. Known unknowns (to be resolved empirically, not guessed)

1. ~~**Security block extent and patchability.**~~ **Resolved by U-001.** The
   premise was wrong twice over. The block is **1040 bytes, `$3F0-$7FF`**, and
   the `lea $000006BC,a0 / adda.l #$00880000,a0 / jmp (a0)` near `$4C0` is not a
   game-specific hand-off at all -- it is internal to the block, which has just
   set `ADEN = 1` and so must relocate itself into the fixed window to keep
   going; `$6BC` is its own work-RAM clear loop. The block ends with `bra.b
   $800` on both paths, carrying its verdict in the carry flag, and **`$800` is
   the application entry point**, whose first instruction must be the `bcs` the
   manual's own sample listing shows. Nothing about it is per-cartridge:
   retail Virtua Racing Deluxe and marsdev's in-source copy agree byte for byte
   across all 1040 bytes and diverge only at `$800`.
2. **Whether `RV = 1` can be held permanently** as an alternative to rebasing. It
   would map the cart at `$000000-$3FFFFF` like a plain Genesis and require zero
   68K changes, but it blocks all SH2 cartridge access. Worth one experiment;
   not the baseline plan.
3. **Genesis VDP DMA source under 32X.** *Largely resolved from the manuals --
   see §2.1. The conclusion (use `RV = 1` windows) stands, but the stated reason
   was wrong: the source register is not the constraint.* What remains genuinely
   unknown is narrow: **is `$880000-$9FFFFF` still readable by the 68000 while
   `RV = 1`?** The manual states what appears at `$000100-$3FFFFF` when `RV = 1`
   (32x-hardware-manual.md:237) and what `$880000-$9FFFFF` holds when `RV = 0`
   (:238), but never says whether the high windows survive an `RV = 1` window.
   We design as if they do not -- the whole window runs from work RAM -- so the
   answer only decides whether that is necessary, not whether the plan works.
4. ~~**SH2 C toolchain.**~~ **Resolved.** marsdev is installed at
   `/mnt/data/src/marsdev` and carries `sh-elf-gcc` 15.1.0 at
   `mars/sh-elf/bin/sh-elf-gcc`. Nothing needs building; the SH2 side can move
   to C whenever it is worth doing.

---

## 6. Milestones

| # | Milestone | Proves |
|---|-----------|--------|
| M0 | Fork builds the Genesis ROM byte-identical | Nothing broken |
| M1 | 32X ROM boots, adapter enabled, SH2s report `M_OK`/`S_OK`, blue screen on the 32X layer | Header, security, SH2 boot |
| M2 | Rebased Aerobiz runs to the title screen on 32X | Rebasing correct |
| M3 | Full game playable on 32X, 32X layer blank | Item 5.3 resolved -- the real gate |
| M4 | World map on the 32X layer | Flagship visual |
| M5 | AI/economy offloaded to SH2 | Flagship responsiveness |
| M6 | PWM audio | Flagship audio |
| M7 | High-colour art and transitions | Polish |

M3 is the gate. Everything after it is additive; everything before it is
plumbing.
