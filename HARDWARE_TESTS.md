# Hardware test checklist

Everything in this project has been measured on PicoDrive. Nothing has run on a
real Sega 32X. These are the questions an emulator cannot answer, each with the
build to flash, what to look at, and what a pass looks like.

Work down the list in order -- item 1 gates the design, the rest are
confirmations.

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
  32-cell plane wrapping and is what U-036 fixes; it is not a hardware fault.

---

## Notes for the session

- Bring a way to read work RAM. Items 1 and 2 both want it. Without one, item 1
  is unreadable -- consider adding a visible readout to the probe before
  flashing, rather than discovering this at the bench.
- Photograph rather than describe. Items 3 and 4 are judgements about colour
  and alignment.
- Record results in `HISTORY.md` and update `PORT_ARCHITECTURE.md` §5, which is
  the design of record for what is known versus assumed.
