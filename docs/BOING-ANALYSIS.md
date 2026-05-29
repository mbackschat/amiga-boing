# BOING-ANALYSIS.md — How this Boing source actually works

Companion to [AMIGA-KNOWHOW.md](AMIGA-KNOWHOW.md) (the hardware/OS reference) and [DEMO-BACKGROUND.md](DEMO-BACKGROUND.md) (the variant history). This document is the **technical analysis of the source in this repository**, written after a thorough reading of every function in `src/*.s`.

The single most important finding, up front:

> **This polite AMICUS Disk 9 Boing uses the same fundamental animation techniques as the lost 1984 CES original**: a static ball bitmap (in fact a 392-facet tessellated polygon mesh whose per-facet colors form a diagonal-stripe spiral — see §4.4), **palette-register cycling** for rotation, and **ViewPort `RxOffset`/`RyOffset` writes** for motion. The polygon-fill (`_init_globe` + `_draw_globe`) runs **once at startup** to *create* the static mesh; per-frame work is the cycle + scroll, not a redraw.
>
> This corrects the earlier characterization in DEMO-BACKGROUND.md §7.4/§7.9 that this source "redraws the ball each frame as polygons." It does not. The polygon machinery is the bitmap-author equivalent — Maher's reconstruction skips it by pre-baking the bitmap into a `__chip` array. The AMICUS version computes the bitmap programmatically. After the bitmap exists, both implementations use the same palette-and-scroll dance.

---

## 1. Identity of the source

- **What it is:** disassembled compiled C from the AMICUS Disk 9 binary, originally distributed by Commodore-Amiga as a developer sample. Sintonen's disassembly, split into `src/*.s` files for readability, then commented and re-labelled by this project. Provenance chain documented in [DEMO-BACKGROUND.md §7.3](DEMO-BACKGROUND.md).
- **Toolchain it was compiled with:** Lattice C 5.02 targeting Kickstart 1.x. Evidence: `link a6,#-N` C-style stack frames; the runtime stubs `_Open`, `_Disable`, `_AllocMem`, `_BeginIO`, `_Sine16`, `POSDIV`, `_strlen`, `_SPSin`, etc. are all the standard Lattice C 5.02 library glue.
- **Build path (preserved from the original):** `vasmm68k_mot -m68000 -Fhunk -linedebug boing.s` → `vlink -bamigahunk -Bstatic boing.o` → `uae/dh0/boing`.

---

## 2. Three concentric layers

| Layer | Files | Lines | Role |
|---|---|---|---|
| **Lattice C startup** | `src/startup.s` | ~195 | The `c.o` boilerplate. Entry point at top, CLI/WB detection, argv parser, `openDOS`, exit handlers. Identical to every other Lattice C 5.02 Amiga executable from this era. |
| **Application** | `src/anim.s` + `src/globe.s` + `src/main.s` | ~2275 | The four named C functions: `_main`, `_GoodBye`, `_init_globe`, `_draw_globe`, `_Boing`, `_initCleanup`, `_InitBoing`, `_CleanUp`, plus all CHIP RAM globals. |
| **Lattice C runtime** | `src/runtime.s` | ~840 | Integer math helpers (`_Sine16`, `_Cosine16`, `POSDIV`, `LONGDIV`, `ldivt`, `ulmult`), FFP math wrappers (`jmp_so`, `jmp_do`, `ffixi`, `faddi`, etc.), and one trampoline per used library entry point (`_Open`, `_Disable`, `_AllocMem`, `_OpenScreen`, `_SetAPen`, …). Pure plumbing. |

Reading the *demo* means reading the middle layer. The outer two are vendor code that doesn't change between Lattice C programs and can be ignored for understanding what Boing does.

---

## 3. The execution timeline

