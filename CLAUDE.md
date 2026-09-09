# CLAUDE.md

Agent briefing for **Aerobiz Ultimate** -- a Sega 32X port of Aerobiz Supersonic,
forked from the byte-identical Genesis disassembly in
[aerobiz-disasm](../aerobiz-disasm/).

**Last Updated**: September 2026

Read [PORT_ARCHITECTURE.md](PORT_ARCHITECTURE.md) before touching anything. It
is the design of record: memory map, dual-build mechanism, feature architecture,
and the open questions that must not be guessed at.

## What changed from the upstream project

Upstream is a *preservation* project: its goal was a byte-identical rebuild and
it reached it. This is a *modification* project. The disassembly work is done
and inherited; do not redo it.

The one inherited rule that still binds absolutely: **the Genesis ROM must stay
byte-identical.** `make verify` is a test that runs on every build. It is how we
know a change to shared game sources did not break the game.

## Build & Test

```bash
make genesis   # byte-identical Genesis ROM -- the regression oracle
make verify    # MUST report an MD5 match; a mismatch is a bug in your change
make sh2       # SH2 image only
make 32x-m1    # milestone-1 32X cartridge: boots the adapter and idles
make 32x       # full 32X cartridge
make clean
```

`make verify` after every change to anything under `disasm/sections/` or
`disasm/modules/68k/`. No exceptions.

One non-distributable input you must supply: the Genesis ROM as
`Aerobiz Supersonic (USA).gen`.

The Sega initial program at `$3F0` is also not in git, but it does **not**
require a retail cartridge: `tools/extract_mars_init.py` reads it either from a
`.32x` image or from an assembly source carrying it as `dc.w` data, such as
marsdev's `examples/32x-skeleton/md_src/md_start.s`. Both produce the same 1040
bytes. Override with `make 32x MARS_DONOR="<path>"`.

## Ground Rules -- STRICTLY ENFORCED

1. **Do Not Guess.** Cite `docs/` for every hardware claim. The 32X manuals are
   `docs/32x-hardware-manual.md` (+ supplement), `docs/sh7604-hardware-manual.md`
   and `docs/sh1-sh2-cpu-core-architecture.md`. If the manual does not say it,
   it is an experiment to run, not a fact to assert. PORT_ARCHITECTURE.md §5
   lists the known unknowns -- add to it rather than papering over one.
2. **Measure, don't estimate.** `tools/scan_rom_refs.py` exists because an
   estimate in this project was already wrong by 6x. Numbers in docs should come
   from a tool that can be re-run.
3. **Understand Before Modifying.** Never patch `dc.w` without understanding it.
4. **Proper Assembly.** Modify assembly source, not binaries. See
   [KNOWN_ISSUES.md](KNOWN_ISSUES.md) for vasm encoding pitfalls -- several will
   silently produce wrong bytes.
5. **Clean Commits.** No stale comments, no partial changes. Revert completely
   if something does not work.
6. **Verify Changes.** `make clean && make all`, then `make verify`.
7. **DRY.** Fix in place, never duplicate a file. Use branches for experiments.
8. **The Genesis check has a blind spot.** Rewriting a numeric constant as
   `ROM_BASE+$xxxx` keeps the Genesis ROM byte-identical while breaking the 32X
   build. For the "review" class in PORT_ARCHITECTURE.md, record the evidence
   for each decision.
9. **VDP Safety (Genesis).** DMA during V-Blank only. Set up registers before
   issuing commands. Auto-increment must be correct before bulk writes.
10. **VDP Safety (32X).** `FM` arbitration is destructive, not cooperative.
    Frame buffer byte writes cannot write zero. The palette has a 1 us access
    window. See the 32X section of KNOWN_ISSUES.md -- read it before writing any
    32X VDP code.
11. **SH2 restrictions.** No `TAS`, no `SLEEP`, no bus state controller, no
    watchdog reset, no standby register, FRT is off limits, and at least one
    interrupt mask must always be set. Manual 5.3.
12. **Z80 Bus Arbitration.** Request the bus at `$A11100` and wait for grant.
13. **Memory Boundaries.** Check the map before assuming an address is valid.

## Memory maps

### 68000, with the adapter enabled (ADEN = 1)

