# Hardware test checklist

Everything in this project has been measured on PicoDrive. Nothing has run on a
real Sega 32X. These are the questions an emulator cannot answer, each with the
build to flash, what to look at, and what a pass looks like.

Work down the list in order -- item 1 gates the design, the rest are
confirmations.

---

## Ares as the stand-in (2026-09-15)

No real 32X is available for these tests. **Ares v148** (flatpak `dev.ares.ares`)
stands in for it, so its source was read for each question below to establish
what it can actually settle. An emulator agreeing with PicoDrive is a second,
independent implementation; it is evidence about hardware only where it models
something from its own research rather than from the same manuals.

Facts that apply to every item:

- **It runs Sega's real boot code.** Ares's bundled `sh2.boot.mrom`,
  `sh2.boot.srom` and `vector.rom` are byte-identical to the BIOS dumps in
  `../32x-playground/32X BIOS/` (MD5).
- **Tests are by eye.** v148 has no input scripting or frame capture from the
  command line, and its GDB server is wired to the N64 only. Our automated
  comparisons stay on PicoDrive.
- **Use `General/ForceInterpreter` for anything about timing.** The default SH2
  recompiler bypasses the cache simulation.

| # | What Ares models | Can it close the item? |
|---|---|---|
| 1 | The manual's model: with `RV` set the 68000 gets open bus at `$880000-$9FFFFF`, and SH2 cartridge reads stall | No -- same reading of the manual as ours. The game running on Ares validates the DMA thunk against that model |
| 2 | An independent 68000, SH2 and VDP, on the real BIOS | **Yes** |
| 3 | The Mega Drive backdrop is transparent to the 32X layer in H32 and H40 alike | Second opinion only |
| 4 | A 13-subpixel offset in H32 -- "approx 3 and 1/4 pixel offset in H40 pixels" -- where PicoDrive applies 4 | Second opinion, and the two emulators disagree |
| 5 | No offset in H40; the 32X layer always spans 320 pixels | **Yes**, as far as emulation can |
| 6 | The SH7604 cache for real (4 ways, 64 entries, LRU; **12 clocks per miss**), but **no wait states** for cache-through regions -- cartridge, frame buffer, palette | Partly. More realistic than PicoDrive for SDRAM work, still optimistic for frame-buffer work; our `VRD_SH2_TIMING` model charges every region |
| 7 | No SH2 bus timing, no bus contention | Longword question: no. Boot-ROM cache question: **answered from the BIOS itself** -- see item 7 |
| 8 | Colour: Mega Drive through a nonlinear DAC table (`0, 52, 87, 116, 144, 172, 206, 255`), 32X linearly; priority never alters a colour | Smoothness and a clean layer-on: **yes**. Frame rate: optimistic, as item 6. Hand-off colour: see item 8 |

Ares enforces FM on both CPUs, waits for the palette access window rather than
corrupting the write, and skips zero bytes in the overwrite image. It does not
model the frame buffer's zero-byte rule; our code writes words, so that does not
matter here.

---

## 1. Does `$880000-$9FFFFF` survive `RV = 1`? (PORT_ARCHITECTURE §5.3)

The one that matters. The DMA thunk is built around the answer, and PicoDrive
cannot give it: `pico/32x/memory.c:2358` says "don't need to care about RV --
not emulated", and :2481 leaves `m68k_map_unmap(0x000000, 0x3fffff)` commented
out. So the probe passing under emulation is not evidence -- nothing was ever
unmapped.

- **Build:** `make 32x-rvprobe`
- **Do:** power on. It runs before anything else touches the cartridge, then
  parks.
- **Read:** work RAM `$FFFD00`, six longwords:

  | Offset | Meaning |
  |---|---|
  | `+$00` | fixed window `$880800`, `RV = 0` |
  | `+$04` | bank window `$900800`, `RV = 0` |
  | `+$08` | fixed window, **`RV = 1`** |
  | `+$0C` | bank window, **`RV = 1`** |
  | `+$10` | cartridge `$100800` at its own offset, `RV = 1` |
  | `+$14` | fixed window, `RV = 0` again |