A full program lifecycle, with key code locations now annotated and re-labelled. Phase numbers match the Phase banners inside `src/main.s` so you can cross-reference directly:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ AmigaDOS loader                                                          │
│   → entry point in src/startup.s                                         │
│       - FindTask(NULL) → A4 = Process *self                              │
│       - tst.l pr_CLI(a4) → CLI vs Workbench                              │
│       - openDOS → cache _DOSBase                                         │
│       - argv build (CLI) OR WaitPort+GetMsg WBStartup (WB)               │
│       - jsr _main                                                        │
│                                                                          │
│ _main (src/main.s) ─ Phases 1..15 (same numbering as source comments):   │
│   Phase  1: .open_gfx → .open_intuition → .open_mathffp →                │
│              .open_mathtrans  (OpenLibrary; bail .no_xxx → _exit)         │
│   Phase  2: Initial constants: _left=-80, _right=+104, pen cache=$0FDD,  │
│              _firsttime=1                                                 │
│   Phase  3: InitBitMap(320×200×5) + InitArea(50 vertices) +              │
│              AllocMem(40824, MEMF_CHIP) for 4 bitplanes + 4536-byte      │
│              scroll buffer + BltClear, then re-InitBitMap(336×216×5)     │
│              and patch Planes[0..3] into the chunk                       │
│   Phase  4: .alloc_bg_loop ×16 AllocRaster for the 16 STAGGERED          │
│              background bitplanes (sub-byte horizontal alignment trick)  │
│   Phase  5: Build NewScreen on stack → OpenScreen                        │
│              (CUSTOMSCREEN | CUSTOMBITMAP)                               │
│   Phase  6: Build NewWindow on stack → OpenWindow                        │
│              (BORDERLESS | BACKDROP, IDCMP=CLOSEWINDOW|MOUSEBUTTONS)     │
│   Phase  7: ScreenToBack; cache RastPort, ViewPort, ColorMap, ColorTable │
│              into A3 / _viewport / _cm / _ct                             │
│   Phase  8: AllocRaster scratch for AreaInfo + InitTmpRas, SetRast       │
│   Phase  9: _init_globe (sphere math) + _draw_globe (paints BALL ONCE)   │
│   Phase 10: .bgrenderloop ×16: render wireframe room 16 times, each      │
│              shifted by 1px, into the 16 staggered _bgptr planes         │
│   Phase 11: SetRGB4 ×4: define palette entries 0, 1, 16, 17              │
│   Phase 12: Reset physics state; jsr _InitBoing (open audio.device,      │
│              load boing.samples)                                          │
│   Phase 13: Final RastPort tweaks (rp_AreaPtrn, rp_Mask) + the ONE       │
│              direct chipset poke: DMACON ← DMAF_RASTER|DMAF_SETCLR       │
│                                                                          │
│   Phase 14: .mainloop ─ per frame:                                       │
│     .handle_msg / .check_lmb / .check_rmb / .toggle_run                  │
│        → IDCMP poll, run/pause toggle, .do_close → _GoodBye              │
│     .nomsg: if running → animate (below); if paused → WaitTOF, loop      │
│        (running-path pacing = the WaitTOF inside RethinkDisplay)         │
│     .palette_step: cycle COLOR02..15 and COLOR18..31                     │
│        (14 entries per half: 7 WHITE + 7 RED + 1 PINK highlight)         │
│     .physics_y / .physics_x: FFP + integer Newtonian motion              │
│        → set _boing = 1/2/3 if hit floor/left/right                      │
│     .scroll_apply: write RxOffset/RyOffset, swap _bgptr[x&15], subtract  │
│        X/Y back from BitMap.Planes[4] to keep background visually fixed  │
│     MakeScreen + RethinkDisplay → commit copperlist; RethinkDisplay      │
│        also WaitTOFs → this is the running loop's frame pacing           │
│     .audio_floor / .audio_left / .audio_right:                           │
│        jsr _Boing(period, vol, balance)                                  │
│     bra .mainloop                                                        │
│                                                                          │
│   Phase 15: .first_frame_init: SetPointer(_DotPointer) — installed once  │
│              after the first frame completes, so the cursor doesn't      │
│              flash during the lengthy Phase 9–11 startup                 │
│                                                                          │
│ _GoodBye (src/main.s) ─ on user quit                                     │
│   FreeRaster _arearas, ClearPointer, CloseWindow, CloseScreen            │
│   FreeRaster ×16 for the staggered bg planes                             │
│   FreeMem _bigmem (40824 bytes)                                          │
│   jsr _exit → CloseLibrary _DOSBase → Forbid+ReplyMsg WBStartup → RTS    │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 4. The animation technique, in detail

### 4.1 The ball: static bitmap, palette-cycled "rotation"

`_draw_globe` is called **once**, from `_main` Phase 9 (see `src/main.s` Phase 9 banner and the timeline in §3 above). It paints the ball polygons into bitplanes 1..4 via graphics.library `AreaMove` / `AreaDraw` / `AreaEnd`, with 16 vertices per polygon. The geometry comes from `_init_globe`'s precomputed `_globe[]` vertex table.

