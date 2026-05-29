;==============================================================================
; src/globe.s -- Sphere geometry and ball rendering
;==============================================================================
; The mathematical and visual core of the demo. Two functions:
;
;   _init_globe    -- Build the sphere vertex table once, at startup. Uses
;                     _Sine16 / _Cosine16 (integer sin/cos lookup helpers
;                     defined in src/runtime.s) and the integer divide/multiply
;                     helpers (ldivt, ulmult) to compute (x, y) pairs for every
;                     vertex of the polygonal sphere mesh. The result is stored
;                     in the _globe table (see src/main.s globals). This
;                     function is the analogue of pre-computing a ball bitmap;
;                     the AMICUS demo "pre-renders" geometry rather than
;                     pixels.
;
;   _draw_globe    -- The per-frame rendering of the ball. Walks the _globe
;                     vertex table, transforms each vertex by the current
;                     rotation matrix, and emits one filled polygon per
;                     latitude/longitude facet via graphics.library
;                     AreaMove / AreaDraw / AreaEnd. The foreground pen is
;                     chosen per facet to produce the red/white check pattern,
;                     with shading at the poles.
;
; This is what makes the AMICUS demo fundamentally different from the 1984
; CES original. The original drew the ball ONCE and used palette cycling for
; "rotation"; this version REDRAWS the ball every frame from polygon data.
; See DEMO-BACKGROUND.md section 7.8 ("Why are the variants so different
; from each other?") for the architectural rationale.
;
; See AMIGA-KNOWHOW.md section J (graphics.library), section K (mathffp /
; mathtrans FFP floats and SPSin / SPCos), and DEMO-BACKGROUND.md section 7.4
; (Maher's reconstruction, for contrast with the palette-cycle approach).
;
; Original line range in monolithic boing.s: 600..1143.
; Public symbols defined: _init_globe, _draw_globe.
;==============================================================================

                    SECTION    boing000918,CODE
;==============================================================================
; _init_globe - pre-compute the sphere vertex coordinate table.
;
; Called once from _main Phase 9. Walks 9 latitude bands (D4 from 8 to 0)
; and 56 longitude steps per band (D5 from $37=55 to 0), computing for
; each vertex:
;     u = D4 * 32767 / 8        (latitude angle: 0..32767 ≈ 0..π in Sine16 units)
;     v = D5 * 32767 / 56       (longitude angle, same 0..32767 scaling)
;     x = cos(v) * sin(u)              (multiplied via ulmult, >>16)
;     z = sin(v) * sin(u)              (same)
;     y = -cos(u) / 2                  (polar axis, halved for aspect)
;
; The integer sin/cos helpers _Sine16 / _Cosine16 (src/runtime.s) use a
; 16-bit angle space where 65536 = full turn. Each vertex tuple is stored
; as 3 signed words: (x at +0, z at +2, y at +4), plus a color-index value
; at +10 derived from (D4 ^ band-parity + D5) mod 14 + 2 - this picks one
; of 14 cycling colors per facet, which is what the palette-rotation in
; _main's main loop animates to spin the ball.
;
; Total vertex count: 9 * 56 = 504 vertices = 504 * 12 = 6048 bytes of
; _globe's ~3900-longword storage. (Extra space is for the rendering
; scratch in _draw_globe.)
;
; This is the SLOW phase Maher's boing5.c calls out explicitly: "The
; original Boing demo drew the ball onto the screen programatically,
; using a series of complex floating point trigonometry functions. This
; is the main reason for the considerable delay that follows the
; execution of that program." (archive/boing-c/boing5.c, line ~773.)
; The AMICUS source keeps the slow startup; Maher's reconstruction
; pre-bakes the ball bitmap into a __chip array to skip the wait.
;
; Note: this uses integer trig (_Sine16/_Cosine16 + ldivt/ulmult), NOT
; the FFP mathtrans.library calls. _draw_globe below DOES use FFP.
;==============================================================================
_init_globe         link       a6,#-4                       ; locals: (-4,a6) = y value cache
                    movem.l    d2-d7/a2/a3,-(sp)
.ig_entry                move.l     #_globe,a2                   ; A2 = walking pointer through _globe[]
                    moveq      #8,d4                        ; D4 = latitude band index (8 -> 0)

;------------------------------------------------------------------------------
; .lat_loop LATITUDE LOOP (D4 = 8 down to 0):  set up sin/cos of latitude angle.
;
; Latitude angle formula (the repeated 14-instruction sequence below):
;       D2 = D4 * 32767          ; latitude_index * 32767 (built by shift-and-add below)
;     then divide by 8 -> D0 = D4 * 32767 / 8
; This walks the latitude angle 0 -> 32767 over the 9 bands, where 32767 is the
; full-scale 16-bit argument _Sine16/_Cosine16 treat as ≈ π (half-circle, south
; pole to north pole). The shift sequence computes ×32767 = ×(2·256·64 − 1)
; without a multiply.
;
; D6 = sin(latitude) - controls the RADIUS of this band's circle (= the
;                      width of the latitude ring around the sphere).
; -2(a6) = cos(latitude) - the band's Y center (0 = equator, +/-32k = poles).
; -4(a6) = sign-extended copy of -2(a6) - cached for the inner loop.
;------------------------------------------------------------------------------
.lat_loop                 move.l     d4,d2                        ; --- compute D4*32767 (in D2) ---
                    move.l     d2,d0
                    add.l      d2,d2                        ;   D2 = 2*D4
                    move.l     d2,d1                        ;   D1 = 2*D4
                    asl.l      #8,d2                        ;   D2 <<= 8  -> D2 = 512*D4
                    asl.l      #6,d2                        ;   D2 <<= 6  -> D2 = 32768*D4
                    sub.l      d1,d2                        ;   D2 = 32768*D4 - 2*D4 = 32766*D4
                    add.l      d0,d2                        ;   D2 = 32766*D4 + D4 = D4 * 32767
                    moveq      #8,d1
                    move.l     d2,d0
                    jsr        (ldivt)                      ; D0 = D4 * 32767 / 8  (latitude angle)
                    move.l     d0,-(sp)
                    jsr        (_Sine16)
                    move.w     d0,d6                        ; D6 = sin(latitude)
                    ext.l      d6
                    move.l     d4,d2                        ; (repeat the same divide for cos)
                    move.l     d2,d0
                    add.l      d2,d2
                    move.l     d2,d1
                    asl.l      #8,d2
                    asl.l      #6,d2
                    sub.l      d1,d2
                    add.l      d0,d2
                    moveq      #8,d1
                    move.l     d2,d0
                    jsr        (ldivt)
                    move.l     d0,-(sp)
                    jsr        (_Cosine16)
                    move.w     d0,(-2,a6)                   ; (-2,a6) = cos(latitude) word
                    move.l     (-4,a6),d7
                    ext.l      d7                           ; sign-extend to longword
                    move.l     d7,(-4,a6)                   ; cache for inner loop
                    moveq      #$37,d5                      ; D5 = longitude index (55 -> 0)
                    addq.l     #8,sp