| Range | Contents |
|-------|----------|
| `$000000-$0000FF` | 32X BIOS vector ROM |
| `$840000-$85FFFF` | 32X frame buffer (needs `FM = 0`) |
| `$860000-$87FFFF` | 32X overwrite image |
| `$880000-$8FFFFF` | cartridge `$000000-$07FFFF`, fixed -- header, security, glue, SH2 image |
| `$900000-$9FFFFF` | cartridge, 1 MB bank via `$A15104` -- **bank 1 holds the game** |
| `$A00000-$A01FFF` | Z80 RAM (bus request required) |
| `$A10000-$A1001F` | Genesis I/O |
| `$A15100-$A1513F` | 32X system registers |
| `$A15180-$A1518F` | 32X VDP registers |
| `$A15200-$A153FF` | 32X palette (word access only) |
| `$C00000-$C00008` | Genesis VDP |
| `$FF0000-$FFFFFF` | 68K work RAM (64 KB) |

### SH2 (cache-through; use `$06000000` for cached SDRAM code)

| Range | Contents |
|-------|----------|
| `$20004000-$2000403F` | system registers |
| `$20004100-$2000410F` | 32X VDP registers |
| `$20004200-$200043FF` | palette |
| `$22000000` | cartridge ROM (unreadable while `RV = 1`) |
| `$24000000` | frame buffer (line table then pixel data) |
| `$24020000` | overwrite image (zero bytes are skipped) |
| `$26000000` | SDRAM, 256 KB |

System and VDP registers **must** be accessed cache-through. Only SDRAM is
cached. Manual 3.4.

## Cartridge layout

```
$000000  68K vectors            -> trampolines at $880206+
$000100  MD / 32X header ("SEGA 32X")
$000200  68K jump table
$0003C0  MARS user header (SH2 load parameters)
$0003F0  Sega initial program + security -- 1040 bytes, verbatim, not in git
$000800  MdMain: 68K 32X bring-up          (fixed: the block falls through here)
$010000  SH2 program image                 (copied to SDRAM by the boot ROM)
$100000  Aerobiz game image, linked $900000 (bank 1)
```

## Source layout

| Path | Purpose |
|------|---------|
| `disasm/aerobiz.asm` | Genesis target entry, `ROM_BASE = 0` |
| `disasm/ultimate_boot.asm` | 32X boot half, linked `$880000` |
| `disasm/ultimate_game.asm` | 32X game half, linked `$900000` |
| `disasm/32x/mars_header.asm` | vectors, header, jump table, MARS user header |
| `disasm/32x/md_main.asm` | 68K bring-up and exception trampolines |
| `disasm/sh2/` | SH2 master, slave, shared definitions, link map |
| `disasm/modules/shared/definitions_32x.asm` | 32X equates, each cited to a manual section |
| `disasm/modules/68k/<category>/` | 801 game modules, **shared by both targets** |
| `disasm/sections/` | game code and data, **shared by both targets** |

Anything under `modules/68k/` or `sections/` is shared. Changing it affects both
ROMs, and `make verify` is what tells you whether that was intended.

## Tools

| Tool | Purpose |
|------|---------|
| `tools/extract_mars_init.py` | lift the Sega initial program from a donor 32X ROM |
| `tools/scan_rom_refs.py` | inventory and classify ROM address literals for rebasing |
| `tools/disasm.py` | capstone disassembler: `pyenv exec python3 tools/disasm.py <start> <end>` |
| `tools/m68k_disasm.py` | older disassembler; **has known decoding bugs**, see KNOWN_ISSUES.md |

## Where to look

| Question | File |
|----------|------|
| How the port works and why | [PORT_ARCHITECTURE.md](PORT_ARCHITECTURE.md) |
| What to work on next | [BACKLOG.md](BACKLOG.md) |
| Pitfalls, Genesis and 32X | [KNOWN_ISSUES.md](KNOWN_ISSUES.md) |
| 32X hardware | [docs/32x-hardware-manual.md](docs/32x-hardware-manual.md) |
| SH2 | [docs/sh7604-hardware-manual.md](docs/sh7604-hardware-manual.md) |
| Genesis hardware | [docs/genesis-software-development-manual.md](docs/genesis-software-development-manual.md) |
| 68K instruction set | [docs/motorola-68000-programmers-reference.md](docs/motorola-68000-programmers-reference.md) |
| Function reference | [analysis/FUNCTION_REFERENCE.md](analysis/FUNCTION_REFERENCE.md) |
| Game phase flow | [analysis/GAME_PHASE_FLOW.md](analysis/GAME_PHASE_FLOW.md) |
| RAM map | [analysis/RAM_MAP.md](analysis/RAM_MAP.md) |
| Data structures | [analysis/DATA_STRUCTURES.md](analysis/DATA_STRUCTURES.md) |
| ROM data tables | [analysis/DATA_TABLES.md](analysis/DATA_TABLES.md) |
