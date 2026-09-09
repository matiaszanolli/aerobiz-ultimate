# Aerobiz Ultimate

A **Sega 32X port of Aerobiz Supersonic** (KOEI, 1994), built from a complete,
byte-identical Genesis disassembly.

|  |  |
|---|---|
| **Base game** | Aerobiz Supersonic (USA), Sega Genesis / Mega Drive, 1 MB |
| **Target** | Sega 32X, 2 MB cartridge |
| **CPUs** | 68000 @ 7.67 MHz + 2x SH2 @ ~23 MHz |
| **Video** | Genesis VDP (tiles, sprites, UI) + 32X bitmap layer (world map, art) |
| **Audio** | Z80 / YM2612 / PSG + 32X PWM stereo PCM |
| **Upstream** | [aerobiz-disasm](../aerobiz-disasm/) -- the preservation project |

## What this is

Aerobiz Supersonic is a turn-based airline management sim. It is a good game on
slow hardware: the world map redraws at tile granularity, aircraft animate in
tile-sized steps, and the AI pauses noticeably between turns.

Aerobiz Ultimate keeps the game exactly as designed and spends the 32X's extra
silicon on making it *fluid*:

- **World map on the 32X bitmap layer** -- 256 colours from a palette of 32,768,
  great-circle route arcs and per-pixel aircraft motion drawn by the SH2, with
  the Genesis planes keeping UI and text crisply in front.
- **AI and economy on the SH2s** -- quarterly processing, route economics and
  the AI decision tree move off the 68000, so turns resolve without the wait.
- **PWM audio** -- stereo PCM alongside the existing FM driver.
- **High-colour art and transitions** -- title, city and aircraft art, and fades
  and wipes rendered on the 32X layer at full frame rate.

## Building

```bash
make genesis   # byte-identical original Genesis ROM (the regression oracle)
make verify    # confirm it still matches the original ROM's MD5
make 32x-m1    # milestone-1 32X test cartridge (boots the adapter, idles)
make 32x       # the full 32X cartridge
make all       # both targets
```

Requires `vasmm68k_mot` (supplied in `tools/`) and the GNU SH2 binutils
(`sh-elf-as`, `sh-elf-ld`, `sh-elf-objcopy`, `sh-elf-nm`).

Two files you must supply yourself, neither of which is distributable:

| File | Why |
|------|-----|
| `Aerobiz Supersonic (USA).gen` | the game. Needed for `make verify`. |
| any retail `.32x` cartridge image | the Sega initial program / security block is lifted from it at build time. Override the default with `make 32x MARS_DONOR="path/to/game.32x"`. |

## The Genesis build is the safety net

`make verify` must keep reporting an MD5 match. The Genesis target is assembled
from the *same* game sources as the 32X target, with `ROM_BASE` set to 0 instead
of `$900000`. Any change to shared sources that alters a single byte of the
Genesis ROM is a bug in that change.

This is why the Genesis target was kept rather than dropped for a clean 32X-only
tree. It is not documentation; it is a test, and it runs on every build.

Its one blind spot is documented in
[PORT_ARCHITECTURE.md](PORT_ARCHITECTURE.md#rebasing-cost): rewriting a plain
numeric constant as `ROM_BASE+$xxxx` leaves the Genesis build byte-identical
while breaking the 32X build. That class of change needs human review.

## Where to look

| Question | File |
|----------|------|
| How the port is structured, and why | [PORT_ARCHITECTURE.md](PORT_ARCHITECTURE.md) |
| What to work on next | [ROADMAP.md](ROADMAP.md) |
| Progress so far | [HISTORY.md](HISTORY.md) |
| 32X and Genesis pitfalls | [KNOWN_ISSUES.md](KNOWN_ISSUES.md) |
| 32X hardware reference | [docs/32x-hardware-manual.md](docs/32x-hardware-manual.md) |
| SH2 reference | [docs/sh7604-hardware-manual.md](docs/sh7604-hardware-manual.md) |
| Genesis hardware reference | [docs/genesis-software-development-manual.md](docs/genesis-software-development-manual.md) |
| Function reference (inherited) | [analysis/FUNCTION_REFERENCE.md](analysis/FUNCTION_REFERENCE.md) |
| Game phase flow (inherited) | [analysis/GAME_PHASE_FLOW.md](analysis/GAME_PHASE_FLOW.md) |
| RAM and data structures (inherited) | [analysis/RAM_MAP.md](analysis/RAM_MAP.md), [analysis/DATA_STRUCTURES.md](analysis/DATA_STRUCTURES.md) |

## Layout

```
aerobiz-ultimate/
  disasm/
    aerobiz.asm              Genesis target entry     (ROM_BASE = 0)
    ultimate_boot.asm        32X boot half            (linked at $880000)
    ultimate_game.asm        32X game half            (linked at $900000)
    32x/
      mars_header.asm        vectors, MD/32X header, jump table, MARS user header
      md_main.asm            68K side 32X bring-up and exception trampolines
    sh2/
      shared/mars.inc        SH2 side 32X definitions
      master/main.s          SH2 master
      slave/main.s           SH2 slave
      sh2.lds                SDRAM link map
    modules/
      shared/definitions.asm      Genesis hardware equates
      shared/definitions_32x.asm  32X hardware equates
      68k/<category>/*.asm        801 game modules, shared by both targets
    sections/                     game code and data, shared by both targets
  tools/
    extract_mars_init.py     lift the Sega initial program from a donor ROM
    scan_rom_refs.py         inventory ROM address literals for rebasing
  analysis/                  inherited disassembly documentation
  docs/                      Genesis, 32X and SH2 hardware manuals
```

## Status

| Milestone | Description | Status |
|-----------|-------------|--------|
| M0 | Genesis ROM still builds byte-identical | **Done** |
| M1 | 32X ROM boots, SH2s synchronise, layer blank | Cartridge builds; **untested on hardware/emulator** |
| M2 | Rebased Aerobiz reaches the title screen on 32X | Not started -- 1,990 safe + 896 review sites |
| M3 | Full game playable on 32X, 32X layer blank | Not started -- gated on ROM DMA, see below |
| M4 | World map on the 32X layer | Not started |
| M5 | AI and economy on the SH2 | Not started |
| M6 | PWM audio | Not started |
| M7 | High-colour art and transitions | Not started |

**M3 is the real gate.** The Genesis VDP's DMA source register is 22 bits and
cannot reach `$900000`, but Aerobiz's graphics loaders DMA straight from ROM.
Resolving that -- `RV=1` windows, or staging through work RAM -- is the highest
risk item in the project and is the first thing to settle after M1 boots.

## Licence

This repository contains no copyrighted ROM data and no Sega code. You must
supply your own legally obtained Genesis ROM to build, and your own 32X
cartridge image for the initial program. Sources, tooling and documentation are
provided for educational and preservation purposes.