After that single call, **the ball's bitplane bits never change for the rest of the program's life.** (Mechanically, the ball is not a flat bitmap — it's a tessellated polygon mesh with 392 per-facet-colored quads. See §4.4 for the mesh structure that gives the rotation its diagonal-stripe pattern.)

Per-frame rotation is achieved by rewriting the **palette entries** that the ball's pixels reference. Each ball pixel encodes a color index in 2..15 (low half) or 18..31 (high half — the 5th bitplane bit selects; see §4.4.6 for what the high-half-toggle achieves). The 14 entries in each half are rewritten every frame:

- 7 are written to `$0FFF` (white)
- 7 are written to `$0F00` (red)
- 1 is written to `$0FDD` (pink-white highlight)

The phase of the rotation lives in D4 (incremented or decremented per frame based on `_vx`'s sign, wrapping modulo 14). Reading the renamed code in `.palette_step`, you can see the structure clearly:

```
.palette_step  : entry from .nomsg
.dir_left      : _vx < 0  → D4++
.dir_right     : _vx ≥ 0  → D4--
.dir_wrap_neg  : D4 = -1  → D4 = 13
.dir_wrap_pos  : D4 = 14  → D4 = 0
.white_loop    : write 7 white stripes at (D0+D4) mod 14 + 2,
                 and again at + 18 (high palette half)
.dir_test_pink :
.pink_left     : (vx<0 path) write pink at D4+6
.pink_right    : (vx≥0 path) write pink at D4+0
.red_loop      : write 7 red stripes at (D0+D4) mod 14 + 2,
                 again at + 18
.physics_y     : continue to Y physics
```

**CPU cost per frame:** roughly 60 `move.w` writes to chip RAM (14 entries × 2 halves × 2 stripes-or-pink), plus the modular index arithmetic. **The bitplane DMA does everything else for free.** This is precisely the original CES technique: push CPU work to near zero, let the chipset do the work.

### 4.2 The ball: motion via ViewPort offsets

When `_vx` is non-zero, the ball appears to translate horizontally; same vertically with `_vy`. **No bits are moved.** Instead, `.scroll_apply` writes:

```
ViewPort.RasInfo.RxOffset =  high-word(_x)      ; signed horizontal scroll
ViewPort.RasInfo.RyOffset = -_y_lower            ; signed vertical scroll
```

These tell Agnus to start fetching the bitplane data from a different offset within the (336×216) source bitmap. The (320×200) display window then shows a different part of the same bitmap, and since the ball was drawn near the center, it appears to slide. The leading `$11B8` (4536-byte) buffer at the start of `_bigmem` exists precisely to let `RyOffset` go up to 100 lines negative without exposing uninitialized memory above the bitplanes.

### 4.3 The background: 16 staggered copies, one per X-scroll alignment

Bitplane 5 holds the wireframe "room" background. Crucially, the background must appear **fixed** while the ball plane scrolls — so the demo cancels the scroll on the background plane by:

1. **Coarse compensation (full-byte X steps):** offset the bitplane's `BitMap.Planes[4]` pointer by `-(_x >> 4) * 2` bytes.
2. **Fine compensation (sub-byte X alignment):** swap `BitMap.Planes[4]` to one of 16 pre-rendered staggered copies in `_bgptr[_x & 15]`. Each copy is the wireframe room drawn 1 pixel further right than the previous, so picking the right copy delivers per-pixel horizontal alignment.
3. **Y compensation:** subtract `_y * BytesPerRow` from `BitMap.Planes[4]`.

The staggered-copies trick is necessary because Amiga bitplane pointers must be even-byte-aligned — the smallest pointer step is 16 lo-res pixels. Without the 16 copies, the background would jerk by 16-pixel steps. Maher describes the same trick in `archive/boing-c/boing5.c` lines 786–815.

This is rendered ONCE during init (`.bgrenderloop` × 16 passes), then never redrawn — same pattern as the ball.

### 4.4 The ball isn't a flat bitmap — it's a 392-facet tessellated polygon mesh

A simplification in §4.1 needs correcting: I described "the ball" as if it were a single colored bitmap that gets palette-cycled. That's true at the level of "what the chipset sees once `_draw_globe` has finished," but the *content* of those bitplanes is much more structured than a flat bitmap. The ball is a **tessellated sphere mesh** drawn polygon-by-polygon at startup with per-facet colors that form the diagonal-stripe pattern.

#### 4.4.1 Mesh topology

`_init_globe` builds a sphere vertex table with:

- **9 latitude bands** (D4 = 8 down to 0): from south pole to north pole.
- **56 longitudes per band** (D5 = 55 down to 0): around the sphere's equator.
- **504 total vertices**, each occupying 12 bytes in `_globe[]`:
  ```
  +0  signed word   vertex.x       = sin(latitude) * cos(longitude) >> 16
  +2  signed word   vertex.z       = sin(latitude) * sin(longitude) >> 16
  +4  signed word   vertex.y       = cos(latitude) / 2
  +6  signed word   vertex.proj_x  (written later by _draw_globe Phase B1)
  +8  signed word   vertex.proj_y  (written later by _draw_globe Phase B1)
  +10 signed word   vertex.color   (palette index 2..15, set at init time)
  ```

The mesh has 9 × 56 = 504 vertices and 7 × 56 = **392 quad facets** between adjacent bands (8 inter-band gaps, but the polar gap is degenerate).

#### 4.4.2 Per-vertex color formula and the diagonal-stripe spiral

The `vertex.color` field is computed once per vertex by `_init_globe` as:

```
color = ((D4 & 1) * 7 + D5) mod 14 + 2     ; range 2..15
```

**The "7" is the critical constant** — it equals **half** the 14-element color cycle. So:

- Even-numbered bands (D4 = 0, 2, 4, 6, 8) get colors at phase offset 0.
- Odd-numbered bands (D4 = 1, 3, 5, 7) get the same 14-color cycle but offset by 7 — exactly **opposite phase** from their neighbors.

This produces a **checkerboard-with-phase-shift** colorisation: each band's stripes are halfway-rotated relative to the bands above and below. Visually, the red and white "stripes" form a continuous **diagonal spiral** across the sphere rather than parallel horizontal rings.

When `.palette_step` in `_main` rotates colors 2..15 forward (or backward) by one slot per frame, the **whole spiral marches around the sphere** in lockstep — and because adjacent bands are offset by half a cycle, the diagonal direction of the spiral is preserved. That's what gives the ball its iconic "screw thread rotation" appearance.

This is identical in *technique* to the original 1984 CES demo. The fact that the mesh has per-facet colors with a halfway-offset between bands is the *source* of the diagonal pattern; palette cycling is the *animator*.

#### 4.4.3 Drawing pipeline: silhouette polygon + 392 facet quads

`_draw_globe` does two distinct things:

1. **Silhouette polygon = an OFFSET DROP-SHADOW (`.vertex_loop` + `.fill_polygon` AreaEnd)**: `SetAPen(rp, 1)` (color 1 = darker grey via COLOR1), then emit a 16-vertex elliptical outline and `AreaEnd`-fill it. Crucially, this silhouette is projected with **X-centre +185** (FFP constant `$B9000048`), whereas the colored facets (step 2) centre on **+160** — so the grey disk is drawn **+25 px to the right** of the ball. It is a genuine **offset drop-shadow**, not a co-located rim. (The constant was previously mis-decoded as "−100", which would have put the shadow off-screen-left; the correct +185 is now annotated in `src/globe.s`.)

2. **Facet quads (Phase B2)**: for each of the 392 inter-band quads, centred on **+160**:
   - **Back-face culling** (next section) — skip the quad if its facet faces away.
   - **`SetAPen(vertex.color)`** — pick the facet's palette index from the precomputed `vertex.color`.
   - **`AreaMove` + 2 or 3 × `AreaDraw` + `AreaEnd`** — fill the quad in that color.

Because the colored ball (centre +160) is drawn over the grey silhouette (centre +185), the facets cover the *left* part of the grey disk and leave it exposed as a **crescent of grey to the lower-right of the ball** — the drop-shadow you see in the demo. (It is *not* a uniform "depth rim"; earlier revisions of this doc described it that way, which is wrong and misleading.) Pen-1 also shows at the very edge where back-facing quads are culled, but the dominant visual is the +25 px offset shadow.

#### 4.4.4 Back-face culling via vertex.x ordering — no normals required

Traditional 3D rendering computes a per-facet **surface normal** and dot-products it with the view direction. The Boing source does something cheaper and almost as effective:

```
; For each facet, compare two of its vertices' X coords:
; - Path .L22 (D4 > 0):  facet visible iff (A3.vertex.x > partner.x)
; - Path .L26 (D4 == 0): facet visible iff (A2.vertex.x > partner.x)
; where "partner" is the previous-longitude vertex of the corresponding band.
```

This works because **after the 2D rotation built into the projection** (see §4.4.5), facets on the front hemisphere have their vertices going **left-to-right** in screen X as longitude advances, while back-hemisphere facets have vertices going **right-to-left**. A simple "is current.x greater than previous.x" test catches the front-facing half cleanly.

It's not strictly correct for arbitrary meshes — it depends on the regular longitude tessellation of a sphere — but for *this* sphere it produces ~196 visible facets per frame and ~196 culled. CPU cost: one `cmp.l` + `sgt` per facet, vs. several muls + a dot product for the proper way.

#### 4.4.5 Integer (not FFP) projection in Phase B1

`_draw_globe` does its silhouette-polygon projection with FFP math (mathtrans.library `SPSin` / `SPCos`), but the **per-vertex projection cache for the 504 facet vertices uses pure integer shifts and adds**:

```
proj_x = 160 + ( vertex.y / 2  +  vertex.x * 1.6875                     ) / 512
proj_y = 100 + (2,a3) - ( vertex.y * 1.4375  -  vertex.x / 2            ) / 512
                                              ; (2,a3) = low_word(_yoff)
```

The multipliers (1.6875 = 2 - 1/4 - 1/16; 1.4375 = 1 + 1/2 - 1/16) are **encoded as shift-and-sub sequences** to avoid muls:

```
D2 = vertex.x << 1            ; vertex.x * 2
D2 -= (vertex.x >> 2)         ;        - vertex.x / 4
D2 -= (vertex.x >> 4)         ;        - vertex.x / 16  → vertex.x * 1.6875
```

This is a manual optimization the C compiler couldn't have done — the constants 1.6875 and 1.4375 are baked into the projection's camera-angle rotation matrix, and the developer (or a hand-optimization pass) chose these specific values because they fit the shift-and-add pattern cleanly. **It's the integer-math equivalent of choosing a power-of-two scaling factor**: makes the inner loop ~3× faster than the FFP version.

The fact that the silhouette uses FFP but the per-vertex pass uses integer shifts shows the developer made a deliberate **inner-loop-speed-vs-precision tradeoff**: the silhouette is one polygon, 16 vertices — FFP precision matters there. The shading pass is 504 vertices, 392 facets — integer speed matters more.

#### 4.4.6 The 5th bitplane as a palette-half-toggle (the "transparency" mechanism)

Reading the Phase 11 SetRGB4 calls in `_main` and the `.palette_step` code in `.mainloop` together reveals a clever palette-overlay trick:

```
COLOR00 = $0AAA  (light grey)    ←─ wireframe-room background "sky"
COLOR01 = $0666  (dark grey)     ←─ ball silhouette rim color
COLOR16 = $0A0A  (magenta)       ←─ wireframe-room background "sky" w/ bg-bit set
COLOR17 = $0606  (dark magenta)  ←─ ball rim color w/ bg-bit set
COLOR02..15  = palette-cycled red/white/pink (low half)
COLOR18..31  = palette-cycled red/white/pink (high half) — KEPT IN SYNC WITH 2..15
```

How the planes combine into a final pixel color:

- Empty pixel (no ball, no bg): planes 1..4 = 0, plane 5 = 0 → COLOR0 = grey "sky"
- Bg only (wireframe room): planes 1..4 = 0, plane 5 = 1 → COLOR16 = magenta wireframe
- Ball silhouette only (no facet drew): planes 1..4 = 1, plane 5 = 0 → COLOR1 = darker grey rim
- Ball silhouette overlapping bg: planes 1..4 = 1, plane 5 = 1 → COLOR17 = darker magenta rim
- Ball facet (front-facing): planes 1..4 ∈ 2..15, plane 5 = 0 → COLOR2..15 = red/white stripes
- Ball facet OVER bg: planes 1..4 ∈ 2..15, plane 5 = 1 → COLOR18..31 = same red/white stripes

The **5th bitplane effectively toggles between the low and high palette halves at the per-pixel level**. The palette is set up so that COLOR2..15 ≡ COLOR18..31 (kept identical by `.palette_step` writing to both halves every frame). That makes the ball color *invariant* to whether the ball overlaps the bg — the ball is fully opaque.

But COLOR0 ≠ COLOR16 and COLOR1 ≠ COLOR17, so the **background and rim do change color** based on bg-plane-bit. That's how the wireframe room is rendered as magenta lines on a grey sky, and how the rim of the ball appears darker over the floor than over the sky.

This is an Amiga-specific palette trick that effectively gives you a **transparency-mask plane** (the 5th bitplane) without the chipset directly supporting transparency. The dual-half palette + plane-5-toggle implements an **on-screen alpha channel** for two states: bg-on or bg-off.

That's why `.palette_step` writes the same color twice per cycle slot (once at COLOR[i+2] and once at COLOR[i+18]). Without that synchronization, the ball would change color where it overlaps the bg — bad for the rotation illusion.

### 4.5 Why the polygon machinery exists if it only runs once

`_init_globe` and `_draw_globe` together compute and rasterize the ball. They run for several seconds at startup, then never again. So why does the source carry ~1000 lines of FFP geometry?

Per Maher's own commentary in `archive/boing-c/boing5.c` line 773:

> "The original Boing demo drew the ball onto the screen programatically, using a series of complex floating point trigonometry functions. This is the main reason for the considerable delay that follows the execution of that program. For the sake of clarity and simplicity, I have chosen to store the image of the ball within my version of the program and merely paint it onto the screen. The original demo having been created before Amiga paint and graphical manipulation programs existed, Luck and Mical obviously did not have the luxury of approaching the problem in this way. This is by far the largest single difference between this reconstruction and the original demo."

So:

- The **original 1984/85 CES Boing** drew the ball programmatically from sphere math, then did palette-cycle + viewport-scroll animation.
- The **AMICUS Disk 9 Boing** (this source) likewise draws programmatically, then does palette-cycle + viewport-scroll.
- **Maher's 2009–2010 reconstruction** (`archive/boing-c/`) pre-bakes the ball bitmap into a `__chip` C array, skipping the geometry phase, but then does the same palette-cycle + viewport-scroll.

So in the technique that *matters* — the per-frame animation — **this source is closer to the original than Maher's reconstruction is.** The geometry slow-start is in fact a *fidelity* feature, not a deviation.

---

## 5. The audio path

Three files cooperate: `_main`'s `.audio_floor` / `.audio_left` / `.audio_right` dispatch (in `src/main.s`), the `_Boing` function (in `src/anim.s`), and the audio.device wrappers (in `src/runtime.s`).

### 5.1 Setup (`_InitBoing` → `_initCleanup(1)` in src/anim.s)

1. Compute `_maxCCDelay = _maxDelay × 3580` (color-clock budget for stereo delay).
2. Compute `_silentLength = (_maxCCDelay / 100) & ~1` (≈ 358 bytes of leading silence).
3. `Lock("boing.samples", READ)`, `Examine` for file size.
4. `AllocMem(silentLength + fileSize, MEMF_CHIP | MEMF_CLEAR)` — chip RAM so Paula can DMA from it. Layout:
   ```
   _silent  → [358 zero bytes][samples...]
   _samples → _silent + 358   = real audio start
   ```
5. Read 2-byte file header (must == 2) and remaining file bytes into the sample area.
6. `CreatePort` → `_audioPort` for reply messages.
7. `AllocMem(ioa_SIZEOF, MEMF_PUBLIC|MEMF_CLEAR)` → `_allocReq` master IOAudio.
8. Fill in `_allocReq` with channel preferences = `_allocMap` (`$03,$05,$0A,$0C` = the four stereo channel-pair candidates).
9. `OpenDevice("audio.device", 0, _allocReq, 0)`.
10. `_sound = 1` (audio is ready).

### 5.2 Per-impact playback (`_Boing` in src/anim.s)

Three callers in `_main`:

```
.audio_floor : _Boing(_bperiod=255, _bvolume=63, balance = -_x * 384)
.audio_left  : _Boing(_speriod=160, _svolume=40, balance = +30000)
.audio_right : _Boing(_speriod=160, _svolume=40, balance = -30000)
```

Inside `_Boing`:

1. **Drain replies** (`.drain_replies`): walk the reply port. Any completed `CMD_WRITE` gets `ADCMD_FREE`'d back to audio.device, then recycled onto `_freeList`. `Disable/Enable` brackets the `Remove` call to prevent the audio interrupt from inserting mid-removal.
2. **Allocate channels** (`.alloc_channels`): send `ADCMD_ALLOCATE` with the master `_allocReq`. audio.device picks one of the four stereo masks and returns it in `io_Unit`. Save the AllocKey per channel into `_key[0..3]` for the eventual `ADCMD_FREE` at shutdown.
3. **Set precedence and pause** (`.setprec_and_stop`): `ADCMD_SETPREC` with `ln_Pri = -period/16` (longer periods win priority), then `CMD_STOP` to pause both channels for synchronized restart.
4. **Voice setup loop** (`.voice_loop`): twice — once per stereo channel:
   - **Voice 1 (delayed/quieter):** ioa_Data = `_samples - extraSamples` (points into the silence prefix), ioa_Volume = `vol × (54613 - |bal|) / 54613` (reduced). The leading silence makes this channel start playing the actual waveform `extraSamples` ticks AFTER the lead channel — an inter-aural time difference, the strongest stereo cue.
   - **Voice 0 (lead/full):** ioa_Data = `_samples` (real start), ioa_Volume = `vol` (full).
5. **Queue writes** (`.queue_write`): for each voice, set ioa_Command = `CMD_WRITE`, ioa_Flags = `ADIOF_PERVOL`, copy ioa_AllocKey, `BeginIO`. Channels are still paused, so the writes queue up.
6. **Start audio** (`.start_audio`): `CMD_START` on the master to unpause both channels simultaneously. The two halves of the sample begin in phase, with the right channel a few samples behind the left (or vice versa, depending on balance sign) — producing the spatial impression.

### 5.3 The one DMACON poke

At `_main` Phase 13, immediately after `jsr _InitBoing` returns (Phase 12) and before entering `.mainloop` (Phase 14):

```
move.w  #DMAF_RASTER|DMAF_SETCLR,(custom+dmacon)   ; = $8100
```

This is the **only direct write to `$DFF000`-range registers** in the entire demo. `DMAF_RASTER` ($0100) | `DMAF_SETCLR` ($8000) sets the bitplane-DMA enable bit.

The most plausible reason: audio.device's `BeginIO`/`WaitIO` handshake leaves the chipset in a transient state with bitplane DMA disabled (or audio.device's own DMA-enable manipulation interferes with bitplane DMA timing). The poke defensively re-enables bitplane DMA so the first frame's display works correctly.

The same effect could be achieved through `LoadView` or graphics.library, but a one-line `move.w` is faster and more direct. The choice to do this in-line rather than via OS calls suggests Luck/Mical knew exactly what state they needed and just set it.

---

## 6. Memory layout

```
CHIP RAM (DMA-able):

  _bigmem (40824 bytes) ────────┐ contiguous via single AllocMem(MEMF_CHIP)
    [4536 bytes scroll buffer]  │  ← absorbs upward RyOffset
    [9072 bytes BitPlane 1]     │  ← drawn into by _draw_globe + .bgrenderloop
    [9072 bytes BitPlane 2]     │  ← these four planes are the BALL
    [9072 bytes BitPlane 3]     │
    [9072 bytes BitPlane 4]     │
                                └─

  _bgptr[0..15] ──────────────── 16 separate AllocRaster calls
    [9072 bytes BG plane 0]     ← shift = 0 px
    [9072 bytes BG plane 1]     ← shift = 1 px
    ...                          ← .bgrenderloop renders one per pass
    [9072 bytes BG plane 15]    ← shift = 15 px

  _arearas (8000 bytes) ──────── 1-plane scratch for AreaEnd / TmpRas

  _silent (~358 + N bytes) ───── audio buffer, leading silence + samples

  _allocReq, Voice1, Voice2 ─── IOAudio structs (each 68 bytes)
                                MEMF_PUBLIC|MEMF_CLEAR (CHIP not required
                                for the structs, but the data they POINT
                                to must be CHIP)

  Intuition-managed:
    Screen struct + RastPort + ViewPort + ColorMap + ColorTable
    Window struct
    Pointer sprite (_DotPointer, 6 words)

FAST RAM (CPU only):
  All other application globals (physics state, library bases, ...)
  Stack frame
```

Total chip RAM use: **40824 + 16×9072 + 8000 + ~25060 (silence prefix + samples) ≈ 219,000 bytes (~214 KiB)**, comfortably fitting the 262,144 bytes (256 KiB) of chip RAM on a stock Amiga 1000.

---

## 7. The renaming convention (now applied)

`.L###` labels were compiler-generated branch targets — opaque. Per [DEMO-BACKGROUND.md §7] and the renaming proposal, every renamed label keeps its `.` prefix (local scope per vasm/Motorola convention) and gets a descriptive snake_case name.

Examples of the difference:

```
Before (after disassembly):                  After rename:

.L124                                        .palette_step
.L116               move.l d0,d2             .white_loop         move.l d0,d2
.L122               addq.l #1,d4             .dir_left           addq.l #1,d4
.L74                move.l ...               .scroll_apply       move.l ...
.L73                ...AreaMove...           .audio_floor        ...
.L27 / .L26 / .L19 / .L20 (in _Boing)        .drain_replies / .alloc_channels /
                                              .voice_loop / .setprec_and_stop
.L46 / .L43 / .L42 / .L41 / .L38 (in        .dg_entry / .vertex_loop /
  _draw_globe outer structure)                .vertex_move / .vertex_draw /
                                              .fill_polygon
```

**Intentionally NOT renamed:**

- `_draw_globe`'s shading-pass inner labels `.L11..L37` (~25 labels) — the FFP-driven coloring math is dense and tightly intertwined; a future careful pass is needed to assign meaningful names without inventing them.
- `runtime.s` `.L1..L17` — these are inside vendor Lattice C runtime stubs (`_CreatePort`, `_NewList`, etc.). Reading those is "look up Lattice C source for that era," not analyzing this demo.

**Byte-equivalence verified:** the instruction stream of the renamed source matches the original byte-for-byte, modulo only label spellings. Comment-stripped + label-stripped diff against `archive/boing_original.s` shows zero meaningful differences.

---

## 8. Surprises and observations

Things I learned while reading the source that didn't match my initial assumptions:

### 8.1 The polygon fill is not the per-frame renderer

The polygon code (`_init_globe` + `_draw_globe`) runs **once at startup** to author the static ball bitmap. Per-frame animation is palette cycling + ViewPort scroll — the same technique as the lost 1984 original; the ball is never redrawn. (It's a natural assumption that the `AreaMove`/`AreaDraw`/`AreaEnd` calls run every frame — they don't.)

### 8.2 The .L144/.L138 "dot grids" appear to do nothing

In `.bgrenderloop` around the wireframe-room rendering, there are two 5×5 nested loops (`.dot_grid1_outer` / `.dot_grid1_inner` and `.dot_grid2_outer` / `.dot_grid2_inner`) that call **only `Move()` and never `Draw()`**. `Move()` in graphics.library just sets the cursor — no pixels are plotted.

Possible explanations:
- (a) Leftover debug-mark code from a previous draft.
- (b) A macro that was supposed to expand to `Move + WritePixel` but lost its pixel-plot.
- (c) Intentional cursor positioning for a feature that never shipped.

The compiled output dutifully emits the calls but they produce no visible result. This is a real artifact of the polite binary.

### 8.3 Stereo balance is implemented via SAMPLE DELAY, not just volume

I expected balance to be done by volume difference between channels. Actually it's done by **inter-aural time delay**: the louder channel plays the sample starting at `_samples`, the softer channel plays from `_samples - extraSamples` — pointing back into a precomputed 358-byte silence prefix. The softer channel hears the waveform `extraSamples` ticks later than the loud channel — a phase delay that the human auditory system processes as direction.

This is psychoacoustically much stronger than a pure volume balance. Volume differences alone produce a "stereo cheat"; volume + time produces convincing spatialization. This is sophisticated audio design for 1985.

### 8.4 The only chipset poke is genuinely surgical

I had been telling readers "there's one DMACON write at line 1776 in the original." Having now read it in context: it's a single defensive `set DMAF_RASTER` after `_InitBoing` returns, almost certainly to recover from a state audio.device leaves the chipset in. Not a meaningful exploit of bare-metal access — just one line of "make sure bitplane DMA is on."

### 8.5 Bitplane allocation in two stages

The bitmap is `InitBitMap`'d **twice**: first at 320×200 (for the planning math), then again at 336×216 (the actual oversize for ViewPort scroll headroom). Only the second is the real one. The first call appears to be C compiler output from a paranoid `InitBitMap(BitMap, depth, displayWidth, displayHeight)` call that the code then immediately re-runs with the actual buffer dimensions. Harmless but mildly wasteful.

### 8.6 Topaz font referenced but never visible

The `NewScreen.Font` is set to a `TextAttr` for "topaz" (the standard Amiga 8-pixel monospace), but the demo never calls `Text()` or any text-rendering function. The font is wired up out of habit / safety — every Amiga screen needs *some* default font and Lattice C's NewScreen template includes one. Harmless.

### 8.7 The PRNG seed and `_vb` array are dead

`_seed` (12 bytes of random-looking data) and `_vb` (a 30-byte word array) appear in the DATA section but are never referenced from any code. They're either:
- (a) Dead globals from a feature that was removed before AMICUS shipped.
- (b) Linker-pulled-in symbols from a runtime library function (`rand`?) that never got called.

A future pass could verify by exhaustively grep'ing for any reference. I'd bet (a) — there's likely a "wobble" or "color noise" feature that was prototyped and cut.

### 8.8 The bgrenderloop draws *more* than what's visible

`.bgrenderloop` draws a 320×200 wireframe room with floor tile rows. The four trapezoidal floor rows are drawn with explicit unrolled code (`.floor_row0` block with 4 manual unrolled iterations using `ldivt` for proportional math). The room's geometry — a back wall plus 4 perspective floor rows plus the "ray" lines fanning out — is hand-coded, not procedural.

This makes the wireframe room a **deliberate hand-tuned artwork** that happens to be drawn via line primitives rather than stored as a bitmap. The room could not be replaced or animated easily; it's part of the program's identity.

### 8.9 Back-face culling without normals or dot products

I expected the demo to compute a surface normal per facet and dot-product it with the view direction to determine visibility — the textbook approach. Instead, the cull-test in `_draw_globe`'s Phase B2 compares **two vertex X-coordinates**:

```
if (current_vertex.x > previous_vertex.x): draw  else: skip
```

That's it. One `cmp.l` + `sgt`, no multiplication, no square roots. It works because the projection in §4.4.5 bakes a 2D rotation into the screen coordinates, so the longitude direction maps directly to screen-X for front-facing facets and to negative-screen-X for back-facing facets. The X-comparison is essentially a winding-order test in disguise — cheap and correct for a regularly-tessellated sphere.

This is the kind of trick that doesn't generalize to arbitrary meshes (it relies on the regular longitude topology of a sphere) but is **dramatically faster** than the textbook approach. For 1985-era 7 MHz 68000 hardware, the difference between "one cmp" and "full normal computation" per facet × 392 facets matters.

### 8.10 The 5th bitplane is a palette-half-toggle = the demo's transparency mechanism

The Amiga OCS chipset has no built-in alpha or transparency. But the demo achieves a **two-state transparency effect** through a clever palette setup:

- 5th bitplane = 0 → palette read from low half (COLOR0..15)
- 5th bitplane = 1 → palette read from high half (COLOR16..31)

The palette is initialized so that **COLOR0 ≠ COLOR16 and COLOR1 ≠ COLOR17** (these are the "shadow / background" colors and DO differ) but **COLOR2..15 ≡ COLOR18..31** at all times (the ball colors, kept in sync by `.palette_step` writing both halves every frame).

The result:
- The wireframe-room plane (plane 5) ALONE produces a magenta wireframe on grey background.
- The ball planes (1..4) carry colors 2..15 (ball facets) or 1 (silhouette/shadow).
- Where ball and bg overlap, plane 5 = 1 SHIFTS the palette index by +16 — but COLOR2..15 == COLOR18..31 so the ball color doesn't visually change.
- However the SHADOW silhouette (color 1 → 17) DOES darken to magenta over the room: making the rim of the ball appear DARKER over the floor than over the sky.

This is an effective per-pixel transparency channel built from one extra bitplane and a half-mirrored palette. See §4.4.6 for the full mechanism. It's the kind of trick I'd expect to see in a Demo Scene production, applied here with restraint.

### 8.11 Lattice C's verbose shift-via-scratch-memory idiom

Throughout the shading pass in `_draw_globe`, the compiler emits a pattern like:

```
move.w   (a2),(-14,a6)          ; stash vertex.x at scratch
move.l   (-12,a6),d7
ext.l    d7                     ; ↑ sign-extend the longword at scratch
move.l   d7,(-12,a6)
move.l   (-12,a6),d7
asr.l    #4,d7                  ; D7 = vertex.x / 16 (signed shift)
move.l   d7,(-12,a6)
move.l   (-12,a6),a0
sub.l    a0,d2                  ; D2 -= vertex.x/16
```

That's **eight instructions** to do what a single `asr.l #4,d2` (after `ext.l d2`) could accomplish. The compiler is making a defensive trip through memory: write the word to a long-aligned scratch slot, read it back as a long, sign-extend, shift, write back, re-read. Why this specific pattern emerges instead of register-only sign-extend-and-shift is presumably an artifact of Lattice C 5.02's IR — perhaps it conservatively assumes the variable address might alias something. The result is dramatically more code bytes than necessary, and slower too.

It doesn't affect correctness but it's a recognizable Lattice C 5.02 compilation-style fingerprint. A modern compiler would produce `ext.l d2; asr.l #4,d2; sub.l d2,d3` for the same source.

---

## 9. Cross-references

| To answer the question … | Read … |
|---|---|
| What hardware does the demo touch? | [AMIGA-KNOWHOW.md §C, §D, §E](AMIGA-KNOWHOW.md) + [§8.4 above](#84-the-only-chipset-poke-is-genuinely-surgical) |
| What's the history of the Boing demo? | [DEMO-BACKGROUND.md §2–§6](DEMO-BACKGROUND.md) |
| What's the lineage of THIS source? | [DEMO-BACKGROUND.md §7.3](DEMO-BACKGROUND.md) |
| How does this differ from other Boing variants? | [DEMO-BACKGROUND.md §7.9 comparison table](DEMO-BACKGROUND.md) |
| What does \_Boing actually do for sound? | [§5.2 above](#52-per-impact-playback-_boing-in-srcanims) + comments in `src/anim.s` |
| What does \_init_globe / \_draw_globe do? | [§4.4 above](#44-why-the-polygon-machinery-exists-if-it-only-runs-once) + comments in `src/globe.s` |
| What does the main loop do per frame? | [§4.1–§4.3 above](#41-the-ball-static-bitmap-palette-cycled-rotation) + comments in `src/main.s` `.mainloop` through `.frame_done` |
| How are libraries called from compiled C? | [AMIGA-KNOWHOW.md §G.1](AMIGA-KNOWHOW.md) + `src/runtime.s` comments |
| What's the CLI/Workbench startup pattern? | [AMIGA-KNOWHOW.md §H.2](AMIGA-KNOWHOW.md) + comments in `src/startup.s` |

---

## 10. AMICUS vs Maher: the per-frame pipeline is identical

AMICUS draws the ball polygon **once at startup**; per-frame work is palette cycling + ViewPort offset — same as the 1984 original. Maher's reconstruction differs in exactly one way: **how the static bitmap is authored** — Maher pre-bakes a `__chip` array, AMICUS computes it from sphere math (`_init_globe`/`_draw_globe`). After the bitmap exists, both animate identically. See [DEMO-BACKGROUND.md §7.4.6](DEMO-BACKGROUND.md) and §4.4.

**After the correction (applied 2026-05-20):**

- DEMO-BACKGROUND.md §7.4.6 now says: *"AMICUS computes the ball bitmap ONCE at startup via sphere geometry (`_init_globe` + `_draw_globe`), then animates via palette cycling and ViewPort offset writes — same technique as the lost 1984 CES original. Maher uses the same animation technique but pre-bakes the bitmap into source instead of computing it."*
- DEMO-BACKGROUND.md §7.9 table row for AMICUS now reads: *"Static bitmap, palette cycling for rotation. Ball drawn ONCE at startup via AreaMove/AreaDraw/AreaEnd from SPSin/SPCos sphere math; never redrawn."* with motion column *"ViewPort RxOffset/RyOffset writes + bg-plane-pointer compensation across 16 staggered planes."*
- DEMO-BACKGROUND.md §7.8 family-categorization paragraph now clarifies that the "OS-respectful family" still uses palette cycling + ViewPort offset for per-frame animation (same as the CES original); the "OS-respectful" label refers to the library-driven *setup* phase, not the animation pipeline.

This BOING-ANALYSIS.md is the canonical source-of-truth for these claims; the DEMO-BACKGROUND.md sections now link back here.

---

*This analysis was prepared after a full read of every function in `src/*.s` and the application of descriptive label names. Comments in the source cross-reference back to specific sections of this document and [AMIGA-KNOWHOW.md](AMIGA-KNOWHOW.md).*
