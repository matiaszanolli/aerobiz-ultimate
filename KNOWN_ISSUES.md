# KNOWN_ISSUES -- Pitfalls, Bugs, and Gotchas

Lessons learned across sessions. **Read this before modifying code.**

---

## 68K Assembly Translation

### Byte-Immediate Junk High Byte
- Instructions like `ORI.B #imm,<ea>`, `ANDI.B`, `CMPI.B`, `SUBI.B`, `ADDI.B`, `EORI.B` use a word-sized immediate extension where only the **low byte** is the actual immediate value
- The high byte is architecturally **undefined** — the original compiler may leave any value there
- Example: ROM has `$0010 $3002` for `ORI.B #$02,(A0)` — the `$30` in the high byte is junk
- vasm always zeroes the high byte, producing `$0010 $0002` — a 1-byte difference
- **Fix:** Use `dc.w $0010,$3002` to preserve the exact original bytes
- `translate_block.py` auto-detects this pattern and emits dc.w when high byte is non-zero

### Indexed Extension Word Junk Bits
- On 68000, the index extension word `(d8,An,Xn)` has bits 10-8 unused (scale factor only exists on 68020+)
- The original compiler may leave non-zero values in these bits
- Example: ROM has `$2A36 $3A3C` for `MOVE.L $3C(A6,D3.L),D5` — bits 10-8 = `010` (junk)
- vasm zeroes bits 10-8, producing `$2A36 $383C` — a 1-byte difference
- **Fix:** Use `dc.w $2A36,$3A3C` to preserve the exact original bytes

### abs.w Suffix Must Be Preserved
- With vasm `-no-opt`, bare addresses like `$01F0` may default to abs.l (6 bytes) instead of abs.w (4 bytes)
- If capstone reports `LEA $1f0.w, A0`, the `.w` suffix MUST be preserved in the vasm output as `($01F0).w`
- Omitting the suffix causes 2 extra bytes per instruction, breaking the ROM layout

### ASL vs LSL -- Different Opcodes
- `ASL.L #4,D0` = $E980 (type bits 4-3 = 00)
- `LSL.L #4,D0` = $E988 (type bits 4-3 = 01)
- Both shift left identically for positive values, but encode differently and have different flag behavior
- **Always verify against ROM bytes**

### BSR.W vs JSR (d16,PC) -- Different Opcodes
- `BSR.W label` = $6100 + displacement
- `JSR label(pc)` = $4EBA + displacement
- **Fix:** Use `jsr label(pc)` syntax in vasm to get the $4EBA encoding

### Indexed vs Displacement Addressing -- Easy to Confuse
- `dc.w $31BC,$0000,$2000` is **NOT** `move.w #$0000,$2000(a0)` (d16,An mode 5)
- It IS `move.w #$0000,(a0,d2.w)` (d8,An,Xn mode 6) -- $2000 is the extension word
- Extension word $2000 = D2.W index register, displacement $00
- **Rule:** When translating dc.w with 3+ words, decode the addressing mode bits before choosing mnemonic syntax

### vasm BSR.W -- Displacement Confirmed CORRECT (No Bug)
**Tested and verified (B-051, 2026-02-26):** `bsr.w Label` generates the correct displacement.
The +2 bug concern from the VRD sister project does NOT apply to this assembler/project.

**Safe to use:** `bsr.w Label` generates byte-identical output verified against MD5
`1269f44e846a88a2de945de082428b39`. All 332 BSR.W calls in the ROM have been symbolized
using `bsr.w Label` syntax. Previously suggested alternatives are still valid but unnecessary:
- `bsr.s label` -- for targets within +/-127 bytes (shorter encoding, fewer bytes)
- `jsr (label,PC)` -- explicit PC-relative JSR (4 bytes vs BSR.W 4 bytes, same size)

### MOVE.W #$0000 vs CLR.W -- Different Encodings
- `MOVE.W #$0000,(addr)` = 6 bytes
- `CLR.W (addr)` = 4 bytes
- They produce the same result but encode differently
- **Never substitute one for the other when byte-matching original ROM**

