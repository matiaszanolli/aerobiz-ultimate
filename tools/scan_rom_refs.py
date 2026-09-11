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
    scan_rom_refs.py --rewrite [--form "<form>"] [path ...]

`--rewrite` applies the safe rebases, sharing this file's classifier so the tool
that finds a site is the tool that fixes it. Restrict a batch with `--form`.
Run `make verify` after every batch: an MD5 match proves no encoding changed.
"""

import collections
import glob
import re
import sys

ROM_LO, ROM_HI = 0x200, 0x100000

INSTR = re.compile(r"^\s+([a-z][a-z0-9]*(?:\.[bwls])?)\s+(.*?)\s*(?:;.*)?$")
BRANCHES = {"bra", "bsr", "jmp", "jsr"}
# Every DBcc, not just dbra/dbf: dbne and dbeq both appear in this ROM and were
# missed until the 32X build refused them as out of range.
DECREMENT_BRANCH = re.compile(
    r"db(ra|f|t|hi|ls|cc|cs|ne|eq|vc|vs|pl|mi|ge|lt|gt|le)$"
)
# PC-relative operands carry the absolute target as a literal and let the
# assembler work out the displacement, so they must be rebased along with
# everything else -- otherwise the target stays near zero while the program
# counter moves to $900000. Covers `$80e(pc)` and `$198e(pc,d0.w)` alike.
PC_RELATIVE = re.compile(r"\$([0-9A-Fa-f]+)\((pc|PC)([^)]*)\)")
CONDITIONAL = re.compile(r"b(hi|ls|cc|cs|ne|eq|vc|vs|pl|mi|ge|lt|gt|le)$")
BARE_TARGET = re.compile(r"\$([0-9A-Fa-f]+)\s*(?:\(pc\))?$")
ABS_LONG = re.compile(r"\(\$([0-9A-Fa-f]{5,8})\)\.l")
IMMEDIATE = re.compile(r"#\$([0-9A-Fa-f]{4,8})")
# dc.l takes a comma-separated list; match the whole operand list, not just
# the first value. Matching only the first undercounted the GameCommand jump
# table by 35 pointers.
DC_LONG_LINE = re.compile(r"\bdc\.l\s+(\S.*?)\s*(?:;.*)?$")
DC_LONG_VALUE = re.compile(r"\$([0-9A-Fa-f]{1,8})\b")

# Mnemonics whose immediate operand is an address by construction.
ADDRESS_IMMEDIATE = {"movea", "lea", "pea"}

# Hand-encoded absolute-long instructions, emitted as `dc.w $op,$hi,$lo` by the
# disassembly where a mnemonic was not trusted to reproduce the exact bytes.
# The address is split across two words, so none of the regexes above can see
# it -- and these are jsr/jmp targets, the class most certain to be addresses.
HAND_ENCODED = re.compile(
    r"\bdc\.w\s+\$([0-9A-Fa-f]{4})\s*,\s*\$([0-9A-Fa-f]{4})\s*,\s*\$([0-9A-Fa-f]{4})"
)
HAND_OPCODES = {
    0x4EB9: "jsr", 0x4EF9: "jmp", 0x4879: "pea",
    0x41F9: "lea", 0x43F9: "lea", 0x45F9: "lea", 0x47F9: "lea",
    0x49F9: "lea", 0x4BF9: "lea", 0x4DF9: "lea",
    0x2079: "movea.l", 0x2279: "movea.l", 0x2479: "movea.l", 0x2679: "movea.l",
}
HAND_REGISTER = {
    0x41F9: "a0", 0x43F9: "a1", 0x45F9: "a2", 0x47F9: "a3",
    0x49F9: "a4", 0x4BF9: "a5", 0x4DF9: "a6",
    0x2079: "a0", 0x2279: "a1", 0x2479: "a2", 0x2679: "a3",
}

# disasm/sections/header.asm is the Genesis vector table. On the 32X the live
# vectors are in the boot half at cartridge $000000 and this copy is inert
# (see disasm/ultimate_game.asm), so rebasing it would be noise.
# A 32-bit ROM pointer can also be emitted as two consecutive dc.w words, which
# neither the dc.l handling nor the hand-encoded-instruction handling sees. The
# disassembly does this for pointer tables ("GraphicSequencePtrs" and friends).
#
# Telling a pointer table from compressed data or a counter table needs a strict
# rule, because the loose one ("some pair reads as a ROM address") matches 2,697
# lines of graphics data. Require, on one line: at least two pairs, every pair a
# ROM address, the high word identical across all of them, and the low words all
# distinct. That keeps $0007,$67FE,$0007,$681E,... and rejects $0005,$0006,
# $0007,$0008,... which is an index sequence.
DCW_TABLE = re.compile(r"\bdc\.w\s+(\S.*?)\s*(?:;.*)?$")
DCW_WORD = re.compile(r"\$([0-9A-Fa-f]{1,4})\b")


def dcw_pointers(operands):
    """Return the pointer list if this dc.w operand list is a ROM pointer table."""
    words = [int(w, 16) for w in DCW_WORD.findall(operands)]
    if len(words) < 4 or len(words) % 2:
        return None
    pairs = [(words[i], words[i + 1]) for i in range(0, len(words), 2)]
    if not all(hi <= 0x000F and in_rom((hi << 16) | lo) for hi, lo in pairs):
        return None
    if len({hi for hi, _ in pairs}) != 1:
        return None
    lows = [lo for _, lo in pairs]
    if len(set(lows)) != len(lows):
        return None
    return [(hi << 16) | lo for hi, lo in pairs]


EXCLUDED = {"disasm/sections/header.asm"}

# A dc.w hand-encoding usually carries the decoded instruction as a comment.
# Once the mnemonic is restored the comment is a duplicate.
# A literal already written as ROM_BASE+$xxxx is done. Blank those out before
# classifying, or the scan reports completed sites as outstanding work.
REBASED = re.compile(r"ROM_BASE\+\$[0-9A-Fa-f]+")

REDUNDANT = re.compile(r"^;\s*(?:jsr|jmp|pea|lea|movea\.l)\s+\$([0-9A-Fa-f]+)\s*$")


def in_rom(value):
    return ROM_LO <= value < ROM_HI


def scan(paths):
    findings = []
    for path in paths:
        if path in EXCLUDED:
            continue
        with open(path, errors="replace") as fh:
            for num, raw in enumerate(fh, 1):
                line = REBASED.sub("REBASED", raw.rstrip("\n"))
                if line.lstrip().startswith(";"):
                    continue

                hand = HAND_ENCODED.search(line)
                if hand:
                    opcode = int(hand.group(1), 16)
                    if opcode in HAND_OPCODES:
                        target = (int(hand.group(2), 16) << 16) | int(hand.group(3), 16)
                        if in_rom(target):
                            findings.append(
                                (path, num, "safe",
                                 f"dc.w {HAND_OPCODES[opcode]} abs.l", line.strip())
                            )

                dcw = DCW_TABLE.search(line)
                if dcw:
                    table = dcw_pointers(dcw.group(1))
                    if table:
                        for _ in table:
                            findings.append(
                                (path, num, "safe", "dc.w pointer table", line.strip())
                            )

                dc_long = DC_LONG_LINE.search(line)
                if dc_long:
                    for hexval in DC_LONG_VALUE.findall(dc_long.group(1)):
                        if in_rom(int(hexval, 16)):
                            findings.append(
                                (path, num, "safe", "dc.l ROM pointer", line.strip())
                            )

                match = INSTR.match(line)
                if not match:
                    continue
                op, args = match.group(1), match.group(2)
                if not args:
                    continue
                mnemonic = op.split(".")[0]

                for pcrel in PC_RELATIVE.finditer(args):
                    if in_rom(int(pcrel.group(1), 16)):
                        findings.append(
                            (path, num, "safe", "pc-relative literal", line.strip())
                        )

                if (mnemonic in BRANCHES or CONDITIONAL.match(mnemonic)
                        or DECREMENT_BRANCH.match(mnemonic)):
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


def split_comment(line):
    """Split a source line into (code, comment). Quote-aware, since dc.b lines
    can carry a ';' inside a string."""
    in_quote = False
    for i, ch in enumerate(line):
        if ch == "'":
            in_quote = not in_quote
        elif ch == ";" and not in_quote:
            return line[:i], line[i:]
    return line, ""


def rebase(hexdigits):
    return f"ROM_BASE+${hexdigits}"


def rewrite_code(code):
    """Apply every safe rebase to one line of code. Returns (code, [forms])."""
    forms = []

    hand = HAND_ENCODED.search(code)
    if hand:
        opcode = int(hand.group(1), 16)
        if opcode in HAND_OPCODES:
            target = (int(hand.group(2), 16) << 16) | int(hand.group(3), 16)
            if in_rom(target):
                indent = code[: len(code) - len(code.lstrip())]
                mnemonic = HAND_OPCODES[opcode]
                operand = f"({rebase('%06X' % target)}).l"
                register = HAND_REGISTER.get(opcode)
                if register:
                    operand += "," + register
                # Same bytes, verified: dc.w $4EB9,$hi,$lo and jsr (abs).l both
                # assemble to 4EB9 hi lo under -no-opt, low targets included.
                return indent + mnemonic.ljust(8) + operand, [
                    f"dc.w {mnemonic} abs.l"
                ], target

    dcw = DCW_TABLE.search(code)
    if dcw:
        table = dcw_pointers(dcw.group(1))
        if table:
            indent = code[: len(code) - len(code.lstrip())]
            # dc.l of the same values is byte-for-byte identical and says what
            # the data actually is.
            values = ",".join(rebase("%06X" % v) for v in table)
            return (indent + "dc.l".ljust(8) + values,
                    ["dc.w pointer table"] * len(table), None)

    dc_long = DC_LONG_LINE.search(code)
    if dc_long:
        operands = dc_long.group(1)

        def sub_dc(match):
            if in_rom(int(match.group(1), 16)):
                forms.append("dc.l ROM pointer")
                return rebase(match.group(1))
            return match.group(0)

        rewritten = DC_LONG_VALUE.sub(sub_dc, operands)
        if forms:
            return (code[: dc_long.start(1)] + rewritten
                    + code[dc_long.end(1):], forms, None)
        return code, [], None, None

    match = INSTR.match(code)
    if not match:
        return code, [], None
    op, args = match.group(1), match.group(2)
    mnemonic = op.split(".")[0]
    start = match.start(2)
    new_args = args

    def sub_pc(match):
        if in_rom(int(match.group(1), 16)):
            forms.append("pc-relative literal")
            # $80e(pc) -> (ROM_BASE+$80e,pc); $198e(pc,d0.w) keeps its index.
            return f"({rebase(match.group(1))},{match.group(2)}{match.group(3)})"
        return match.group(0)

    new_args = PC_RELATIVE.sub(sub_pc, new_args)

    if (mnemonic in BRANCHES or CONDITIONAL.match(mnemonic)
            or DECREMENT_BRANCH.match(mnemonic)):
        target = BARE_TARGET.search(new_args)
        if target and in_rom(int(target.group(1), 16)):
            new_args = (
                new_args[: target.start(1) - 1]
                + rebase(target.group(1))
                + new_args[target.end(1):]
            )
            forms.append(f"{mnemonic} literal target")

    def sub_abs(match):
        if in_rom(int(match.group(1), 16)):
            forms.append("($imm).l operand")
            return f"({rebase(match.group(1))}).l"
        return match.group(0)

    new_args = ABS_LONG.sub(sub_abs, new_args)

    if mnemonic in ADDRESS_IMMEDIATE:
        def sub_imm(match):
            if in_rom(int(match.group(1), 16)):
                forms.append(f"{mnemonic} #imm")
                return "#" + rebase(match.group(1))
            return match.group(0)

        new_args = IMMEDIATE.sub(sub_imm, new_args)

    if not forms:
        return code, [], None
    return code[:start] + new_args, forms, None


def rewrite_line(line):
    """Rebase one source line, preserving its trailing comment column."""
    if "ROM_BASE" in line or line.lstrip().startswith(";"):
        return line, []
    code, comment = split_comment(line)
    new_code, forms, decoded = rewrite_code(code.rstrip())
    if not forms:
        return line, []
    if comment and decoded is not None and REDUNDANT.match(comment):
        # The dc.w carried a decoded-instruction comment; the mnemonic now says
        # the same thing, so drop it rather than state it twice.
        if int(REDUNDANT.match(comment).group(1), 16) == decoded:
            return new_code.rstrip(), forms
    if not comment:
        return new_code, forms
    column = len(code)
    padding = max(column - len(new_code), 1)
    return new_code + " " * padding + comment, forms


def rewrite(paths, only=None):
    changed = collections.Counter()
    files = 0
    for path in paths:
        if path in EXCLUDED:
            continue
        with open(path, errors="replace") as fh:
            lines = fh.readlines()
        touched = False
        for index, raw in enumerate(lines):
            line = raw.rstrip("\n")
            new_line, forms = rewrite_line(line)
            if not forms:
                continue
            if only and any(form != only for form in forms):
                # A line mixing forms is rewritten whole or not at all, so that
                # a batch never leaves a half-converted line behind.
                if not all(form == only for form in forms):
                    continue
            if only and forms[0] != only:
                continue
            lines[index] = new_line + "\n"
            touched = True
            changed.update(forms)
        if touched:
            files += 1
            with open(path, "w") as fh:
                fh.writelines(lines)
    return changed, files


# ---------------------------------------------------------------------------
# Indirect pointers: longwords stored in ROM *data* that code loads and then
# dereferences. The load site is rebased (`move.l (ROM_BASE+$0AF190).l,-(a7)`),
# but the value it reads is still a raw Genesis address, so on 32X it points at
# the boot half's $FF padding.
#
# These cannot be found by looking at the data: a pointer sits in the middle of
# a compressed-graphics dc.w line and looks like graphics. They can be found
# exactly by looking at the *code*: every `move/movea.l (ROM_BASE+$X).l` says
# that ROM offset X holds a pointer. In this ROM all 260 such sites load a value
# that is itself a ROM address, which is the confirmation that the rule is right.
# ---------------------------------------------------------------------------
INDIRECT_LOAD = re.compile(
    r"^\s+(?:move|movea)\.l\s+\(ROM_BASE\+\$([0-9A-Fa-f]+)\)\.l"
)
DCW_ADDR = re.compile(r"^(\s*)dc\.w\s+(\S.*?)\s*;\s*\$([0-9A-Fa-f]{6})\s*$")


def indirect_targets(paths, rom):
    """ROM offsets that code loads a longword from, where the value is an address."""
    targets = {}
    for path in paths:
        if path in EXCLUDED:
            continue
        with open(path, errors="replace") as fh:
            for num, raw in enumerate(fh, 1):
                match = INDIRECT_LOAD.match(raw.rstrip("\n"))
                if not match:
                    continue
                off = int(match.group(1), 16)
                if off + 4 > len(rom):
                    continue
                value = int.from_bytes(rom[off:off + 4], "big")
                if in_rom(value):
                    targets[off] = value
    return targets


TABLE_BASE = re.compile(
    r"(?:lea\s+\(ROM_BASE\+\$([0-9A-Fa-f]+)\)\.l|movea\.l\s+#ROM_BASE\+\$([0-9A-Fa-f]+))"
)


def table_targets(paths, rom):
    """Pointer tables the code takes the address of.

    A rebased literal used as a base (`lea (ROM_BASE+$0780BC).l,a0`) followed in
    ROM by a run of longwords that are all even ROM addresses is a pointer table
    indexed at runtime. The entries are data, so nothing in the source marks
    them; the code taking their address is the evidence.
    """
    bases = set()
    for path in paths:
        if path in EXCLUDED:
            continue
        with open(path, errors="replace") as fh:
            for raw in fh:
                m = TABLE_BASE.search(raw)
                if m:
                    bases.add(int(m.group(1) or m.group(2), 16))
    targets = {}
    for base in bases:
        n = 0
        while base + 4 * n + 4 <= len(rom):
            v = int.from_bytes(rom[base + 4 * n:base + 4 * n + 4], "big")
            if not in_rom(v) or v & 1:
                break
            n += 1
        if n < 3:
            continue
        # The code may take the address of the middle of a table -- the palette
        # pointer at $07702E sits one entry before the base the code names -- so
        # walk backwards on the same test as well as forwards.
        first = base
        while first - 4 >= 0:
            v = int.from_bytes(rom[first - 4:first], "big")
            if not in_rom(v) or v & 1:
                break
            first -= 4
        for off in range(first, base + 4 * n, 4):
            targets[off] = int.from_bytes(rom[off:off + 4], "big")
    return targets


def rewrite_indirect(paths, rom, also_tables=False):
    """Split the dc.w line holding each pointer so the pointer becomes a dc.l."""
    targets = indirect_targets(paths, rom)
    if also_tables:
        targets.update(table_targets(paths, rom))
    placed, missing = 0, dict(targets)
    for path in paths:
        if path in EXCLUDED:
            continue
        with open(path, errors="replace") as fh:
            lines = fh.readlines()

        # A pointer can straddle two dc.w lines once an earlier pass has split
        # the line that held it. Merge address-contiguous dc.w lines when a
        # target falls on the last word of one, so the pair can be joined.
        merged = True
        while merged:
            merged = False
            for i in range(len(lines) - 1):
                a = DCW_ADDR.match(lines[i].rstrip("\n"))
                b = DCW_ADDR.match(lines[i + 1].rstrip("\n"))
                if not a or not b:
                    continue
                aw = DCW_WORD.findall(a.group(2))
                addr = int(a.group(3), 16)
                if addr + 2 * len(aw) != int(b.group(3), 16):
                    continue
                if addr + 2 * (len(aw) - 1) not in targets:
                    continue
                lines[i] = (a.group(1) + "dc.w".ljust(8)
                            + ",".join("$" + w for w in aw + DCW_WORD.findall(b.group(2)))
                            + " " * 4 + "; $%06X\n" % addr)
                del lines[i + 1]
                merged = True
                break

        touched = False
        for index, raw in enumerate(lines):
            match = DCW_ADDR.match(raw.rstrip("\n"))
            if not match:
                continue
            indent, operands, addr = match.group(1), match.group(2), int(match.group(3), 16)
            words = DCW_WORD.findall(operands)
            if not words:
                continue
            hit = [o for o in targets if addr <= o < addr + 2 * len(words) and not (o - addr) % 2]
            hit = [o for o in hit if (o - addr) // 2 + 1 < len(words) or (o - addr) // 2 + 2 <= len(words)]
            if not hit:
                continue
            out, i, changed = [], 0, False
            pending = []
            while i < len(words):
                off = addr + 2 * i
                if off in targets and i + 1 < len(words):
                    if pending:
                        out.append(indent + "dc.w".ljust(8) + ",".join("$" + w for w in pending)
                                   + " " * 4 + "; $%06X" % (off - 2 * len(pending)))
                        pending = []
                    out.append(indent + "dc.l".ljust(8) + rebase("%06X" % targets[off])
                               + " " * 4 + "; $%06X" % off)
                    missing.pop(off, None)
                    placed += 1; changed = True; i += 2
                else:
                    pending.append(words[i]); i += 1
            if not changed:
                continue
            if pending:
                out.append(indent + "dc.w".ljust(8) + ",".join("$" + w for w in pending)
                           + " " * 4 + "; $%06X" % (addr + 2 * (len(words) - len(pending))))
            lines[index] = "\n".join(out) + "\n"
            touched = True
        if touched:
            with open(path, "w") as fh:
                fh.writelines(lines)
    return placed, missing


def main(argv):
    listing = None
    rewriting = False
    only = None
    args = argv[1:]
    while args and args[0].startswith("--"):
        if args[0] == "--list":
            listing, args = args[1], args[2:]
        elif args[0] == "--rewrite":
            rewriting, args = True, args[1:]
        elif args[0] == "--rewrite-indirect":
            rewriting, only, args = "indirect", None, args[1:]
        elif args[0] == "--rewrite-tables":
            rewriting, only, args = "tables", None, args[1:]
        elif args[0] == "--form":
            only, args = args[1], args[2:]
        else:
            sys.exit(__doc__)

    paths = args or (
        sorted(glob.glob("disasm/modules/68k/*/*.asm"))
        + sorted(glob.glob("disasm/sections/*.asm"))
    )

    if rewriting in ("indirect", "tables"):
        with open("build/aerobiz.bin", "rb") as fh:
            rom = fh.read()
        placed, missing = rewrite_indirect(paths, rom, also_tables=(rewriting == "tables"))
        print("indirect pointers rebased: %d" % placed)
        if missing:
            print("not placed (%d):" % len(missing))
            for off, val in sorted(missing.items())[:10]:
                print("   $%06X -> $%06X" % (off, val))
        return

    if rewriting:
        changed, files = rewrite(paths, only)
        for form, count in sorted(changed.items(), key=lambda kv: -kv[1]):
            print(f"{form:28} {count:7}")
        print(f"{'total':28} {sum(changed.values()):7}  in {files} files")
        return

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