;------------------------------------------------------------------------------
; .lon_loop LONGITUDE LOOP (D5 = 55 down to 0): emit one vertex per (D4, D5).
;
; Longitude angle = D5 * 32767 / 56.
; Vertex coordinates:
;       x = (sin(latitude) * cos(longitude)) >> 16    ; signed word at (a2)+0
;       z = (sin(latitude) * sin(longitude)) >> 16    ; signed word at (a2)+2
;       y = cos(latitude) >> 1                        ; signed word at (a2)+4
;
; Color index at (a2)+10:
;       parity = D4 & 1                                ; 0 or 1
;       value  = (parity * 14 + D5) mod 14 + 2         ; 2..15
; This gives alternating ring colors so adjacent latitude bands offset by 1
; in the cycle - the diagonal "stripe" appearance of the rotating ball.
;
; Each iteration advances A2 by 12 bytes (one vertex record).
;------------------------------------------------------------------------------
.lon_loop                 move.l     d6,d3                        ; D3 = sin(latitude) (radius)
                    move.l     d5,d2                        ; --- compute D5*32767/56 (in D0) ---
                    move.l     d2,d0
                    add.l      d2,d2
                    move.l     d2,d1
                    asl.l      #8,d2
                    asl.l      #6,d2
                    sub.l      d1,d2
                    add.l      d0,d2
                    moveq      #$38,d1                      ; divisor = 56
                    move.l     d2,d0
                    jsr        (ldivt)                      ; D0 = D5 * 32767 / 56
                    move.l     d0,-(sp)
                    jsr        (_Cosine16)                  ; D0 = cos(longitude)
                    move.l     d3,d1                        ; D1 = sin(latitude)
                    ext.l      d0
                    jsr        (ulmult)                     ; D0 = sin(lat) * cos(lon)
                    move.l     d0,d3
                    moveq      #$10,d0
                    asr.l      d0,d3                        ; D3 = (...) >> 16
                    move.w     d3,(a2)                      ; vertex.x

                    move.l     d6,d3                        ; D3 = sin(latitude) again
                    move.l     d5,d2                        ; same longitude angle
                    move.l     d2,d0
                    add.l      d2,d2
                    move.l     d2,d1
                    asl.l      #8,d2
                    asl.l      #6,d2
                    sub.l      d1,d2
                    add.l      d0,d2
                    moveq      #$38,d1
                    move.l     d2,d0
                    jsr        (ldivt)
                    move.l     d0,-(sp)
                    jsr        (_Sine16)                    ; D0 = sin(longitude)
                    move.l     d3,d1
                    ext.l      d0
                    jsr        (ulmult)                     ; D0 = sin(lat) * sin(lon)
                    move.l     d0,d3
                    moveq      #$10,d0
                    asr.l      d0,d3                        ; >> 16
                    move.w     d3,(2,a2)                    ; vertex.z

                    move.l     (-4,a6),d0                   ; cos(latitude) (signed long)
                    asr.l      #1,d0                        ; D0 = cos(lat) / 2 (Y aspect)
                    move.w     d0,(4,a2)                    ; vertex.y

                    move.l     a2,a3                        ; A3 = current vertex ptr (saved)
                    moveq      #12,d2
                    add.l      d2,a2                        ; advance A2 to next vertex (+12 bytes)

                    ; --- color index = ((D4 & 1) * 7 + D5) mod 14 + 2 ---
                    ;
                    ; Per-vertex color formula:
                    ;     parity = D4 & 1                ; 0 for even bands, 1 for odd
                    ;     color  = (parity * 7 + D5) mod 14 + 2     ; range 2..15
                    ;
                    ; The shift-and-add sequence below computes parity * 7 without
                    ; using muls/mulu:
                    ;     D2 *= 2  (parity*2)
                    ;     D0  = D2 (parity*2)
                    ;     D2 *= 2  (parity*4)
                    ;     D2 += D0 = parity*6
                    ;     D2 += D1 = parity*7   (D1 had been saved as the original parity)
                    ;
                    ; The +7 OFFSET between adjacent bands (= half of 14) is what
                    ; produces the diagonal-stripe spiral on the rotating ball:
                    ; each band's 14-color cycle is half-rotated relative to its
                    ; neighbors. When .palette_step in _main rotates colors 2..15,
                    ; the entire diagonal pattern marches around the sphere.
                    move.l     d4,d2
                    moveq      #1,d0
                    and.l      d0,d2                        ; D2 = D4 & 1  (parity)
                    move.l     d2,d1                        ; D1 = parity (saved for final add)
                    add.l      d2,d2                        ; D2 = parity * 2
                    move.l     d2,d0                        ; D0 = parity * 2
                    add.l      d2,d2                        ; D2 = parity * 4
                    add.l      d0,d2                        ; D2 = parity * 4 + parity*2 = parity * 6
                    add.l      d1,d2                        ; D2 = parity * 6 + parity = parity * 7
                    add.l      d5,d2                        ; D2 = parity*7 + D5
                    moveq      #14,d1
                    move.l     d2,d0
                    jsr        (lmodt)                      ; D0 = (parity*7 + D5) mod 14
                    addq.w     #2,d0                        ; D0 += 2 (palette index range 2..15)
                    move.w     d0,(10,a3)                   ; vertex.color = D0
                    addq.l     #8,sp
.next_lon                 subq.l     #1,d5
                    tst.l      d5
                    bge.w      .lon_loop                          ; D5 >= 0 -> next longitude
.next_lat                 subq.l     #1,d4
                    tst.l      d4
                    bge.w      .lat_loop                          ; D4 >= 0 -> next latitude
.ig_exit                 movem.l    (sp)+,d2-d7/a2/a3
                    unlk       a6
                    rts

