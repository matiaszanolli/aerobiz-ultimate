#!/usr/bin/env python3
"""Extract the Sega 32X initial program / security block from a retail cartridge.

The block at cartridge $0003F0 is Sega copyright, so it is not stored in this
repository.  It is lifted at build time from a retail 32X ROM the user supplies.

docs/32x-hardware-manual.md section 5.2:

    "The Initial program must begin from the start of the program (address
     3F0h) without change.  The Boot ROM built into 32X confirms that the
     Initial program is provided here.  When contents do not match, 32X becomes
     locked and access cannot be done from the Mega Drive side."

Extent
------
The block runs $0003F0-$0007FF, 1040 bytes, and the application entry point is
$000800 immediately after it.  The block does not "jump" to the application: it
ends with `bra.b $800` on both its success and failure paths, having set the
carry flag to report the result.  That is why the manual's own sample listing
(docs/32x-hardware-manual.md, "Included in the Initial Program") reads

    .include icd_mars.prg   ; Sega Designation - Initial Program & Security
    bcs     _error()        ; if cs=1 then ID error or Self check error

-- the `bcs` is the first application instruction, at $800.

Measured, not assumed: retail Virtua Racing Deluxe (USA) and the marsdev
skeleton's in-source copy of the block agree byte for byte across all 1040
bytes of $3F0-$7FF and diverge at $800, where each cartridge's own `bcs` error
branch begins.

Note that the `lea $6BC,a0 / adda.l #$880000,a0 / jmp (a0)` sequence near $4C0
is NOT a hand-off to the application.  It is internal to the block: having just
set ADEN = 1, the cartridge is no longer visible at $000000, so the block
relocates itself into the fixed window to continue.  $6BC is the block's own
work-RAM clear loop.  An earlier version of this tool mistook that jump for the
application hand-off, truncated the block to 228 bytes and placed the
application at $6BC -- on top of the block.

Sources
-------
Two kinds of source are accepted, and they produce identical bytes:

  * a retail 32X cartridge image (`.32x`), from which $3F0-$7FF is sliced; or
  * an assembly source file carrying the block as `dc.w`/`.word` data, such as
    marsdev's `examples/32x-skeleton/md_src/md_start.s`.

The second removes any need for a retail ROM.  Point MARS_DONOR at it:

    make 32x-m1 MARS_DONOR="$MARSDEV/examples/32x-skeleton/md_src/md_start.s"

Usage:
    extract_mars_init.py <donor.32x|donor.s> <out.bin> <out.inc>
"""

import re
import sys

BLOCK_START = 0x3F0
BLOCK_END = 0x800          # exclusive; also the application entry point
BLOCK_SIZE = BLOCK_END - BLOCK_START

# ASCII banner carried inside the block, used as a sanity check that the donor
# really holds the initial program and that our offsets line up.
SIGNATURE = b"MARS Initial & Security Program"


def block_from_rom(donor, rom):
    """Slice $3F0-$7FF out of a retail 32X cartridge image."""
    if rom[0x100:0x108] != b"SEGA 32X":
        sys.exit(
            f"{donor}: console name at $100 is "
            f"{rom[0x100:0x110]!r}, not 'SEGA 32X'. "
            "The donor must be a 32X cartridge image."
        )
    if len(rom) < BLOCK_END:
        sys.exit(f"{donor}: only {len(rom)} bytes, too short to hold the block")
    return rom[BLOCK_START:BLOCK_END]


def block_from_source(donor, text):
    """Assemble the block from `dc.w`/`.word` hex data in an assembly source.

    Reads every 16-bit literal on `dc.w`/`.word` lines, in order, and keeps the
    first BLOCK_SIZE bytes.  The banner check in main() is what confirms we
    picked up the right run of data.
    """
    words = []
    for line in text.splitlines():
        stripped = line.strip()
        if not re.match(r"(?i)^(dc\.w|\.word)\b", stripped):
            continue
        for lit in re.findall(r"(?i)\b(?:0x|\$)([0-9a-f]{1,4})\b", stripped):
            words.append(int(lit, 16) & 0xFFFF)
    data = b"".join(w.to_bytes(2, "big") for w in words)
    if len(data) < BLOCK_SIZE:
        sys.exit(
            f"{donor}: found only {len(data)} bytes of dc.w data, "
            f"need {BLOCK_SIZE}"
        )
    return data[:BLOCK_SIZE]


def main(argv):
    if len(argv) != 4:
        sys.exit(__doc__)
    donor, out_bin, out_inc = argv[1:]

    with open(donor, "rb") as fh:
        raw = fh.read()

    if donor.lower().endswith((".s", ".asm", ".inc", ".src")):
        block = block_from_source(donor, raw.decode("utf-8", "replace"))
    else:
        block = block_from_rom(donor, raw)

    if SIGNATURE not in block:
        sys.exit(
            f"{donor}: the {BLOCK_SIZE}-byte window $%04X-$%04X does not contain "
            "the %r banner. This donor uses a different initial-program variant; "
            "extend this tool rather than guessing a block length."
            % (BLOCK_START, BLOCK_END - 1, SIGNATURE.decode())
        )

    with open(out_bin, "wb") as fh:
        fh.write(block)

    with open(out_inc, "w") as fh:
        fh.write(
            "; Generated by tools/extract_mars_init.py -- do not edit.\n"
            "; Source: %s\n"
            "; Sega initial program block: cartridge $%04X-$%04X (%d bytes).\n"
            "; The block falls through to the application at $%06X with the\n"
            "; carry flag set on an ID or self-check failure (manual 5.2).\n"
            "MARS_APP_ENTRY  equ $%06X\n"
            "MARS_INIT_SIZE  equ %d\n"
            % (donor, BLOCK_START, BLOCK_END - 1, len(block),
               BLOCK_END, BLOCK_END, len(block))
        )

    print(
        "extracted %d bytes from %s ($%04X-$%04X); application entry $%06X"
        % (len(block), donor, BLOCK_START, BLOCK_END - 1, BLOCK_END)
    )


if __name__ == "__main__":
    main(sys.argv)