### m68k_disasm.py Known Bugs
The project disassembler (`tools/m68k_disasm.py`) has these confirmed issues:
- **ASL/LSL:** Shift count field 000 means 8, not 0 (shows wrong count)
- **EXT.L** ($48C0): Confused with MOVEM.L when followed by certain words
- **CLR.W** ($4268): Decoded as CLR.B (size bits 01=word decoded as byte)
- **DIVS.W** ($81Cx): Shown as "OR" (opcode line 8 misidentified)
- **BSR target address:** Computed incorrectly (uses wrong PC base)
- **Multi-word instructions:** Extension words sometimes parsed as new opcodes

**Rule:** Always verify disassembler output against ROM hex bytes for critical code.

---

## Genesis Hardware

### VDP DMA Timing
- DMA transfers must happen during V-Blank or H-Blank on real hardware
- DMA during active display causes VRAM corruption
- Emulators may be more lenient than real hardware -- always assume strict timing
- **Reference:** docs/genesis-software-development-manual.md

### VDP Auto-Increment
- Register $0F controls auto-increment for VRAM/CRAM/VSRAM writes
- Must be set before bulk write operations
- Common value: $02 (increment by 2 for word writes)
- Wrong increment = data scattered across VRAM at wrong addresses

### Z80 Bus Arbitration
- Write $0100 to $A11100 to request bus
- Poll $A11100 until bit 0 is set (bus granted)
- Access Z80 RAM ($A00000-$A01FFF) only while bus is held
- Write $0000 to $A11100 to release
- **Never access Z80 RAM without holding the bus**

### Genesis Memory Map Quick Reference
| Range | Size | Description |
|-------|------|-------------|
| $000000-$3FFFFF | 4MB max | Cartridge ROM |
| $A00000-$A01FFF | 8KB | Z80 RAM (bus required) |
| $A04000-$A04003 | 4B | YM2612 FM sound chip |
| $A10000-$A1001F | 32B | I/O ports (controllers) |
| $A11100-$A11101 | 2B | Z80 bus request |
| $A11200-$A11201 | 2B | Z80 reset |
| $C00000-$C00003 | 4B | VDP data port |
| $C00004-$C00007 | 4B | VDP control port |
| $C00008-$C0000F | 8B | VDP HV counter, PSG |
| $FF0000-$FFFFFF | 64KB | 68K Work RAM |

### SEGA ROM Header
- $000100-$0001FF: Standard Sega Genesis ROM header
- Contains: console name, copyright, game title (domestic/overseas), ROM checksum, I/O support, ROM address range, RAM address range, SRAM info, modem info, region
- Checksum at $00018E covers $000200 to end of ROM

---

## Aerobiz-Specific (to be populated)

### KOEI Game Engine Patterns
(To be documented as the disassembly progresses. KOEI games often share engine patterns
across titles -- look for common structures in save/load, menu systems, AI logic.)

---

## Abandoned Approaches (Don't Re-Try)

| Approach | Why It Failed |
|----------|--------------|
| (none yet) | |

---

# 32X Pitfalls (Aerobiz Ultimate)

Every entry cites `docs/32x-hardware-manual.md`. Add nothing here without a citation.

## Frame buffer: byte writes cannot write zero

Manual 3.3, "DRAM": *"Write speeds are all the same, but 0 cannot be written in
byte access."* A byte write of `$00` to the frame buffer or the overwrite image
is silently dropped and the original pixel is retained. Clearing a pixel to
palette entry 0 must use a **word** write, the Auto Fill registers, or a palette
entry other than 0 for "background".

This is the 32X equivalent of the Genesis "no byte access to VRAM" rule and will
bite exactly the same way: it fails silently and only on real timing.

## Overwrite image treats a zero byte as transparent

Manual 3.3, "Over Write Image": when writing a word to `$860000` (MD) /
`$24020000` (SH2), any half whose byte is `$00` is skipped and the destination
keeps its old value. This is a feature for sprite-style blitting and a trap for
general copies. Use the plain frame buffer aperture for opaque copies.

## Frame buffer must not be touched during a fill or right after a swap

Manual 3.2: after writing FS, access only once `VBLK = 1` or the FS bit has
visibly changed. After an Auto Fill, access only once `FEN = 0`.

## Palette access window

Manual 3.2 / 3.3: the palette is word-access only, and in packed pixel and run
length modes it can only be accessed while `PEN = 1`. Manual 5.3 adds that the
access must complete within 1 us of PEN falling 1 -> 0, and the VDP does not
enforce this -- both reads and writes are simply unreliable if you miss it. In
direct colour mode the palette is always accessible.

