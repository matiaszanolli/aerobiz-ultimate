#!/usr/bin/env python3
"""Inventory every bare ROM address literal in the shared game sources.

Rebasing the game from $000000 to $900000 (PORT_ARCHITECTURE.md section 2) means
finding every place a ROM address appears as a literal rather than a label.
This tool produces that inventory and classifies each site by how safely it can
be rewritten as ROM_BASE+$xxxxxx.

  safe       the operand is an address by construction (address register load,
             pea/lea, any ($imm).l operand, a branch or loop target)
  review     the literal sits where either an address or a plain number is
             plausible; it must be classified by hand against
             analysis/DATA_TABLES.md before being touched

Addresses outside the ROM ($000200-$0FFFFF) are ignored: work RAM ($00FFxxxx),
I/O ($00Axxxxx) and the VDP ($00Cxxxxx) do not move on the 32X.

Usage:
    scan_rom_refs.py [--list safe|review] [path ...]
"""

import collections
import glob
import re
import sys

ROM_LO, ROM_HI = 0x200, 0x100000

INSTR = re.compile(r"^\s+([a-z][a-z0-9]*(?:\.[bwls])?)\s+(.*?)\s*(?:;.*)?$")
BRANCHES = {"bra", "bsr", "jmp", "jsr", "dbra", "dbf"}
CONDITIONAL = re.compile(r"b(hi|ls|cc|cs|ne|eq|vc|vs|pl|mi|ge|lt|gt|le)$")
BARE_TARGET = re.compile(r"\$([0-9A-Fa-f]+)\s*(?:\(pc\))?$")
ABS_LONG = re.compile(r"\(\$([0-9A-Fa-f]{5,8})\)\.l")
IMMEDIATE = re.compile(r"#\$([0-9A-Fa-f]{4,8})")
DC_LONG = re.compile(r"dc\.l\s+\$([0-9A-Fa-f]{8})")

# Mnemonics whose immediate operand is an address by construction.
ADDRESS_IMMEDIATE = {"movea", "lea", "pea"}


def in_rom(value):
    return ROM_LO <= value < ROM_HI


def scan(paths):
    findings = []
    for path in paths:
        with open(path, errors="replace") as fh:
            for num, raw in enumerate(fh, 1):
                line = raw.rstrip("\n")
                if line.lstrip().startswith(";"):
                    continue

                for hexval in DC_LONG.findall(line):
                    if in_rom(int(hexval, 16)):
                        findings.append((path, num, "safe", "dc.l ROM pointer", line.strip()))

                match = INSTR.match(line)
                if not match:
                    continue
                op, args = match.group(1), match.group(2)
                if not args:
                    continue
                mnemonic = op.split(".")[0]

                if mnemonic in BRANCHES or CONDITIONAL.match(mnemonic):
                    target = BARE_TARGET.search(args)
                    if target and in_rom(int(target.group(1), 16)):
                        findings.append(
                            (path, num, "safe", f"{mnemonic} literal target", line.strip())
                        )

                for hexval in ABS_LONG.findall(args):
                    if in_rom(int(hexval, 16)):
                        findings.append(
                            (path, num, "safe", "($imm).l operand", line.strip())
                        )

                for hexval in IMMEDIATE.findall(args):
                    if not in_rom(int(hexval, 16)):
                        continue
                    kind = "safe" if mnemonic in ADDRESS_IMMEDIATE else "review"
                    findings.append(
                        (path, num, kind, f"{mnemonic} #imm", line.strip())
                    )
    return findings


def main(argv):
    listing = None
    args = argv[1:]
    if args and args[0] == "--list":
        listing = args[1]
        args = args[2:]

    paths = args or (
        sorted(glob.glob("disasm/modules/68k/*/*.asm"))
        + sorted(glob.glob("disasm/sections/*.asm"))
    )

    findings = scan(paths)

    if listing:
        for path, num, kind, _, text in findings:
            if kind == listing:
                print(f"{path}:{num}: {text}")
        return

    by_kind = collections.Counter(f[2] for f in findings)
    by_form = collections.Counter((f[2], f[3]) for f in findings)

    print(f"{'form':28} {'class':8} {'count':>7}")
    print("-" * 46)
    for (kind, form), count in sorted(by_form.items(), key=lambda kv: -kv[1]):
        print(f"{form:28} {kind:8} {count:7}")
    print("-" * 46)
    for kind, count in sorted(by_kind.items()):
        print(f"{kind:37} {count:7}")
    print(f"{'total':37} {len(findings):7}")
    print(f"\nfiles scanned: {len(paths)}")


if __name__ == "__main__":
    main(sys.argv)