;==============================================================================
; _draw_globe(rastport) - render the ball into the bitplanes via polygon
; area-fill. Called ONCE from _main Phase 9, after _init_globe has built
; the vertex table.
;
; Argument:
;     +8(a6)  RastPort *  - the target RastPort (Screen->RastPort)
;
; Strategy (FFP-driven this time, since the actual drawing needs sub-pixel
; precision for the equatorial bands' shading and the polar caps):
;
;   1. For each latitude band (-45..0..+45 degrees, in FFP):
;        a. Compute the band's Y center.
;        b. SetAPen to one of the 14 cycling colors (or red/white for the
;           top-and-bottom caps and equator highlight).
;        c. For each longitude segment (16 around the sphere):
;             i.   AreaMove to the first vertex.
;             ii.  AreaDraw to vertices 2, 3, 4.
;             iii. AreaEnd to close + fill the quad polygon.
;
;   2. Each quad polygon's color is picked from the precomputed indices
;      stored at offset +10 in _globe[] - 2..15 range, cycling through the
;      14 stripe colors. The static bitmap thus encodes which palette slot
;      each facet uses; the main loop palette-rotation makes them spin.
;
; Math: _srad is the sphere radius in FFP (e.g. 0x37 = 55 integer at top).
; _yoff is the Y offset in FFP. _angoff is the rotation angle. The FFP
; constants in the code are recognizable encodings:
;   $C90FD03F = π/8 (0.3927);  $C90FD043 = 2π (6.2832);  $B4000049 = 360.0
;     -> rot_const = _angoff(=12) * 2π / 360  (i.e. 12 degrees expressed in radians)
;   $8CCCCD41 = 1.1  (FFP per-vertex angle step)
;   (These decodes were previously wrong — see docs/BOING-ANALYSIS.md §4.4.)
;
; Output: the bitplanes 1..4 of the RastPort's BitMap now contain a fully
; rendered ball that occupies roughly 110 x 110 pixels centered in the
; (336x216) chip-RAM buffer. The bits will never change again until exit.
;
; This is THE function that takes a few seconds to run at startup - and
; is also what makes this version of the demo "polite": instead of poking
; raw bitplane bytes from the C source like the original CES demo would
; have, it goes through graphics.library AreaMove/AreaDraw/AreaEnd, which
; in turn drive the Blitter via OS-managed Copperlist.
;==============================================================================
_draw_globe         link       a6,#-$010C                   ; 268 bytes of local FFP/scratch
                    movem.l    d2-d7/a2-a4,-(sp)
.dg_entry                move.l     (8,a6),d6                    ; D6 = RastPort *
                    move.l     #_AreaDraw,a4                ; A4 = &_AreaDraw (cached)
                    move.l     #_srad,a2                    ; A2 -> _srad (sphere radius)
                    move.l     #_yoff,a3                    ; A3 -> _yoff  (current Y offset)
.outer_loop                moveq      #$37,d2
                    move.l     d2,(a2)
                    moveq      #12,d2
                    move.l     d2,(_angoff)
                    pea        (1).w
                    move.l     d6,-(sp)
                    jsr        (_SetAPen)
                    move.l     #$C90FD03F,d5
                    clr.l      -(sp)
                    move.l     #$B4000049,-(sp)
                    move.l     (_angoff),d0
                    jsr        (fflti)
                    move.l     d1,(-$0028,a6)
                    move.l     d0,(-$002C,a6)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    moveq      #0,d1
                    move.l     #$C90FD043,d0
                    jsr        (fmuli)
                    jsr        (fdivi)
                    move.l     d0,(-$0014,a6)
                    moveq      #-$2D,d2
                    move.l     d2,(a3)
                    clr.w      d4
                    addq.l     #8,sp
;------------------------------------------------------------------------------
; .vertex_loop - LONGITUDE LOOP: emit 16 vertices around the current latitude band.
;
;   for (D4 = 0; D4 < 16; D4++):
;       angle = _angoff + D4 * (1.1)        ; FFP angle for this vertex
;       x_proj = (a2->x  *  cos(angle)) + (+185.0)    ; vertex X in screen pixels
;       y_proj = (a2->z  *  sin(angle)) / a3->r + a3->y + 100  ; vertex Y
;       if D4 == 0: AreaMove(rp, x_proj, y_proj)       ; start polygon
;       else:       AreaDraw(rp, x_proj, y_proj)       ; add vertex
;
; The two branches (.vertex_draw for D4 != 0 -> AreaDraw via cached a4=&_AreaDraw,
; .vertex_move for D4 == 0 -> AreaMove explicitly) are nearly identical FFP code
; emitted by the compiler for the if/else.
;
; FFP constants used:
;   $C90FD03F ≈ π/8 (0.3927)   $C90FD043 ≈ 2π (6.2832)   $8CCCCD41 ≈ 1.1
;   $B4000049 ≈ 360.0          $B9000048 ≈ +185.0 (silhouette X-centre; +25 px right of the
;                              facets' 160 -> the grey pen-1 silhouette is an offset drop-shadow)
;
; The per-vertex angle increment is 1.1 (FFP); 16 vertices are drawn per band
; (the front-facing half — back faces are culled implicitly by the projection).
;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; The vertex-projection kernel (used both here and in .vertex_move below).
; In C-like pseudocode:
;
;     theta   = rot_const + (float)D4 * 1.1           ; angle for this vertex
;     fy_raw  = (sin(theta) * D5) / band_radius       ; sphere-Y projection
;     y_int   = (int)( fy_raw + (band_y_center + 100) )    ; → screen Y
;     fx_raw  = cos(theta) * band_radius
;     x_int   = (int)( fx_raw + 185.0 )               ; → screen X (silhouette centre 185
;                                                     ;   = facet centre 160 + 25 px shadow offset)
;     AreaDraw_or_AreaMove(rp, x_int, y_int);
;
; Where:
;   D4 ∈ [0,15]   = vertex index within this band (looped by .vertex_loop)
;   D5            = outer-loop counter (radius scale factor for this band)
;   rot_const     = -$14(a6), the cached FFP value computed in .outer_loop
;                   (= _angoff(12) * 2π / 360 = 12 degrees in radians).
;   band_radius   = *(a2) = _srad   ; band's sphere-radius in FFP
;   band_y_center = *(a3) = _yoff   ; band's vertical center in screen pixels
;
; FFP constants in this block (Motorola Fast Float bit-pattern decoded):
;   $8CCCCD41 ≈  1.1         (FFP angle-step per vertex)
;   $B9000048 ≈ +185.0       (silhouette X-centre; +25 px right of the facets' 160 → drop-shadow)
;   100 (= $64) is added to fy as an integer (sphere center Y in screen px)
;
; The arithmetic uses 64-bit FFP-on-stack convention: each FFP value is
; pushed as (high-word, low-word) = D1, D0. fmuli / faddi / fdivi pop one
; 64-bit pair from the stack and combine it with D0:D1 (passed in registers).
;
; The two branches (.vertex_draw vs .vertex_move) differ ONLY in their final
; jsr target -- _AreaDraw via cached (a4) for D4 != 0, _AreaMove explicitly
; for D4 == 0. The FFP projection math is identical in both.
;------------------------------------------------------------------------------
.vertex_loop                tst.w      d4
                    beq.w      .vertex_move                         ; D4 == 0 -> AreaMove (.vertex_move)

;------------------------------------------------------------------------------
; .vertex_draw - emit one polygon vertex via _AreaDraw (subsequent vertices).
;------------------------------------------------------------------------------
.vertex_draw        ; --- Step 1: compute the per-vertex angle θ = rot_const + D4*1.1 ---
                    ; Stack now holds 0 (high) | $8CCCCD41 (low) = FFP 1.1.
                    clr.l      -(sp)                        ; high half of 1.1 (= 0)
                    move.l     #$8CCCCD41,-(sp)             ; FFP 1.1 (angle step per vertex)
                    move.l     d5,d0                        ; D0 = D5 (radius scale)
                    moveq      #0,d1
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)                     ; push (0, D5) as FFP pair
                    move.w     d4,d2
                    ext.l      d2
                    move.l     d2,d0                        ; D0 = (int) D4
                    jsr        (fflti)                      ; D0:D1 = (float) D4 = FFP D4
                    move.l     d1,(-$00C8,a6)               ; scratch (compiler temp)
                    move.l     d0,(-$00CC,a6)
                    jsr        (fmuli)                      ; D0:D1 = D4 * 1.1
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)                     ; push (D4*1.1)
                    move.l     (-$0014,a6),d0               ; rot_const (cached this band)
                    moveq      #0,d1
                    jsr        (faddi)                      ; D0 = rot_const + D4*1.1 = θ

                    ; --- Step 2: y_int = (int)( sin(θ) * D5 / band_radius + (band_y_center + 100) )
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)                     ; push θ for SPSin arg
                    jsr        (_SPSin)                     ; D0 = sin(θ)  (FFP)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)                     ; push sin(θ)
                    move.l     (a2),d0                      ; D0 = band_radius (in FFP)
                    jsr        (fflti)                      ; if needed, int→FFP (no-op when already FFP)
                    move.l     d1,(-$00D0,a6)
                    move.l     d0,(-$00D4,a6)
                    jsr        (fmuli)                      ; D0 = sin(θ) * band_radius
                    addq.l     #8,sp                        ; (pop the D5 we pushed earlier? compiler bookkeeping)
                    jsr        (fdivi)                      ; D0 = (sin(θ) * band_radius) / D5
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (a3),d2                      ; D2 = band_y_center (int)
                    moveq      #$64,d0
                    add.l      d0,d2                        ; D2 = band_y_center + 100
                    move.l     d2,d0
                    jsr        (fflti)                      ; D0 = (FFP)(band_y_center + 100)
                    move.l     d1,(-$00D8,a6)
                    move.l     d0,(-$00DC,a6)
                    jsr        (faddi)                      ; D0 = fy_raw + (band_y_center + 100)
                    jsr        (ffixi)                      ; D0 = (int)(...)  → y_int
                    move.l     d0,-(sp)                     ; push y_int as 3rd AreaDraw arg

                    ; --- Step 3: x_int = (int)( cos(θ) * band_radius - 100.0 ) ---
                    ; Recompute θ (same as Step 1) -- the C compiler didn't CSE this.
                    move.l     d5,d0
                    moveq      #0,d1
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.w     d4,d0
                    ext.l      d0
                    jsr        (fflti)                      ; D0 = (FFP) D4
                    move.l     d1,(-$0100,a6)
                    move.l     d0,(-$0104,a6)
                    jsr        (fmuli)                      ; D0 = D4 * 1.1 (still on stack from above)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (-$0014,a6),d0               ; rot_const
                    moveq      #0,d1
                    jsr        (faddi)                      ; D0 = θ again
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    jsr        (_SPCos)                     ; D0 = cos(θ)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (a2),d0                      ; D0 = band_radius
                    jsr        (fflti)
                    move.l     d1,(-$0108,a6)
                    move.l     d0,(-$010C,a6)
                    jsr        (fmuli)                      ; D0 = cos(θ) * band_radius = fx_raw
                    addq.l     #8,sp
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    moveq      #0,d1
                    move.l     #$B9000048,d0                ; FFP +185.0 (silhouette X-centre)
                    jsr        (faddi)                      ; D0 = fx_raw + (+185.0)
                    jsr        (ffixi)                      ; D0 = (int)(...) → x_int
                    move.l     d0,-(sp)                     ; push x_int

                    ; --- Step 4: emit vertex via AreaDraw(rp, x_int, y_int) ---
                    move.l     d6,-(sp)                     ; push rp (D6 = RastPort *)
                    jsr        (a4)                         ; A4 = &_AreaDraw (cached at .dg_entry)
                    lea        (12,sp),sp                   ; pop 3 args (rp, x, y)
                    bra.w      .next_vertex

