# ANIMATION-DETAILS.md — motion, timing and distances of the Boing animation

Goal: enough numbers to **recreate the animation without reading the assembly**. Everything here is reconstructed from `src/main.s` (physics + palette + audio) and `src/globe.s` (ball geometry), cross-checked against `archive/boing_original.s`.

The numbers below are **calibrated against a screen recording** (`boing-uae.mov`, FS-UAE, PAL/50 Hz). Frame-by-frame ball tracking confirms the source-derived constants and measures what can't be read cleanly off the FFP code. Source-derived values are marked **[src]**, recording-measured **[meas]**; where both exist they agree.

## 0. Measured headline numbers (PAL/50 Hz capture)

| Quantity | Value | Source |
|---|---|---|
| Effective update rate | **~50 Hz** (one step per PAL field) | [meas] 184 steps ÷ ~3.67 s traverse |
| Ball size on screen | **111 × 96 px** (W×H), oblate ~1.16:1 | [meas] (rate-independent) |
| Horizontal travel (ball-centre) | **184 px** (centred on source X≈160) | [meas] = [src] `x∈[-80,+104]` |
| Horizontal speed | **~50 px/s**, constant | [meas]; = [src] 1 px/step × ~50 Hz |
| Wall-to-wall traverse / round trip | **~3.67 s** / **~7.33 s** | [meas] (184 / 368 steps at ~50 Hz) |
| Vertical travel (ball-centre) | **90 px** (apex→floor) | [meas] (rate-independent) |
| Bounce period (apex→floor→apex) | **~1.92 s**, perfectly constant ⇒ **elastic, no decay** | [meas] (intervals 1.90–1.93 s); confirms [src] `dampy=0` |
| Apex dwell (slow near top) | **~0.4 s** | [meas] |
| Rotation (full stripe cycle) | **~0.28 s** (14 steps × 1/50 Hz) | [src] × field rate |
| Bounces per horizontal traverse | ~1.9 (periods incommensurate ⇒ slowly-drifting path) | [meas] (ratio is rate-independent) |

Everything below expands these with the per-step constants needed to reproduce them at any update rate.

