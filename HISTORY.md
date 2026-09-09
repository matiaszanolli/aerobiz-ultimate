# Aerobiz Ultimate -- History

What has actually happened, newest first. [ROADMAP.md](ROADMAP.md) is the other
half of this pair: it says what is next, this says what was done and -- more
usefully -- what we believed that turned out to be wrong.

Entries record evidence, not intentions. A claim here should name the file, the
manual section or the tool output that backs it.

---

## 2026-09-08

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