;------------------------------------------------------------------------------
; .vertex_move - AreaMove path (first vertex of each polygon, D4 == 0).
;
; Identical FFP math to .vertex_draw above (see banner there for the algebra).
; The only material difference is the final call: _AreaMove starts a new
; polygon, whereas (a4) = _AreaDraw extends the current polygon by one edge.
;
; Local FFP-scratch offsets differ from the .vertex_draw block ((-$58,a6)
; vs (-$C8,a6) etc.) -- the C compiler allocated separate stack scratch
; for each branch of the if/else rather than sharing.
;------------------------------------------------------------------------------
.vertex_move        ; --- Step 1: θ = rot_const + (float)D4 * 1.1 ---
                    clr.l      -(sp)
                    move.l     #$8CCCCD41,-(sp)             ; FFP 1.1
                    move.l     d5,d0
                    moveq      #0,d1
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.w     d4,d2
                    ext.l      d2
                    move.l     d2,d0
                    jsr        (fflti)                      ; D0 = FFP(D4)
                    move.l     d1,(-$0058,a6)               ; scratch (move-branch)
                    move.l     d0,(-$005C,a6)
                    jsr        (fmuli)                      ; D0 = D4 * 1.1
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (-$0014,a6),d0               ; rot_const
                    moveq      #0,d1
                    jsr        (faddi)                      ; D0 = θ

                    ; --- Step 2: y_int = (int)( sin(θ) * band_radius / D5 + (band_y + 100) )
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    jsr        (_SPSin)                     ; D0 = sin(θ)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (a2),d0                      ; D0 = band_radius
                    jsr        (fflti)
                    move.l     d1,(-$0060,a6)
                    move.l     d0,(-$0064,a6)
                    jsr        (fmuli)                      ; D0 = sin(θ) * band_radius
                    addq.l     #8,sp
                    jsr        (fdivi)                      ; D0 /= D5
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (a3),d2                      ; D2 = band_y_center
                    moveq      #$64,d0
                    add.l      d0,d2                        ; D2 = band_y_center + 100
                    move.l     d2,d0
                    jsr        (fflti)
                    move.l     d1,(-$0068,a6)
                    move.l     d0,(-$006C,a6)
                    jsr        (faddi)                      ; D0 = fy_raw + (band_y + 100)
                    jsr        (ffixi)                      ; D0 = (int)(...) = y_int
                    move.l     d0,-(sp)                     ; push y_int

                    ; --- Step 3: x_int = (int)( cos(θ) * band_radius - 100.0 ) ---
                    move.l     d5,d0
                    moveq      #0,d1
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.w     d4,d0
                    ext.l      d0
                    jsr        (fflti)
                    move.l     d1,(-$0090,a6)
                    move.l     d0,(-$0094,a6)
                    jsr        (fmuli)                      ; D0 = D4 * 1.1
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (-$0014,a6),d0               ; rot_const
                    moveq      #0,d1
                    jsr        (faddi)                      ; D0 = θ
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    jsr        (_SPCos)                     ; D0 = cos(θ)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (a2),d0
                    jsr        (fflti)
                    move.l     d1,(-$0098,a6)
                    move.l     d0,(-$009C,a6)
                    jsr        (fmuli)                      ; D0 = cos(θ) * band_radius
                    addq.l     #8,sp
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    moveq      #0,d1
                    move.l     #$B9000048,d0                ; FFP +185.0 (silhouette X-centre)
                    jsr        (faddi)                      ; D0 = fx_raw + (+185.0)
                    jsr        (ffixi)                      ; D0 = (int)(...) = x_int
                    move.l     d0,-(sp)                     ; push x_int

                    ; --- Step 4: emit FIRST vertex via _AreaMove (starts polygon) ---
                    move.l     d6,-(sp)                     ; push rp
                    jsr        (_AreaMove)                  ; start the polygon
                    lea        (12,sp),sp                   ; pop 3 args