## FM bit arbitration is destructive, not cooperative

Manual 3.2.1 / 3.4: whichever side writes FM wins immediately. If the 68000
writes FM while the SH2 is mid-access to the 32X VDP, the SH2's access is
aborted and the result is undefined -- and vice versa. FM must be owned by a
single agreed protocol, not grabbed opportunistically.

## Genesis resolution is constrained while the 32X layer is visible

Manual 3.3: with the 32X layer in any non-blank mode, the Genesis VDP must be at
a matching 320-pixel-wide mode (320x224 or 320x240). H32 (256-pixel) Genesis
modes are legal only with the 32X layer blanked. **Aerobiz's display mode must be
audited against this before the 32X layer is enabled.**

## SH2 instructions and resources that are forbidden

Manual 5.3:

- Do not use `TAS`.
- Do not use `SLEEP` in an application.
- Do not touch the bus state controller (`$FFFFFFE0-$FFFFFFFF`).
- Do not use the watchdog timer for reset.
- Do not touch the standby control register (`$FFFFFE91`).
- The free-running timer (FRT) is not available to the application; it must be
  left at TIER `$01`, OCRA `$0002`, FTCSR `$01`.
- NMI is tied high.
- Never use interrupt levels 15, 13, 11, 9, 7 or 1; always leave at least one
  mask set.

## Master/slave DMA interference

Manual 5.3: if master and slave both run auto-request DMA at once, one crawls
until the other finishes. A CPU that drives PWM, or that touches the VDP inside
an H interrupt, cannot use auto-request DMA at all.

## CMD interrupt behaves differently from the others

Manual 3.2.2: VRES/V/H/PWM interrupts keep asserting until their clear register
is written. CMD is negated instead -- but re-asserts if it is re-enabled after
having been missed. Do not write a CMD handler that assumes the "keeps firing"
behaviour of the others.

## System and VDP registers must be cache-through from the SH2

Manual 3.1 / 3.4: read them at `$2000xxxx`, never `$0000xxxx`. Another processor
or the VDP can change them underneath the cache, and the manual explicitly says
cache cannot be used for these. Only SDRAM should be accessed cached.

## Cartridge ROM is invisible to the SH2 while RV = 1

Manual 3.2.1 / 3.4: with `RV = 1` the SH2 stalls on any cartridge access until
the 68000 clears it. The 68000 needs `RV = 1` for Genesis VDP DMA from ROM, so
these two requirements are in direct conflict. See PORT_ARCHITECTURE.md §5.3 --
this is the port's highest-risk open item.

---

## Emulator and tooling traps (PicoDrive / libretro harness)

Each of these cost real time in the 2026-09-12 session, and each is invisible
until you know it: the wrong answer looks like a plausible finding about the
game rather than a broken measurement.

### Savestates store VRAM, CRAM and work RAM byte-swapped

A logical byte at address `a` is at index `a ^ 1`; a logical word is a
**little-endian** read. Read big-endian, a tilemap renders as convincing
coloured noise, and tile-distribution statistics come out meaningless while
still looking like data.

Cheap check: Genesis CRAM entries are `0000 bbb0 ggg0 rrr0`. Read the first 16
both ways and count how many match the pattern -- it was 16/16 little-endian
against 4/16 big-endian. `tools/extract_map.py` does this correctly.

### Debug reads return zero for the `$A151xx` I/O range

`vrd_debug_read` serves RAM but not 32X system registers, so a counter parked
in a comm register reads as zero -- **indistinguishable from "never called"**.
Put anything you intend to sample from outside in SDRAM (`read master <addr>`)
or work RAM, and validate the read path against a case you know is non-zero
before trusting a zero.

### Any timing change makes the demo diverge

Shifting input by one frame, changing display mode, or changing plane geometry
all send the AI demo down a different path. Two builds are then on **different
screens at the same frame number**, so frame-to-frame comparison is
meaningless. It produced two wrong conclusions in one session, both from
looking at a single frame.

Compare 68000 work RAM, or match screens by content first. Never compare
captured frames across builds by frame number.

One qualified exception: the **first** frame at which two builds disagree is
meaningful even by frame number, because up to that point they are in lockstep
by definition. Use it to find where to look, then stop -- everything after it
may be divergence rather than defect. That is how U-034 stage 1's failure was
located at frame 8250, and it is also why the 432 differing frames after it
were not all evidence of the same fault.

