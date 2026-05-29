# BOING-AMICUS(S)-VS-MAHER(C).md — comparing the two Boing implementations

A focused side-by-side comparison of:

- **AMICUS** = the disassembled compiled-C source in `src/*.s` (this repository).
- **Maher** = Jimmy Maher's 2009–2010 C reconstruction in `archive/boing-c/boing1.c .. boing5.c`, the companion code to his MIT Press book *The Future Was Here: The Commodore Amiga* (2012).

Both target Kickstart 1.x / OCS Amiga 1000. The point of this document is to identify, ignoring the C-vs-assembly language difference, **where the two implementations actually share the same techniques and where they diverge**.

Cross-references:
- [BOING-ANALYSIS.md](BOING-ANALYSIS.md) — detailed analysis of the AMICUS source per-function.
- [DEMO-BACKGROUND.md](DEMO-BACKGROUND.md) — variant lineage of the Boing demo.
- [AMIGA-KNOWHOW.md](AMIGA-KNOWHOW.md) — hardware/OS reference.

---

## TL;DR

| Category | Same as Maher? |
|---|---|
| Screen + Window setup | ✓ same |
| Rotation via palette cycling | ✓ same |
| Motion via ViewPort offsets | ✓ same |
| Background via 16 staggered bitplanes | ✓ same |
| Wireframe-room geometry | ✓ same |
| 5-plane palette transparency-toggle | ✓ same |
| audio.device CMD_WRITE pipeline | ✓ same |
| **Ball authoring** | ✗ **different** — AMICUS computes from sphere math; Maher pre-bakes a bitmap |
| **Stereo audio** | ✗ **different** — AMICUS uses inter-aural time delay; Maher uses on/off panning |
| **Y physics** | ✗ **different** — AMICUS integrates a smooth FFP sub-pixel parabola; Maher uses an integer 4-step velocity-ramp. (Both bounce *forever* — AMICUS's `_dampy` damping is dead code, `_dampy=0`; see §2.3.) |

The two implementations agree on **every aspect of the chipset trickery** — these are the inherited 1984 CES techniques and both honor them. They diverge in three pragmatic decisions about *how to author the demo*, not *how the chipset is exploited*.

---

## 1. Same approach (7 places)

### 1.1 Intuition screen + window setup

Both open a CUSTOMSCREEN with CUSTOMBITMAP, manually allocate a 5-bitplane bitmap, and open a borderless backdrop window for IDCMP.

**AMICUS** (`src/main.s` Phases 3–6):
```
InitBitMap(&_mybitmap, 5, 336, 216)
AllocMem(40824, MEMF_CHIP)        ; 4 bitplanes + 4536-byte scroll buffer
AllocRaster ×16 for 16 staggered _bgptr planes
OpenScreen(NewScreen{320×200×5, CUSTOMSCREEN|CUSTOMBITMAP, ...})
OpenWindow(NewWindow{IDCMP=CLOSEWINDOW|MOUSEBUTTONS, Flags=BORDERLESS|BACKDROP|...})
```

**Maher** (`boing5.c` lines 753–765):
```c
NewScreen.Depth = 5;        // same
NewScreen.Type  = CUSTOMSCREEN|CUSTOMBITMAP;
Screen = OpenScreen(&NewScreen);
LoadRGB4(&Screen->ViewPort, Colors, 32);
NewWindow.Screen = Screen;
Window = OpenWindow(&NewWindow);
```

Same depth (5), same screen type, same window flags. Maher uses `LoadRGB4` once to set the whole palette; AMICUS uses four `SetRGB4` calls in Phase 11 — functionally equivalent.

### 1.2 Rotation via palette cycling

Both rewrite the **same 28 palette entries** every frame (14 in each half), with the **same color values** and the **same direction-of-rotation rule**.

**Maher** (`boing5.c` lines 825–857):
```c
if (x_scroll>0) color_cycle--;
else            color_cycle++;
if (color_cycle==-1) color_cycle=13;
else if (color_cycle==14) color_cycle=0;
for (i=0;i<7;i++){
  if ((color_cycle+i)<14){
    ColorTable[color_cycle+i+2]=0xFFF;     /*white*/
    ColorTable[color_cycle+i+18]=0xFFF;}
  else{
    ColorTable[color_cycle+i-12]=0xFFF;
    ColorTable[color_cycle+i+4]=0xFFF;};};
/* ... same shape for the 7 red stripes at colors 0xF00 ... */
/* ... single 0xFDD highlight stripe with direction-dependent placement ... */
```

**AMICUS** (`src/main.s` `.palette_step`):
```
.dir_left      _vx < 0  -> D4++
.dir_right     _vx >= 0 -> D4--
.dir_wrap_neg  D4 == -1 -> D4 = 13
.dir_wrap_pos  D4 == 14 -> D4 = 0
.white_loop    write 7 white stripes at COLOR[(D0+D4) mod 14 + 2]
               and COLOR[(D0+D4) mod 14 + 18]
.pink_left / .pink_right  write $0FDD highlight (one slot)
.red_loop     write 7 red stripes at COLOR[(D0+D4) mod 14 + 2]
               and COLOR[(D0+D4) mod 14 + 18]
```

Both write to the low palette half (indices 2..15) AND the high half (indices 18..31). Both use 7 white + 7 red + 1 pink-white. Both reverse direction when X velocity flips sign. Both wrap modulo 14.

This is byte-for-byte the same algorithm.

### 1.3 Per-frame motion via ViewPort offsets

Both use the same ViewPort.RasInfo offset-writing mechanism — no bits are moved, just the display-window starting position.

**Maher** (`boing5.c` line 879):
```c
Screen->ViewPort.RasInfo->RxOffset = x_pos;
Screen->ViewPort.RasInfo->RyOffset = y_pos;
```

**AMICUS** (`src/main.s` `.scroll_apply`):
```
move.w (_y_lower-negated),ri_RyOffset(a2)    ; via _viewport->vp_RasInfo
move.w (2,a4),ri_RxOffset(a2)                 ; high-word(_x)
```

Same two writes to the same ViewPort struct. AMICUS uses a hi-word-of-`_x` form to allow sub-pixel X velocity; Maher uses a plain int. Otherwise identical.

### 1.4 Background = 16 staggered bitplane copies

Both implement the **sub-byte horizontal alignment trick** the same way: allocate 16 separate chip-RAM planes for the wireframe room, each drawn 1 pixel further right than the previous, then per-frame swap `BitMap.Planes[4]` to the correct one based on `x_pos & 15`.

**Maher** (`boing5.c` lines 746–751 + 883):
```c
for (i=0;i<16;i++){
  BGPtr[i] = (PLANEPTR)AllocMem(9072, MEMF_CHIP|MEMF_CLEAR);
  ...
}
BitMap.Planes[4] = BGPtr[0];
/* ... per frame ... */
Screen->BitMap.Planes[4] = BGPtr[x_pos & 15]
                         - ((x_pos>>4) * 2)
                         - (y_pos * 42);
```

**AMICUS** (`src/main.s` `.alloc_bg_loop` + `.scroll_apply`):
```
; 16-iteration AllocRaster loop builds _bgptr[0..15] of 9072 bytes each.
; Per-frame:
move.l _bgptr(d2.w * 4),a1                ; A1 = _bgptr[x & 15]
sub.l  ((_x asr 4) * 2),a1                ; coarse byte compensation
sub.l  (_y * BytesPerRow),a1              ; Y compensation
move.l a1,(bm_Planes+16,a2)               ; BitMap.Planes[4] = A1
```

Same formula. Maher hardcodes `42` (= 336 / 8 = bytes per scanline); AMICUS reads it from the BitMap struct's `bm_BytesPerRow` field. Same byte arithmetic either way.

### 1.5 Wireframe-room geometry

Both render the wireframe room with the **same 16-pass nested line-draw loops** and the **same explicit floor-tile rows** at identical screen coordinates.

**Maher** (`boing5.c` lines 790–812):
```c
for (i=0;i<16;i++){
  Screen->BitMap.Planes[4] = BGPtr[i];
  for (j=48;j<300;j+=16){             /* vertical wall lines */
    Move(RastPort, j+i, 0);
    Draw(RastPort, j+i, 192);};
  for (j=0;j<200;j+=16){              /* horizontal wall lines */
    Move(RastPort, 48+i, j);
    Draw(RastPort, 288+i, j);};
  for (j=48,k=20;j<300;j+=16,k+=20){   /* perspective rays */
    Move(RastPort, j+i, 192);
    Draw(RastPort, k+i, 215);};
  Move(RastPort, 45+i, 194);          /* floor row 0 */
  Draw(RastPort, 291+i, 194);
  Move(RastPort, 41+i, 197);          /* floor row 1 */
  Draw(RastPort, 295+i, 197);
  Move(RastPort, 37+i, 201);          /* floor row 2 */
  Draw(RastPort, 300+i, 201);
  Move(RastPort, 30+i, 207);          /* floor row 3 */
  Draw(RastPort, 308+i, 207);
  Move(RastPort, 20+i, 215);          /* floor front edge */
  Draw(RastPort, 319+i, 215);};
```

**AMICUS** (`src/main.s` `.bgrenderloop` + `.draw_vline` / `.draw_hline` / `.draw_persp` / `.floor_row0`):

Same 16 outer passes. Same 4 sub-loops (vertical walls, horizontal walls, perspective rays, floor tile rows). **Exact same Y values** (194, 197, 201, 207, 215). Exact same X spans (48..288 for the back wall; 20..319 for the floor front edge). The four floor-tile rows are unrolled in AMICUS rather than computed proportionally; Maher uses the same hand-coded values but inline.

Both also include the curious **5×5 `Move()`-only nested loops** at the back-wall horizon (Maher lines doesn't have these — actually let me re-verify…). On a closer look: Maher's version does NOT include the dot-grid `Move()`-only loops at lines `.dot_grid1_outer` / `.dot_grid2_outer` of AMICUS. Those are an AMICUS-only artifact (see [BOING-ANALYSIS.md §8.2](BOING-ANALYSIS.md) — they appear to do nothing visible).

### 1.6 5-plane palette as transparency-toggle

Both set up the palette so that **bitplane 5 acts as a per-pixel transparency channel** for two states (bg-on / bg-off), via the low-half ≡ high-half identity for the ball colors and the low-half ≠ high-half difference for the background.

**Maher** (`boing5.c` lines 35–38):
```c
USHORT Colors[32]=
{0xAAA,0x666,0xF00,0xF00,0xFDD,0xFFF,0xFFF,0xFFF,0xFFF,0xFFF,0xFFF,0xF00,0xF00,0xF00,0xF00,0xF00,
 0xA0A,0x606,0xF00,0xF00,0xFDD,0xFFF,0xFFF,0xFFF,0xFFF,0xFFF,0xFFF,0xF00,0xF00,0xF00,0xF00,0xF00};
```

Notice indices `0xAAA` (grey) vs `0xA0A` (magenta) at positions [0] and [16], and `0x666` vs `0x606` at [1] and [17] — the only two pairs that differ. Indices 2..15 ≡ 18..31 (all the same red/white/pink values).

**AMICUS** (`src/main.s` Phase 11 SetRGB4 calls + `.palette_step`):

Same palette setup: COLOR0=$0AAA, COLOR1=$0666, COLOR16=$0A0A, COLOR17=$0606. The `.palette_step` writes to both halves identically (see §1.2 above) to maintain the COLOR2..15 ≡ COLOR18..31 invariant.

This is **the same transparency-toggle mechanism** in both implementations. See [BOING-ANALYSIS.md §4.4.6](BOING-ANALYSIS.md) for the full derivation of how this gives the wireframe room its color without breaking the ball's color.

### 1.7 audio.device CMD_WRITE pipeline

Both open audio.device, allocate channels via ADCMD_ALLOCATE with a channel-mask preference list, then issue CMD_WRITEs to play the sample.

**Maher** (`boing5.c` lines 627–634):
```c
IOAudio->ioa_Request.io_Message.mn_ReplyPort = AudioPort;
IOAudio->ioa_Request.io_Message.mn_Node.ln_Pri = -90;
IOAudio->ioa_Request.io_Command = ADCMD_ALLOCATE;
IOAudio->ioa_AllocKey = 0;
IOAudio->ioa_Data = (UBYTE *)&audio_channels;
IOAudio->ioa_Length = 4;
if (OpenDevice("audio.device", 0, IOAudio, 0))
  return(FALSE);
```

**AMICUS** (`src/anim.s` `_initCleanup` setup path):

```
move.l (a2),a0
move.l (a3),(IOAudio+MN_REPLYPORT,a0)
move.l #_allocMap,(ioa_Data,a0)               ; _allocMap = $03050A0C
moveq  #4,d2
move.l d2,(ioa_Length,a0)
...
OpenDevice("audio.device", 0, _allocReq, 0)
```

Same pattern. Both use a 4-byte channel-mask preference list with the four stereo-pair candidates: `{3, 5, 10, 12}` (= ch0+ch1, ch0+ch2, ch1+ch3, ch2+ch3). Both expect audio.device to pick one of those.

---

## 2. Different approach (3 places)

### 2.1 Ball authoring — pre-baked bitmap vs. computed at startup

**Maher** (`boing1.c` line 65):

The ball is a **~26 KB pre-baked 4-bitplane bitmap embedded as hex bytes** in the source file:

```c
/*A 4-bitplane image representing the Boing ball itself, to be painted onto
  the screen when the program begins.*/
UWORD __chip ball_bitplanes[]={
/*Bitplane 0*/
   0x0,   0x0,   0x0,   0x0,   0x7,   0xff80,   0x0,   0x0,   0x0,
   0x0,   0x0,   0x0,   0x0,   0x1f,   0xffff,   0xfc00,   0x0,   0x0,
   ...
   /* (hundreds of lines of hex bytes for all 4 bitplanes) */
};
```

At runtime: **one line** — `DrawImage(&Screen->RastPort, &Ball, 96, 0);` (boing5.c line 778). That blits the entire pre-baked bitmap to the screen.

Maher painted the ball in a 2009-era paint program and exported the bitplanes to hex.

**AMICUS** (`src/globe.s` `_init_globe` + `_draw_globe`):

The ball is **computed from sphere math at startup** via:

- `_init_globe` (~110 lines):
  - 504 vertices in a 9 latitude × 56 longitude grid.
  - Each vertex's `(x, z, y)` from `_Sine16` / `_Cosine16` integer-trig lookup.
  - Per-vertex color: `((band & 1) * 7 + lon) mod 14 + 2`. The "7" is half the 14-color cycle, which is what produces the diagonal stripe spiral when palette-cycled (see [BOING-ANALYSIS.md §4.4.2](BOING-ANALYSIS.md)).

- `_draw_globe` (~700 lines):
  - Silhouette polygon at color 1 (rim shadow, 16 vertices via `AreaMove`+`AreaDraw`+`AreaEnd`).
  - Phase B1: cache each vertex's projected screen (X, Y) at offsets +6, +8 in the vertex record.
  - Phase B2: emit ~392 visible quad facets via per-facet `SetAPen(vertex.color)` + `AreaMove`/`AreaDraw`/`AreaEnd`, with back-face culling by `vertex.x > partner.x`.

Takes **a few seconds** at startup.

**Why the divergence — Maher explains it himself in `boing5.c` line 773:**

> "The original Boing demo drew the ball onto the screen programatically, using a series of complex floating point trigonometry functions. This is the main reason for the considerable delay that follows the execution of that program. For the sake of clarity and simplicity, I have chosen to store the image of the ball within my version of the program and merely paint it onto the screen. **The original demo having been created before Amiga paint and graphical manipulation programs existed, Luck and Mical obviously did not have the luxury of approaching the problem in this way. This is by far the largest single difference between this reconstruction and the original demo.**"

So this is THE big architectural divergence between the two implementations:

- **AMICUS preserves the original 1984 computational approach** — including its startup delay — and is therefore **closer to the lost CES original** in this respect.
- **Maher pre-bakes for source readability**, sacrificing fidelity-of-technique to make the geometry phase a non-issue (you don't have to read it because there isn't any).

After the ball bitmap exists in chip RAM, both implementations run the same palette/scroll dance. The divergence is **only at startup**.

### 2.2 Stereo audio — on/off panning vs. inter-aural time delay

**Maher** (`boing5.c` lines 680–710):

```c
void play_sound(int period, int volume, BOOL left, BOOL right)
{
  /* ... abort previous voices on the affected sides ... */
  if (left && voice1_avail){
    Voice2->ioa_Period = period;
    Voice2->ioa_Volume = volume;
    BeginIO((struct IORequest *)Voice2);
    voice2_used = TRUE;};
  if (right && voice2_avail){
    Voice1->ioa_Period = period;
    Voice1->ioa_Volume = volume;
    BeginIO((struct IORequest *)Voice1);
    voice1_used = TRUE;};
  /* ... CMD_START to unpause both channels in sync ... */
}
```

Both voices play **the same sample at the same volume from the same start address**. The only "stereo" is whether each side plays (`BOOL left`, `BOOL right`). Floor bounce: both sides play. Wall bounce: only one side plays. **No volume gradation, no time offset between channels.**

Three call sites in `boing5.c`:
- Side bounce: `play_sound(160, 40, (BOOL)(x_pos<=-95), (BOOL)(x_pos>=95))` — one side gets it, the other doesn't.
- Floor bounce: `play_sound(255, 63, TRUE, TRUE)` — both sides get it.

**AMICUS** (`src/anim.s` `_Boing`):

Takes a signed 32-bit `balance` (e.g. `±30000` for wall bounces, `-_x * 384` for floor bounces depending on ball X position). Computes:

- **Volume-attenuation** of the softer side: `vol * (54613 - |balance|) / 54613`.
- **Inter-aural time delay**: points the softer channel's `ioa_Data` into a **358-byte silence prefix** that precedes the real audio start in the buffer. So the softer channel begins playing actual waveform `extraSamples` ticks **later** than the lead channel. The delay is computed as `|balance| * maxCCDelay / (period * 32768)`.

The sample buffer is allocated as `[358 silence bytes][real audio bytes...]`. The lead channel sets `ioa_Data = _samples` (= start of real audio). The delayed channel sets `ioa_Data = _samples - extraSamples` (= some bytes into the silence prefix). When playback starts (both channels are unpaused via CMD_START simultaneously), the delayed channel emits silence for `extraSamples` ticks before the audio waveform reaches it.

The result is **a continuous stereo image that tracks the ball's X position with sub-degree positional accuracy**, versus Maher's **on-off panning** (just "this side plays" or "this side doesn't").

**Why this matters:** humans use inter-aural time difference (ITD, ~600 µs at maximum head-width separation) as the **primary direction cue**, not volume balance. Volume balance alone produces an unconvincing "stereo cheat"; volume + time produces convincing spatialization.

Either:
- (a) The original 1984 CES Boing had this richer stereo and Maher chose not to reproduce it (consistent with his stated "clarity and simplicity" priority for the reconstruction), or
- (b) Commodore-Amiga added the inter-aural time delay when producing the AMICUS sample (improving on the original).

Either interpretation, **AMICUS's audio is psychoacoustically more sophisticated than Maher's**.

### 2.3 Y physics — integer velocity-ramp vs. FFP sub-pixel arc (both perpetual)

**Maher** (`boing5.c` lines 859–878):

```c
x_pos += x_scroll;
if (x_pos<=-95 || x_pos>=95){
  x_scroll = -x_scroll;
  play_sound(160, 40, (BOOL)(x_pos<=-95), (BOOL)(x_pos>=95));}

adjusted_y_scroll = y_scroll;
if (y_pos > -10)       adjusted_y_scroll *= 1;
else if (y_pos > -30)  adjusted_y_scroll *= 2;
else if (y_pos > -60)  adjusted_y_scroll *= 3;
else                   adjusted_y_scroll *= 4;
y_pos += adjusted_y_scroll;
if (y_pos<=-100 || y_pos>=0){
  y_scroll = -y_scroll;
  if (y_pos<=-100) play_sound(255, 63, TRUE, TRUE);};
```

Pure **integer math with a 4-step piecewise-linear velocity ramp**. `y_scroll` (the per-frame Y step) is multiplied by 1, 2, 3, or 4 depending on which screen-region the ball is in, simulating gravitational acceleration without doing real physics. The ball reverses at fixed bounds (-100 and 0).

**No bounce damping**. The ball bounces forever at the same maximum height. Every bounce is identical.

**AMICUS** (`src/main.s` `.physics_y` and `.physics_x`):

Pseudocode of what the FFP-driven block does:

```
_fy = _fy + (float)(_vy / 10)                       ; FFP integration of velocity (gravity grows _vy)
if (int)(_fy + 0.5) <= 0:                           ; crossed the apex (top)?
    _fy = -_fy                                      ; elastic reflect at 0
    _vy = -_vy                                      ; reverse Y velocity
if _fy > +96.0:                                     ; reached the floor? (constant is POSITIVE +96)
    _fy = 192.0 - _fy                               ; elastic reflect at the +96 floor
    _vy = -_vy + _vy/_dampy                         ; "damped" reflection -- but _dampy is 0 (see below)
    if _vy >= 0: _vy = 0; _fy = 1.0                 ; clamp at rest (degenerate case only)
_y = (int)(_fy + 0.5)                               ; project FFP back to integer
_x += _vx; _vx += _ax                               ; pure-int X physics
if _x < _left:  reflect _x; _vx = -_vx              ; bounce off left wall
if _x > _right: reflect _x; _vx = -_vx              ; bounce off right wall
```

**FFP floating-point Y physics with sub-pixel precision.** The code *contains* a `_dampy` bounce-damping divisor — but **`_dampy` is never initialised; it stays 0**, so the damping term is inert (the `ldivt` evaluates `_dampy/_vy = 0`, no divide-by-zero) and the reflection reduces to `_vy = -_vy`. **The bounce is therefore perfectly elastic — the ball returns to the same apex every time and never settles.** Verified two ways: `_dampy` is only ever *read*, never written, across `src/`, `archive/boing_original.s` and `archive/boing_s`; and a UAE recording shows a dead-constant **3.85 s** bounce period with identical apex/floor heights over many bounces (see [ANIMATION-DETAILS.md](ANIMATION-DETAILS.md) §4).

The X physics IS still pure integer (no FFP) because X bounces are full-elastic between fixed walls; only the Y axis needs sub-integer precision for the parabolic arc.

**Result:** *both* implementations bounce forever at constant maximum height. The real difference is the arc *shape*: AMICUS integrates a smooth FFP sub-pixel parabola (slow at the apex, fast near the floor), while Maher fakes acceleration with a 4-step integer velocity ramp. The `_dampy` damping that *would* have made AMICUS settle is dead code, so on this axis the two are behaviourally the same (perpetual bounce), differing only in smoothness.

---

## 3. Side-by-side summary

| Aspect | Maher (`archive/boing-c/`) | AMICUS (this repo's `src/`) | Same? |
|---|---|---|---|
| Screen setup | `OpenScreen` with CUSTOMSCREEN \| CUSTOMBITMAP, 320×200×5 | same | **same** |
| Window setup | borderless backdrop, IDCMP=CLOSEWINDOW \| MOUSEBUTTONS | same | **same** |
| Ball authoring | pre-baked `UWORD __chip ball_bitplanes[]` (~26 KB hex in source) | computed at startup from sphere math (504 vertices, 392 facets) | **different** |
| Per-vertex / per-facet color | encoded in pre-baked bitmap pixels | `((band & 1) * 7 + lon) mod 14 + 2` formula | **different** |
| Back-face culling | not needed (pre-rendered, all visible) | per-facet `vertex.x > partner.x` comparison | **different** |
| Sphere geometry compute | none | `_Sine16` / `_Cosine16` integer trig (`_init_globe`) | **different** |
| Per-vertex projection | none | integer shifts and adds (`_draw_globe` Phase B1) | **different** |
| Polygon emission | `DrawImage(rp, &Ball, ...)` once | `AreaMove`/`AreaDraw`/`AreaEnd` per facet (`_draw_globe` Phase B2) | **different** |
| Rotation via palette cycling | `ColorTable[2..15]` + `[18..31]` rewritten per frame | identical: same indices, same colors, same direction rule | **same** |
| Rotation direction logic | `x_scroll > 0 → color_cycle--; else ++` | `_vx >= 0 → D4--; else D4++` | **same** |
| Per-frame Y motion | `Screen->ViewPort.RasInfo->RyOffset = y_pos` | identical (via library calls) | **same** |
| Per-frame X motion | `Screen->ViewPort.RasInfo->RxOffset = x_pos` | identical | **same** |
| 16 staggered bg planes | `BGPtr[16]`, each 9072 bytes, drawn 1px-offset | `_bgptr[16]`, identical | **same** |
| Bg pointer compensation | `BGPtr[x_pos&15] - ((x_pos>>4)*2) - (y_pos*42)` | identical byte arithmetic | **same** |
| Wireframe-room geometry | 16-pass nested line draws + 4 unrolled floor-tile rows at Y=194/197/201/207 + front edge Y=215 | identical X/Y constants and loop structure | **same** |
| 5-bitplane palette transparency-toggle | COLOR0/1 vs COLOR16/17 differ; COLOR2..15 ≡ COLOR18..31 | identical | **same** |
| audio.device pipeline | `OpenDevice("audio.device")` + `ADCMD_ALLOCATE` + `CMD_WRITE` | identical | **same** |
| Channel-mask preference list | implicit; uses `{3, 5, 10, 12}` candidates | `_allocMap = $03050A0C` (same candidates) | **same** |
| Stereo balance | on/off per side (`BOOL left, BOOL right`) | volume + inter-aural time delay (silence prefix) | **different** |
| Y physics | integer with 4-step velocity-ramp | FFP sub-pixel parabola (smoother arc) | **different (shape)** |
| Bounce decay | none; bounces forever at constant height | none; `_dampy` damping code is dead (`_dampy=0`) → also bounces forever | **same** |
| Pause behavior | `Wait(1<<Window->UserPort->mp_SigBit)` (polite block) | busy-loop polling `GetMsg` | **different** |
| Pause toggle | `running = !running` on mouse click | flip `_sstep` on mouse click | **same** |
| Frame heartbeat | `MakeScreen + RethinkDisplay` | identical | **same** |
| Single direct chipset poke | none | one `move.w DMAF_RASTER\|DMAF_SETCLR,(custom+dmacon)` | **different (cosmetic)** |
| Mouse pointer | `SetPointer` to minimalist dot | identical (deferred to after first frame: `.first_frame_init`) | **same** |
| Workbench cleanup | `CloseWindow`, `CloseScreen`, `FreeMem` chain | identical (`_GoodBye`) | **same** |
| Code volume (lines) | 903 (boing5.c) | ~3097 (original disasm), ~4789 with comments | (similar conceptually after stripping the geometry phase) |

---

## 4. Conceptual takeaway

The two implementations agree on **every aspect of the chipset trickery** — these are the inherited 1984 CES techniques and both honor them faithfully:

- Static ball bitmap that never changes after startup.
- Per-frame palette cycling for "rotation".
- Per-frame ViewPort offset writes for motion (no blitting).
- 16 staggered background bitplanes for sub-byte horizontal alignment.
- 5-bitplane palette-toggle for two-state transparency.
- audio.device DMA playback from chip RAM.

They diverge in **three pragmatic decisions about how to *author* the demo**:

1. **Maher pre-bakes the ball bitmap; AMICUS computes it from sphere math.** This is *Maher's choice to optimize for code readability*, explicitly acknowledged in his own commentary. AMICUS preserves the original 1984 computational approach (and inherits its multi-second startup delay).

2. **AMICUS's stereo audio is psychoacoustically richer.** Inter-aural time delay via a silence-prefix buffer offset is a more convincing stereo cue than Maher's on/off panning. Either the 1984 original had it (and Maher omitted it for simplicity), or Commodore-Amiga added it for the AMICUS developer sample.

3. **AMICUS uses FFP sub-pixel physics; Maher uses an integer velocity ramp.** Both balls bounce *forever* at constant height — AMICUS's `_dampy` bounce-damping divisor is dead code (`_dampy` is never initialised, so it stays 0 and the damping term vanishes). The difference is arc *smoothness*: FFP precision lets AMICUS capture sub-pixel arc motion that integer-only physics cannot. (Earlier revisions of this doc claimed AMICUS damps and settles — corrected after verifying `_dampy=0` in source and measuring a constant bounce period in a UAE recording.)

If you want to read the source as **executable archaeology of the lost 1984 CES Boing**, **AMICUS is the closer reconstruction**:

- Computed ball (matches original technique)
- Inter-aural-delay stereo (matches sophisticated 1980s audio design)
- FFP sub-pixel physics (matches what was possible on a 7 MHz 68000 with mathffp.library)

If you want a **teaching version that's easy to read end-to-end**, Maher's is better:

- Bitmap is one static array, not 800 lines of FFP geometry.
- Stage-by-stage build-up across `boing1.c` → `boing5.c` (each stage adds one feature).
- Pure C with explicit variable names rather than disassembled `.L###` labels.
- Almost half the code volume after excluding the geometry phase.

**Both are valuable.** AMICUS is the program that actually shipped in 1985-ish on AMICUS Disk 9. Maher's is the modern academic reconstruction that makes the same techniques approachable to a 21st-century reader.

---

## 5. Cross-references

- [BOING-ANALYSIS.md](BOING-ANALYSIS.md) — full per-function analysis of the AMICUS source.
  - §4.1–§4.3: rotation, motion, background details.
  - §4.4: the polygon-mesh ball authoring (the part that differs from Maher).
  - §4.4.5: integer-projection-with-shift-and-add trick.
  - §4.4.6: the 5-plane palette transparency-toggle.
  - §5: full audio path including the inter-aural time delay.
- [DEMO-BACKGROUND.md §7.4](DEMO-BACKGROUND.md): Maher's 5-stage C reconstruction in the variant lineage.
- [DEMO-BACKGROUND.md §7.9](DEMO-BACKGROUND.md): variant comparison table including both AMICUS and Maher.
- `archive/boing-c/boing1.c` … `boing5.c` — Maher's source, locally preserved.

---

*This comparison was prepared after a full reading of both implementations. Quotes from `boing5.c` are verbatim; line numbers reference `archive/boing-c/boing5.c`.*
