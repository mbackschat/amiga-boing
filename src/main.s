;==============================================================================
; src/main.s -- Final cleanup, main entry, application globals
;==============================================================================
; The control-flow heart of the demo and the single largest C function in the
; binary. Three sections:
;
;   _GoodBye       -- Final teardown of all OS resources: closes the Window,
;                     closes the Screen, frees the AreaInfo / RastPort scratch
;                     buffer, frees the bitplane raster memory, calls _CleanUp
;                     (audio teardown, from src/anim.s), and closes the four
;                     libraries (intuition, graphics, mathffp, mathtrans).
;                     Counterpart to the initialization phase inside _main.
;
;   _main          -- The C main() of the application. ~1000 lines of compiled
;                     C covering, in roughly this order:
;                       1. OpenLibrary calls for intuition, graphics, mathffp,
;                          mathtrans (with bail-out on failure).
;                       2. Manual BitMap setup (InitBitMap + AllocRaster) to
;                          control bitplane allocation exactly (5 bitplanes,
;                          chip RAM, contiguous).
;                       3. OpenScreen with CUSTOMSCREEN|CUSTOMBITMAP, LoadRGB4
;                          to set the palette, then OpenWindow over the whole
;                          screen with BORDERLESS|RMBTRAP for IDCMP-only input.
;                       4. SetPointer to install the near-invisible cursor.
;                       5. _init_globe call to build the sphere vertex table.
;                       6. _InitBoing call to set up audio.device channels.
;                       7. The main loop -- WaitTOF for frame pacing, physics
;                          step (gravity, bounce, velocity damping), call to
;                          _draw_globe to render the ball, MakeScreen +
;                          RethinkDisplay to commit, IDCMP poll for quit.
;                       8. The single surgical DMACON write that gives this
;                          file its one direct chipset access. The poke writes
;                          DMAF_RASTER | DMAF_SETCLR -- it forces the bitplane
;                          DMA bit on, presumably to recover from a transient
;                          state that audio.device left it in.
;                       9. On quit, falls through to _GoodBye via bra.
;
;   DATA,CHIP      -- All application globals: library name strings, library
;                     bases (_IntuitionBase, _GfxBase, _MathBase,
;                     _MathTransBase), NewScreen / NewWindow / BitMap / RastPort
;                     structures, the _globe vertex table (35 longs reserved
;                     for sphere coords + temporaries), physics state
;                     (_x, _y, _vx, _vy, _ax, _ay, _dampy, _fy, _y_lower),
;                     audio parameters (_bperiod=255, _bvolume=63 for bottom
;                     bounce; _speriod=160, _svolume=40 for side bounce),
;                     the _DotPointer cursor data, the _fillpat area-fill
;                     pattern, the _bgptr background-plane pointers, the
;                     pseudo-random _seed, and miscellaneous scratch.
;
; See DEMO-BACKGROUND.md section 7 (variant lineage) and AMIGA-KNOWHOW.md
; section M (the runtime picture) for how this fits together at a system level.
;
; Original line range in monolithic boing.s: 1144..2321.
; Public symbols defined: _GoodBye, _main, plus ~70 application globals
;   beginning with graphicslibra__MSG / intuitionlibr__MSG / mathffplibrar__MSG
;   / mathtranslibr__MSG / topaz__MSG and ending with _bigmem.
;==============================================================================

;==============================================================================
; _GoodBye - final teardown and program exit.
;
; Called from the IDCMP loop on CloseWindow. Frees every OS resource that
; _main allocated, in reverse order, then calls _exit (which is in startup.s)
; to close dos.library and return to AmigaDOS / Workbench.
;
; Order matters: the AreaInfo scratch raster must be freed before the
; Window; the Window before the Screen; the 16 staggered background bitplane
; rasters before the main playfield chip-RAM block.
;==============================================================================
_GoodBye            movem.l    d2/d3,-(sp)                  ; preserve callee-saved
.free_arearas                ; --- free the polygon-fill scratch raster (320x200, 1 plane)
                    pea        (200).w                      ;   height
                    pea        (320).w                      ;   width
                    move.l     (_arearas),-(sp)             ;   raster ptr
                    jsr        (_FreeRaster)
                    ; --- restore default Workbench mouse pointer & close window
                    move.l     (_Window),-(sp)
                    jsr        (_ClearPointer)
                    move.l     (_Window),-(sp)
                    jsr        (_CloseWindow)
                    ; --- close our custom screen (releases the View)
                    move.l     (_myScreen),-(sp)
                    jsr        (_CloseScreen)
                    moveq      #0,d3                        ; loop counter for background planes
                    lea        ($0018,sp),sp                ; pop the four 4-byte args above
.free_bg_loop                ; --- free one of the 16 staggered background bitplanes (336x216)
                    pea        (216).w                      ;   height
                    pea        (336).w                      ;   width
                    move.w     d3,d2
                    asl.w      #2,d2                        ;   D2 = index * 4 (longword stride)
                    move.l     #_bgptr,a0                   ;   A0 -> _bgptr[]
                    move.l     (a0,d2.w),-(sp)              ;   push _bgptr[D3]
                    jsr        (_FreeRaster)
                    lea        (12,sp),sp
.next_bg_free                addq.l     #1,d3
                    moveq      #$10,d0                      ; 16 background planes total
                    cmp.l      d3,d0
                    bgt.b      .free_bg_loop                         ; loop while D3 < 16
.free_bigmem                ; --- free the main playfield chip-RAM block (~37 KB, 4 bitplanes)
                    move.l     (_bigbytesgot),-(sp)
                    move.l     (_bigmem),-(sp)
                    jsr        (_FreeMem)
                    jsr        (_exit)                      ; close dos.library and exit
                    addq.l     #8,sp                        ; (unreached - _exit does not return)
.gb_exit                movem.l    (sp)+,d2/d3
                    rts