- **Pass:** `+$08` equals `+$00` and `+$0C` equals `+$04` -- the windows survive,
  and the thunk can run in place from the boot half.
- **Fail:** either differs. The thunk must stay RAM-resident, which is how it is
  written today, so a failure costs nothing but confirms the constraint.

## 2. Does the game boot and play at all?

- **Build:** `make 32x` -> `build/aerobiz-ultimate.32x`
- **Pass:** reaches the title, a scenario starts, a turn completes.
- **Also check:** save to SRAM, power cycle, and confirm CONTINUE lists the save.
  The save path is exercised under emulation (U-021) but battery-backed SRAM on
  a real cartridge is a different thing.

## 3. Is the H32 backdrop really transparent with the layer on? (U-003)

We observed the Genesis backdrop going transparent when the 32X layer is
enabled, which would mean every screen loses its background colour. PicoDrive's
own `pico/32x/draw.c:14-17` calls the `/YS` signal handling in this case
"unclear" and warns of "race conditions by the different video clocks", so this
observation is the least trustworthy thing we have.

- **Build:** `make 32x-layeron`
- **Pass/fail is descriptive, not binary:** photograph the trademark screen. Is
  the background the gradient (as under emulation), the game's own blue, or
  something unstable?

## 4. The 4-pixel MD/32X offset in H32 (U-003)

`draw.c` applies `H32_OFFSET 4` between layers in H32. Scanning offsets against
captured frames put the best match at 0, so it is already inside the composite
-- but that is emulator internals, not hardware.

- **Build:** `make 32x-layeron`
- **Look for:** whether the Genesis image sits 4 pixels off the 32X layer.
  Only matters if H32 compositing is ever relied on; the U-036 decision avoids
  it.

## 5. H40 with the layer on (U-036)

Expected to be fine -- H40 is the mode the 32X actually supports -- so this is
a confirmation, not a question.

- **Build:** `make 32x-h40`
- **Pass:** the game renders unstretched and 1:1 with the 32X layer, as it does
  under emulation (measured 100.00% pixel match against the Genesis build).
- **Expected artefact:** the right 64 pixels repeat the left 64. That is the
  32-cell plane wrapping, and it is not a hardware fault -- but it is no longer
  something U-036 fixes by widening the plane. Widening it to 64 cells slides
  the game's live off-screen scratch into the visible rows (HISTORY,
  2026-09-12), so this test confirms H40 registration only; the wrap stays.

## 6. Map zoom cost with a real cache (U-035)

The one measurement in the project that the emulator provably cannot make.
PicoDrive models neither the SH2 cache nor SDRAM latency (KNOWN_ISSUES), so its
2.13 frames per full-screen 1:1 blit is close to a raw instruction count.

- **Build:** `make 32x-zoomtest`
- **What to read:** `sh2_zoom_frames[3]` and `sh2_zoom_rows[3]` in SDRAM --
  V-Blanks per 32 blits at 1x, 2x and 4x. Get their addresses from
  `sh-elf-nm build/sh2/sh2.elf`; they do not move unless the image does.
- **Pass:** the animation is smooth from 2x in. The numbers matter more than
  the look: emulation says 68 / 34 / 17 frames per 32 blits.
- **What would change the plan:** hardware materially worse than 2x at the 2x
  level. That would push the renderer off the master alone and reopen the
  master/slave split in U-043.
- **Note:** `master_start` now purges and enables the cache itself, so this
  measures the cache-on case whether or not the boot ROM did it.

## 7. What the manuals say versus what the silicon does (U-093)

The emulator now implements the SH2 timing model and the `RV` bit, both
validated against the manuals -- the timing model to the cycle, `RV` by running
3,000 frames through 233 mapping changes with no visible change. That makes
these behaviours *documented and self-consistent*, which is not the same as
*confirmed*. Three questions need a console.

- **Is a longword access to a 16-bit port one bus cycle or two?** Manual 4.1
  gives wait figures without reference to width. The model charges one access
  regardless. If it is really two, longword-heavy SH2 code is more expensive
  than every number we have. Test: a loop of N longword frame-buffer reads
  against a loop of 2N word reads; equal time means one cycle each.