> ⚠ **Absolute on-screen positions are capture-relative, not source geometry.** Any X/Y screen ranges measured off a recording depend on where the PAL-overscan play area landed in that capture's frame (and on whether it's a full-screen or cropped grab). The **source** centres the ball at screen **(160, 100)** (the projection's `+160`/`+100`) with the floor near `y ≈ 150`. The **amplitudes** (184 px horizontal, 90 px vertical), ball **size**, and all **periods** are differential and capture-robust — trust those; treat absolute offsets as capture artifacts (§3, §4).

---

## 1. Update rate (the master clock) and PAL vs NTSC

**One animation step per video field — 50 Hz PAL / 60 Hz NTSC.** The running loop has exactly one vblank wait per frame: the `WaitTOF` that `RethinkDisplay` performs internally (RKRM: *"RethinkDisplay … also does a WaitTOF()"*), and the running path adds no explicit `WaitTOF` of its own. So the demo advances one step per field, at the field rate — the recording confirms it: 184 px ÷ ~3.67 s traverse = ~50 px/s, and with the source's 1 px/step that's ~50 steps/s.

> **Forward guard.** Don't add an explicit `WaitTOF` on the running path. `RethinkDisplay`/`MakeScreen` already carry a `WaitTOF`, so a second one means two vblank waits per frame ⇒ half the rate (~25 Hz). The running path's only frame sync is `RethinkDisplay`'s internal `WaitTOF`. See [DEVIATIONS.md](DEVIATIONS.md).

**For a recreation, drive the per-step constants (1 px X, gravity +1 Y, 1 rotation step — §3–§5) at the field rate: one step per tick at 50 Hz (PAL) or 60 Hz (NTSC).** That yields the ~3.67 s traverse / ~1.92 s bounce measured here.

PAL vs NTSC then matters in three ways:

- **Speed (the one legitimate gap).** Motion is one step per field with no wall-clock timing, so the whole tempo scales with the field rate. PAL (50 Hz) runs at **50 ÷ 60 ≈ 0.83×** the NTSC original's speed — ~17 % slower, the only speed difference from the authentic NTSC demo. FS-UAE won't switch this A500/KS1.3 to NTSC (the model forces PAL), so this build is PAL; for true NTSC tempo, run the binary on an NTSC machine/config.
- **Vertical geometry.** NTSC shows ~200 visible lines and the 320×**200** screen fills the frame; PAL (~256 lines) leaves a bottom border (visible in the recording as grey below the floor).
- **Audio pitch.** Paula's rate is `colorclock / period`, colorclock **3.579545 MHz** (NTSC) vs **3.546895 MHz** (PAL) ⇒ same period plays ~0.9 % lower on PAL (§7).

(FS-UAE forces PAL for this A500/KS1.3 — see RUNNING.md.)

---

## 2. Coordinate model and the screen

- Display: **320 × 200**, lo-res, 5 bitplanes (32 colours). Ball centred near screen **(160, 100)** (the projection adds `+160` / `+100`, `src/globe.s`).
- Two independent position variables, both integers, updated once per field:
  - `x` — horizontal ball offset. Starts at **0**, velocity **+1** (moving right).
  - `y` — vertical ball offset, derived from a floating-point `fy` (the smooth arc). Starts at the top.
- Motion is applied on the Amiga via ViewPort scroll offsets (`RxOffset = x`, `RyOffset = -y`) of an oversized 336×216 bitmap, while the wireframe room is held still by counter-scrolling a background plane. **For a browser/canvas recreation none of that plumbing matters** — just translate the pre-rendered ball image to `(screen_x, screen_y)`; the values below are the offsets to apply.

---

## 3. Horizontal motion — EXACT

```
per field:  x += vx           (vx is +1 or -1, never any other magnitude)
            vx += ax          (ax = 0  -> horizontal speed is CONSTANT, no drag)
left wall:  if x < -80 :  x = (2*-80) - x ;  vx = -vx ;  play wall sound (pan right)
right wall: if x > +104:  x = (2*104) - x ;  vx = -vx ;  play wall sound (pan left)
```

- **Speed: exactly 1 px per update** [src], constant — confirmed by the recording's dead-straight `cx(t)` ramp at **~50 px/s** [meas] (= 1 px/step × ~50 Hz). No acceleration, no damping horizontally.
- **Travel limits: `x ∈ [-80, +104]`** [src] → amplitude **184 px**. The recording measured the ball-centre range as spanning **184 px** [meas] — exact match on the *amplitude*. (⚠ The absolute figures from that capture — `screen_cx ≈ x + 136`, left edge ~0, right edge ~295 — are **PAL-overscan crop artifacts**, not source. The source centres the ball at screen **X = 160** at `x=0` (the projection's `+160`), so the true mapping is ~`160 + x`. Trust the 184 px amplitude and the `x∈[-80,+104]` limits, not the absolute offsets.)
- **Bounce is a mirror reflection** (`x = 2·limit − x`) with instant velocity flip — perfectly elastic, no speed loss.
- **Timing [meas]:** wall-to-wall traverse = **~3.67 s**, full round trip = **~7.33 s** (184 / 368 steps at ~50 Hz, §1).
- The horizontal motion **never decays** — the ball oscillates between the two walls forever.

---

## 4. Vertical motion — EXACT algorithm + MEASURED extents

Gravity and the arc, per update, in execution order:

```
1.  step = trunc(vy / 10)          ; INTEGER divide (so vy 0..9 -> 0, 10..19 -> 1, ...)
2.  fy  += step                    ; advance float Y by that many pixels
3.  floor handling (see below)
4.  y    = round(fy)               ; integer Y -> RyOffset = -y  (this is the on-screen scroll)
5.  (horizontal physics, §3)
6.  vy  += 1                       ; GRAVITY: vertical velocity grows 1 unit per field
```

Key exact facts:

- **Gravity = `vy += 1` every field.** Initial `vy = 0`.
- **Position advances by `trunc(vy/10)` px per field** — i.e. effective downward step is `vy/10`. Because of the `/10` and integer truncation, the ball **barely moves for the first ~10 fields** (`vy` 0→9 ⇒ step 0), then accelerates: +1 px/field while `vy` 10–19, +2 px/field while 20–29, etc. The result is a discretised parabola — slow at the apex, fast near the floor, exactly like real gravity.
- **The floor bounce is perfectly ELASTIC — no energy loss.** The damping term in the code is `vy / dampy`, but **`dampy` is never initialised (stays 0)**, and the divide is evaluated as `dampy / vy = 0/vy = 0` (verified: it does *not* divide by zero). So the bounce reduces to `vy = -vy`. **The ball returns to the same apex every bounce, forever — it never settles.** (This matches the demo's known "bounces forever" behaviour and the `dampy` damping feature is effectively disabled in this binary.)
- A floor impact sets the audio trigger (`_boing = 1`) → deep "boing" sample (§7).

**Measured from the recording [meas]:**
- **Vertical travel = 90 px** (ball-centre apex → floor). ⚠ The absolute values (`cy≈57` apex, `cy≈147` floor, edges ~9 and ~198) are **crop-relative to this PAL capture**, not source — the source projection centres the ball at screen `y=100` with the floor near `y≈150`. The **90 px travel** is the crop-robust figure to use.
- **Bounce period (apex→floor→apex) = ~1.92 s** [meas] (96 steps ÷ ~50 Hz), dead constant across every bounce in the clip (intervals 1.90–1.93 s) → **the ball returns to the exact same height every time — elastic, confirming `dampy=0`**.
- **Apex dwell ≈ 0.4 s** [meas]: `cy` sits near the top (the `trunc(vy/10)=0` region for `vy<10`) then accelerates downward — the characteristic "hangs at the top, snaps down" gravity feel.
- **X and Y are incommensurate**: bounce ~1.92 s vs traverse ~3.67 s (ratio ~1.9, not integer) → the ball traces a **slowly-drifting path**, never exactly repeating. Over the ~14 s clip: ~2 horizontal round trips, ~7 vertical bounces.

(The FFP floor/apex thresholds in the code are `±96`/`±192`; the measured 90 px travel is consistent with the `±96` magnitude, resolving the earlier sign ambiguity.)

---

## 5. Ball rotation (the palette-cycling spin) — EXACT

The ball bitmap never changes; rotation is faked by cycling 14 colour-registers once per update.

- **Rotation phase `D4` steps by exactly 1 every update** [src], wrapped mod 14.
- **Direction is tied to horizontal velocity:**
  - moving **right** (`vx ≥ 0`): `D4 -= 1`
  - moving **left**  (`vx < 0`): `D4 += 1`
  - so the spin direction **flips at every wall bounce**, matching the reversal of travel.
- **One full stripe cycle = 14 updates** → at the ~50 Hz field rate that's **~0.28 s per full stripe march** (≈ 3.6 cycles/s). (Derived from the 1-step/update source constant × the field rate.)
- The 14 cycled entries are **7 white** (`$0FFF`), **7 red** (`$0F00`), and **1 pink-white highlight** (`$0FDD`) that replaces one of them. The highlight sits at cycle offset **0** when moving right, offset **6** when moving left, so the bright stripe always leads the rotation.
- Each colour is written into **two** palette halves (indices 2–15 and 18–31); the ball's 5th bitplane selects which half, which is also how the "darken the ball over the wireframe floor" effect works. (Static colours: background `$0AAA` grey, ball rim `$0666`, wireframe `$0A0A` magenta.)

---

## 6. Ball geometry and on-screen size — EXACT mesh, ⚠ size to calibrate

From `src/globe.s` (`_init_globe`), built **once** at startup:

- **9 latitude bands × 56 longitudes** = 504 vertices; ~**392 visible facets** after back-face culling.
- Per-vertex sphere coords: `x = sin(lat)·cos(lon)`, `z = sin(lat)·sin(lon)`, **`y = cos(lat)/2`** — note the **vertical squash by ½** (the ball is modelled slightly oblate).
- Per-vertex stripe colour: **`((band_parity)·7 + lon) mod 14 + 2`** → the half-cycle (`·7`) offset between adjacent bands is what makes the stripes a **diagonal spiral**, not horizontal rings.
- Projection to screen (a fixed shift-and-add rotation matrix, `src/globe.s`):
  ```
  proj_x = 160 + (y/2 + x·1.6875) / 512
  proj_y = 100 + y_offset − (y·1.4375 − x/2) / 512
  ```
  The `1.6875 = 2−¼−1/16` and `1.4375 = 1+½−1/16` constants bake in a ~30° camera tilt (so the spiral reads as diagonal) and are chosen to be shift-add-implementable on the 68000.

**On-screen ball diameter [meas]: 111 px wide × 96 px tall** (rock-steady across the whole clip), i.e. ~35 % of screen width and ~48 % of screen height. The **1.16:1 wider-than-tall** ratio confirms the `cos(lat)/2` vertical squash (the ball is visibly oblate, not circular). For a recreation: draw the ball at **~111 × 96 px** on a 320 × 200 field.

---

## 7. Audio — EXACT

One sample (`boing.samples`, 8-bit signed PCM, 2-byte header then data) is replayed at two pitches:

| Event | Trigger | Paula period | Volume (of 64) | Stereo balance |
|---|---|---|---|---|
| **Floor bounce** | `_boing=1` | **255** (low pitch, deep) | **63** (≈ max) | `balance = -x · 384` (follows ball position, opposite speaker) |
| **Left-wall bounce** | `_boing=2` | **160** (higher pitch) | **40** (≈ 0.63×) | **+30000** (pans right — ball is at left) |
| **Right-wall bounce** | `_boing=3` | **160** | **40** | **−30000** (pans left — ball is at right) |

- **Resulting sample rate** = `colorclock / period`:
  - Floor (255): **14,037 Hz** NTSC / **13,909 Hz** PAL.
  - Wall (160): **22,372 Hz** NTSC / **22,168 Hz** PAL.
- The stereo "balance" is implemented as an **inter-aural delay + volume difference** between two Paula channels (the far channel is quieter *and* delayed), not a simple pan — see `src/anim.s` `_Boing`. Wall volume ratio is **40/63 ≈ 0.63** of the floor volume.
- Floor balance is **proportional to ball X** (`-x·384`); wall balances are **fixed** (`±30000`), because a wall hit always comes fully from one side.

---

## 8. Findings / non-obvious behaviours (also see RUNNING.md)

- **Perpetual motion, both axes.** Horizontal is exactly elastic (`vx` only flips sign); vertical is elastic because `dampy=0` disables the damping divide. The ball never loses energy and never rests.
- **`y` / `y_lower` overlap.** The integer Y is stored with a `move.l` into a `dc.w _y` immediately followed by `dc.w _y_lower`, so `_y_lower` is just the low word of `y`; `RyOffset = -_y_lower = -y`. (The disassembly's two labels look like separate variables but are one longword.)
- **`dampy` damping is dead code** (always 0) — see §4.
- **Auto-start / pacing** is this repo's one deviation from the original (which starts paused; `_sstept` is never signalled) — see [DEVIATIONS.md](DEVIATIONS.md).
- Per-update work order matters for exact reproduction: rotate palette → Y arc → X step → apply scroll → **then** add gravity to `vy`. (Gravity is applied at the *end* of the step, after the position update.)
- **The loop runs at the field rate (~50 Hz PAL), one step per field** — paced by the `WaitTOF` inside `RethinkDisplay` (the running path adds no explicit `WaitTOF`; don't add one — §1). Getting the rate right is the single most important thing for matching the original tempo.

---

## 9. A minimal recreation recipe (all values calibrated)

Run a step function at the field rate — **50 Hz (PAL)** or **60 Hz (NTSC)**, one step per tick. State: `x` (start 0, `vx=+1`), `vy` (start 0), `fy` (start "top"), `rot` (0–13). Each step:

```
rot += (vx>=0 ? -1 : +1);  rot mod 14          # stripe spin (full cycle ~0.28 s at 50 Hz)
fy  += trunc(vy/10)                            # gravity arc
if floor reached: fy reflects; vy = -vy        # ELASTIC (no damping); play floor sound
x   += vx
if x < -80 : x = -160 - x; vx = -vx            # left wall  -> wall sound, pan right
if x > 104 : x =  208 - x; vx = -vx            # right wall -> wall sound, pan left
draw ball (111×96 px) centred at screen (160 + x, ~100), bouncing over a 90 px vertical range
   (source geometry: ball centred at 160,100. The 56→240 / cy57→147 figures elsewhere are crop-relative.)
vy  += 1                                        # gravity, applied last
```

Calibrated targets to match the original (PAL recording):

| | value |
|---|---|
| Ball image | **111 × 96 px** on 320 × 200 (oblate; diagonal red/white spiral, §5–§6) |
| Horizontal | **184 px** range (source X≈160 centre), **~50 px/s**, traverse **~3.67 s**, round trip **~7.33 s** |
| Vertical | **90 px** travel (source Y≈100 centre), bounce **~1.92 s**, apex dwell **~0.4 s**, elastic |
| Rotation | 14-step stripe cycle ≈ **0.28 s**, direction flips at each wall |
| Audio | floor: period 255 / vol 63 / pan ∝ −x; wall: period 160 / vol 40 / pan ±full; inter-aural delay + volume (§7) |

All items are measured against a **PAL/50 Hz** recording (FS-UAE forces PAL for this A500/KS1.3 — see RUNNING.md); the demo runs at the field rate, one step per field (§1). On an NTSC machine expect the wall-clock figures ~17 % faster (60/50) while every *per-step* constant and *pixel* distance stays identical.