.next_vertex        addq.w     #1,d4
                    moveq      #$10,d2
                    cmp.w      d4,d2                        ; D4 < 16 ?
                    bgt.w      .vertex_loop                 ; loop next vertex

;------------------------------------------------------------------------------
; .fill_polygon - close & fill the (16-vertex outline-)polygon, then transition
; to the SHADING PASS that draws all the inter-band facets of the sphere.
;
; The body of _draw_globe is logically two phases:
;
;   Phase A: .vertex_loop above emitted ONE single 16-vertex polygon (the
;            current latitude band's outline) and AreaEnd-fills it now.
;            This produces the SILHOUETTE of the current band.
;
;   Phase B: The shading pass below — it does two things:
;            (B1) Walk all 504 vertices in _globe[] BACKWARDS and cache each
;                 vertex's projected screen (X, Y) at offsets +6 / +8 in the
;                 vertex record (so the polygon-emit pass below doesn't have
;                 to re-run the FFP transforms). This is the .L37 / .L36
;                 nested-loop block immediately following.
;            (B2) Walk vertex PAIRS (a2 and a3 point to adjacent bands) and
;                 emit one filled quad per facet, using the cached (X,Y) from
;                 (B1) and the per-vertex color index at offset +10. This is
;                 the .L32 / .L31 / .L30 ... .L11 nested-loop region.
;
; All shading-pass labels (.L11 through .L37) are intentionally LEFT with
; their compiler-generated names — see DEMO-BACKGROUND.md §7 and the rename
; decision in the project history. The shading pass is dense FFP/integer
; math interleaved and needs a careful future pass to name properly.
;
; What follows below the AreaEnd is **the same kind of FFP projection math
; you've already seen in .vertex_draw / .vertex_move**, but applied vertex-
; by-vertex with the results cached, rather than recomputed per polygon.
; Note that the integer math here uses raw shifts (`asr.l #1`, `asr.l #9`,
; `add.w #$00A0`) rather than FFP — the shading pass projects with integer
; arithmetic because the vertex data is already at usable precision after
; _init_globe.
;------------------------------------------------------------------------------
.fill_polygon       move.l     d6,-(sp)
                    jsr        (_AreaEnd)                   ; fill the silhouette polygon
                    move.l     #_bperiod,a2                 ; A2 = end of _globe[] (just past it)
                                                            ;   walks backward through the table
                    moveq      #8,d4                        ; D4 = 9 latitude bands counter (8..0)
                    addq.l     #4,sp

;------------------------------------------------------------------------------
; Phase B1 - cache projected (X,Y) for every vertex.
;
;   For each band (D4 = 8..0):
;     For each longitude D5 = 55..0:
;       a2 -= 12                            ; back one vertex record
;       proj_y = ((vertex.y >> 1) + vertex.x*2 - (vertex.x >> 2) - (vertex.x >> 4)) >> 9 + 160
;              ; = (y/2 + x*(2 - 1/4 - 1/16)) / 512 + 160
;              ; = (y/2 + x * 1.6875) / 512 + 160
;       proj_x = ((vertex.z + vertex.z/2 - vertex.z/16 - vertex.x/2)) >> 9 + (band_z + 100)
;       vertex.proj_x = proj_x   ; stored at offset +6 (word)
;       vertex.proj_y = proj_y   ; stored at offset +8 (word)
;
; The shift-and-add sequence `x*2 + x*0 - x*1/4 - x*1/16 = x*(2 - 5/16)`
; computes the projection multiplier without using muls/mulu. The compiler
; emits this kind of integer-shift trick when it can prove the constant
; multipliers are short shift-sums.
;------------------------------------------------------------------------------
.L37                moveq      #$37,d5                      ; D5 = 55 (longitude counter)
;------------------------------------------------------------------------------
; .L36 INNER LOOP body - cache (proj_x, proj_y) for ONE vertex.
;
; Per-vertex layout in _globe[] (12 bytes/vertex, from _init_globe):
;     +0  vertex.x  (word, signed)  sin(latitude) * cos(longitude) >> 16
;     +2  vertex.z  (word, signed)  sin(latitude) * sin(longitude) >> 16
;     +4  vertex.y  (word, signed)  cos(latitude) / 2
;     +6  vertex.proj_x  (word)     ← WRITTEN BY THIS BLOCK
;     +8  vertex.proj_y  (word)     ← WRITTEN BY THIS BLOCK
;     +10 vertex.color   (word)     palette index 2..15 (from _init_globe)
;
; This block computes a 2D-rotated orthographic-ish projection from the
; sphere's (vertex.x, vertex.y) into screen (proj_x, proj_y), with shift-
; and-add multipliers approximating a fixed rotation matrix:
;
;     proj_x = 160 + ( vertex.y / 2
;                    + vertex.x * (2 - 1/4 - 1/16)         ; = vertex.x * 1.6875
;                    ) / 512
;
;     proj_y = 100 + low_word(_yoff)
;            - ( vertex.y * (1/2 + 1 - 1/16)               ; = vertex.y * 1.4375
;              - vertex.x / 2
;              ) / 512
;
; The /512 (= asr.l #9) brings the >>16-scaled sphere coords back down to
; screen-pixel magnitude (sphere coords are amplified roughly 2^9 above the
; final pixel range). The +160 and +100 center the ball at screen (160, 100).
;
; The reason the math uses both vertex.x and vertex.y for each of proj_x and
; proj_y (rather than a pure orthographic projection) is that this projection
; bakes in a fixed CAMERA ANGLE for the sphere — the viewer looks at the ball
; from slightly above and slightly to one side, so X and Y axes mix in the
; image. The shift constants encode that angle.
;------------------------------------------------------------------------------
.L36                moveq      #12,d2
                    sub.l      d2,a2                        ; A2 -= 12 (step back to next vertex)

                    ; ----- proj_x = 160 + (vertex.y/2 + vertex.x*1.6875) / 512 -----
                    move.w     (4,a2),d3                    ; D3 = vertex.y (signed word)
                    ext.l      d3
                    asr.l      #1,d3                        ; D3 = vertex.y / 2

                    move.w     (a2),d2                      ; D2 = vertex.x
                    ext.l      d2
                    asl.l      #1,d2                        ; D2 = vertex.x * 2

                    ; Compute (vertex.x / 4) via stack scratch -- compiler used a
                    ; signed-shift-via-memory pattern rather than direct asr on D2
                    move.w     (a2),(-10,a6)                ; stash vertex.x at scratch -10(a6)
                    move.l     (-12,a6),d7                  ; load scratch (-12,a6) as long
                    ext.l      d7                           ; sign-extend
                    move.l     d7,(-12,a6)
                    move.l     (-12,a6),d7
                    asr.l      #2,d7                        ; D7 = vertex.x / 4
                    move.l     d7,(-12,a6)
                    move.l     (-12,a6),a0
                    sub.l      a0,d2                        ; D2 = vertex.x*2 - vertex.x/4

                    ; Compute (vertex.x / 16), subtract again
                    move.w     (a2),(-14,a6)                ; stash vertex.x at scratch -14(a6)
                    move.l     (-$0010,a6),d7
                    ext.l      d7
                    move.l     d7,(-$0010,a6)
                    move.l     (-$0010,a6),d7
                    asr.l      #4,d7                        ; D7 = vertex.x / 16
                    move.l     d7,(-$0010,a6)
                    move.l     (-$0010,a6),a0
                    sub.l      a0,d2                        ; D2 = vertex.x*(2 - 1/4 - 1/16)
                                                            ;    = vertex.x * 1.6875

                    add.l      d2,d3                        ; D3 = vertex.y/2 + vertex.x*1.6875
                    moveq      #9,d2
                    asr.l      d2,d3                        ; D3 /= 512  (sphere → screen scale)
                    move.w     d3,a0                        ; A0 = result (low 16 bits)
                    move.l     a0,d7
                    add.w      #$00A0,d7                    ; D7 = result + 160 (screen center X)
                    move.w     d7,(6,a2)                    ; vertex.proj_x = D7

                    ; ----- proj_y = 100 + (2,a3) - (vertex.y*1.4375 - vertex.x/2) / 512 -----
                    ; Note: (2,a3) reads the LOW word of _yoff (A3 = &_yoff). _yoff
                    ; was set in .outer_loop to a band-specific Y offset.
                    move.w     (2,a3),a0                    ; A0 = low_word(_yoff)
                    move.l     a0,d7
                    add.w      #$0064,d7                    ; D7 = A0 + 100 (screen center Y)
                    move.w     d7,a0                        ; A0 = base proj_y (before delta)

                    move.w     (4,a2),d3                    ; D3 = vertex.y
                    ext.l      d3
                    asr.l      #1,d3                        ; D3 = vertex.y / 2
                    move.w     (4,a2),d2                    ; D2 = vertex.y
                    ext.l      d2
                    add.l      d2,d3                        ; D3 = vertex.y/2 + vertex.y
                                                            ;    = vertex.y * 1.5
                    move.w     (4,a2),d2                    ; D2 = vertex.y
                    ext.l      d2
                    asr.l      #4,d2                        ; D2 = vertex.y / 16
                    sub.l      d2,d3                        ; D3 = vertex.y * (1.5 - 1/16)
                                                            ;    = vertex.y * 1.4375
                    move.w     (a2),d2                      ; D2 = vertex.x
                    ext.l      d2
                    asr.l      #1,d2                        ; D2 = vertex.x / 2
                    sub.l      d2,d3                        ; D3 = vertex.y*1.4375 - vertex.x/2
                    moveq      #9,d2
                    asr.l      d2,d3                        ; D3 /= 512
                    move.w     d3,d2
                    sub.w      d2,a0                        ; A0 = base - delta (so proj_y goes DOWN
                                                            ;       as vertex.y goes UP — screen Y
                                                            ;       is inverted relative to math Y)
                    move.w     a0,(8,a2)                    ; vertex.proj_y = A0

.L35                subq.w     #1,d5                        ; next longitude (D5 -> D5-1)
                    tst.w      d5
                    bge.w      .L36                         ; loop while D5 >= 0
.L33                subq.w     #1,d4                        ; next latitude band (D4 -> D4-1)
                    tst.w      d4
                    bge.w      .L37                         ; loop while D4 >= 0

;------------------------------------------------------------------------------
; Phase B2 - walk vertex pairs (one band paired with the next) and emit
; one filled quad per facet across the inter-band gap.
;
;   A2 = current band's "tail" vertex pointer (= _bperiod, just past _globe)
;   A3 = adjacent band's vertex pointer (= A2 - 672 = back one full band's
;        worth of vertices, since 56 vertices * 12 bytes = 672 bytes)
;   D4 = 7 (outer-loop counter: 8 latitudes -> 7 inter-band gaps)
;
; Each iteration emits ONE quad polygon using AreaMove/AreaDraw on the four
; vertices' cached (proj_x, proj_y) at offsets +6, +8 of the records,
; colored by vertex.color at offset +10. The polygon-emission uses the
; cached projection from Phase B1; no FFP math here.
;------------------------------------------------------------------------------
.L32                move.l     #_bperiod,a0                 ; A0 = end of _globe (= A2 from B1)
                    move.l     a0,a2                        ; A2 = tail vertex pointer (current band)
                    move.l     a0,d7
                    sub.l      #672,d7                      ; D7 = end - 672 (= one band earlier;
                                                            ;   672 = 56 vertices * 12 bytes)
                    move.l     d7,a3                        ; A3 = adjacent band's vertex pointer
                    moveq      #7,d4                        ; D4 = 7  (9 bands → 8 inter-gaps,
                                                            ;   but only 7 visible because the
                                                            ;   north pole has just one vertex)