;==============================================================================
; _main - the application's main entry point.
;
; Called from the startup boilerplate in src/startup.s (CLI or Workbench path).
; Layout:
;   Phase  1 : Open the 4 libraries (graphics, intuition, mathffp, mathtrans).
;   Phase  2 : Initial constants and physics bounds.
;   Phase  3 : Build the BitMap and AreaInfo, allocate the main playfield
;              chip-RAM block (4 contiguous bitplanes + 1 alignment buffer).
;   Phase  4 : Allocate 16 staggered copies of the 5th bitplane for the
;              non-scrolling background room (see Phase 11 for the rationale).
;   Phase  5 : Build a NewScreen on the stack and OpenScreen.
;   Phase  6 : Build a NewWindow on the stack and OpenWindow.
;   Phase  7 : Push the screen behind Workbench (visible only when WB closes).
;              Cache RastPort, ViewPort, ColorMap, ColorTable pointers.
;   Phase  8 : Allocate the AreaInfo scratch raster; InitTmpRas; SetRast.
;   Phase  9 : Call _init_globe + _draw_globe to PAINT the ball ONCE.
;   Phase 10 : Render the wireframe background into the 16 staggered planes.
;   Phase 11 : Define initial palette entries (SetRGB4 for COLOR00, 01, 16, 17).
;   Phase 12 : Reset physics state, call _InitBoing to set up audio device.
;   Phase 13 : Final RastPort tweaks, area-fill pattern, the ONE direct
;              chipset poke (DMACON), enter main loop.
;   Phase 14 : The main loop (.mainloop). Per frame:
;              - poll IDCMP for user input,
;              - WaitTOF for vertical-blank pacing,
;              - rotate the palette to spin the ball (color-register trick),
;              - run Y physics with FFP floating-point math,
;              - run X physics with integer math + bounce on left/right,
;              - write ViewPort RxOffset/RyOffset to slide the ball bitmap,
;              - swap the BitMap's 5th-plane pointer + apply Y-scroll
;                compensation so the background appears motionless,
;              - MakeScreen + RethinkDisplay to rebuild the system copperlist,
;              - if the ball bounced this frame, call _Boing for sample audio.
;   Phase 15 : First-time pointer setup (deferred from Phase 6 so the cursor
;              dot doesn't flash visibly during the long init phase).
;
; This is the same technique as the lost 1984 CES original: a static ball
; bitmap, rotated by palette cycling and translated by ViewPort offsets.
; The polygon-fill in Phase 9 only creates the static bitmap once (because
; the AMICUS source had no paint program to author it as a hand-drawn IFF).
;
; Stack frame: link a6,#-$B2 allocates 178 bytes of local storage.
;   Frame offsets in use (negative from A6):
;     -$04  ... pointer to _bitmap global
;     -$08  ... background-plane render-loop index
;     -$0A  ... pen color $0FDD (pinkish-white, used in palette rotation)
;     -$0E..-$12  ... TextAttr for NewScreen.Font
;     -$36..-$82  ... NewScreen + NewWindow structs built on stack
;     -$8E..-$92  ... FFP scratch
;     -$B2  ... start of locals
;==============================================================================
_main               link       a6,#-$00B2                   ; allocate locals (178 bytes)
                    movem.l    d2-d7/a2-a5,-(sp)            ; preserve callee-saved regs
.entry               move.l     #_x,a4                       ; A4 = &_x (ball X position, used a lot)
                    move.l     #_Move,d6                    ; D6 = &_Move (graphics.library wrapper);
                                                            ;   cached because background render
                                                            ;   calls Move many times
                    move.l     #_bitmap,(-4,a6)             ; local -4 = address of _bitmap global

;------------------------------------------------------------------------------
; Phase 1 - open the four libraries we need. Each open requires version >= 31
; (Kickstart 1.4 = pre-1.3? Actually 31 is the typical "1.2 or later" spec).
; On failure we bail out via _exit(1).
;------------------------------------------------------------------------------
.open_gfx               pea        (31).w                       ; version
                    pea        (graphicslibra__MSG)         ; name
                    jsr        (_OpenLibrary)
                    move.l     d0,(_GfxBase)
                    addq.l     #8,sp
                    bne.b      .open_intuition
.no_gfx               pea        (1).w
                    jsr        (_exit)                      ; exit(1) if no graphics.library
                    addq.l     #4,sp
.open_intuition               pea        (31).w
                    pea        (intuitionlibr__MSG)
                    jsr        (_OpenLibrary)
                    move.l     d0,(_IntuitionBase)
                    addq.l     #8,sp
                    bne.b      .open_mathffp
.no_intuition               pea        (1).w
                    jsr        (_exit)
                    addq.l     #4,sp
.open_mathffp               pea        (31).w
                    pea        (mathffplibrar__MSG)         ; FFP basic arithmetic
                    jsr        (_OpenLibrary)
                    move.l     d0,(_MathBase)
                    addq.l     #8,sp
                    bne.b      .open_mathtrans
.no_mathffp               pea        (1).w
                    jsr        (_exit)
                    addq.l     #4,sp
.open_mathtrans               pea        (31).w
                    pea        (mathtranslibr__MSG)         ; FFP sin/cos/sqrt
                    jsr        (_OpenLibrary)
                    move.l     d0,(_MathTransBase)
                    addq.l     #8,sp
                    bne.b      .libs_open
.no_mathtrans               pea        (1).w
                    jsr        (_exit)
                    addq.l     #4,sp

;------------------------------------------------------------------------------
; Phase 2 - initial constants.
;------------------------------------------------------------------------------
.libs_open               move.w     #1,(_firsttime)              ; flag: pointer not yet installed
                    move.w     #$0FDD,(-10,a6)              ; local color cache: pink-white (FDD = 4-bit RGB)
                    moveq      #-$50,d2                     ;
                    move.l     d2,(_left)                   ; _left  = -80 (ball X bounce-left limit)
                    moveq      #$68,d2                      ;
                    move.l     d2,(_right)                  ; _right = +104 (ball X bounce-right limit)

;------------------------------------------------------------------------------
; Phase 3a - InitBitMap(_mybitmap, depth=5, width=320, height=200) and
; InitArea(AreaInfo @ -$2A(a6), vertex_buffer=_areavect, max_vertices=50).
; The AreaInfo will be hooked to the RastPort in Phase 8.
;------------------------------------------------------------------------------
                    move.l     (-4,a6),a5
                    move.l     #_mybitmap,(a5)              ; *(local _bitmap) = _mybitmap
                    pea        (200).w                      ; height
                    pea        (320).w                      ; width
                    pea        (5).w                        ; depth: 5 bitplanes (32 colors)
                    move.l     (-4,a6),a5
                    move.l     (a5),-(sp)                   ; &_mybitmap
                    jsr        (_InitBitMap)
                    pea        (50).w                       ; max polygon vertices
                    pea        (_areavect)                  ; vertex buffer
                    pea        (-$002A,a6)                  ; AreaInfo on stack
                    jsr        (_InitArea)

;------------------------------------------------------------------------------
; Phase 3b - allocate the main playfield chip-RAM block. The size:
;     $11B8 = 4536 bytes leading "scroll buffer" (allows RyOffset to go up to
;             100 lines backward without exposing garbage above the bitplane)
;   + $8DC0 = 36288 bytes for 4 bitplanes of 336 x 216 pixels each
;             (336 * 216 / 8 = 9072 bytes per plane; 4 planes = 36288)
;   = $9F78 = 40824 bytes total in one contiguous chip-RAM allocation.
;
; Allocation flag $2 = MEMF_CHIP (required because the chipset will DMA from
; here; see AMIGA-KNOWHOW.md section G.3).
;
; After AllocMem we immediately BltClear the entire region to zero. BltClear
; uses the Blitter to clear chip RAM at ~16 MB/s - much faster than a CPU
; loop (see AMIGA-KNOWHOW.md section J.5).
;------------------------------------------------------------------------------
                    move.l     #$000011B8,(_bytesneeded)    ; 4536 leading buffer
                    add.l      #$00008DC0,(_bytesneeded)    ; + 4 * 9072 bitplane bytes = 40824
                    move.l     (_bytesneeded),(_bigbytesgot); remember size for FreeMem in _GoodBye
                    pea        (2).w                        ; MEMF_CHIP
                    move.l     (_bytesneeded),-(sp)         ; byte count
                    jsr        (_AllocMem)
                    move.l     d0,(_bigmem)
                    lea        ($0024,sp),sp
                    bne.b      .bigmem_ok
.no_chip_ram               jsr        (_exit)                      ; out of chip RAM - fatal
.bigmem_ok               clr.l      -(sp)                        ; BltClear flags = 0
                    move.l     (_bytesneeded),-(sp)         ; byte count
                    move.l     (_bigmem),-(sp)              ; chip-RAM base
                    jsr        (_BltClear)                  ; zero everything via blitter
;------------------------------------------------------------------------------
; Phase 3c - re-init the BitMap to its REAL size: 336 wide x 216 tall x 5
; deep. The display window is only 320x200, but the bitmap is oversized so
; the ViewPort RxOffset / RyOffset can scroll the ball without exposing
; garbage at the edges (the ball's bounce travels up to 100 lines off-screen
; vertically and ~16 pixels horizontally beyond the visible area).
;
; The four "extra" planes (1..4) point into _bigmem at offsets:
;   plane 1 -> _bigmem + $11B8         (4536  = the leading buffer)
;   plane 2 -> _bigmem + $11B8 + $2370 (= +13104)
;   plane 3 -> _bigmem + $11B8 + $4740 (= +22176)
;   plane 4 -> _bigmem + $11B8 + $6B10 (= +31248)
; Each plane is 336*216/8 = 9072 = $2370 bytes. The leading $11B8 is the
; "scroll buffer" that absorbs the upward-going RyOffset.
;
; Plane 5 is set up separately in Phase 4 below; it points into the first of
; the 16 staggered background rasters.
;------------------------------------------------------------------------------
                    pea        (216).w                      ; height
                    pea        (336).w                      ; width
                    pea        (5).w                        ; depth
                    move.l     (-4,a6),a5
                    move.l     (a5),-(sp)                   ; &_mybitmap
                    jsr        (_InitBitMap)
                    ; Patch plane 1 pointer = _bigmem + 4536 (skip leading buffer)
                    move.l     #$000011B8,(_bytesneeded)
                    move.l     (-4,a6),a5
                    move.l     (a5),a0                      ; A0 = &_mybitmap
                    move.l     (_bytesneeded),a1            ; A1 = $11B8
                    add.l      (_bigmem),a1                 ; A1 = _bigmem + $11B8
                    move.l     a1,(8,a0)                    ; _mybitmap.Planes[0] = A1
                    ; Patch planes 2..4 pointers, each plane $2370 bytes after the previous
                    move.l     #$00002370,(_bytesneeded)
                    move.l     (-4,a6),a5
                    move.l     (a5),a0                      ; A0 = &_mybitmap (recomputed)
                    move.l     (_bytesneeded),a1            ; A1 = $2370 (one plane size)
                    move.l     (-4,a6),a5
                    move.l     (a5),a2
                    add.l      (8,a2),a1                    ; A1 = previous plane addr + $2370
                    move.l     a1,(12,a0)                   ; _mybitmap.Planes[1]
                    move.l     (-4,a6),a5
                    move.l     (a5),a0
                    move.l     (_bytesneeded),a1
                    move.l     (-4,a6),a5
                    move.l     (a5),a2
                    add.l      (12,a2),a1
                    move.l     a1,($0010,a0)                ; _mybitmap.Planes[2]
                    move.l     (-4,a6),a5
                    move.l     (a5),a0
                    move.l     (_bytesneeded),a1
                    move.l     (-4,a6),a5
                    move.l     (a5),a2
                    add.l      ($0010,a2),a1
                    move.l     a1,($0014,a0)                ; _mybitmap.Planes[3]

;------------------------------------------------------------------------------
; Phase 4 - allocate 16 STAGGERED copies of the 5th bitplane for the wireframe
; background. Each is a separate 336x216 chip-RAM raster (AllocRaster).
;
; The "staggered" trick - critical to understanding the demo:
;   The Amiga can only set a bitplane pointer at an even-byte boundary, so
;   the smallest horizontal step a bitplane-pointer move can produce is
;   16 pixels in lo-res (= 1 byte). To get sub-byte (per-pixel) horizontal
;   alignment of the background relative to the scrolling ball plane, the
;   demo draws 16 different copies of the background, each offset by 1
;   pixel from the previous. Per frame we then SELECT which copy to use
;   based on the low 4 bits of the X scroll (.mainloop near _bgptr).
;
; This is the SAME trick Maher describes in his boing4.c reconstruction
; (lines ~786-790 of archive/boing-c/boing5.c). See DEMO-BACKGROUND.md
; section 7.4.4 ("The fifth bitplane for the background").
;------------------------------------------------------------------------------
                    moveq      #0,d4                        ; loop index 0..15
                    lea        ($001C,sp),sp
.alloc_bg_loop               move.w     d4,d2
                    asl.w      #2,d2                        ; D2 = index*4 (longword stride)
                    move.l     #_bgptr,a2                   ; A2 = _bgptr[]
                    pea        ($D8).w                      ; 216 (height)
                    pea        ($0150).w                    ; 336 (width)
                    jsr        (_AllocRaster)               ; chip-RAM raster for one plane
                    move.l     d0,(a2,d2.w)                 ; _bgptr[d4] = D0
                    addq.l     #8,sp
                    bne.b      .bg_alloc_ok
.no_bg_ram               pea        (1).w
                    jsr        (_exit)                      ; out of chip RAM
                    addq.l     #4,sp
.bg_alloc_ok               addq.l     #1,d4
                    moveq      #$10,d2                      ; 16 total
                    cmp.l      d4,d2
                    bgt.b      .alloc_bg_loop
.bg_planes_done               ; Point _mybitmap.Planes[4] at _bgptr[0] for now. The main loop
                    ; will swap this pointer per frame depending on the X-scroll.
                    move.l     (-4,a6),a5
                    move.l     (a5),a0
                    move.l     (_bgptr),($0018,a0)          ; _mybitmap.Planes[4] = _bgptr[0]
;------------------------------------------------------------------------------
; Phase 5 - build a NewScreen struct on the stack at offset -$82(a6) and
; OpenScreen it. The struct layout (per <intuition/intuition.h>):
;     +0   WORD  LeftEdge       = 0
;     +2   WORD  TopEdge        = 0
;     +4   WORD  Width          = $0140 = 320
;     +6   WORD  Height         = $00C8 = 200
;     +8   WORD  Depth          = 5
;     +10  UBYTE DetailPen      = $FF (white-ish)
;     +11  UBYTE BlockPen       = $FF
;     +12  UWORD ViewModes      = $4000 = SCREENBEHIND (start hidden)
;     +14  UWORD Type           = $004F = CUSTOMSCREEN | CUSTOMBITMAP |
;                                          SHOWTITLE | SCREENQUIET | NS_DEFAULT
;     +16  TextAttr * Font      = -> _topaz_attr (built at -$12(a6))
;     +20  UBYTE *  DefaultTitle = NULL
;     +24  Gadget * Gadgets     = NULL
;     +28  BitMap * CustomBitMap = _mybitmap
;
; ViewModes = $4000 means the screen is SCREENQUIET-ish + custom-built;
; Type = $4F includes CUSTOMSCREEN|CUSTOMBITMAP which tells Intuition NOT to
; allocate bitplanes (we already did so in Phase 3-4).
;------------------------------------------------------------------------------
                    ; TextAttr struct at -$12(a6): { "topaz", 8, 0, 0 }
                    move.l     #topaz__MSG,(-$0012,a6)      ; .ta_Name = "topaz"
                    move.w     #8,(-14,a6)                  ; .ta_YSize = 8
                    clr.b      (-12,a6)                     ; .ta_Style
                    clr.b      (-11,a6)                     ; .ta_Flags
                    ; NewScreen struct at -$82(a6):
                    clr.w      (-$0082,a6)                  ; LeftEdge = 0
                    clr.w      (-$0080,a6)                  ; TopEdge = 0
                    move.w     #$0140,(-$007E,a6)           ; Width = 320
                    move.w     #$00C8,(-$007C,a6)           ; Height = 200
                    move.w     #5,(-$007A,a6)               ; Depth = 5 bitplanes (32 colors)
                    move.b     #$FF,(-$0078,a6)             ; DetailPen
                    move.b     #$FF,(-$0077,a6)             ; BlockPen
                    move.w     #$4000,(-$0076,a6)           ; ViewModes (SCREENBEHIND-ish flag)
                    move.w     #$004F,(-$0074,a6)           ; Type = CUSTOMSCREEN|CUSTOMBITMAP|...
                    lea        (-$0012,a6),a0
                    move.l     a0,(-$0072,a6)               ; Font -> our TextAttr
                    clr.l      (-$006E,a6)                  ; DefaultTitle = NULL
                    clr.l      (-$006A,a6)                  ; Gadgets = NULL
                    move.l     #_mybitmap,(-$0066,a6)       ; CustomBitMap = &_mybitmap
                    pea        (-$0082,a6)
                    jsr        (_OpenScreen)
                    move.l     d0,(_myScreen)
                    addq.l     #4,sp
                    beq.w      .screen_opened                        ; (no actual error handling here)

;------------------------------------------------------------------------------
; Phase 6 - build a NewWindow struct on the stack at offset -$62(a6) and
; OpenWindow it. The window covers the entire screen and is borderless. We
; only want it for IDCMP message delivery (mouse buttons, CloseWindow).
;
; NewWindow layout in this struct:
;     +0   LeftEdge=0, TopEdge=0, Width=320, Height=200
;     +8   DetailPen=$FF, BlockPen=$FF
;     +10  IDCMPFlags = $00000208 = MOUSEBUTTONS | CLOSEWINDOW
;     +14  Flags      = $00011808 = ACTIVATE | BORDERLESS | RMBTRAP | BACKDROP
;     +18  FirstGadget=NULL, CheckMark=NULL, Title=NULL
;     +30  Screen     = _myScreen
;     +34  BitMap     = NULL (use the screen's)
;     +38  MinWidth, MinHeight, MaxWidth, MaxHeight = 0 (not user-resizable)
;     +46  Type       = CUSTOMSCREEN (window goes on our screen, not WB)
;
; RMBTRAP = 1 in Flags means the right mouse button is delivered to the
; window's IDCMP rather than triggering Workbench's menu bar.
;------------------------------------------------------------------------------
.screen_opened               clr.w      (-$0062,a6)                  ; LeftEdge=0
                    clr.w      (-$0060,a6)                  ; TopEdge=0
                    move.w     #$0140,(-$005E,a6)           ; Width=320
                    move.w     #$00C8,(-$005C,a6)           ; Height=200
                    move.b     #$FF,(-$005A,a6)             ; DetailPen
                    move.b     #$FF,(-$0059,a6)             ; BlockPen
                    move.l     #$00000208,(-$0058,a6)       ; IDCMP = MOUSEBUTTONS|CLOSEWINDOW
                    move.l     #$00011808,(-$0054,a6)       ; Flags = ACTIVATE|BORDERLESS|RMBTRAP|BACKDROP
                    clr.l      (-$0050,a6)                  ; FirstGadget = NULL
                    clr.l      (-$004C,a6)                  ; CheckMark = NULL
                    clr.l      (-$0048,a6)                  ; Title = NULL
                    move.l     (_myScreen),(-$0044,a6)      ; Screen = _myScreen
                    clr.l      (-$0040,a6)                  ; BitMap = NULL
                    clr.w      (-$003C,a6)                  ; MinWidth
                    clr.w      (-$0038,a6)                  ; MaxWidth
                    clr.w      (-$003A,a6)                  ; MinHeight
                    clr.w      (-$0036,a6)                  ; MaxHeight
                    move.w     #15,(-$0034,a6)              ; Type = CUSTOMSCREEN
                    pea        (-$0062,a6)
                    jsr        (_OpenWindow)
                    move.l     d0,(_Window)
                    addq.l     #4,sp
                    beq.w      .window_opened                        ; (no error handling)

;------------------------------------------------------------------------------
; Phase 7 - send the screen behind Workbench, then cache pointers into the
; screen's RastPort / ViewPort / ColorMap / ColorTable.
;
; The "nasty poke" comments here (preserved from the disassembly) note that
; we are reaching INTO the OS-owned Screen struct to grab pointers we can
; index directly. This is technically a private-API violation in modern
; AmigaOS terms, but in 1.x-era code it was the standard pattern.
;
; A3 holds the RastPort pointer through most of _main from this point on:
; many graphics.library calls take a RastPort* in slot-0 of the stack frame,
; and the compiler caches it in A3 to avoid reloading every time.
;------------------------------------------------------------------------------
.window_opened               move.l     (_myScreen),-(sp)
                    jsr        (_ScreenToBack)              ; let Workbench cover us until ready
                    move.l     (_myScreen),a0
                    lea        (sc_RastPort,a0),a1          ;poking screen rastport.. nasty
                    move.l     a1,a3                        ; A3 = &Screen->RastPort (kept across loop)
                    move.l     a1,(_wact_ras)
                    move.l     (_myScreen),a0
                    lea        (sc_ViewPort,a0),a2
                    move.l     a2,(_viewport)               ; cache &Screen->ViewPort
                    ; Hook the AreaInfo (initialized in Phase 3a) into RastPort.AreaInfo.
                    lea        (-$002A,a6),a0
                    move.l     a0,(rp_AreaInfo,a3)
                    ; AllocRaster a 320x200 chip-RAM scratch buffer for AreaEnd's
                    ; polygon-mask renderer (TmpRas). 320*200/8 = 8000 bytes.
                    pea        (200).w
                    pea        (320).w
                    jsr        (_AllocRaster)
                    move.l     d0,(_arearas)
                    pea        (8000).w
                    move.l     (_arearas),-(sp)
                    pea        (-$0032,a6)                  ; TmpRas struct on stack
                    jsr        (_InitTmpRas)
                    move.l     d0,(rp_TmpRas,a3)
                    ; Cache ViewPort.ColorMap and ColorMap.ColorTable. (_ct) is
                    ; written directly by the palette-rotation code in the main
                    ; loop (see Phase 14's "poking colortable directly" passage).
                    move.l     (_viewport),a0
                    move.l     (vp_ColorMap,a0),(_cm)
                    move.l     (_cm),a0
                    move.l     (cm_ColorTable,a0),(_ct)
                    move.b     #$10,(rp_Mask,a3)            ; rp_Mask = $10 (5th plane only)
                    move.b     #15,(rp_Mask,a3)             ; then = $0F (planes 1..4 only)

;------------------------------------------------------------------------------
; Phase 8/9 - clear the playfield, build the static ball image, and the
; background. This is where the demo deviates from a "modern" approach:
;
; - SetRast clears the rastport to pen 0 (background).
; - _init_globe computes the sphere vertex coordinates using mathtrans.library
;   SPSin/SPCos (see src/globe.s).
; - _draw_globe walks the vertex table and emits AreaMove/AreaDraw/AreaEnd
;   calls for every sphere facet, rendering the ball into bitplanes 1..4.
;   THIS HAPPENS ONCE. After this call the bitmap is static for the rest of
;   the demo (apart from palette changes - the bitplane bits never change).
;
; Then the mask is reset to $10 (5th plane only) so the background-render
; loop below draws ONLY into plane 5, leaving the ball undisturbed.
;------------------------------------------------------------------------------
                    clr.l      -(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetRast)                   ; clear rastport with pen 0
                    jsr        (_init_globe,pc)             ; build sphere vertex table
                    move.l     a3,-(sp)
                    jsr        (_draw_globe,pc)             ; paint static ball into planes 1..4
                    move.b     #$10,(rp_Mask,a3)            ; rp_Mask = $10 -> draw into plane 5 only
                    clr.l      (-8,a6)                      ; local -8 = background-pass counter (0..15)
                    lea        ($0024,sp),sp

;------------------------------------------------------------------------------
; Phase 10 - render the wireframe "room" background into all 16 staggered
; copies of bitplane 5. Each pass:
;   1. Swap _mybitmap.Planes[4] to _bgptr[pass_index].
;   2. SetDrMd JAM1, SetAPen 0, SetBPen 0, RectFill entire raster (clear).
;   3. SetAPen $FFFFFFFF (= -1 = all-ones, plane-5 bits set everywhere drawn).
;   4. Inner loop .draw_vline: vertical grid lines at X = 48..288 step 16, with
;      X offset of (pass_index) - i.e. one pixel further right each pass.
;   5. Inner loop .draw_hline: horizontal grid lines at Y = 48..192 step 16.
;   6. Inner loops .start_persp/.floor_row0/etc: the foreshortened perspective lines
;      that converge to a vanishing point near the screen center, plus
;      the four trapezoid floor-tile rows below the back wall.
;   7. Bump pass counter, loop while < 16.
;
; The result: 16 identical-looking-but-1-pixel-offset wireframe rooms,
; one per pass index. The main loop selects which one to display based on
; the low 4 bits of the X scroll, achieving sub-byte (= sub-16-pixel)
; precision on the background's apparent position.
;------------------------------------------------------------------------------
.bgrenderloop       move.l     (rp_BitMap,a3),a0            ;poking screen bitmap pointer.. even nastier
                    move.w     (-6,a6),d2
                    asl.w      #2,d2
                    move.l     #_bgptr,a2
                    move.l     (a2,d2.w),(bm_Planes+16,a0)  ; rp_BitMap.Planes[4] = _bgptr[pass]
                    pea        (1).w
                    move.l     a3,-(sp)
                    jsr        (_SetDrMd)                   ; SetDrMd(rp, JAM1)
                    clr.l      -(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetAPen)                   ; SetAPen(rp, 0) - draw "clear" pen
                    clr.l      -(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetBPen)                   ; SetBPen(rp, 0)
                    pea        (215).w                      ; bottom-right Y
                    pea        (335).w                      ; bottom-right X
                    clr.l      -(sp)                        ; top-left Y
                    clr.l      -(sp)                        ; top-left X
                    move.l     a3,-(sp)                     ; RastPort
                    jsr        (_RectFill)                  ; clear plane 5 of this pass
                    move.l     #$FFFFFFFF,-(sp)             ; pen $FFFFFFFF (all-ones)
                    move.l     a3,-(sp)
                    jsr        (_SetAPen)                   ; SetAPen(rp, -1) - draw "set" pen
                    moveq      #$30,d4                      ; D4 = X coord, starting at 48 ($30)
                    lea        ($0034,sp),sp

;------------------------------------------------------------------------------
; .draw_vline Sub-loop A: BACK-WALL VERTICAL LINES.
;
;   for (D4 = 48; D4 < 300; D4 += 16):
;       Move(rp, D4 + pass, 0)              ; top of wall
;       Draw(rp, D4 + pass, 192)            ; bottom of wall (Y=$C0)
;
; Draws 16 evenly spaced vertical lines forming the bars of the back wall.
; The "+ pass" shift gives the 16 staggered copies each their 1-pixel offset.
;------------------------------------------------------------------------------
.draw_vline               ; Vertical wireframe-room line at X = D4+pass_offset.
                    clr.l      -(sp)                        ; Move Y = 0 (top)
                    move.l     d4,d3
                    add.l      (-8,a6),d3                   ; X = D4 + pass
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5                        ;a5 = Move
                    jsr        (a5)                         ; Move(rp, D4+pass, 0)
                    pea        ($C0).w                      ; Draw Y = 192 (bottom of wall)
                    move.l     d4,d3
                    add.l      (-8,a6),d3
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_Draw)                      ; Draw(rp, D4+pass, 192)
                    lea        ($0018,sp),sp
.next_vline               moveq      #$10,d2                      ; step = 16 pixels
                    add.l      d2,d4
                    cmp.l      #300,d4                      ; X < 300 ?
                    blt.b      .draw_vline                        ; loop

;------------------------------------------------------------------------------
; .draw_hline Sub-loop B: BACK-WALL HORIZONTAL LINES.
;
;   for (D4 = 0; D4 <= 200; D4 += 16):
;       Move(rp, 48 + pass, D4)             ; left edge
;       Draw(rp, 288 + pass, D4)            ; right edge
;
; Draws 13 evenly spaced horizontal lines across the back wall.
;------------------------------------------------------------------------------
.start_hlines               moveq      #0,d4                        ; Y = 0
.draw_hline               move.l     d4,-(sp)                     ; Move Y
                    move.l     (-8,a6),d3
                    moveq      #$30,d2
                    add.l      d2,d3                        ; X = 48 + pass
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)                         ; Move(rp, 48+pass, Y)
                    move.l     d4,-(sp)                     ; Draw Y (same)
                    move.l     (-8,a6),d3
                    add.l      #288,d3                      ; X = 288 + pass
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_Draw)                      ; Draw(rp, 288+pass, Y)
                    lea        ($0018,sp),sp
