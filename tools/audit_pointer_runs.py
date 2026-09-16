#!/usr/bin/env python3
"""Audit the rebased pointer runs in ROM data -- U-014.

U-010's dc.w-table pass and U-013's table-run pass rewrote word pairs in ROM
data as `dc.l ROM_BASE+$xxxxxx`. Both passes guessed from shape, and 41 of their
guesses were wrong: palettes, index tables and tile pixels turned into pointers.
The Genesis ROM is byte-identical either way (ROM_BASE is 0 there), so nothing
in the build catches a mistake -- ground rule 8.

This tool answers U-014's question for every run at once, with two tests that
need no judgement about what a value "looks like":

  reachability  does any longword in the ROM hold an address inside this run?
                An absolute operand encodes the address, so this finds
                `lea ($05E680).l,a0` and `movea.l #$05E680,a0` alike. PC-relative
                operands would be missed; there are three left in the sources and
                none addresses a table.

  access width  at each reference, decode the instruction and follow the address
                register forward to the first read through it. A longword read
                means the run is a table of pointers. A byte or word read means
                it is data that was mistaken for one -- the defect.

The two reference forms must be kept apart, or the second test reports a false
defect on every string table:

    movea.l  $047992.l, a0     loads the table ENTRY. A later `move.b (a0)+` is
                               the string that entry points at, which is correct.
    movea.l  #$047982, a0      loads the table ADDRESS. A later `move.b (a0)+`
                               would mean the table itself is bytes.

Usage:
    audit_pointer_runs.py [--verbose]

Reads build/aerobiz.bin, so run `make genesis` first.
"""

import collections
import glob
import re
import struct
import sys

import capstone

ROM = "build/aerobiz.bin"
DC_LONG = re.compile(r"^\s*dc\.l\s+(\S.*?)\s*(?:;.*)?$")
REBASED_VALUE = re.compile(r"ROM_BASE\+\$([0-9A-Fa-f]+)")
LINE_ADDRESS = re.compile(r";\s*\$([0-9A-Fa-f]{4,6})\s*$")


def load_runs():
    """Group consecutive `dc.l ROM_BASE+...` lines into runs."""
    runs = []
    for path in sorted(glob.glob("disasm/sections/*.asm")):
        lines = open(path, errors="replace").read().split("\n")
        current = None
        for number, raw in enumerate(lines, 1):
            match = DC_LONG.match(raw)
            values = REBASED_VALUE.findall(match.group(1)) if match else []
            if values:
                address = LINE_ADDRESS.search(raw.rstrip())
                if current is None:
                    current = {"path": path, "line": number, "base": None, "n": 0}
                if current["base"] is None and address:
                    current["base"] = int(address.group(1), 16)
                current["n"] += len(values)
            else:
                if current:
                    runs.append(current)
                current = None
        if current:
            runs.append(current)
    return [r for r in runs if r["base"] is not None]


def longword_index(rom):
    index = collections.defaultdict(list)
    for offset in range(0, len(rom) - 3, 2):
        index[rom[offset:offset + 4]].append(offset)
    return index


def audit(rom, index, runs):
    md = capstone.Cs(capstone.CS_ARCH_M68K, capstone.CS_MODE_BIG_ENDIAN)
    widths = collections.Counter()
    defects = []
    reachable, orphans = [], []

    for run in runs:
        base, count = run["base"], run["n"]
        hits = [(a, h)
                for a in range(base, base + 4 * count, 4)
                for h in index.get(struct.pack(">I", a), [])]
        if not hits:
            # A short run can be a fragment of a bigger table whose other
            # entries are still bare dc.w. Say so rather than calling it dead.
            neighbour = bool(index.get(struct.pack(">I", base - 4))
                             or index.get(struct.pack(">I", base + 4 * count)))
            orphans.append((run, neighbour))
            continue
        reachable.append(run)

        for target, site in hits:
            instruction = next(md.disasm(rom[site - 2:site + 10], site - 2), None)
            if instruction is None or instruction.size < 6:
                continue
            text = "%x" % target
            if ("#$" + text) in instruction.op_str:
                register = re.search(r",\s*(a\d)$", instruction.op_str)
                if not register:
                    widths["address-of, not into a register"] += 1
                    continue
                register = register.group(1)
                pc = instruction.address + instruction.size
                for following in md.disasm(rom[pc:pc + 120], pc):
                    if re.match(r"(jmp|rts|rte|bra)", following.mnemonic):
                        break
                    if re.search(r"\(%s" % register, following.op_str):
                        size = following.mnemonic.rsplit(".", 1)[-1]
                        widths["indexed read .%s" % size] += 1
                        if size in ("b", "w"):
                            defects.append((run, following))
                        break
                    if re.search(r",\s*%s$" % register, following.op_str):
                        break
            elif ("$" + text + ".l") in instruction.op_str.replace(" ", ""):
                size = instruction.mnemonic.rsplit(".", 1)[-1]
                widths["entry read .%s" % size] += 1
                if size in ("b", "w"):
                    defects.append((run, instruction))

    return reachable, orphans, widths, defects


def main(argv):
    verbose = "--verbose" in argv
    try:
        rom = open(ROM, "rb").read()
    except OSError:
        sys.exit("%s not found -- run `make genesis` first" % ROM)

    runs = load_runs()
    index = longword_index(rom)
    reachable, orphans, widths, defects = audit(rom, index, runs)

    pointers = sum(r["n"] for r in runs)
    print("rebased pointer runs in ROM data: %d runs, %d pointers\n" % (len(runs), pointers))

    fragments = [o for o in orphans if o[1]]
    dead = [o for o in orphans if not o[1]]
    print("  %3d runs, %4d pointers   referenced inside their own extent"
          % (len(reachable), sum(r["n"] for r in reachable)))
    print("  %3d runs, %4d pointers   fragments: an adjacent entry is referenced"
          % (len(fragments), sum(r["n"] for r, _ in fragments)))
    print("  %3d runs, %4d pointers   unreferenced anywhere in the ROM"
          % (len(dead), sum(r["n"] for r, _ in dead)))

    print("\nhow the referenced runs are read:")
    for kind, n in widths.most_common():
        print("  %-32s %5d" % (kind, n))

    print("\ndefects (a table addressed, then read at byte or word width): %d" % len(defects))
    for run, instruction in defects:
        print("  %s:%d base $%06X -> $%06X  %s %s"
              % (run["path"], run["line"], run["base"],
                 instruction.address, instruction.mnemonic, instruction.op_str))

    if verbose:
        print("\nunreferenced runs:")
        for run, neighbour in sorted(orphans, key=lambda o: -o[0]["n"]):
            print("  %-26s:%-6d $%06X %4d pointers   %s"
                  % (run["path"].replace("disasm/sections/", ""), run["line"],
                     run["base"], run["n"],
                     "fragment of a referenced table" if neighbour else "no neighbour referenced"))

    return 1 if defects else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