;------------------------------------------------------------------------------
; .L31 OUTER LOOP (inter-band gap counter, D4 = 7..0).
; .L30 INNER LOOP (longitude counter, D5 = 55..0).
;
; Each (D4, D5) iteration considers ONE quadrilateral facet bridging:
;     - vertex (A2 - 12)         current band, previous longitude
;     - vertex A2                current band, current longitude
;     - vertex A3                adjacent band, current longitude
;     - vertex (A3 - 12)         adjacent band, previous longitude
;
; Before drawing, a BACK-FACE CULL test runs to decide whether the facet
; faces the viewer (visible) or faces away (skip). The cull test compares
; vertex.x of the current vs. adjacent vertex — if the spatial ordering
; says the facet is on the back side, the .L15 fall-through skips drawing.
;
; The cull-test logic branches twice on edge conditions:
;   - .L25 path: D4 > 0  (not a north-pole edge band)
;   - .L29 path: D4 == 0 (north-pole edge — special-case the wrap-around)
; Each of those further branches on D5:
;   - D5 > 0 ::  pair with the previous-longitude vertex (a2 - 12 / a3 - 12)
;   - D5 == 0:: pair with the WRAP-AROUND vertex at the other end of the band
;
; The cull test result lands in D3 (boolean; 0 = cull, non-zero = draw).
;------------------------------------------------------------------------------
.L31                moveq      #$37,d5                      ; D5 = 55 (longitude counter)
.L30                moveq      #12,d2
                    sub.l      d2,a2                        ; A2 -= 12 (next vertex this band)
                    moveq      #12,d2
                    sub.l      d2,a3                        ; A3 -= 12 (next vertex adjacent band)
                    tst.w      d4                           ; is this the special last-band case?
                    ble.b      .L29                         ; D4 <= 0 -> north-pole path

                    ; --- .L25: D4 > 0 path. Cull-test uses A3 vertex pair. ---