.next_hline               moveq      #$10,d2                      ; step = 16
                    add.l      d2,d4
                    cmp.l      #200,d4                      ; Y <= 200 ?
                    ble.b      .draw_hline                        ; loop

;------------------------------------------------------------------------------
; .draw_persp Sub-loop C: PERSPECTIVE "RAY" LINES (foreshortened floor edges).
;
;   for (D4 = 48; D4 < 300; D4 += 16):
;       Move(rp, D4 + pass, 192)            ; from back-wall floor line
;       fx = (D4 - 160) * 1.25              ; FFP multiply
;       Draw(rp, 160 + pass + (int)fx, 215) ; to screen-bottom edge
;
; These are the "rays" that fan out from the back wall's bottom corners
; toward the screen's bottom edges, giving the floor its perspective look.
; The FFP multiplication by 1.25 (constant $A0000041, ~ 1.25 in FFP, scaled
; by an inverse-Y term derived from $A0=160) provides the foreshortening.
;------------------------------------------------------------------------------
.start_persp               moveq      #$30,d4                      ; X = 48
.draw_persp               pea        ($C0).w                      ; Move Y = 192
                    move.l     d4,d3
                    add.l      (-8,a6),d3                   ; X = D4 + pass
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)                         ; Move(rp, D4+pass, 192)
                    pea        (215).w                      ; Draw Y = 215 (floor edge)
                    clr.l      -(sp)
                    move.l     #$A0000041,-(sp)             ; FFP constant ~ 1.25 (scale factor)
                    move.l     d4,d0
                    sub.l      #$000000A0,d0                ; D0 = D4 - 160 (offset from center)
                    jsr        (fflti)                      ; (int) -> FFP
                    move.l     d1,(-$008E,a6)               ; save FFP scratch
                    move.l     d0,(-$0092,a6)
                    jsr        (fmuli)                      ; D0 = (D4-160) * 1.25  (FFP)
                    jsr        (ffixi)                      ; D0 = (int)(...)
                    move.l     d0,d3
                    move.l     (-8,a6),d2
                    add.l      #$000000A0,d2                ; D2 = 160 + pass
                    add.l      d2,d3                        ; D3 = 160 + pass + scaled-offset
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_Draw)                      ; Draw(rp, computed_X, 215)
                    lea        ($0018,sp),sp
.next_persp               moveq      #$10,d2                      ; step = 16
                    add.l      d2,d4
                    cmp.l      #$0000012C,d4                ; X < 300 ?
                    blt.b      .draw_persp                        ; loop

