#!/usr/bin/env python3
"""Match frames between two builds by what is on screen, not by frame number.

U-092.  Any change that perturbs timing makes the demo diverge, so at the same
frame number two builds are on different screens and a frame-to-frame diff is
meaningless.  It produced two wrong conclusions in one session.

The frontend's VRD_FRAME_FINGERPRINT CSV gives, per frame, a hash of VRAM,
CRAM, VSRAM and the VDP registers plus the 68000 PC.  VRAM and CRAM together
identify a screen: the loaded tile set and palette change when the screen
changes and hold still while it is displayed.  So a (vram, cram) pair that
occurs in both runs names the same screen in each, and *those* frames are the
ones worth comparing.

Usage:
    match_screens.py a.csv b.csv                    # summary of shared screens
    match_screens.py a.csv b.csv --pairs            # one frame pair per screen
    match_screens.py a.csv b.csv --key=cram         # match on palette alone
    match_screens.py a.csv b.csv --min-run=20       # ignore transient states

The key deliberately excludes the PC and VSRAM: the PC differs by construction
between builds, and VSRAM changes with scroll position within a screen.

Choosing the key matters, and the default is not always right:

  both (default)  VRAM + CRAM.  The most specific, and correct when the two
                  builds should be drawing the same thing.
  cram            palette only.  Use when the change under test alters VRAM
                  itself -- a plane-geometry or display-mode change rewrites
                  the nametable, so a VRAM key would match nothing and report
                  "these builds never show the same screen", which is true and
                  useless.  Palettes survive such changes.
  vram            tile set only.  Use when the palette is what changed.

--min-run=N keeps only screens displayed for at least N consecutive frames.
Without it the comparison is dominated by transients: over 12,000 frames of the
demo, 1,050 screens recur as more than one run and most last a handful of
frames, so two builds that differ in timing will reach them at different
sub-frame points and appear to disagree. Screens a player would call a screen
last far longer. 20 is a good starting value.
"""
import csv
import sys
from collections import OrderedDict


KEYS = {"both": ("vram", "cram"), "cram": ("cram",), "vram": ("vram",)}


def load(path, fields):
    """frame -> key tuple, in file order."""
    out = OrderedDict()
    with open(path, newline="") as fh:
        for row in csv.DictReader(fh):
            out[int(row["frame"])] = tuple(row[f] for f in fields)
    return out


def runs(frames):
    """Collapse consecutive frames sharing a key into (key, first, last, n)."""
    result = []
    for frame, key in frames.items():
        if result and result[-1][0] == key and frame == result[-1][2] + 1:
            k, lo, _, n = result[-1]
            result[-1] = (k, lo, frame, n + 1)
        else:
            result.append((key, frame, frame, 1))
    return result


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    opts = argv[3:]
    show_pairs = "--pairs" in opts
    key_name = "both"
    min_run = 1
    for o in opts:
        if o.startswith("--key="):
            key_name = o.split("=", 1)[1]
        elif o.startswith("--min-run="):
            min_run = int(o.split("=", 1)[1])
    if key_name not in KEYS:
        print("unknown --key=%s; expected one of %s"
              % (key_name, ", ".join(sorted(KEYS))))
        return 1
    fields = KEYS[key_name]
    a, b = load(argv[1], fields), load(argv[2], fields)
    ra, rb = runs(a), runs(b)

    # First occurrence of each screen, so a screen revisited later does not
    # silently match the wrong visit.
    first_a, first_b = {}, {}
    for key, lo, hi, n in ra:
        if n >= min_run:
            first_a.setdefault(key, (lo, hi, n))
    for key, lo, hi, n in rb:
        if n >= min_run:
            first_b.setdefault(key, (lo, hi, n))

    shared = [k for k in first_a if k in first_b]
    what = "screens" if min_run <= 1 else "screens held >= %d frames" % min_run
    print("%s: %d frames, %d distinct %s" % (argv[1], len(a), len(first_a), what))
    print("%s: %d frames, %d distinct %s" % (argv[2], len(b), len(first_b), what))
    print("shared screens: %d  (key: %s)" % (len(shared), key_name))

    if not shared:
        print("\nNo screen appears in both runs.  Either they diverge before "
              "the first shared screen, or one of them never got going.")
        return 2

    # Ordering.  Sort the shared screens by where they first appear in A; if
    # the runs agree, their positions in B are then also increasing.  Count
    # inversions rather than answering yes/no, because a handful among
    # thousands means transient states, and hundreds means real divergence.
    #
    # An earlier version compared the two full run sequences elementwise. That
    # can never succeed: screens recur constantly (1,050 of them over 12,000
    # frames of the demo) and one extra transient run in either build shifts
    # everything after it. It reported disagreement on builds that agreed.
    ordered = sorted((first_a[k][0], first_b[k][0]) for k in shared)
    inversions = sum(1 for i in range(1, len(ordered))
                     if ordered[i][1] < ordered[i - 1][1])
    if inversions == 0:
        print("screen order agrees: yes, no inversions in %d shared screens"
              % len(ordered))
    else:
        print("screen order: %d inversions in %d shared screens (%.2f%%)"
              % (inversions, len(ordered), 100.0 * inversions / len(ordered)))
        print("  Re-run with --min-run=20 before believing this means "
              "divergence; short-lived states invert on timing alone.")

    if show_pairs:
        print("\n%-10s %-10s %-8s %-8s %s" %
              ("a.frame", "b.frame", "a.len", "b.len", "drift"))
        for key in sorted(shared, key=lambda k: first_a[k][0]):
            fa, _, na = first_a[key]
            fb, _, nb = first_b[key]
            print("%-10d %-10d %-8d %-8d %+d" % (fa, fb, na, nb, fb - fa))
    else:
        drifts = [first_b[k][0] - first_a[k][0] for k in shared]
        print("frame drift over shared screens: min %+d, max %+d"
              % (min(drifts), max(drifts)))
        print("\nRe-run with --pairs for the frame pairs to compare.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
