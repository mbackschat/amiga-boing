# Boing — Modern Browser Demo

**Date:** 2026-05-23
**Status:** draft
**Implementation target:** a separate new project (not this Amiga repo). This spec is the handoff artifact.

---

## Intent

Build a modern, single-page browser demo that faithfully recreates the visual and auditory identity of the **Amiga Boing Ball** demo (Dale Luck / RJ Mical, 1984 CES) — a red-and-white spirally-checkered sphere bouncing inside a magenta wireframe room, with a metallic "BOING!" panned to impact side. Specifically: reproduce the **AMICUS Disk 9** variant whose source lives in this repository (the `amiga-boing` repo: `src/boing.s` + `src/`), because it is fully analyzed, byte-equivalent to a circulating PD binary, and uses the same per-frame animation pipeline as the lost 1984 original.

The demo is a tribute / educational artifact, not a port. It runs in any modern desktop browser (Chrome, Firefox, Safari) with no install. Done correctly, someone who has seen the original on real Amiga hardware should recognise this immediately and be unable to point at anything visually wrong.

### Why this, not "just animate a sphere"

The Boing Ball has a specific *technique signature* that defines its identity:

1. The ball is a **static image**. Its pixel data never changes. Apparent rotation is produced by **palette cycling** — rewriting a small set of color registers every frame. A naive "rotate a textured sphere" demo loses the iconic look (the stripe pattern marches, it doesn't roll).
2. The ball's stripe pattern is a **diagonal spiral**, not horizontal rings. This comes from a 9-latitude × 56-longitude tessellation with per-vertex color phase-offset by half-cycle between adjacent bands (formula in §4 below). Get this wrong and the ball looks like a beach ball, not Boing.
3. Motion is via **viewport scroll offset**, not per-frame redraw — conceptually. On modern canvas we don't have an Agnus, but the *visual result* (the ball appears to translate without re-rendering its shading) should be the same: render the ball once into an offscreen bitmap, then composite it at the per-frame position.
4. The "shadow" / rim-darkening over the wireframe floor uses the Amiga **5th-bitplane palette-half-toggle trick** to darken the ball's silhouette where it overlaps the background, without re-drawing. The browser equivalent is a multiply/darken composite for the silhouette area only.
5. Stereo "BOING!" panning uses both **volume difference and inter-aural time delay** — a softer-AND-later channel on one side. This is psychoacoustically much stronger than volume-only pan and is part of the original's signature audio.

Recreating these techniques in browser idioms (Canvas2D, WebAudio) is itself the educational value. A WebGL three.js sphere is the cheap but wrong way.

---

## Scope

### In scope

- A single-page web app: open `index.html`, see the demo running.
- Faithful visual identity: red/white diagonal-stripe sphere, magenta wireframe room (back wall + 4-row perspective floor + radial "ray" lines), darker rim over the floor.
- Faithful animation technique: palette cycling for rotation, position offsets for motion (no per-frame sphere re-rasterisation after startup).
- Physics: gravity, horizontal bounce off left/right walls, vertical bounce off floor, slight energy loss. Match the AMICUS source's qualitative feel; numeric constants are approximate (see §6).
- Stereo audio: deeper "boom" on floor impact (full volume), sharper "boing" on wall impact (~63% volume), stereo pan based on impact X position, with both volume and time-delay components.
- Pause/resume on click or key press; quit / close not applicable (it's a webpage).
- Aspect ratio: maintains the 320×200 NTSC-lo-res "shape" of the original, integer-scaled up to fill the viewport (default 4×, see §7).

### Out of scope

- Multi-ball, configurable physics, settings UI, theming. This is a single fixed demo, not a toy.
- Mobile / touch support beyond "doesn't crash on tap." No portrait mode.
- Headless / server-side rendering, SSR, accessibility flourishes beyond basic `aria-label`.
- WebGL / Three.js / any 3D framework — explicitly rejected in §3.1.
- Recreating the Amiga's full color cycling subsystem in general — only the specific 14-entry cycle the demo uses.
- Recreating the audio.device channel allocation protocol — WebAudio's stereo bus replaces it.
- The Workbench / Intuition multitasking demonstration — there is no OS to multitask with in a browser tab.

---

## Background — what we're recreating

The reference implementation is this repository's `boing.s` (a vasm-assembleable splitting of Harry "Piru" Sintonen's disassembly of the AMICUS Disk 9 PD binary). It is fully analyzed in these top-level docs in this repo:

- **[ANIMATION-DETAILS.md](../docs/ANIMATION-DETAILS.md)** — ⭐ **start here for the numbers.** Motion/timing/distances *measured from a UAE recording* and reconciled with source: ball size (111×96 px), travel ranges, speeds, bounce period (3.85 s), the elastic-no-damping result, and a drop-in recreation recipe (§0/§9). Supersedes the by-eye estimates in §4–§7 below where they differ.
- **[BOING-ANALYSIS.md](../docs/BOING-ANALYSIS.md)** — per-function source analysis. The single most important reference: §4 covers the animation technique in full, §4.4 covers the sphere mesh, §5 covers audio, §8 lists non-obvious tricks.
- **[DEMO-BACKGROUND.md](../docs/DEMO-BACKGROUND.md)** — history, variant lineage, what people saw and heard. §4 and §6 are most relevant for visual identity; §7.9 is the variant comparison table.
- **[AMIGA-KNOWHOW.md](../docs/AMIGA-KNOWHOW.md)** — hardware/OS reference. Not required for the browser port, but explains *why* the source does what it does.

If you are implementing this spec and have access to those files: read **BOING-ANALYSIS.md §4 in full** before starting. The spec below distills it but cannot replicate every nuance. If you do not have access to them, this spec stands alone.

---

## Design

### 3. Approach

#### 3.1 Tech stack — chosen and rejected

**Chosen:** TypeScript + Vite, vanilla Canvas2D rendering, WebAudio for sound. No framework, no 3D library, no state management library.

Rationale: the entire app is one Canvas, one animation loop, one audio buffer, one keyboard handler. React/Vue/Svelte add zero value here and 200KB+ of bundle. Canvas2D's `putImageData` lets us implement *literal palette cycling* (rebuild the indexed-color → RGBA mapping every frame, paint with `putImageData`) which is the closest browser idiom to what the Amiga chipset does. Vite gives modern DX (TS, HMR, single-file build output) without lock-in.

**Rejected — WebGL / Three.js / Babylon.** A textured-sphere approach with `rotation.y += dt` is the obvious lazy implementation and *does not produce Boing*. The stripe pattern would not be a half-cycle-offset diagonal spiral; the "rotation" would be a literal mesh rotation rather than a marching palette; the rim-darken-over-floor trick has no clean GL analogue. We'd lose all four technique signatures listed in Intent.

**Rejected — SVG / DOM animation.** SVG can do the sphere as filled polygons, but per-frame palette swaps mean mutating CSS variables on hundreds of `<polygon>` elements — slow and clunky. No clean path to the bitplane-overlap composite either.

**Rejected — plain JS, no TypeScript.** The palette/index math, the sphere vertex tables, and the bitplane composite logic all benefit from typed arrays and named structs. TS catches a class of bugs that would be tedious to chase in this code shape.

**Rejected — React / Vue / framework.** No state surface large enough to justify it. One `requestAnimationFrame` loop manages everything.

#### 3.2 Rendering pipeline — overview

The Amiga used 5 bitplanes (5 bits per pixel = 32 colors via palette). We emulate this with a single Uint8Array "indexed framebuffer" the same logical size, plus a `Uint32Array(32)` palette. Every frame:

1. **Physics** — advance ball position, detect impacts, set impact flags.
2. **Palette cycling step** — rotate the 14 stripe colors in palette slots 2..15 and 18..31, write the highlight ("pink") color into the right slot for current direction. ~60 word-writes-equivalent; trivial CPU.
3. **Composite** — for each visible pixel, look up palette index from the indexed framebuffer, apply the ball offset (positional scroll), apply the bg offset (zero — bg is fixed), write the resulting RGBA to an `ImageData` buffer.
4. **Blit** — `ctx.putImageData(imageData, 0, 0)` for the 1× framebuffer; the canvas is CSS-scaled to integer multiples for the visible size.
5. **Audio dispatch** — if an impact flag is set, trigger the appropriate WebAudio source with computed pan and gain.

The **ball bitmap** (the 5-bit-per-pixel indexed image of the rasterized sphere) is computed **once at startup** (§4 below) into a sub-region of the framebuffer. After that, it is never re-rasterized. This is the load-bearing fidelity invariant.

The **wireframe room** is likewise drawn **once at startup** into a fixed bitplane-5-equivalent overlay buffer, then composited every frame without redraw.

#### 3.3 The "two-buffer" architecture

To allow ball-vs-background-overlap detection (for the rim-darken trick) without re-rasterising, keep two indexed-color buffers:

- **`ballBuf`** — `Uint8Array(BW × BH)`. Pixel value 0 = transparent, 1 = silhouette (rim), 2..15 = facet colors. Drawn once at startup. Size big enough to allow ball offset within (logical 336×216 like the Amiga buffer; matches the source).
- **`bgBuf`** — `Uint8Array(W × H)` matching the visible 320×200 area. Pixel value 0 = sky, 1 = wireframe. Drawn once at startup.

Per-frame composition rule for output pixel `(x, y)`:

```
ball_index = ballBuf[ x + ball_offset_x, y + ball_offset_y ]   // 0 if outside ball region
bg_bit     = bgBuf[ x, y ]                                     // 0 or 1
if ball_index == 0:
  palette_index = (bg_bit == 0) ? 0 : 16          // sky or wireframe
elif ball_index == 1:
  palette_index = (bg_bit == 0) ? 1 : 17          // ball-rim sky / rim-over-wireframe
else:
  palette_index = (bg_bit == 0) ? ball_index : ball_index + 16   // facet stripes (same value either side; see §5)
```

Color lookup: `rgba = palette[palette_index]`.

This is exactly the AMICUS 5th-bitplane palette-half-toggle from BOING-ANALYSIS.md §4.4.6, expressed as JS pixel logic.

### 4. The ball — sphere mesh, color formula, drawing pipeline

This section is the heart of the fidelity. Implement it precisely.

#### 4.1 Mesh topology

- 9 latitude bands, indexed `lat = 0..8` (south pole to north pole).
- 56 longitudes per band, indexed `lon = 0..55`.
- 9 × 56 = **504 vertices** in a regular sphere lat/lon grid.
- 8 inter-band gaps × 56 = **448 quads**; the two polar bands degenerate, leaving ~**392 visible facets** after back-face culling.

For each vertex, compute (use any sane unit system; on a 320×200 viewport the ball **measures ~111 × 96 px on screen** — slightly wider than tall; see [ANIMATION-DETAILS.md](../docs/ANIMATION-DETAILS.md) §6. Earlier "~140×100" estimates were high):

```
theta = (lat / 8) * PI            // latitude angle, 0 = south pole, PI = north pole
phi   = (lon / 56) * 2 * PI       // longitude angle, 0..2PI
x = R * sin(theta) * cos(phi)
z = R * sin(theta) * sin(phi)
y = R * cos(theta)
```

(The AMICUS source halves `y` — `y = cos(theta) / 2` — which slightly squashes the sphere vertically. Optional; producing a circular silhouette is also fine.)

#### 4.2 Per-vertex color formula — THE diagonal stripe

```
vertex.color = ((lat & 1) * 7 + lon) % 14 + 2     // result in 2..15
```

The constant `7` is half the 14-color cycle. Even bands have phase-offset 0, odd bands have phase-offset 7. This produces a **half-cycle offset between adjacent bands**, which appears as a **diagonal spiral** of red and white when the colors at slots 2..15 are 7 red + 7 white + 1 pink-highlight.

When palette-cycling rotates slots 2..15 forward (or backward) by one per frame, the whole spiral marches around the sphere. This *is* the iconic Boing rotation. Drop the `(lat & 1) * 7` term and you get a beach ball — wrong.

#### 4.3 Projection — 2D rotation baked in

Project each vertex to 2D screen coords using an integer matrix that bakes in a camera-angle rotation (the AMICUS source's clever bit — keeps back-face culling cheap):

```
proj_x = 160 + (y/2 + x * 1.6875) / 512
proj_y = 100 + y_offset - (y * 1.4375 - x/2) / 512
```

Values `1.6875 = 2 - 1/4 - 1/16` and `1.4375 = 1 + 1/2 - 1/16` are chosen so the constant matrix can be implemented as shift-and-add on a 68000. They give a ~30° rotation that makes the spiral visibly diagonal. Browser JS doesn't care about the shift-and-add; use the floating-point form.

The `160, 100` center the ball in a 320×200 frame; `y_offset` shifts the ball within the static bitmap so it sits where viewport-scroll motion can offset it both up and down. For the browser port, drop the FFP machinery and just use these constants directly.

#### 4.4 Drawing — silhouette pass + 392 facet quads

**Pass 1 — silhouette polygon:** fill the equatorial-band outline (a ~16-vertex disk-shaped silhouette around the ball) with `palette_index = 1` (the grey shadow color). Implementation: trace the 56 outermost edge vertices into a closed path, fill with index 1.

> **Correction (from source review):** in the AMICUS source this silhouette is **offset ~+25 px to the right** of the colored ball (it is projected with X-centre +185 vs the facets' +160), so it reads as a real **offset drop-shadow** to the lower-right — *not* a co-located rim. For faithful Boing, draw/composite this grey disk shifted +25 px right of the ball, with the facets (Pass 2) on top at the ball's true centre. See [BOING-ANALYSIS.md](../docs/BOING-ANALYSIS.md) §4.4.3.

**Pass 2 — 392 facets:** for each inter-band quad (lat ∈ 0..7, lon ∈ 0..55):

1. **Back-face cull:** check `current_vertex.proj_x > previous_vertex.proj_x` (where "previous" is the corresponding vertex one longitude back). If false, skip the quad.
   - This is the cheap winding-order test; works only because the projection bakes in the camera rotation. See BOING-ANALYSIS.md §4.4.4 / §8.9.
2. **Fill the quad** with the four vertices' projected positions, using `palette_index = vertex.color` (computed in §4.2).

Because the facets sit at the ball's true centre while the grey silhouette is offset right (Pass 1), the facets overpaint the left of the grey disk and leave it exposed as the **offset drop-shadow** on the lower-right. (Pen-1 also shows at the very rim where back-facing facets are culled, but the dominant effect is the offset shadow — see the Pass 1 correction above.)

All of Pass 1 + Pass 2 happens **once** at startup, into `ballBuf`. Implementation note: Canvas2D's polygon-fill can drop sub-pixel anti-aliasing if you want a pure indexed image; alternatively, render each quad to a temporary 1-bit mask via an off-DOM canvas and resolve to the nearest palette index per pixel.

### 5. The palette — 32 entries, cycled every frame

Define the palette as 32 RGBA values. Amiga 4-bit-per-channel `$0RGB` values translated:

| Slot | Amiga | Browser RGB | Role |
|---|---|---|---|
| 0  | `$0AAA` | `#AAAAAA` | Background sky |
| 1  | `$0666` | `#666666` | Ball silhouette / rim |
| 2..8  | 7 entries cycled, see below | RED stripe positions |
| 9..15 | 7 entries cycled | WHITE stripe positions |
| 16 | `$0A0A` | `#AA00AA` | Wireframe-overlap sky (magenta) |
| 17 | `$0606` | `#660066` | Wireframe-overlap ball-rim (dark magenta) |
| 18..31 | mirror of 2..15 every frame | (KEEP IN SYNC) |

Stripe values per cycle:
- White: `#FFFFFF` (Amiga `$0FFF`)
- Red: `#FF0000` (Amiga `$0F00`)
- Pink highlight: `#FFDDDD` (Amiga `$0FDD`)

**Per-frame palette update (the "rotation"):**

```
// rot_phase is incremented (if vx < 0) or decremented (if vx >= 0) each frame, wrapped modulo 14
// Write 7 white entries, 7 red entries, 1 pink highlight, in slots 2..15 (and mirror to 18..31).

for (let i = 0; i < 7; i++) {
  let slot = ((i + rot_phase) % 14) + 2;   // 7 white stripes
  palette[slot] = palette[slot + 16] = WHITE;
}
for (let i = 7; i < 14; i++) {
  let slot = ((i + rot_phase) % 14) + 2;   // 7 red stripes
  palette[slot] = palette[slot + 16] = RED;
}

// Pink highlight: at offset 0 if moving right, offset 6 if moving left.
let highlightSlot = (vx >= 0)
  ? (rot_phase % 14) + 2
  : ((6 + rot_phase) % 14) + 2;
palette[highlightSlot] = palette[highlightSlot + 16] = PINK;
```

(See BOING-ANALYSIS.md §4.1 / §4.4.6 for the original; the `.palette_step` block in `src/main.s` is the reference assembly.)

### 6. Physics

Pure Newtonian with energy loss on impact. The AMICUS source uses FFP-mixed-with-integer math; we use plain JS Number.

#### 6.1 State

```ts
let x: number;       // ball center X in "virtual screen pixels", range roughly -80..+104
let y: number;       // ball center Y, vertical, gravity acts here
let vx: number;      // X velocity (px/frame at 60fps)
let vy: number;      // Y velocity (px/frame at 60fps)
let rotPhase: number; // 0..13, increments/decrements per frame based on sign(vx)
let running: boolean; // pause flag
```

#### 6.2 Constants (from AMICUS source where known; otherwise tuned to feel right)

| Constant | Value | Source |
|---|---|---|
| Left X bounce limit | `-80` | `src/main.s:215` (`_left = -80`) |
| Right X bounce limit | `+104` | `src/main.s:217` (`_right = +104`) |
| Initial X | 0 (center) | source default |
| Initial Y | top (e.g., -50) | the demo starts mid-air, falls |
| Initial vx | `+1` or `-1` integer | source |
| Initial vy | `0` | source |
| Gravity per frame | tune to feel right (try ~0.4 px/frame²) | not directly captured; see open Q |
| Bounce damping (floor) | 1.0 then -1.0 reflect | `src/main.s:1541` block |
| Bounce damping (walls) | 1.0 then -1.0 reflect (no damping) | `src/main.s:1591` / `:1605` |

The AMICUS source's exact Y-physics constants involve FFP math that this spec deliberately abstracts (the open question is whether the implementer wants to extract them precisely — see Open Questions). For first-cut, tune by eye until the bounce feels right.

#### 6.3 Per-frame update

```
if (!running) return;

vy += gravity;
x += vx;
y += vy;

if (y >= floorY) {            // floor impact
  y = floorY - (y - floorY);  // reflect
  vy = -vy;                    // also damp here if you want energy loss
  triggerAudio("floor", x);
}
if (x <= LEFT)   { x = 2*LEFT  - x;  vx = -vx; triggerAudio("wall", +1); }
if (x >= RIGHT)  { x = 2*RIGHT - x;  vx = -vx; triggerAudio("wall", -1); }

rotPhase = (vx >= 0)
  ? (rotPhase + 13) % 14    // decrement, wrap
  : (rotPhase + 1)  % 14;   // increment, wrap
```

Note: the AMICUS code *contains* a floor-damping term but it is **inert** (`_dampy=0`, dead code — see [ANIMATION-DETAILS.md](../docs/ANIMATION-DETAILS.md) §4), so the AMICUS ball is **perfectly elastic and never settles** — the "minimum-velocity clamp that stops the ball" only triggers in a degenerate case that normal play never reaches. So: don't damp to rest; keep `vy` magnitude constant across the floor bounce (measured bounce period ≈ 3.85 s, constant). The original demo never "settles."

### 7. Display geometry and scaling

The "virtual screen" is 320×200 pixels. Render at 1× into the indexed framebuffer, then scale up via CSS for display.

**Default:** 4× CSS scale (1280×800 visible). Center the canvas in the viewport with a dark background. Use `image-rendering: pixelated` so scaling produces hard pixels, not blurry interpolation. The Amiga's NTSC pixel aspect ratio is approximately 1:1.2 (slightly tall), but the demo was designed to look right at 1:1; render square pixels and don't worry about it unless the implementer wants pixel-accurate NTSC.

**Frame loop:** `requestAnimationFrame`. Target 60 Hz; the original ran at NTSC 60 Hz field rate. If `rAF` delivers >60 Hz on a high-refresh display, either cap the physics to 60 Hz internally or run at native rate and tune the gravity constant accordingly.

### 8. The wireframe room

Drawn ONCE at startup into `bgBuf` (1 = line, 0 = empty):

- A back wall as a rectangle in the upper portion of the frame, with vertical and horizontal grid lines forming a rectangular grid.
- A perspective floor made of **4 trapezoidal rows** receding into the back wall — each row's vertical edges converge toward a vanishing point at the back wall's horizontal center.
- Radial "ray" lines fanning out from the vanishing point through each floor row, intersecting the back wall.

The exact geometry is hand-coded in `src/main.s` (the `.bgrenderloop` block, see BOING-ANALYSIS.md §8.8) — not procedural. A clean modern recreation is acceptable: take a screenshot of the AMICUS Boing running in UAE (the `uae/` directory in this repo has a working setup), measure the line positions, hard-code them. Or eyeball it from the canonical Boing screenshots referenced in DEMO-BACKGROUND.md.

Lines are drawn with `palette_index = 1` (the bg-bit), which makes them magenta (`#AA00AA`) when composited (see §3.3 rule).

The wireframe must not animate. The sky behind it is flat `#AAAAAA`.

### 9. Audio

#### 9.1 Sound source

The original Amiga `boing.samples` file is in this repository (`boing.samples` in the repo root, also `uae/dh0/boing.samples`; 24706 bytes). Format:

- Bytes 0..1: header (a 2-byte word with value 2; not audio data)
- Bytes 2..24705: 8-bit signed PCM, mono

There's exactly **one sample** in the file — the metallic "BOING!". Both floor and wall impacts replay the same sample at different Paula periods:

- **Floor impact (`_bperiod = 255`):** Paula period 255 → NTSC sample rate ≈ 14036 Hz (lower pitch, deeper)
- **Wall impact (`_speriod = 160`):** Paula period 160 → NTSC sample rate ≈ 22372 Hz (higher pitch)

For the browser:

- Recommended: bundle the original `boing.samples` file as a static asset, parse 8-bit signed PCM starting at byte offset 2, load it into a WebAudio `AudioBuffer` at a chosen native sample rate (e.g. 22050 Hz), and pitch-shift via `AudioBufferSourceNode.playbackRate`.
- Floor playback rate: `14036 / 22050 ≈ 0.637`.
- Wall playback rate: `22372 / 22050 ≈ 1.015`.

Alternative — if licensing the original sample is a concern (it should not be; the PD binary has been freely distributed since 1985, and the foley source is "Bob Pariseau hitting an aluminium garage door with a foam bat, digitized by an Apple II" per Amiga lore), synthesize a comparable metallic clang. But the original sample is part of the demo's identity.

#### 9.2 Volume

- Floor: `vol = 1.0` (max).
- Wall: `vol = 40/63 ≈ 0.635` (the AMICUS ratio).

#### 9.3 Stereo pan — volume + inter-aural time delay

This is the subtle bit. Don't just `pan = x / RIGHT`. The AMICUS source plays the sample on TWO channels:

- **Lead channel** (the side the ball is closer to): full volume, sample plays from offset 0.
- **Follow channel** (the far side): reduced volume AND starts playing the sample a few samples later, i.e. an **inter-aural time delay**.

The volume of the follow channel is `vol * (54613 - |balance|) / 54613` where `balance` is the X position projected to a signed range. Re-target to browser:

```
// pan in [-1, +1] from ball X position
let pan = clamp(x / RIGHT, -1, +1);
let leadGain = vol;
let followGain = vol * (1 - Math.abs(pan));
let delaySeconds = Math.abs(pan) * MAX_DELAY_SEC;  // try 4-8 ms max

// In WebAudio:
//   leadSource → leadPan → destination   (panned to lead side)
//   followSource → delay → followPan → destination  (panned to follow side, delayed)
```

Max delay should be in the 4–8 ms range to feel natural. The AMICUS source uses `_maxDelay = 10` "demo units" which translates to roughly 10 ms at the typical sample rate.

For floor bounces, balance is `-_x * 384` (effectively `pan = -x / RIGHT` since the floor sound spatializes opposite to ball position — the impact is *under* the ball). For wall bounces, balance is hard-coded `+30000` (left wall → pan right) or `-30000` (right wall → pan left) — the impact comes from the opposite side. See `src/main.s:1747` and `:1762`.

### 10. Interaction

- **Click or Space:** toggle pause/resume.
- **Esc or Q:** no quit (it's a webpage). If the user opens this in a screensaver-style context, optional `Esc → close()` is OK but not required.
- **Right-click:** the original demo used right-mouse for pause. Browser convention is right-click=context-menu, so map to Space/click instead. Don't preventDefault on right-click.

No other UI. No buttons, no settings panel.

---

## Implementation plan

A reasonable task order. Each task should be a separate commit per the guide's atomic-commit discipline.

- [ ] **Bootstrap.** `npm create vite@latest boing-web -- --template vanilla-ts`. Strip the demo template; leave one `index.html`, one `src/main.ts`, one `src/style.css`.
- [ ] **Canvas + scaled CSS.** Create a 320×200 canvas, CSS-scale it 4×, `image-rendering: pixelated`, centered black background.
- [ ] **Indexed framebuffer + palette.** Set up `Uint8Array(320*200)` indexed buffer, `Uint32Array(32)` palette, an `ImageData` for output. Wire a `composite()` function that walks pixels and applies the §3.3 rule. Verify by filling the buffer with sample indices and checking colors render.
- [ ] **Palette cycling test.** Hard-code the 14 stripe slots to 7 white + 7 red + 1 pink, run the per-frame rotation, and paint a static test pattern (vertical bars index 2..15) to verify the rotation visibly marches.
- [ ] **Wireframe room.** Draw the back-wall grid + 4 perspective floor rows + radial rays into `bgBuf`. One-shot at startup; verify it renders correctly composited (magenta lines on grey sky).
- [ ] **Sphere mesh: vertex generation + projection.** Generate the 504 vertices with §4.2 color formula, project to 2D with §4.3 matrix.
- [ ] **Sphere mesh: silhouette pass.** Fill the equatorial outline with index 1. Verify the ball appears as a uniform-dark-grey disk.
- [ ] **Sphere mesh: facet pass + back-face cull.** Render all 392 quads with their per-vertex colors. Verify the diagonal stripe pattern.
- [ ] **Physics.** Implement §6.3 update; verify the ball bounces around the box without audio.
- [ ] **Animation loop.** `requestAnimationFrame`, per-frame: physics → palette step → composite → blit. Verify the ball is moving and rotating, the wireframe is fixed, and the rim darkens where the ball overlaps the floor.
- [ ] **Audio.** Load `boing.samples`, build the floor / wall buffers, wire WebAudio with delay+pan per §9.3. Verify the impact triggers play with stereo movement.
- [ ] **Pause / resume.** Click and Space toggle `running`. When paused, no physics step, no palette step. (Display stays.)
- [ ] **Polish.** Fullscreen mode (optional `f` key). Title, brief credit footer. Build production bundle (`npm run build`) and verify the static output works opened directly in the browser.

Estimated time for a competent developer with this spec in hand: **6–12 hours** end to end, including verification.

---

## References

- This repository's source-of-truth analysis:
  - [BOING-ANALYSIS.md](../docs/BOING-ANALYSIS.md) — read §4 in full
  - [DEMO-BACKGROUND.md](../docs/DEMO-BACKGROUND.md) — §4 (what people saw), §6 (technique), §7.9 (variant table)
  - [AMIGA-KNOWHOW.md](../docs/AMIGA-KNOWHOW.md) — optional, for hardware context only
- Specific assembly references inside this repo:
  - `src/main.s` — `_main`, palette-step block (`.palette_step` ~line 1200), physics (`.physics_y`/`.physics_x` ~1540–1610), audio dispatch (`.audio_floor`/`.audio_left`/`.audio_right` ~1720–1770), data constants (~1840–1900)
  - `src/globe.s` — `_init_globe` (sphere math), `_draw_globe` (silhouette + facet rendering)
  - `src/anim.s` — `_Boing` audio routine, audio.device sequence; the stereo delay logic is in `.voice_loop`
- External / historical:
  - [Jimmy Maher, *The Future Was Here* Ch. 2 "Boing"](https://direct.mit.edu/books/book/4417/chapter/189199/Boing) — MIT Press, 2012. The most rigorous academic analysis. His `boing5.c` reconstruction (linked in DEMO-BACKGROUND.md §7.4) is the closest published C analogue.
  - [Amiga Graphics Archive: AmigaBoingBall](https://amiga.lychesis.net/applications/AmigaBoingBall.html) — visual reference, screenshots
  - [pouët.net: Boing](https://www.pouet.net/prod.php?which=27096) — community technical notes
- Asset:
  - `boing.samples` (repo root, or `uae/dh0/boing.samples`) — the original 8-bit signed PCM sound effect (header 2 bytes, then PCM). Copy into the new project's `public/` or `assets/`.

---

## Non-goals (re-stated for emphasis)

- **No 3D engine.** No Three.js, no WebGL shaders, no `<canvas>` 3D context. Pure 2D indexed-color compositing.
- **No physics tuning UI.** Constants are baked in.
- **No multi-ball, no theming, no settings.**
- **No mobile-first responsive layout.** It's a desktop demo.
- **No build-time sample re-encoding** to MP3/Ogg. Ship the raw `boing.samples` file (24KB; trivially small).
- **No back-compat with old browsers.** Modern Chrome / Firefox / Safari only. ES2022, WebAudio, `OffscreenCanvas` if useful.

---

## Open questions

These are choices the spec deliberately leaves to the implementer. Resolve them before starting, or with the first commit of substance:

1. **Sphere y-squash.** AMICUS uses `y = cos(theta) / 2` (vertical squash). **Measured (UAE recording, see [ANIMATION-DETAILS.md](../docs/ANIMATION-DETAILS.md) §6): the rendered ball is ~111 × 96 px — i.e. WIDER than tall (~1.16:1), not taller.** (An earlier draft of this note guessed "taller than wide" — that was backwards: a vertical squash makes the ball shorter in Y, hence wider.) Decide: replicate exactly (~111×96), or use round sphere geometry (simpler, less iconic).
    - ==> use round sphere geometry

2. **Gravity & impact damping constants.** **Resolved by measurement — see [ANIMATION-DETAILS.md](../docs/ANIMATION-DETAILS.md) §0/§4.** Key correction: there is **no damping** (`_dampy=0` is dead code) — the ball bounces forever at constant height; don't add energy loss. Measured bounce period ≈ 3.85 s, vertical travel ≈ 90 px, apex dwell ≈ 0.8 s (on the CPU-bound ~25 Hz update rate; see §1 of that doc — driving 1 step/frame at 60 fps would run ~2× too fast). The implementer can still hand-tune to feel, but these are the real targets.
    - ==> (c)

3. **Wireframe room exact geometry.** Currently described loosely. The implementer should either: (a) measure from a screenshot, (b) port the line-drawing code from `src/main.s` `.bgrenderloop` (hand-coded coordinates, see BOING-ANALYSIS.md §8.8), or (c) eyeball it from canonical images. Default: (b) for fidelity.
    - ==> (b)

4. **Audio sample fidelity.** Ship the original `boing.samples` byte-for-byte (recommended; PD since 1985), or synthesize a clang? Default: original.
    - ==> original

5. **Visible canvas size at default load.** 4× scale = 1280×800. Some monitors want 5× (1600×1000) or fullscreen. Default: 4× with optional fullscreen on `f` key.
    - ==> Default

6. **Should the ball ever come to rest?** Original demo doesn't; energy is loosely conserved so it bounces forever. Default: never rests. (Add a tiny energy boost to the floor bounce if needed to fight floating-point drift.)
    - ==> Default

7. **Touch / mobile.** Out of scope per §10, but: should the page render at all on mobile (gracefully scaled), or display "desktop only"? Default: render but unsupported.
    - ==> Default

---

## Notes from implementation

*(empty — to be filled by the implementer as they go: surprises, deviations, lessons)*