;------------------------------------------------------------------------------
; .floor_row0 Sub-block D: FOUR PERSPECTIVE FLOOR-TILE ROWS, unrolled.
;
; Draws four trapezoid-shaped horizontal rows of floor tiles, with
; positions / widths computed by ldivt-based proportional math. Each row
; is at a different Y and has its own horizontal extent and X offset to
; create the receding-floor illusion. Y positions: 195, 197, 201, 207.
;
; The math kernel for each line:
;     y    = D8 - row_D4 - 1                    ; row Y, growing downward
;     left = 48 + pass - row_D4 * (24-row_D4) * 7 / 24
;     right = 0x11F + pass + row_D4 * (24-row_D4) * 32 / 24
;
; The "24-row_D4 * ..." form is a classic perspective projection in fixed
; point: width grows quadratically with row distance from the horizon.
;
; The four unrolled rows use D4 = $15, $12, $0E, $08 (= 21, 18, 14, 8),
; corresponding to floor tile rows at increasing distances from the
; back wall.
;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; The trapezoid-row math kernel, repeated 4 times for D4 = 21, 18, 14, 8.
;
; Each row draws ONE horizontal line:
;     Y      = 216 - D4 - 1                       ; row's screen Y
;     left_X = 48  + pass - ((24 - D4) * 28) / 24 ; trapezoid left edge
;     right_X= 287 + pass + ((24 - D4) * 32) / 24 ; trapezoid right edge
;
; The "28" and "32" coefficients differ because the floor is wider than it
; is deep -- the right edge fans out faster than the left edge retreats, so
; the trapezoid is asymmetric matching the perspective of the back wall.
;
; The shift trick `asl #2 / move / asl #3 / sub` computes (24-D4) * 28 by:
;   (24-D4) << 2  = (24-D4) * 4
;   (24-D4) << 5  = (24-D4) * 32
;   subtract      = (24-D4) * 28
; ... avoiding a muls call. ldivt does the /24 division (no 32-bit divide
; on bare 68000).
;
; Computed coords per row (with pass = 0 for clarity):
;     D4=21 (closest): Y=194, X = 45 .. 291  (width 246)
;     D4=18          : Y=197, X = 41 .. 295  (width 254)
;     D4=14          : Y=201, X = 37 .. 300  (width 263)
;     D4=8  (farthest): Y=207, X = 30 .. 308 (width 278)
; After all four rows, a final isolated horizontal at Y=215 (the floor
; front edge, full screen width) closes the floor.
;------------------------------------------------------------------------------
.floor_row0         ; ===== Row 0 (closest to viewer, Y=194, D4 = 21) =====
                    moveq      #$15,d4                      ; D4 = 21
                    move.l     #$000000D8,d3
                    sub.l      d4,d3
                    subq.l     #1,d3                        ; D3 = 216 - 21 - 1 = 194 (Y)
                    move.l     d3,-(sp)                     ; push Move Y
                    move.l     (-8,a6),d2
                    moveq      #$30,d0
                    add.l      d0,d2                        ; D2 = 48 + pass
                    moveq      #$18,d3
                    sub.l      d4,d3                        ; D3 = 24 - 21 = 3
                    asl.l      #2,d3                        ; D3 = 12
                    move.l     d3,d0                        ; D0 = 12
                    asl.l      #3,d3                        ; D3 = 96
                    sub.l      d0,d3                        ; D3 = 96 - 12 = 84  = (24-D4)*28
                    moveq      #$18,d1                      ; D1 = 24
                    move.l     d3,d0                        ; D0 = 84
                    jsr        (ldivt)                      ; D0 = 84 / 24 = 3
                    move.l     d0,d3
                    sub.l      d3,d2                        ; D2 = 48 + pass - 3 = 45 + pass (left X)
                    move.l     d2,-(sp)                     ; push Move X
                    move.l     a3,-(sp)                     ; push RastPort
                    move.l     d6,a5                        ; A5 = &_Move
                    jsr        (a5)                         ; Move(rp, left_X, Y)
                    move.l     #216,d3
                    sub.l      d4,d3
                    subq.l     #1,d3                        ; D3 = 194 (same Y)
                    move.l     d3,-(sp)                     ; push Draw Y
                    moveq      #$18,d0
                    sub.l      d4,d0                        ; D0 = 24 - 21 = 3
                    asl.l      #5,d0                        ; D0 = 96 = (24-D4)*32
                    moveq      #$18,d1                      ; D1 = 24
                    jsr        (ldivt)                      ; D0 = 96 / 24 = 4
                    move.l     d0,d2
                    move.l     (-8,a6),d3
                    add.l      #$0000011F,d3                ; D3 = 287 + pass
                    add.l      d3,d2                        ; D2 = 4 + 287 + pass = 291 + pass (right X)
                    move.l     d2,-(sp)                     ; push Draw X
                    move.l     a3,-(sp)
                    jsr        (_Draw)                      ; Draw(rp, right_X, Y)

                    ; ===== Row 1 (Y=197, D4 = 18). Same math, new D4. =====
                    moveq      #$12,d4                      ; D4 = 18
                    move.l     #216,d3
                    sub.l      d4,d3
                    subq.l     #1,d3                        ; D3 = 197 (Y)
                    move.l     d3,-(sp)
                    move.l     (-8,a6),d2
                    moveq      #$30,d0
                    add.l      d0,d2                        ; D2 = 48 + pass
                    moveq      #$18,d3
                    sub.l      d4,d3                        ; D3 = 6
                    asl.l      #2,d3                        ; D3 = 24
                    move.l     d3,d0                        ; D0 = 24
                    asl.l      #3,d3                        ; D3 = 192
                    sub.l      d0,d3                        ; D3 = 192 - 24 = 168 = (24-18)*28
                    moveq      #$18,d1
                    move.l     d3,d0
                    jsr        (ldivt)                      ; D0 = 168 / 24 = 7
                    move.l     d0,d3
                    sub.l      d3,d2                        ; D2 = 48 + pass - 7 = 41 + pass
                    move.l     d2,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)                         ; Move(rp, 41+pass, 197)
                    move.l     #$000000D8,d3
                    sub.l      d4,d3
                    subq.l     #1,d3                        ; D3 = 197
                    move.l     d3,-(sp)
                    moveq      #$18,d0
                    sub.l      d4,d0                        ; D0 = 6
                    asl.l      #5,d0                        ; D0 = 192 = 6*32
                    moveq      #$18,d1
                    jsr        (ldivt)                      ; D0 = 192 / 24 = 8
                    move.l     d0,d2
                    move.l     (-8,a6),d3
                    add.l      #$0000011F,d3                ; D3 = 287 + pass
                    add.l      d3,d2                        ; D2 = 8 + 287 + pass = 295 + pass
                    move.l     d2,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_Draw)                      ; Draw(rp, 295+pass, 197)

                    ; ===== Row 2 (Y=201, D4 = 14). =====
                    moveq      #14,d4                       ; D4 = 14
                    move.l     #$000000D8,d3
                    sub.l      d4,d3
                    subq.l     #1,d3                        ; D3 = 201
                    move.l     d3,-(sp)
                    move.l     (-8,a6),d2
                    moveq      #$30,d0
                    add.l      d0,d2                        ; D2 = 48 + pass
                    moveq      #$18,d3
                    sub.l      d4,d3                        ; D3 = 10
                    asl.l      #2,d3
                    move.l     d3,d0
                    asl.l      #3,d3
                    sub.l      d0,d3                        ; D3 = 280 = (24-14)*28
                    moveq      #$18,d1
                    move.l     d3,d0
                    jsr        (ldivt)                      ; D0 = 280 / 24 = 11
                    move.l     d0,d3
                    sub.l      d3,d2                        ; D2 = 37 + pass
                    move.l     d2,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)                         ; Move(rp, 37+pass, 201)
                    move.l     #$000000D8,d3
                    sub.l      d4,d3
                    subq.l     #1,d3                        ; D3 = 201
                    move.l     d3,-(sp)
                    moveq      #$18,d0
                    sub.l      d4,d0                        ; D0 = 10
                    asl.l      #5,d0                        ; D0 = 320 = 10*32
                    moveq      #$18,d1
                    jsr        (ldivt)                      ; D0 = 320 / 24 = 13
                    move.l     d0,d2
                    move.l     (-8,a6),d3
                    add.l      #$0000011F,d3
                    add.l      d3,d2                        ; D2 = 13 + 287 + pass = 300 + pass
                    move.l     d2,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_Draw)                      ; Draw(rp, 300+pass, 201)

                    ; ===== Row 3 (farthest, Y=207, D4 = 8). =====
                    moveq      #8,d4                        ; D4 = 8
                    ; Row 3 body: same kernel with D4=8.
                    move.l     #$000000D8,d3
                    sub.l      d4,d3
                    subq.l     #1,d3                        ; D3 = 216 - 8 - 1 = 207 (Y)
                    move.l     d3,-(sp)
                    move.l     (-8,a6),d2
                    moveq      #$30,d0
                    add.l      d0,d2                        ; D2 = 48 + pass
                    moveq      #$18,d3
                    sub.l      d4,d3                        ; D3 = 24 - 8 = 16
                    asl.l      #2,d3                        ; D3 = 64
                    move.l     d3,d0
                    asl.l      #3,d3                        ; D3 = 512
                    sub.l      d0,d3                        ; D3 = 512 - 64 = 448 = (24-8)*28
                    moveq      #$18,d1
                    move.l     d3,d0
                    jsr        (ldivt)                      ; D0 = 448 / 24 = 18
                    move.l     d0,d3
                    sub.l      d3,d2                        ; D2 = 48 + pass - 18 = 30 + pass
                    move.l     d2,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)                         ; Move(rp, 30+pass, 207)
                    move.l     #$000000D8,d3
                    sub.l      d4,d3
                    subq.l     #1,d3                        ; D3 = 207
                    move.l     d3,-(sp)
                    moveq      #$18,d0
                    sub.l      d4,d0                        ; D0 = 16
                    asl.l      #5,d0                        ; D0 = 512 = 16*32
                    moveq      #$18,d1
                    jsr        (ldivt)                      ; D0 = 512 / 24 = 21
                    move.l     d0,d2
                    move.l     (-8,a6),d3
                    add.l      #$0000011F,d3                ; D3 = 287 + pass
                    add.l      d3,d2                        ; D2 = 21 + 287 + pass = 308 + pass
                    move.l     d2,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_Draw)                      ; Draw(rp, 308+pass, 207)

                    ; ===== Final FLOOR FRONT-EDGE horizontal (Y=215, full screen width) =====
                    ; Spans X = 20+pass .. 319+pass; this is the bottom of the floor,
                    ; below all the trapezoid rows. Note $FFFFFF74 = -140 in signed long.
                    pea        ($D7).w                      ; Y = 215
                    move.l     (-8,a6),d3                   ; D3 = pass
                    add.l      #$000000A0,d3                ; D3 = pass + 160
                    add.l      #$FFFFFF74,d3                ; D3 = pass + 160 - 140 = pass + 20
                    move.l     d3,-(sp)                     ; push Move X
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)                         ; Move(rp, pass+20, 215)
                    pea        ($D7).w                      ; Y = 215 (same)
                    move.l     (-8,a6),d3
                    add.l      #$000000A0,d3                ; D3 = pass + 160
                    add.l      #$0000009F,d3                ; D3 = pass + 160 + 159 = pass + 319
                    move.l     d3,-(sp)                     ; push Draw X
                    move.l     a3,-(sp)
                    jsr        (_Draw)                      ; Draw(rp, pass+319, 215)
;------------------------------------------------------------------------------
; .dot_grid1_outer Sub-block E1: PIXEL-DOT ANCHOR GRID #1 (near horizon, X=$3C=60, Y=$6E=110).
;
;   SetAPen(0)                          ; pen 0 = clear
;   for (D4 = -2; D4 <= 2; D4++):
;       for (D5 = -2; D5 <= 2; D5++):
;           Move(rp, 60+D5, 110+pass+D4)
;
; Curious detail: only Move() is called, no Draw(). The graphics.library
; Move just sets the cursor position; it does not plot pixels. This double
; loop appears to do nothing visible.
;
; Possible explanations:
;   (a) Leftover scaffolding from a previous draft of the C source that
;       was meant to plot crosshairs but lost its Draw() calls.
;   (b) A no-op artifact of a macro that should have expanded to a
;       single-pixel plot.
;   (c) The original C used WritePixel() at these grid points but the
;       compiler aliased it to Move() somehow (unlikely).
; Either way, no visible pixels result.
;
; The horizon mark at (60, 110+pass) IS drawn by .horizon_mark1 below with pen -1.
;------------------------------------------------------------------------------
                    clr.l      -(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetAPen)                   ; SetAPen(rp, 0)
                    moveq      #-2,d4                       ; D4: -2..+2
                    lea        ($0080,sp),sp
.dot_grid1_outer               moveq      #-2,d5                       ; D5: -2..+2
.dot_grid1_inner               move.l     d5,d3
                    moveq      #$3C,d2
                    add.l      d2,d3                        ; X = 60 + D5
                    move.l     d3,-(sp)
                    move.l     (-8,a6),d3
                    moveq      #$6E,d2
                    add.l      d2,d3
                    add.l      d4,d3                        ; Y = 110 + pass + D4
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)                         ; Move(rp, 60+D5, 110+pass+D4) - no Draw
                    lea        (12,sp),sp
