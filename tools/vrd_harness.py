#!/usr/bin/env python3
"""Drive a cartridge in the instrumented PicoDrive and collect what it shows.

A thin layer over ../32x-playground's profiling frontend (ROADMAP U-091/U-093),
so that a capture is one call rather than a page of environment variables:

    capture(rom, script, total, start, end, every, outdir, env=None)
        run `total` frames under a debugger script, dumping every `every`th
        composited frame between `start` and `end` into `outdir`
    sheet(outdir, png, cols=4, scale=2)
        a labelled contact sheet of whatever capture() dumped
    rgb565(path, w, h)
        one dumped frame as a PIL image
    cut_script(script, frame, *extra)
        the script's input up to `frame`, then `extra` commands
    save_script(script, outdir, frames)
        the script's input with a `save <outdir>/<frame>.state` at each frame

Scripts are the frontend's debugger scripts: `run N`, `joypad <mask>`,
`save <path>`, `read`, `regs`, `quit`.  tools/fixtures/demo_game.cmds starts a
DEMO game from power-on.

Two preconditions the frontend enforces, loudly (KNOWN_ISSUES): the dump window
must end before the last frame, and an input script must be exactly as long as
the run.  And one it does not: the checked-in `profiling_frontend` binary
predates frame fingerprints and video dumps and silently ignores them, so build
the frontend from source --

    cd ../32x-playground/tools/libretro-profiling
    cc -O2 -o vrd_fe profiling_frontend.c -ldl

VRD_FRONTEND_DIR overrides where it is looked for.
"""
import csv
import os
import shutil
import subprocess

from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRONTEND_DIR = os.environ.get(
    "VRD_FRONTEND_DIR",
    os.path.join(os.path.dirname(REPO), "32x-playground", "tools", "libretro-profiling"))
FRONTEND = os.path.join(FRONTEND_DIR, "vrd_fe")
CORE = os.path.join(FRONTEND_DIR, "picodrive_libretro.so")


def capture(rom, script, total, start, end, every, outdir, env=None):
    """Run the frontend; returns the CompletedProcess.  Paths are made absolute,
    since the frontend runs from its own directory."""
    outdir = os.path.abspath(outdir)
    shutil.rmtree(outdir, ignore_errors=True)
    os.makedirs(outdir)
    full = dict(os.environ, VRD_LIBRETRO_CORE=CORE,
                VRD_VIDEO_DUMP_DIR=outdir,
                VRD_VIDEO_DUMP_START=str(start),
                VRD_VIDEO_DUMP_END=str(end),
                VRD_VIDEO_DUMP_EVERY=str(every))
    full.update(env or {})
    args = [FRONTEND, os.path.abspath(rom), str(total)]
    if script:
        args += ["--debug-script", os.path.abspath(script)]
    return subprocess.run(args, env=full, capture_output=True, text=True, cwd=FRONTEND_DIR)


def frames(outdir):
    """The dump's manifest, keyed by frame number."""
    with open(os.path.join(outdir, "video-frames.csv")) as fh:
        return {int(r["frame"]): r for r in csv.DictReader(fh)}


def rgb565(path, w, h):
    data = open(path, "rb").read()
    im = Image.new("RGB", (w, h))
    px = im.load()
    assert px is not None
    for y in range(h):
        row = y * w
        for x in range(w):
            v = data[2 * (row + x)] | (data[2 * (row + x) + 1] << 8)
            px[x, y] = (((v >> 11) & 31) * 255 // 31,
                        ((v >> 5) & 63) * 255 // 63,
                        (v & 31) * 255 // 31)
    return im


def load(outdir, frame):
    r = frames(outdir)[frame]
    return rgb565(os.path.join(outdir, r["path"]), int(r["width"]), int(r["height"]))


def sheet(outdir, png, cols=4, scale=2):
    """Contact sheet of every dumped frame, each labelled with its number."""
    shots = []
    for n, r in sorted(frames(outdir).items()):
        path = os.path.join(outdir, r["path"])
        if not os.path.exists(path):
            continue
        im = rgb565(path, int(r["width"]), int(r["height"]))
        ImageDraw.Draw(im).text((2, 2), str(n), fill=(255, 255, 0))
        shots.append(im)
    if not shots:
        return 0
    rows = (len(shots) + cols - 1) // cols
    out = Image.new("RGB", (cols * 320, rows * 224))
    for i, im in enumerate(shots):
        out.paste(im, ((i % cols) * 320, (i // cols) * 224))
    if scale != 1:
        out = out.resize((out.width // scale, out.height // scale))
    out.save(png)
    return len(shots)


def _input_lines(script):
    for line in open(script):
        words = line.split()
        if words and words[0] not in ("save", "quit"):
            yield line.rstrip(), words


def cut_script(script, frame, *extra):
    """The script's input up to `frame`, followed by `extra` commands."""
    out, at = [], 0
    for line, words in _input_lines(script):
        if words[0] == "run":
            n = int(words[1])
            if at + n >= frame:
                if frame > at:
                    out.append("run %d" % (frame - at))
                break
            at += n
        out.append(line)
    return "\n".join(out + list(extra)) + "\n"


def save_script(script, outdir, save_at):
    """The script's input with a savestate at each requested frame, then quit.
    States are named <outdir>/<frame, six digits>.state."""
    pending = sorted(set(save_at))
    out, at = [], 0
    for line, words in _input_lines(script):
        if words[0] != "run":
            out.append(line)
            continue
        n = int(words[1])
        while pending and at + n >= pending[0]:
            step = pending[0] - at
            if step:
                out.append("run %d" % step)
            out.append("save %s/%06d.state" % (os.path.abspath(outdir), pending[0]))
            at, n = at + step, n - step
            pending.pop(0)
        if n:
            out.append("run %d" % n)
            at += n
        if not pending:
            break
    return "\n".join(out + ["quit"]) + "\n"