- ~~**Does the boot ROM actually leave the cache on?**~~ **Answered 2026-09-15,
  from the BIOS dumps themselves.** Both SH2 boot ROMs run the same sequence:
  master at `$1B4-$1BE`, slave at `$198-$1A2`, write `0` to `SBYCR`
  (`$FFFFFE91`) and then **`$11` to `CCR`** (`$FFFFFE92`) -- `CP`, purge, and
  `CE`, enable (`docs/sh7604-hardware-manual.md:3563`, `:6089`). The `CCR`
  literal is referenced once in each ROM, so nothing later turns it off. Yes,
  on both CPUs.

  That puts U-093's finding in doubt. The timing model saw **zero** cached
  accesses on the slave until our `slave_start` wrote `CCR`, and HISTORY reads
  that as the slave never having enabled its cache. With the real BIOS it had.
  PicoDrive has an HLE boot path for when no BIOS is loaded (`pico/32x/32x.c`),
  which would skip the write; which path that run took is not yet confirmed.
  Our code enables the cache explicitly either way, so the shipping build is
  unaffected -- the claimed bus saving on hardware is what is in doubt.
- **Does `$880000-$9FFFFF` really stop responding while `RV = 1`?** This is
  PORT_ARCHITECTURE §5.3, open since U-020. The manual implies it
  (`docs/32x-hardware-manual.md:237-238` presents the two windows as
  alternatives) and the emulator now enforces that reading, but the DMA thunk
  deliberately runs its windowed sequence from below the stack pointer
  precisely because the answer was unknown. Test: with `RV = 1`, read a known
  byte from `$880000` and compare against its value with `RV = 0`. If it still
  reads correctly, the thunk could be simplified.

Also unmodelled, and not resolvable by a single reading: **contention between
the two SH2s and the 68000 on the cartridge bus.** The model charges each CPU
independently. This is why U-046's batching case rests on FM handover and the
frame-buffer FIFO rather than on bus contention.

---

## 8. The SEGA intro on real hardware (U-037)

The one screen where the shipping build shows the 32X layer. Two questions the
emulator cannot answer.

- **Build:** `make 32x`. For comparison, `make 32x-licensing` boots without the
  intro.
- **Frame rate.** Under PicoDrive the SH2 drew all 127 frames and skipped none,
  but PicoDrive models neither the SH2 cache nor SDRAM latency (item 6). Read
  `sh2_sega_drawn` and `sh2_sega_skipped` in SDRAM after the intro; get the
  addresses from `nm build/sh2/sh2.elf`. Skipped frames shorten the motion but
  cannot overrun the Genesis hold.
- **The hand-off.** When the spin stops, the Genesis logo takes the front; about
  a quarter of a second later the layer blanks. Under emulation both steps are
  pixel-identical. On hardware the Genesis and 32X DACs differ, so any colour
  shift should appear at the first step -- the moment the logo stops -- and
  nothing at the second.
- **Pass:** smooth motion, no garbage when the layer comes on (both frame
  buffers are cleared first), and no visible change when it blanks.
- **On Ares, expect a small colour step at the hand-off.** The intro's palette
  matches PicoDrive's Genesis levels. Ares converts Genesis colour through a
  nonlinear DAC table and 32X colour linearly, so level 7 is 255 on the Genesis
  and about 238 from the 32X palette: the white and brightest blue should
  brighten by roughly 17/255 as the Genesis logo takes the front. A palette
  derived from that DAC table would shrink the step; under PicoDrive the hold
  frames would stay pixel-identical either way, because they show the Genesis
  logo.

---

## Notes for the session

- Bring a way to read work RAM. Items 1 and 2 both want it. Without one, item 1
  is unreadable -- consider adding a visible readout to the probe before
  flashing, rather than discovering this at the bench.
- Photograph rather than describe. Items 3 and 4 are judgements about colour
  and alignment.
- Record results in `HISTORY.md` and update `PORT_ARCHITECTURE.md` §5, which is
  the design of record for what is known versus assumed.