.dg1_next_x               addq.l     #1,d5
                    moveq      #2,d2
                    cmp.l      d5,d2
                    bge.b      .dot_grid1_inner
.dg1_next_y               addq.l     #1,d4
                    moveq      #2,d2
                    cmp.l      d4,d2
                    bge.b      .dot_grid1_outer

;------------------------------------------------------------------------------
; .horizon_mark1 - the lone horizon-mark pen-down at (60, 110+pass).
; Sets pen -1 (= color $0F = white-bit-on-plane-5) and Moves there, leaving
; the pen at that position. (Again no Draw, so no visible mark - the cursor
; just ends up here. The intent appears to be to mark the horizon point.)
;------------------------------------------------------------------------------
.horizon_mark1               move.l     #$FFFFFFFF,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetAPen)                   ; SetAPen(rp, -1)
                    pea        ($3C).w                      ; X = 60
                    move.l     (-8,a6),d3
                    moveq      #$6E,d2
                    add.l      d2,d3                        ; Y = 110 + pass
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)                         ; Move(rp, 60, 110+pass) - no Draw

;------------------------------------------------------------------------------
; .dot_grid2_outer Sub-block E2: PIXEL-DOT ANCHOR GRID #2 (near floor, X=$7C=124, Y=$4E=78).
; Same structure as the first grid, same observation about Move-without-Draw.
;------------------------------------------------------------------------------
                    clr.l      -(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetAPen)                   ; SetAPen(rp, 0)
                    moveq      #-2,d4
                    lea        ($001C,sp),sp
.dot_grid2_outer               moveq      #-2,d5
.dot_grid2_inner               move.l     d5,d3
                    moveq      #$7C,d2
                    add.l      d2,d3                        ; X = 124 + D5
                    move.l     d3,-(sp)
                    move.l     (-8,a6),d3
                    moveq      #$4E,d2
                    add.l      d2,d3
                    add.l      d4,d3                        ; Y = 78 + pass + D4
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)                         ; Move only
                    lea        (12,sp),sp
.dg2_next_x               addq.l     #1,d5
                    moveq      #2,d2
                    cmp.l      d5,d2
                    bge.b      .dot_grid2_inner
.dg2_next_y               addq.l     #1,d4
                    moveq      #2,d2
                    cmp.l      d4,d2
                    bge.b      .dot_grid2_outer

;------------------------------------------------------------------------------
; .horizon_mark2 - the second horizon-mark Move at (124, 78+pass). Same pattern.
;------------------------------------------------------------------------------
.horizon_mark2               move.l     #$FFFFFFFF,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetAPen)                   ; SetAPen(rp, -1)
                    pea        ($7C).w
                    move.l     (-8,a6),d3
                    moveq      #$4E,d2
                    add.l      d2,d3                        ; Y = 78 + pass
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)                         ; Move(rp, 124, 78+pass) - no Draw
                    lea        ($0014,sp),sp

;------------------------------------------------------------------------------
; End of one background-render pass. Advance to the next of 16 staggered
; passes; this draws the SAME geometry but offset by +1 pixel horizontally
; (via the "+ pass" terms above).
;------------------------------------------------------------------------------
.next_bg_pass               addq.l     #1,(-8,a6)                   ;16 loops
                    moveq      #16,d2
                    cmp.l      (-8,a6),d2
                    bgt.w      .bgrenderloop                ; loop while pass < 16

;------------------------------------------------------------------------------
; Phase 11 - reset the displayed background pointer to _bgptr[0] (the X-scroll
; compensation in the main loop will swap it again every frame), then load
; the initial palette for entries 0, 1, 16, 17:
;
;   COLOR00 = $0AAA  light grey       (wireframe room foreground)
;   COLOR01 = $0666  darker grey      (alternative grid color)
;   COLOR16 = $0A0A  magenta-ish      (shadow plane)
;   COLOR17 = $0606  dark magenta     (shadow plane darker)
;
; Colors 2..14 are written every frame by the palette-rotation code in the
; main loop (the "color register trick" that spins the ball - see Phase 14).
; Colors 18..30 mirror 2..14 with offset 16, so the ball reads either
; subpalette depending on the high bit of bitplane 5.
;
; Note: SetRGB4 takes (ViewPort, index, R, G, B) as four longwords. The
; channel values 0..15 are written into the low nibble of each component.
;------------------------------------------------------------------------------
.bg_done               move.l     (-4,a6),a5
                    move.l     (a5),a0
                    move.l     (_bgptr),(bm_Planes+16,a0)   ; reset Planes[4] = _bgptr[0]
                    pea        (10).w                       ; B=10
                    pea        (10).w                       ; G=10
                    pea        (10).w                       ; R=10  -> COLOR00 = $0AAA grey
                    clr.l      -(sp)                        ; index 0
                    move.l     (_viewport),-(sp)
                    jsr        (_SetRGB4)
                    pea        (6).w
                    pea        (6).w
                    pea        (6).w                        ; COLOR01 = $0666 darker grey
                    pea        (1).w
                    move.l     (_viewport),-(sp)
                    jsr        (_SetRGB4)
                    pea        (10).w
                    clr.l      -(sp)
                    pea        (10).w                       ; COLOR16 = $0A0A magenta-ish
                    pea        ($10).w
                    move.l     (_viewport),-(sp)
                    jsr        (_SetRGB4)
                    pea        (6).w
                    clr.l      -(sp)
                    pea        (6).w                        ; COLOR17 = $0606 dark magenta
                    pea        ($11).w
                    move.l     (_viewport),-(sp)
                    jsr        (_SetRGB4)

;------------------------------------------------------------------------------
; Phase 12 - reset physics state to ball-at-top-center.
;   _x   = 0          ball X position (relative; 0 = screen center)
;   _fy  = $80000041  FFP encoding of negative-something Y position
;   _y   = 3          integer Y position
;   _vx  = 1          X velocity (positive = moving right)
;   _vy  = 0          Y velocity
;   _ax  = 0          X acceleration (no air resistance horizontally)
;   _ay  = 1          Y acceleration (= gravity, positive = downward)
;
; Then call _InitBoing (in src/anim.s) to OpenDevice("audio.device"), load
; boing.samples from disk, and allocate channel-mask requests.
;------------------------------------------------------------------------------
                    clr.l      (a4)                         ; _x = 0
                    move.l     #$80000041,(_fy)             ; _fy = FFP value (initial Y in float form)
                    moveq      #3,d2
                    move.l     d2,(_y)                      ; _y = 3
                    moveq      #1,d2
                    move.l     d2,(_vx)                     ; _vx = 1
                    clr.l      (_vy)                        ; _vy = 0
                    clr.l      (_ax)                        ; _ax = 0
                    moveq      #1,d2
                    move.l     d2,(_ay)                     ; _ay = 1 (gravity)
                    clr.l      (_icount)                    ; impact-count counter cleared
                    jsr        (_InitBoing)                 ; open audio.device, load samples