.L25                tst.w      d5
                    ble.b      .L24                         ; D5 <= 0 -> wrap-around (.L24)

                    ; .L23: D5 > 0 -- cull-test partner = (a3 - 12).vertex.x
.L23                move.l     a3,a0
                    moveq      #12,d3
                    sub.l      d3,a0                        ; A0 = A3 - 12
                    move.w     (a0),(-2,a6)                 ; scratch -2(a6) = partner.x (word)
                    move.l     (-4,a6),d7
                    ext.l      d7
                    move.l     d7,(-4,a6)                   ; sign-extend the scratch longword
                    bra.b      .L22

                    ; .L24: D5 == 0 -- wrap: cull-test partner = (a2 - 12).vertex.x
.L24                move.l     a2,a0
                    moveq      #12,d3
                    sub.l      d3,a0                        ; A0 = A2 - 12
                    move.w     (a0),(-2,a6)                 ; scratch -2(a6) = partner.x
                    move.l     (-4,a6),d7
                    ext.l      d7
                    move.l     d7,(-4,a6)

                    ; .L22: do the cull comparison (D4 > 0 path).
                    ; D3 = (vertex_A3.x > partner.x) ? 1 : 0
.L22                moveq      #0,d3
                    move.w     (a3),d2                      ; D2 = A3.vertex.x
                    ext.l      d2
                    cmp.l      (-4,a6),d2                   ; compare against partner.x
                    sgt        d3                           ; D3 = -1 if greater, 0 otherwise
                    neg.b      d3                           ; D3 = 1 if greater, 0 otherwise
                    bra.b      .L21                         ; jump to draw-or-cull decision

                    ; --- .L29: D4 == 0 path (north-pole edge band). ---
.L29                tst.w      d5
                    ble.b      .L28                         ; D5 <= 0 -> wrap-around (.L28)

                    ; .L27: D5 > 0 -- cull-test partner = (a2 - 12).vertex.x
.L27                move.l     a2,a0
                    moveq      #12,d3
                    sub.l      d3,a0                        ; A0 = A2 - 12
                    move.w     (a0),(-6,a6)                 ; scratch -6(a6) = partner.x
                    move.l     (-8,a6),d7
                    ext.l      d7
                    move.l     d7,(-8,a6)
                    bra.b      .L26

                    ; .L28: D5 == 0 -- wrap: cull-test partner = (a2 + 672 - 12).vertex.x
                    ; (a2+672 hops forward a full band; -12 then backs up to that band's
                    ; last vertex — the wrap-around partner)
.L28                move.l     a2,d7
                    add.l      #672,d7                      ; D7 = A2 + 672 (next band's tail)
                    move.l     d7,a0
                    moveq      #12,d2
                    sub.l      d2,a0                        ; A0 = (A2 + 672) - 12
                    move.w     (a0),(-6,a6)                 ; scratch -6(a6) = partner.x
                    move.l     (-8,a6),d7
                    ext.l      d7
                    move.l     d7,(-8,a6)

                    ; .L26: cull comparison for D4 == 0 case.
                    ; D3 = (vertex_A2.x > partner.x) ? 1 : 0