### `$FF0006` is not a usable frame counter

`analysis/RAM_MAP.md` calls it "incremented each MainLoop iteration". In
practice it is cleared and sits at 1 for an entire game. `GAME_PHASE_FLOW.md`
even notes a `clr.w $FF0006` described as dead code. Do not use it as a clock.

### PicoDrive models no SH2 cache and no SDRAM latency

`CCR` (`$FFFFFE92`) appears in `pico/32x/sh2soc.c:16` only as a line in the
address-map comment; nothing reads or acts on it, and there is no memory
latency accounting for SDRAM. So an SH2 timing figure measured under PicoDrive
is close to a raw instruction count.

Real hardware is not: SDRAM reads are 8-word-burst-fixed at 12 clocks per burst
(`docs/32x-hardware-manual.md:897`), and a cache-through read of a single word
pays the whole burst. **Emulated SH2 timings are therefore optimistic, and by an
amount that depends on the access pattern.** Quote them as emulator numbers and
put a hardware item behind anything that matters.

The corollary is a trap: enabling the cache under PicoDrive changes the measured
time by exactly zero. That is evidence about the emulator, not evidence that
the cache was already on.

### A core-side trace produces nothing when the input script is the wrong length

Already recorded below for the frontend's own preconditions, repeated here
because the failure mode is worse than it looks from inside the core.
`VRD_INPUT_SCRIPT` is parsed **before** the core is dlopen'd, so a row-count
mismatch aborts the run with the core never loaded. Anything core-side --
`VRD_VRAM_TRACE`, `VRD_SH2_TIMING` -- then writes no file and prints no error,
which reads as "the feature is broken" rather than "the run never happened".
Check the frontend's own output before debugging a core hook.

### PicoDrive sources are CRLF

`pico/videoport.c` and `pico/pico_int.h` (and others) use CRLF. A Python
`open().read()` / `open('w').write()` round trip silently rewrites them as LF,
which turns a small patch into a whole-file diff. Edit in binary mode, or
convert back before committing, and check `git diff --stat` looks like the
change you made.

### A savestate fixture scopes an equivalence test to what it can reach

Resuming from a savestate is the fast way to compare two builds on a screen
deep in the game, and it silently limits the comparison to the states reachable
*from that point*. A change that breaks an earlier screen then passes, and
passes convincingly: the 64-cell plane experiment (U-034 stage 1) was
**pixel-identical over 30,000 consecutive frames and over 3,001 frames sampled
across a whole 20-year game**, both resumed from a pre-game savestate, and
**differed on 432 of 600 frames** when the same builds were driven from
power-on. The defect was on a setup screen the fixture skipped.

Drive at least one comparison from power-on with `VRD_INPUT_SCRIPT` before
believing an equivalence result. A run that agrees everywhere is the case to
distrust, not the case to report.

### The capture path used to demand 320x224, and Aerobiz is 256x224

Fixed 2026-09-12 in `../32x-playground/tools/libretro-profiling/profiling_frontend.c`,
recorded because it cost this project two measurements a month apart. The video
callback compared `width != 320 || height != 224 || pitch != 640` and counted
anything else as an error with no message. The game runs **H32, 256x224**, so
every Genesis frame was dropped and a capture came back with an empty manifest
and `errors=N` in `video-session.csv`.

Geometry now comes from the core, bounded and with the pitch checked. Two
habits are still worth keeping: **read `video-session.csv` and check `errors`
is 0** before trusting a capture, and remember that a 32X cartridge composites
at **320x224 even when the Genesis build of the same game reports 256x224**, so
32X-versus-Genesis frames cannot be compared pixel for pixel at all. Compare a
32X build against a 32X build.

Use `VRD_VIDEO_DUMP_EVERY` for long runs: a whole-game comparison at every
frame is tens of gigabytes, at every 50th a few hundred megabytes.

### Harness preconditions fail loudly but early

`VRD_INPUT_SCRIPT` must have **exactly** `max_frames` rows, and
`VRD_VIDEO_DUMP_END` must be **strictly less than** `max_frames`. Violate
either and the run aborts before the core starts -- which reads as "the test
produced nothing" rather than "the test never ran".