;------------------------------------------------------------------------------
; Phase 13 - final RastPort tweaks and the ONE direct chipset poke.
;
; rp_AreaPtrn = _fillpat (alternating $FFFF/$8000 pattern; see globals)
; rp_AreaPtSz = 4        (pattern size = 16 lines high)
; rp_Mask     = $10      (subsequent area fills only touch bitplane 5)
;
; The DMACON write: DMAF_RASTER ($0100) | DMAF_SETCLR ($8000) = $8100.
; This SETS the bitplane-DMA enable bit. Standard practice would be to leave
; this alone (audio.device's BeginIO call should not have touched it), so
; this poke is presumably defensive - or it covers a known case where
; _InitBoing's audio-channel handshake interferes with bitplane DMA.
;
; This is the ONLY direct $DFF000-range write in the entire demo.
; See AMIGA-KNOWHOW.md section C.1 for the DMACON bit layout.
;------------------------------------------------------------------------------
                    move.l     #$FFFFFFFF,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetAPen)                   ; SetAPen(rp, -1)
                    move.l     #_fillpat,(rp_AreaPtrn,a3)   ; area-fill pattern
                    move.b     #4,(rp_AreaPtSz,a3)          ; pattern height = 2^4 = 16 lines
                    move.b     #$10,(rp_Mask,a3)            ; only touch bitplane 5
                    move.w     #DMAF_RASTER||DMAF_SETCLR,(custom+dmacon)  ; bitplane DMA on

                    clr.l      (_sstep)                     ; _sstep = 0 (paused state at start)
                    lea        ($0058,sp),sp
;==============================================================================
; Phase 14 - the main loop.
;
; Top of loop: poll IDCMP for user input.
;   - GetMsg(Window->UserPort)
;     - If no message: fall through to .nomsg (do one frame of animation).
;     - If message:
;       - CLOSEWINDOW   -> jsr _GoodBye (which calls _exit; never returns).
;       - MOUSEBUTTONS:
;           SELECTDOWN (LMB) or MENUDOWN (RMB) -> toggle _sstep (run/pause).
;       - Anything else -> loop without animating this frame.
;
; _sstep semantics:
;   0 = paused (no animation)
;   non-zero = running. Inside the running path, _sstept is set by some
;              external event (maybe the audio.device finish-interrupt? or
;              not used here at all - it's clr'd unconditionally and the
;              flag's purpose is opaque without symbols).
;==============================================================================
.mainloop           move.l     (_Window),a2
                    move.l     (wd_UserPort,a2),-(sp)
                    jsr        (_GetMsg)                    ; D0 = IntuiMessage * or NULL
                    move.l     d0,a0
                    cmp.w      #0,a0
                    addq.l     #4,sp
                    beq.b      .nomsg                       ; no message -> run one frame
.handle_msg                move.l     (im_Class,a0),d2             ; D2 = im_Class
                    move.w     (im_Code,a0),d3              ; D3 = im_Code
                    move.l     a0,-(sp)
                    jsr        (_ReplyMsg)                  ; release the message back to OS
                    move.l     d2,a0
                    addq.l     #4,sp
                    cmp.w      #MOUSEBUTTONS,a0             ; class == MOUSEBUTTONS ?
                    blt.b      .mainloop                    ; class < MOUSEBUTTONS -> ignore
                    bgt.b      .check_close                        ; class > MOUSEBUTTONS -> check CLOSE
                    bra.b      .check_lmb                         ; class == MOUSEBUTTONS -> handle button

.check_close               cmp.w      #CLOSEWINDOW,a0              ; class == CLOSEWINDOW ?
                    bne.b      .mainloop                    ; not close -> ignore
.do_close                jsr        (_GoodBye,pc)                ; close gadget -> quit
.check_lmb                moveq      #SELECTDOWN,d2               ;LMB?
                    cmp.w      d3,d2
                    beq.w      .toggle_run                         ; LMB pressed -> toggle
.check_rmb                moveq      #MENUDOWN,d2                 ;RMB?
                    cmp.w      d3,d2
                    bne.b      .mainloop                    ;change rates  (any other code -> ignore)
; Toggle run/pause. Under the reworked .nomsg semantics _sstep==0 = running,
; _sstep!=0 = paused. (Label names kept from the original; .set_run now sets
; the paused state and vice-versa, but the toggle is correct either way.)
.toggle_run                tst.l      (_sstep)                     ; currently running (==0)?
                    beq.b      .set_run                         ; yes -> pause it
.set_pause                clr.l      (_sstep)                     ; was paused -> resume (run)
                    bra.b      .mainloop

.set_run                moveq      #1,d2
                    move.l     d2,(_sstep)                  ; was running -> pause
                    bra.b      .mainloop

;------------------------------------------------------------------------------
; .nomsg: no user input this iteration. Running -> animate one frame; paused
; -> WaitTOF and loop.
;------------------------------------------------------------------------------
; Original AMICUS logic: `tst _sstep / beq .palette_step` (run path, NO explicit
; WaitTOF) then `WaitTOF / tst _sstept / beq .mainloop / clr _sstept`. _sstept is
; never assigned in the binary (verified vs archive/boing_original.s + boing_s),
; so _sstep!=0 just WaitTOF'd and looped (frozen); animation only ran on the
; _sstep==0 path.
;
; PACING: the running path takes NO explicit WaitTOF. Frame pacing is the
; WaitTOF that RethinkDisplay does internally (RKRM: "RethinkDisplay ... also
; does a WaitTOF()") -- one vblank per frame -> the video FIELD RATE (50Hz PAL
; / 60Hz NTSC). Do NOT add an explicit WaitTOF on the running path: combined
; with RethinkDisplay's it would be two waits per frame and halve the rate.
; Only the paused path WaitTOFs, to avoid busy-spinning the IDCMP poll.
;
; This repo's one deviation is AUTO-START: default _sstep=0 (init clr near the
; top + .first_frame_init) so it runs from boot without a click; the pacing
; above is the original's, unchanged. Dead _sstept flag retired. See DEVIATIONS.md.
.nomsg              tst.l      (_sstep)                     ; paused?
                    beq.b      .palette_step                ; _sstep==0 -> running: animate; RethinkDisplay's own WaitTOF paces it (field rate)
                    jsr        (_WaitTOF)                   ; _sstep!=0 -> paused: pace here to avoid busy-spin, then loop
                    bra.b      .mainloop
;------------------------------------------------------------------------------
; .palette_step - palette-rotation step. THIS IS THE COLOR-REGISTER TRICK that gives
; the ball its apparent rotation. The ball's bitplanes (1..4) hold a static
; image, but the palette indices they reference are rewritten every frame
; so the red/white checker stripes appear to march around the sphere.
;
; D4 is the rotation phase (modulo 14). Incremented when ball moves left
; (_vx < 0) and decremented when ball moves right, so the spin direction
; matches the ball's motion.
;
; The 14 cycled palette entries are arranged in pairs (low and high
; palette halves at indices 2..15 and 18..31):
;     - 7 of them are set to $0FFF (white)
;     - 7 of them are set to $0F00 (red)
;     - 1 is set to $0FDD (pink-white, the "shading" stripe stored in
;       local -10(a6)). Its position changes with direction so the
;       shading appears to lead the leading edge of the rotation.
;
; The cycling logic walks D0 from 0..13 and writes COLOR(((D0 + D4) mod 14)
; + 2) twice - once in the low palette half (+ 2) and once in the high half
; (+ 18). Bitplane 5 selects between halves so the ball-pixel plane and
; the background-pixel plane see different colors.
;
; Compare boing2.c in archive/boing-c (Maher reconstruction) for the same
; trick written in C: the rotation loop there is just a few lines that
; rewrite the ColorMap entries directly, exactly like this code does.
;------------------------------------------------------------------------------
.palette_step               tst.l      (_vx)                        ; direction depends on X velocity
                    bge.b      .dir_right                        ; vx >= 0 -> rotate one way
.dir_left               addq.l     #1,d4                        ; vx < 0 (left)  -> D4++
                    bra.b      .dir_wrap_neg

.dir_right               subq.l     #1,d4                        ; vx >= 0 (right) -> D4--
.dir_wrap_neg               moveq      #-1,d2
                    cmp.l      d4,d2
                    bne.b      .dir_wrap_pos
.dir_set_13               moveq      #13,d4                       ; wrap D4: -1 -> 13
.dir_wrap_pos               moveq      #14,d2
                    cmp.l      d4,d2
                    bne.b      .white_loop_init
.dir_set_0               moveq      #0,d4                        ; wrap D4: 14 -> 0
;------------------------------------------------------------------------------
; Phase 14a: write the 7 WHITE stripes ($0FFF) into both palette halves.
;
; For each D0 in 0..6, compute:
;     low_idx  = (D0 + D4) mod 14, then + 2  -> COLOR[2..15]
;     high_idx = (D0 + D4) mod 14, then + 18 -> COLOR[18..31]
; and write $0FFF (white) at both positions.
;
; The "mod 14" is done branch-free by comparing (D0+D4) to 14: if greater
; we subtract 12 (the .white_lo_wrap branch), otherwise we add 2 (the .white_lo_nowrap branch).
; That looks asymmetric but produces the right result: D0+D4 ranges 0..19,
; and:
;   - For D0+D4 in 0..14, target_idx = D0+D4+2  (range 2..16)
;   - For D0+D4 in 15..19, target_idx = D0+D4-12 (range 3..7)
; ...wrapping the cycle phase around. Index times 2 (add.l d3,d3) converts
; word-stride to byte-stride for (_ct) which is the ColorTable byte array.
;
; The "+ $10" path at .white_hi_nowrap/.white_hi_wrap is the high-palette half (offset +16
; entries from the low half) - same computation, plus 16 to the target
; index.
;------------------------------------------------------------------------------
.white_loop_init               moveq      #0,d0                        ; D0 = inner loop counter (0..6)
.white_loop               ; --- WHITE stripe at low palette half ---
                    move.l     d0,d2
                    add.l      d4,d2                        ; D2 = D0 + D4 (raw cycle phase)
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .white_lo_wrap                        ; D2 > 14 -> wrap (.white_lo_wrap)
.white_lo_nowrap               move.l     d0,d1                        ; --- no-wrap path ---
                    add.l      d4,d1
                    addq.l     #2,d1                        ; D1 = D0 + D4 + 2   (low half index)
                    bra.b      .write_white_lo

.white_lo_wrap               move.l     d0,d1                        ;poking colortable directly.. again nasty
                    add.l      d4,d1                        ; --- wrap path ---
                    moveq      #12,d2
                    sub.l      d2,d1                        ; D1 = D0 + D4 - 12  (wrapped low idx)
.write_white_lo               move.l     d1,d3
                    add.l      d3,d3                        ; D3 = index * 2  (word-stride)
                    move.l     d3,a1
                    add.l      (_ct),a1                     ; A1 = &ColorTable[index]
                    move.w     #$0FFF,(a1)                  ; write WHITE
                    ; --- WHITE stripe at high palette half (low_idx + 16) ---
                    move.l     d0,d2
                    add.l      d4,d2
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .white_hi_wrap                        ; D2 > 14 -> wrap (.white_hi_wrap)
.white_hi_nowrap               move.l     d0,d1
                    add.l      d4,d1
                    addq.l     #2,d1
                    moveq      #$10,d2
                    add.l      d2,d1                        ; D1 = D0 + D4 + 2 + 16  (high idx)
                    bra.b      .write_white_hi

.white_hi_wrap               move.l     d0,d1
                    add.l      d4,d1
                    moveq      #12,d2
                    sub.l      d2,d1
                    moveq      #$10,d3
                    add.l      d3,d1                        ; D1 = D0 + D4 - 12 + 16 (wrapped high)
.write_white_hi               move.l     d1,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     #$0FFF,(a1)                  ; write WHITE in high half
.next_white               addq.l     #1,d0
                    moveq      #7,d2
                    cmp.l      d0,d2
                    bgt.b      .white_loop                        ; loop D0: 0..6 (7 white stripes)
;------------------------------------------------------------------------------
; Phase 14b: write the PINK-WHITE shading stripe ($0FDD, cached in -10(a6)).
;
; There's one stripe in the cycle that's a slightly off-white "highlight"
; color. Its position in the cycle depends on direction so the highlight
; appears to lead the rotation:
;   - If moving right (_vx >= 0): highlight at cycle offset 0    (.pink_right path)
;   - If moving left  (_vx <  0): highlight at cycle offset 6    (.pink_left path)
; This makes the brightest stripe always face the "leading" side of the ball.
;------------------------------------------------------------------------------
.dir_test_pink               tst.l      (_vx)
                    bge.b      .pink_right                        ; vx >= 0 -> highlight at offset 0
.pink_left               ; --- vx < 0: highlight at offset 6 (low half) ---
                    move.l     d4,d2
                    addq.l     #6,d2                        ; D2 = D4 + 6
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .pink_left_lo_wrap
.pink_left_lo_nowrap                move.l     d4,d0                        ; (no-wrap)
                    addq.l     #6,d0
                    addq.l     #2,d0                        ; D0 = D4 + 6 + 2 (low idx)
                    bra.b      .write_pink_lo_l

.pink_left_lo_wrap                move.l     d4,d0                        ; (wrap)
                    addq.l     #6,d0
                    moveq      #12,d2
                    sub.l      d2,d0                        ; D0 = D4 + 6 - 12 (low idx)
.write_pink_lo_l                move.l     d0,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     (-10,a6),(a1)                ; write $0FDD pink-white
                    move.l     d4,d2
                    addq.l     #6,d2                        ; same again for the high half
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .pink_left_hi_wrap
.pink_left_hi_nowrap                move.l     d4,d0
                    addq.l     #6,d0
                    addq.l     #2,d0
                    moveq      #$10,d2
                    add.l      d2,d0
                    bra.b      .write_pink_hi_l

.pink_left_hi_wrap                move.l     d4,d0
                    addq.l     #6,d0
                    moveq      #12,d2
                    sub.l      d2,d0
                    moveq      #$10,d3
                    add.l      d3,d0
.write_pink_hi_l                move.l     d0,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     (-10,a6),(a1)
                    bra.b      .red_loop_init

;------------------------------------------------------------------------------
; .pink_right: vx >= 0 path - highlight at offset 0 in both palette halves.
; Mirror of the .pink_left vx<0 branch above but with D4+0 instead of D4+6.
;------------------------------------------------------------------------------
.pink_right               move.l     d4,d2                        ; D2 = D4 + 0 (highlight here)
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .pink_right_lo_wrap
.pink_right_lo_nowrap               move.l     d4,d0
                    addq.l     #2,d0                        ; D0 = D4 + 2 (low idx)
                    bra.b      .write_pink_lo_r

.pink_right_lo_wrap               move.l     d4,d0
                    moveq      #12,d2
                    sub.l      d2,d0                        ; D0 = D4 - 12 (wrapped)
.write_pink_lo_r               move.l     d0,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     (-10,a6),(a1)                ; write $0FDD pink-white
                    move.l     d4,d2                        ; same again for high half
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .pink_right_hi_wrap
.pink_right_hi_nowrap               move.l     d4,d0
                    addq.l     #2,d0
                    moveq      #$10,d2
                    add.l      d2,d0                        ; D0 = D4 + 2 + 16 (high idx)
                    bra.b      .write_pink_hi_r

.pink_right_hi_wrap               move.l     d4,d0
                    moveq      #12,d2
                    sub.l      d2,d0
                    moveq      #$10,d3
                    add.l      d3,d0                        ; D0 = D4 - 12 + 16 (wrapped high)
.write_pink_hi_r               move.l     d0,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     (-10,a6),(a1)                ; write $0FDD high half

;------------------------------------------------------------------------------
; Phase 14c: write the 7 RED stripes ($0F00) at cycle offsets 7..13.
; Same shape as Phase 14a (white at offsets 0..6) but with red color
; and an inner counter going 7..13 instead of 0..6.
;------------------------------------------------------------------------------
.red_loop_init                moveq      #7,d0                        ; D0 = 7
.red_loop                move.l     d0,d2
                    add.l      d4,d2
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .red_lo_wrap                         ; > 14 -> wrap
.red_lo_nowrap                move.l     d0,d1
                    add.l      d4,d1
                    addq.l     #2,d1                        ; D1 = D0 + D4 + 2  (low idx)
                    bra.b      .write_red_lo

.red_lo_wrap                move.l     d0,d1
                    add.l      d4,d1
                    moveq      #12,d2
                    sub.l      d2,d1                        ; D1 = D0 + D4 - 12 (wrapped)
.write_red_lo                move.l     d1,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     #$0F00,(a1)                  ; write RED at low half
                    move.l     d0,d2
                    add.l      d4,d2
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .red_hi_wrap
.red_hi_nowrap                move.l     d0,d1
                    add.l      d4,d1
                    addq.l     #2,d1
                    moveq      #$10,d2
                    add.l      d2,d1                        ; high half index
                    bra.b      .write_red_hi

.red_hi_wrap                move.l     d0,d1
                    add.l      d4,d1
                    moveq      #12,d2
                    sub.l      d2,d1
                    moveq      #$10,d3
                    add.l      d3,d1                        ; wrapped high half
.write_red_hi                move.l     d1,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     #$0F00,(a1)                  ; write RED at high half
.next_red                addq.l     #1,d0
                    moveq      #14,d2
                    cmp.l      d0,d2
                    bgt.b      .red_loop                         ; loop D0: 7..13 (7 red stripes)
;------------------------------------------------------------------------------
; .physics_y - Y-axis physics step (FFP floating point).
;
; Conceptual operation (_fy is FFP, oscillates 0..+96 — apex at 0, floor at +96):
;     _fy   = _fy + (float)(_vy / 10)          ; integrate velocity (_vy grows via gravity)
;     if (int)(_fy + 0.5) <= 0 :               ; crossed the apex (top)?
;         _fy   = -_fy ; _vy = -_vy            ; elastic reflect at 0
;     if _fy > +96.0 :                         ; reached the floor?
;         _fy   = 192.0 - _fy ; _vy = -_vy     ; elastic reflect at +96 (damping is dead: _dampy=0)
;         play "boing"
;     _y    = (int)(_fy + 0.5)                 ; integer Y for the ViewPort scroll
;     _x   += _vx ; _vx += _ax                 ; integer X step (_ax = 0)
;
; The FFP calls are: ldivt (longword integer divide), fflti (int->FFP),
; faddi/fsubi/fmuli/fdivi (FFP arithmetic taking FFP value in D0:D1 pairs),
; ffixi (FFP->int truncate), fcmpi (FFP compare), fnegi (FFP negate).
; All come from the math library wrappers in src/runtime.s.
;
; Why FFP: the Y physics needs sub-integer precision (the ball decelerates
; smoothly approaching the apex of its arc, where motion is sub-pixel per
; frame). Pure integer math would either lose precision or require a
; high-resolution fixed-point format. FFP is the standard 1985-era choice
; for sub-FPU 68000 floating point. See AMIGA-KNOWHOW.md section K for
; the FFP format and call convention.
;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; FFP constants used below (decoded from the 32-bit Motorola Fast Float
; bit-pattern: 24-bit mantissa | 1-bit sign | 7-bit excess-64 exponent):
;     $80000040 ≈  0.5      (mantissa $800000 = .5,  exp $40 = 0)
;     $80000041 ≈  1.0      (mantissa $800000 = .5,  exp $41 = +1, so .5*2)
;     $C0000047 = +96.0     (POSITIVE; mantissa $C00000 = .75, exp $47 = +7; sign bit = 0)
;     $C0000048 = +192.0    (POSITIVE; exp $48 = +8, doubled)
; Both are stored POSITIVE — the leading $C0 is the normalised mantissa's MSB,
; not a sign bit (the FFP sign is bit 7 of the low byte). _fy starts at +1.0 and
; grows under gravity; it oscillates 0..96 — apex reflected at 0 (.fy_negate),
; floor reflected at +96 via 192-_fy (.bounced_floor) — giving the ~90 px bounce
; measured in docs/ANIMATION-DETAILS.md §4. [Earlier comments mis-decoded these
; as negative; corrected — see docs/BOING-ANALYSIS.md §4.4.]
;------------------------------------------------------------------------------
.physics_y          ; --- Step 1: integrate velocity into FFP position ---
                    ; _fy = _fy + ((float)_vy / 10.0)
                    moveq      #10,d1
                    move.l     (_vy),d0
                    jsr        (ldivt)                      ; D0 = _vy / 10  (int divide)
                    jsr        (fflti)                      ; D0 = float(D0)  (int → FFP)
                    moveq      #0,d1
                    move.l     d1,-(sp)                     ; push high half of FFP arg
                    move.l     d0,-(sp)                     ; push low half  (faddi takes 64-bit pair)
                    move.l     (_fy),d0                     ; D0 = _fy (current FFP Y)
                    moveq      #0,d1
                    jsr        (faddi)                      ; D0 = _fy + (vy/10)  (FFP add)
                    move.l     d0,(_fy)                     ; _fy = D0  (write back)

                    ; --- Step 2: bounce-test the floor at FFP +0.5
                    ; if (_fy + 0.5) > 0  :  the ball has crossed the floor plane
                    clr.l      -(sp)
                    move.l     #$80000040,-(sp)             ; push FFP 0.5 (one operand)
                    move.l     (_fy),d0                     ; D0 = _fy (other operand)
                    moveq      #0,d1
                    jsr        (faddi)                      ; D0 = _fy + 0.5
                    jsr        (ffixi)                      ; D0 = (int)(_fy + 0.5)
                    move.l     d0,d3                        ; D3 = (int)(_fy + 0.5)
                    bgt.b      .fy_compare                  ; if D3 > 0, ball above floor → check apex

.fy_negate          ; --- Floor crossed: reflect _fy and _vy across the floor ---
                    ; _fy = -_fy   ; _vy = -_vy   (the elastic-bounce primitive)
                    move.l     (_fy),d0
                    moveq      #0,d1
                    jsr        (fnegi)                      ; D0 = -_fy
                    move.l     d0,(_fy)                     ; _fy = -_fy
                    move.l     (_vy),d2
                    neg.l      d2                           ; D2 = -_vy
                    move.l     d2,(_vy)                     ; _vy = -_vy

.fy_compare         ; --- Step 3: floor hit-detection at +96.0 ---
                    ; if _fy > +96.0 the ball has reached the floor this frame, so
                    ; trigger the bounce (.bounced_floor) and the "boing" sound.
                    clr.l      -(sp)
                    move.l     #$C0000047,-(sp)             ; push FFP +96.0
                    move.l     (_fy),d0
                    moveq      #0,d1
                    jsr        (fcmpi)                      ; FFP compare _fy : +96.0
                    ble.b      .physics_x                   ; _fy ≤ +96  → no floor-impact this frame

.bounced_floor      ; --- Floor impact: trigger audio, damp velocity, clamp at rest ---
                    move.w     #1,(_boing)                  ; _boing = 1  → audio dispatcher plays floor sample
                    ; reflect _fy about the floor: _fy = 192.0 - _fy
                    move.l     (_fy),d0
                    moveq      #0,d1
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    moveq      #0,d1
                    move.l     #$C0000048,d0                ; +192.0
                    jsr        (fsubi)                      ; D0 = 192.0 - _fy
                    move.l     d0,(_fy)                     ; _fy = 192 - _fy  (elastic reflect at floor)
                    ; _vy = -_vy + (_vy / _dampy)   ; damped reflection
                    move.l     (_vy),d1
                    move.l     (_dampy),d0
                    jsr        (ldivt)                      ; D0 = _vy / _dampy  (bounce loss)
                    move.l     d0,d3
                    move.l     (_vy),d2
                    neg.l      d2
                    add.l      d2,d3                        ; D3 = -_vy + (_vy / _dampy)
                    move.l     d3,(_vy)
                    blt.b      .physics_x                   ; if still going up, proceed

.vy_rest            ; --- Damping reduced _vy to ≤ 0: clamp to "at rest" state ---
                    clr.l      (_vy)                        ; _vy = 0
                    move.l     #$80000041,(_fy)             ; _fy = 1.0 (rest position above floor)

.physics_x          ; --- Step 4: project final integer Y for the scroll offset ---
                    ; _y = (int)(_fy + 0.5)   ; rounded integer Y for ViewPort.RyOffset
                    clr.l      -(sp)
                    move.l     #$80000040,-(sp)             ; FFP 0.5
                    move.l     (_fy),d0
                    moveq      #0,d1
                    jsr        (faddi)                      ; D0 = _fy + 0.5
                    jsr        (ffixi)                      ; D0 = (int)(_fy + 0.5)
                    move.l     d0,(_y)                      ; commit integer Y

                    ; --- Step 5: X physics (pure integer; no FFP needed for left/right) ---
                    ; _x  += _vx           ; ball X position
                    ; _vx += _ax           ; (always 0 here - _ax = 0 = no horizontal drag)
                    move.l     (_vx),d2
                    add.l      d2,(a4)                      ; *_x = _x + _vx        (a4 = &_x)
                    move.l     (_ax),d2
                    add.l      d2,(_vx)                     ; _vx += _ax  (no-op since _ax=0)

                    ; --- Step 6: bounce off left wall? ---
                    ; if (_x < _left):  reflect _x across _left and flip _vx
                    move.l     (a4),d2
                    cmp.l      (_left),d2
                    bge.b      .check_right                 ; _x ≥ _left  → no left-wall impact

.bounced_left       move.w     #2,(_boing)                  ; _boing = 2  → audio plays left-wall sample
                    move.l     (_left),d2
                    add.l      d2,d2                        ; D2 = 2 * _left
                    sub.l      (a4),d2                      ; D2 = 2*_left - _x  (mirror)
                    move.l     d2,(a4)                      ; _x = 2*_left - _x  (reflected)
                    move.l     (_vx),d2
                    neg.l      d2
                    move.l     d2,(_vx)                     ; _vx = -_vx

                    ; --- Step 7: bounce off right wall? ---
.check_right        move.l     (a4),d2
                    cmp.l      (_right),d2
                    ble.b      .scroll_apply                ; _x ≤ _right → no right-wall impact

.bounced_right      move.w     #3,(_boing)                  ; _boing = 3  → audio plays right-wall sample
                    move.l     (_right),d2
                    add.l      d2,d2
                    sub.l      (a4),d2                      ; mirror across _right
                    move.l     d2,(a4)
                    move.l     (_vx),d2
                    neg.l      d2
                    move.l     d2,(_vx)                     ; _vx = -_vx
;------------------------------------------------------------------------------
; .scroll_apply - SCROLL THE BALL ONTO THE SCREEN via ViewPort offsets, then patch
; the 5th-bitplane pointer to compensate for the scroll so the background
; appears stationary.
;
; This is the SAME technique as the lost 1984 CES original and Maher's
; boing3.c + boing4.c reconstruction:
;
;   1. Write ViewPort.RasInfo.RyOffset = -_y_lower (so the bitmap's
;      origin is shifted upward by _y_lower lines, exposing rows below).
;   2. Write ViewPort.RasInfo.RxOffset = high-word(_x) (sub-pixel X scroll).
;   3. Pick which of the 16 staggered background bitplanes to display
;      based on (_x & 15) - that gives sub-byte X alignment.
;   4. Offset the chosen background plane pointer by -(_x / 16) * 2 bytes
;      (= -1 byte stride per 16 pixels of X) and Y * bytes-per-row,
;      so the displayed background patch tracks the OPPOSITE of the
;      ViewPort offset, cancelling it out -> background looks static.
;
; This is the part of the demo Maher describes as:
;   "moving the pointer to account for most of the rastport scroll we
;    introduce to the other bitplanes, but also selecting the appropriate
;    bitplane from this array of 16 bitplanes to make the more fine-grained
;    adjustments."
; See archive/boing-c/boing5.c around line 786-815, and DEMO-BACKGROUND.md
; section 7.4.4 ("The fifth bitplane for the background").
;------------------------------------------------------------------------------
.scroll_apply                move.l     (_viewport),a0               ;do the scrolling
                    move.l     (vp_RasInfo,a0),a2
                    clr.w      d2
                    sub.w      (_y_lower),d2
                    move.w     d2,(ri_RyOffset,a2)          ; RyOffset = -_y_lower  (Y scroll)
                    move.l     (_viewport),a0
                    move.l     (vp_RasInfo,a0),a2
                    move.w     (2,a4),(ri_RxOffset,a2)      ; RxOffset = hi-word(_x)  (X scroll)
                    ; --- pick the right staggered background plane for sub-byte X alignment ---
                    move.l     (_viewport),a0
                    move.l     (vp_RasInfo,a0),a2
                    move.l     (ri_BitMap,a2),a2            ; A2 = visible BitMap
                    move.l     (a4),d3
                    moveq      #15,d2                       ;pick correct background pointer for the amount
                    and.l      d2,d3                        ;of scroll, this way the bg doesn't move along
                    move.w     d3,d2
                    asl.w      #2,d2                        ; D2 = (_x & 15) * 4 (longword stride)
                    move.l     #_bgptr,a0
                    move.l     (a0,d2.w),a1                 ; A1 = _bgptr[_x & 15]
                    ; --- back the plane pointer up by (_x >> 4) bytes * 2 ---
                    move.l     (a4),d2
                    asr.l      #4,d2                        ; D2 = _x / 16  (signed)
                    add.l      d2,d2                        ; D2 *= 2
                    sub.l      d2,a1                        ; A1 -= D2 bytes (cancel scroll)
                    move.l     a1,(bm_Planes+16,a2)         ; visible BitMap.Planes[4] = A1
                    ; --- vertical compensation: back the plane pointer up by _y rows worth ---
                    move.l     (_viewport),a0
                    move.l     (vp_RasInfo,a0),a2
                    move.l     (ri_BitMap,a2),a2
                    moveq      #0,d3
                    sub.l      (_y),d3                      ; D3 = -_y
                    move.l     (_wact_ras),a0
                    move.l     (rp_BitMap,a0),a0
                    move.l     d3,d2
                    mulu       (bm_BytesPerRow,a0),d3       ; D3 = -_y * BytesPerRow (low word)
                    swap       d2
                    mulu       (bm_BytesPerRow,a0),d2
                    swap       d2
                    clr.w      d2
                    add.l      d2,d3                        ; full 32-bit unsigned multiply
                    move.l     d3,d7
                    sub.l      d7,(bm_Planes+16,a2)         ; Plane[4] -= _y * BytesPerRow
                    ; --- apply Y gravity step ---
                    move.l     (_ay),d2
                    add.l      d2,(_vy)                     ; _vy += _ay (gravity)
                    ; --- commit display state to the system copperlist ---
;------------------------------------------------------------------------------
; DEVIATION #2 (see docs/DEVIATIONS.md) - KS2.0+ frame-rate fix.
; On graphics.library v36+ (Kickstart 2.0+) the MakeScreen+RethinkDisplay pair
; costs TWO vblank waits per frame (vs one on 1.x), so the demo advances one step
; per TWO fields instead of one - i.e. half rate on any system (~25 Hz PAL / 30
; Hz NTSC). This fix is rate-agnostic: it gates on the gfx lib_Version, not on
; PAL/NTSC, and restores "one step per video field" on both.
; MakeScreen is required on BOTH paths (it propagates this frame's RasInfo scroll
; + bitplane-pointer changes into the screen's copperlist - dropping it freezes
; the ball). The extra wait lives in RethinkDisplay's reconstruction, so on v36+
; we replace RethinkDisplay with its essentials - MrgCop + LoadView + ONE WaitTOF
; - giving a single per-frame vblank wait -> back to the field rate (50 Hz PAL /
; 60 Hz NTSC, matching 1.x on each).
; KS1.x (gfx v34) is UNCHANGED: it still runs MakeScreen then RethinkDisplay.
;------------------------------------------------------------------------------
                    move.l     (_myScreen),-(sp)
                    jsr        (_MakeScreen)                ;rebuild this screen's viewport copperlist (both paths)
                    move.l     (_GfxBase),a0
                    cmp.w      #36,(20,a0)                  ; graphics lib_Version (offset 20) >= 36 ? (KS2.0+)
                    bcc.b      .ks2_commit                  ; KS2.0+ -> light commit (single WaitTOF)
                    jsr        (_RethinkDisplay)            ;KS1.x: original full reconstruct (its own WaitTOF paces us)
                    bra.b      .commit_done
.ks2_commit         move.l     (_GfxBase),a0
                    move.l     (34,a0),-(sp)                ; view = GfxBase->ActiView (offset 34)
                    jsr        (_MrgCop)                    ; merge viewport copperlists into the system list
                    jsr        (_LoadView)                  ; install it (same view arg still on stack)
                    addq.l     #4,sp                        ; drop view arg
                    jsr        (_WaitTOF)                   ; exactly one vblank wait -> field-rate pacing
.commit_done
                    move.w     (_boing),d2
                    ext.l      d2
                    addq.l     #4,sp
                    exg        d2,a5
                    cmp.w      #1,a5
                    exg        d2,a5
                    blt.w      .frame_done
                    bgt.b      .cmp_boing_2
                    bra.b      .audio_floor

.cmp_boing_2               exg        d2,a5
                    cmp.w      #2,a5
                    exg        d2,a5
                    bne.b      .cmp_boing_3
                    bra.b      .audio_left

.cmp_boing_3               exg        d2,a5
                    cmp.w      #3,a5
                    exg        d2,a5
                    bne.w      .frame_done
                    bra.b      .audio_right

;------------------------------------------------------------------------------
; .audio_floor - audio dispatch for "bounced off floor" (_boing == 1).
;
; The "Boing" wrapper (in src/anim.s) takes (period, volume, balance):
;     period   - Paula period value, controls pitch
;     volume   - 0..64
;     balance  - signed; positive = right channel, negative = left
;
; For floor bounce we use _bperiod / _bvolume (deeper, louder) and a
; balance computed from the ball's X position:
;     balance = -_x * 128 + (-_x * 256) = -_x * 384
; i.e. the louder the ball is off-center, the louder on the opposite
; speaker. The sign of -_x mirrors the screen position to the speakers.
;------------------------------------------------------------------------------
.audio_floor                move.l     (a4),d3                      ; D3 = _x
                    neg.l      d3                           ; D3 = -_x
                    asl.l      #7,d3                        ; D3 *= 128
                    move.l     (a4),d2
                    neg.l      d2
                    asl.l      #8,d2                        ; D2 = -_x * 256
                    add.l      d2,d3                        ; D3 = -_x * 384  (balance)
                    move.l     d3,-(sp)                     ; arg 3: balance
                    move.w     (_bvolume),d2
                    ext.l      d2
                    move.l     d2,-(sp)                     ; arg 2: bottom-bounce volume
                    move.w     (_bperiod),d2
                    ext.l      d2
                    move.l     d2,-(sp)                     ; arg 1: bottom-bounce period
                    jsr        (_Boing)                     ; play the bottom-bounce sample
                    lea        (12,sp),sp
                    bra.b      .frame_done

;------------------------------------------------------------------------------
; .audio_left - audio dispatch for "bounced off left wall" (_boing == 2).
; Balance = $7530 = +30000 (mostly right channel; ball hit left wall so
; sound comes from the right).
;------------------------------------------------------------------------------
.audio_left                pea        ($7530).w                    ; balance = +30000 (pan right)
                    move.w     (_svolume),d3
                    ext.l      d3
                    move.l     d3,-(sp)                     ; side-bounce volume (quieter)
                    move.w     (_speriod),d2
                    ext.l      d2
                    move.l     d2,-(sp)                     ; side-bounce period (higher pitch)
                    jsr        (_Boing)
                    lea        (12,sp),sp
                    bra.b      .frame_done

;------------------------------------------------------------------------------
; .audio_right - audio dispatch for "bounced off right wall" (_boing == 3).
; Balance = $FFFF8AD0 = -30000 (mostly left channel; ball hit right wall).
;------------------------------------------------------------------------------
.audio_right                move.l     #$FFFF8AD0,-(sp)             ; balance = -30000 (pan left)
                    move.w     (_svolume),d3
                    ext.l      d3
                    move.l     d3,-(sp)                     ; side-bounce volume
                    move.w     (_speriod),d2
                    ext.l      d2
                    move.l     d2,-(sp)                     ; side-bounce period
                    jsr        (_Boing)
                    lea        (12,sp),sp

;------------------------------------------------------------------------------
; .frame_done - end of frame. Clear the "_boing" trigger flag, and if this was the
; very first frame, install the minimal-dot mouse pointer (deferred from
; Phase 6 so it doesn't flash during the lengthy init phase). Also set
; _sstep = 1 to enable animation on the next frame (the demo starts paused
; and unpauses itself after the first frame's setup completes).
;------------------------------------------------------------------------------
.frame_done                clr.w      (_boing)                     ; reset bounce-triggered flag
                    tst.w      (_firsttime)                 ; first frame?
                    beq.w      .mainloop                    ; no -> back to top of main loop
.first_frame_init                ; Original set _sstep=1 here ("unpause"), which actually froze the
                    ; demo (see the .nomsg note above), so it started paused until a
                    ; mouse click. We leave _sstep=0 so it keeps running automatically.
                    clr.w      (_firsttime)                 ; mark first-time done
                    ; SetPointer(Window, _DotPointer, height=1, width=$10, xOff=0, yOff=0)
                    clr.l      -(sp)                        ; yOffset = 0
                    clr.l      -(sp)                        ; xOffset = 0
                    pea        ($10).w                      ; width = 16
                    pea        (1).w                        ; height = 1
                    pea        (_DotPointer)                ; pointer image data (mostly transparent)
                    move.l     (_Window),-(sp)
                    jsr        (_SetPointer)
                    lea        ($0018,sp),sp
                    bra.w      .mainloop                    ; back to top of main loop


;==============================================================================
; Application globals. CHIP RAM because _mybitmap, _DotPointer, _fillpat, and
; _globe are all read by the custom chips (Denise/Agnus via DMA, Blitter via
; area-fill). Putting the rest of the section here too is harmless if a bit
; wasteful of chip-RAM bytes.
;
; Variable conventions used through this section:
;   _x, _vx, _ax   - X position, velocity, acceleration (signed long, integer)
;   _y, _vy, _ay   - Y position, velocity, acceleration (mixed int/FFP)
;   _fy            - Y position in FFP form (sub-integer precision for arc)
;   _dampy         - bounce-damping divisor
;   _y_lower       - integer Y offset applied to RyOffset
;   _bperiod/_bvolume  - audio period/volume for floor-bounce sound
;   _speriod/_svolume  - audio period/volume for wall-bounce sound
;   _bgptr[16]     - the 16 staggered background bitplane pointers (Phase 4)
;   _globe         - sphere vertex coordinate table (built by _init_globe)
;==============================================================================
                    SECTION    boing001DA0,DATA,CHIP
graphicslibra__MSG  dc.b       'graphics.library',0,0
intuitionlibr__MSG  dc.b       'intuition.library',0
mathffplibrar__MSG  dc.b       'mathffp.library',0
mathtranslibr__MSG  dc.b       'mathtrans.library',0
topaz__MSG          dc.b       'topaz',0                    ; default font name for NewScreen.Font
_wact_ras           dc.l       0                            ; cached &Screen->RastPort
_angoff             dc.l       0                            ; (FFP) sphere-rotation angle offset
_srad               dc.l       0                            ; (FFP) sphere radius
_yoff               dc.l       0                            ; (FFP) Y offset for sphere drawing
_sstep              dc.l       0                            ; run/pause flag (0 = paused)
_sstept             dc.l       0                            ; transient single-step flag (unused?)
_bytesneeded        dc.l       0                            ; scratch: bytes for AllocMem call
_bigbytesgot        dc.l       0                            ; size of _bigmem allocation
_cm                 dc.l       0                            ; cached &ViewPort.ColorMap
_ct                 dc.l       0                            ; cached &ColorMap.ColorTable (palette)
_firsttime          dc.w       0                            ; 1 until first frame completes
_myScreen           dc.l       0                            ; struct Screen *
_viewport           dc.l       0                            ; cached &Screen->ViewPort
_view               dc.l       0                            ; (unused?)
_bitmap             dc.l       0                            ; (unused at runtime; set at startup)
_mybitmap           dc.w       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  ; struct BitMap (40 bytes)
_Window             dc.l       0                            ; struct Window *
_arearas            dc.l       0                            ; scratch raster for AreaEnd / TmpRas
_DotPointer         dc.w       0,0,$8000,0,0,0              ; sprite data: 1 pixel "dot" cursor
_left               dc.l       0                            ; ball X bounce-left limit (-80)
_right              dc.l       0                            ; ball X bounce-right limit (+104)
_fillpat            dc.w       $FFFF,$8000,$8000,$8000,$8000,$8000,$8000,$8000,$8000,$8000,$8000
                    dc.w       $8000,$8000,$8000,$8000,$8000
_seed               dc.w       $B807,$C324,$9E87,$32B5,$E509,$57BC          ; PRNG seed (unused?)
_globe              dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.l       0,0,0,0,0,0,0
_bperiod            dc.w       255                          ; Paula period for floor-bounce sound (low pitch)
_bvolume            dc.w       63                           ; volume 63/64 - near-max for floor bounce
_speriod            dc.w       160                          ; Paula period for wall-bounce (higher pitch)
_svolume            dc.w       40                           ; volume 40/64 - quieter for wall bounce
_boing              dc.w       0                            ; per-frame trigger flag: 0=none, 1=floor, 2=left, 3=right
_pattern            dc.w       $AAAA,$5555                  ; alternative area-fill pattern (unused?)
_bgptr              dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  ; 16 staggered background plane pointers
_bckgnd             dc.l       0,0
_areavect           dc.w       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  ; AreaInfo vertex buffer (50 vtx)
                    dc.w       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.w       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.w       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
_x                  dc.l       0                            ; ball X position (signed; high word = pixels, low word = sub-pixel)
_y                  dc.w       0                            ; ball integer Y position (used to compute plane-pointer offset)
_y_lower            dc.w       0                            ; ball Y offset applied to RasInfo.RyOffset
_vx                 dc.l       0                            ; ball X velocity (integer; +1 = right, -1 = left)
_vy                 dc.l       0                            ; ball Y velocity (integer; used by FFP math via fflti)
_ax                 dc.l       0                            ; ball X acceleration (= 0, no air drag horizontally)
_ay                 dc.l       0                            ; ball Y acceleration (= 1 = gravity, downward)
_dampy              dc.l       0                            ; bounce-velocity damping divisor
_fy                 dc.l       0                            ; ball Y position in FFP (sub-integer precision)
_vb                 dc.w       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  ; vertical-blank-related scratch (unused?)
_icount             dc.l       0                            ; impact counter (unused after init?)
_GfxBase            dc.l       0                            ; graphics.library base
_IntuitionBase      dc.l       0                            ; intuition.library base
_MathBase           dc.l       0                            ; mathffp.library base
_MathTransBase      dc.l       0                            ; mathtrans.library base
_bigmem             dc.l       0                            ; chip-RAM allocation for bitplanes 1..4