.L26                moveq      #0,d3
                    move.w     (a2),d2                      ; D2 = A2.vertex.x
                    ext.l      d2
                    cmp.l      (-8,a6),d2                   ; compare against partner.x
                    sgt        d3
                    neg.b      d3

                    ; --- .L21: cull decision. If D3 == 0, the facet is back-facing
                    ; (cull it: skip to .L15 and advance the loop without drawing).
.L21                tst.l      d3
                    beq.w      .L15                         ; cull → skip drawing this facet

;------------------------------------------------------------------------------
; .L20 - draw the visible facet. The polygon emission has three branches:
;   .L20  → SetAPen(facet.color); AreaMove(A2.proj_x, A2.proj_y);
;           AreaDraw(A3.proj_x, A3.proj_y)        ← always: 1st edge
;   .L18  → if D5 > 0: 2 more AreaDraws using (A3-12) and (A2-12)
;                       (i.e. the "previous longitude" of both bands → quad)
;   .L19  → if D5 == 0: 2 more AreaDraws using (A2-12) and (A2+672-12)
;                       (wrap-around: the "previous longitude" of THIS band
;                        and the wrap-around partner)
;   .L17  → AreaEnd  (close polygon, blitter-fill)
;------------------------------------------------------------------------------
.L20                ; --- SetAPen(rp, vertex.color) ---
                    move.w     (10,a2),d3                   ; D3 = current vertex.color
                    ext.l      d3
                    move.l     d3,-(sp)
                    move.l     d6,-(sp)                     ; push rp
                    jsr        (_SetAPen)

                    ; --- AreaMove(rp, A2.proj_x, A2.proj_y) — first vertex of quad ---
                    move.w     (8,a2),d3                    ; D3 = A2.proj_y
                    ext.l      d3
                    move.l     d3,-(sp)
                    move.w     (6,a2),d2                    ; D2 = A2.proj_x
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     d6,-(sp)
                    jsr        (_AreaMove)

                    ; --- AreaDraw(rp, A3.proj_x, A3.proj_y) — second vertex ---
                    move.w     (8,a3),d3                    ; D3 = A3.proj_y
                    ext.l      d3
                    move.l     d3,-(sp)
                    move.w     (6,a3),d2                    ; D2 = A3.proj_x
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     d6,-(sp)
                    jsr        (a4)                         ; AreaDraw (cached via a4 from .dg_entry)

                    tst.w      d5                           ; choose 3rd+4th vertex path:
                    lea        ($0020,sp),sp                ;   D5 > 0  → .L18 (normal pair)
                    ble.b      .L19                         ;   D5 == 0 → .L19 (wrap-around pair)

;------------------------------------------------------------------------------
; .L18 - D5 > 0 case: emit 3rd and 4th vertices from the previous-longitude
; column. Quad = { A2, A3, A3-12, A2-12 } (counter-clockwise around the face).
;------------------------------------------------------------------------------
.L18                ; AreaDraw(rp, (A3-12).proj_x, (A3-12).proj_y)
                    move.l     a3,a0
                    moveq      #12,d2
                    sub.l      d2,a0                        ; A0 = A3 - 12
                    move.w     (8,a0),d2                    ; D2 = proj_y
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     a3,a0
                    moveq      #12,d2
                    sub.l      d2,a0
                    move.w     (6,a0),d2                    ; D2 = proj_x
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     d6,-(sp)
                    jsr        (a4)                         ; AreaDraw

                    ; AreaDraw(rp, (A2-12).proj_x, (A2-12).proj_y)
                    move.l     a2,a0
                    moveq      #12,d2
                    sub.l      d2,a0                        ; A0 = A2 - 12
                    move.w     (8,a0),d2                    ; D2 = proj_y
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     a2,a0
                    moveq      #12,d2
                    sub.l      d2,a0
                    move.w     (6,a0),d2                    ; D2 = proj_x
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     d6,-(sp)
                    jsr        (a4)                         ; AreaDraw
                    lea        ($0018,sp),sp
                    bra.b      .L17                         ; → AreaEnd

;------------------------------------------------------------------------------
; .L19 - D5 == 0 wrap case: emit 3rd and 4th vertices from the OTHER side of
; the band (via the A2+672 wrap-around). Quad = { A2, A3, A2-12, wrap-1 }.
;------------------------------------------------------------------------------
.L19                ; AreaDraw(rp, (A2-12).proj_x, (A2-12).proj_y)
                    move.l     a2,a0
                    moveq      #12,d2
                    sub.l      d2,a0                        ; A0 = A2 - 12
                    move.w     (8,a0),d2                    ; proj_y
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     a2,a0
                    moveq      #12,d2
                    sub.l      d2,a0
                    move.w     (6,a0),d2                    ; proj_x
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     d6,-(sp)
                    jsr        (a4)                         ; AreaDraw

                    ; AreaDraw(rp, (A2+672-12).proj_x, (A2+672-12).proj_y)  — wrap partner
                    move.l     a2,d2
                    add.l      #672,d2                      ; D2 = A2 + 672 (next-band wrap)
                    move.l     d2,a0
                    moveq      #12,d2
                    sub.l      d2,a0                        ; A0 = (A2 + 672) - 12
                    move.w     (8,a0),d2                    ; proj_y
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     a2,d2
                    add.l      #672,d2
                    move.l     d2,a0
                    moveq      #12,d2
                    sub.l      d2,a0
                    move.w     (6,a0),d2                    ; proj_x
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     d6,-(sp)
                    jsr        (a4)                         ; AreaDraw
                    lea        ($0018,sp),sp

;------------------------------------------------------------------------------
; .L17 - close the quad and fill it via Blitter area-fill.
;------------------------------------------------------------------------------
.L17                move.l     d6,-(sp)
                    jsr        (_AreaEnd)                   ; complete polygon, blitter-fill
                    addq.l     #4,sp

;------------------------------------------------------------------------------
; .L15 / .L13 - inner & outer loop tails.
; .L11        - function epilogue.
;------------------------------------------------------------------------------
.L15                subq.w     #1,d5                        ; next longitude
                    tst.w      d5
                    bge.w      .L30                         ; while D5 >= 0
.L13                subq.w     #1,d4                        ; next inter-band gap
                    tst.w      d4
                    bge.w      .L31                         ; while D4 >= 0
.L11                movem.l    (sp)+,d2-d7/a2-a4            ; restore callee-saved
                    unlk       a6
                    rts

