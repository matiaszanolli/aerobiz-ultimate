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
        elif args[0] == "--form":
            only, args = args[1], args[2:]
        else:
            sys.exit(__doc__)

    paths = args or (
        sorted(glob.glob("disasm/modules/68k/*/*.asm"))
        + sorted(glob.glob("disasm/sections/*.asm"))
    )

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
