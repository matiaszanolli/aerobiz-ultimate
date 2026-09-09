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
