;==============================================================================
; src/runtime.s -- Lattice C runtime helpers and Amiga library glue stubs
;==============================================================================
; This file is NOT application code. Every routine here is part of the Lattice
; C runtime support library that the linker stitches in around the compiled
; C application. You can ignore this file when studying how Boing works,
; unless you specifically want to know how a particular library function is
; reached from the C-style _LVO wrapping.
;
; The contents organize into four functional groups:
;
;   Group 1 -- Integer math helpers
;   --------------------------------
;     _Cosine16 / _Sine16    16-bit integer sin/cos via lookup table.
;                            Operates on word arg from stack.
;     _strlen                Standard strlen.
;     POSDIV / LONGDIV       32-bit unsigned/signed long divide kernel.
;     ldivt / ulmult         Lattice-style longword divide / unsigned multiply.
;     ffixi / similar        FFP float -> integer conversion glue.
;
;   Group 2 -- dos.library wrappers (each loads _DOSBase into A6 then jsrs LVO)
;   ----------------------------------------------------------------
;     _Open, _Close, _Read, _Write, _Lock, _UnLock, _Examine, _Delay,
;     _Input, _Output, _CurrentDir, _DateStamp, _Exit, _IoErr, ...
;
;   Group 3 -- exec.library wrappers (each loads _SysBase into A6 then jsrs LVO)
;   ----------------------------------------------------------------
;     _Disable, _Enable, _Forbid, _Permit, _AllocMem, _FreeMem, _FindTask,
;     _Remove, _AddTail, _NewList, _AllocSignal, _FreeSignal, _CreatePort,
;     _DeletePort, _GetMsg, _ReplyMsg, _WaitPort, _Wait, _Signal, _Signal,
;     _OpenLibrary, _CloseLibrary, _OpenDevice, _CloseDevice, _DoIO, _SendIO,
;     _BeginIO, _WaitIO, _AbortIO, _CopyMem, ...
;
;   Group 4 -- graphics / intuition / math library wrappers
;   -------------------------------------------------------
;     _Text, _SetRast, _Move, _RectFill, _SetAPen, _SetBPen, _SetDrMd,
;     _SetRGB4, _InitArea, _InitBitMap, _AllocRaster, _FreeRaster,
;     _ScrollRaster, _BltClear, _WaitTOF, _WaitBlit, ... (graphics.library)
;
;     _OpenScreen, _CloseScreen, _OpenWindow, _CloseWindow, _SetPointer,
;     _ClearPointer, _DisplayBeep, _MakeScreen, _RethinkDisplay,
;     _ScreenToBack, ... (intuition.library)
;
;     _SPSin, _SPCos, _SPAdd, _SPSub, _SPMul, _SPDiv, _SPFlt, _SPFix,
;     _SPNeg, _SPAbs, _SPTst, _SPCmp, jmp_so, jmp_do, ...
;     (mathffp.library + mathtrans.library)
;
; Each wrapper has the same shape:
;     move.l   a6,-(sp)
;     move.l   (_LibraryBase),a6
;     ; load arguments from stack into the D0/D1/A0/A1 registers the LVO expects
;     jsr      (_LVOSomething,a6)
;     move.l   (sp)+,a6
;     rts
;
; That is the standard C-callable Amiga library stub pattern.
;
; See AMIGA-KNOWHOW.md section G.1 (Exec library calling convention) for the
; underlying convention these stubs implement.
;
; Original line range in monolithic boing.s: 2322..3097.
; The file ends with the `end` directive.
;==============================================================================

;==============================================================================
; _Sine16(angle) / _Cosine16(angle) - integer sine/cosine via 65-entry
; lookup table (Sine6).
;
; Calling convention: angle is a 16-bit value passed in (6,sp). Returns
; a 16-bit signed result in D0 where 0x7FFF = +1.0 and 0x8001 = -1.0.
; The angle space wraps every 65536 (= 2*pi).
;
; _Cosine16 just adds $4000 (= pi/2) to the angle and falls through to
; _Sine16 - the identity cos(x) = sin(x + pi/2).
;
; Used by _init_globe to compute sphere vertices (the slow path, since
; this is integer trig, not FFP - cheaper but less precise).
;==============================================================================
                    SECTION    boing0037DC,CODE
_Cosine16           add.w      #$4000,(6,sp)                ; cos(x) = sin(x + pi/2)
_Sine16             move.w     (6,sp),d0
                    bge.b      Sine3
                    cmp.w      #$C000,d0
                    bge.b      Sine1
                    add.w      #$8000,d0
                    bra.b      Sine2

Sine1               neg.w      d0
Sine2               bsr.b      Sine4
                    neg.w      d0
                    rts

Sine3               cmp.w      #$4000,d0
                    blt.b      Sine4
                    neg.l      d0
                    add.w      #$8000,d0
Sine4               move.w     d0,d1
                    lsr.w      #7,d0
                    and.w      #$FFFE,d0
                    lea        (Sine6,pc,d0.w),a0
                    move.w     (a0)+,d0
                    and.w      #$00FF,d1
                    beq.b      Sine5
                    move.w     d0,-(sp)
                    move.w     (a0),d0
                    sub.w      (sp),d0
                    mulu       d1,d0
                    lsr.l      #8,d0
                    add.w      (sp)+,d0
Sine5               rts

Sine6               dc.w       0,$0324,$0648,$096B,$0C8C,$0FAB,$12C8,$15E2,$18F9,$1C0C,$1F1A,$2224
                    dc.w       $2528,$2827,$2B1F,$2E11,$30FC,$33DF,$36BA,$398D,$3C57,$3F17,$41CE
                    dc.w       $447B,$471D,$49B4,$4C40,$4EC0,$5134,$539B,$55F6,$5843,$5A82,$5CB4
                    dc.w       $5ED7,$60EC,$62F2,$64E9,$66D0,$68A7,$6A6E,$6C24,$6DCA,$6F5F,$70E3
                    dc.w       $7255,$73B6,$7505,$7642,$776C,$7885,$798A,$7A7D,$7B5D,$7C2A,$7CE4
                    dc.w       $7D8A,$7E1E,$7E9D,$7F0A,$7F62,$7FA7,$7FD9,$7FF6,$7FFF


;==============================================================================
; _strlen(s) - standard C strlen. Counts bytes until first NUL.
;==============================================================================
                    SECTION    boing0038AC,CODE
_strlen             move.l     (4,sp),a0
                    moveq      #0,d0
lbC0038B2           tst.b      (a0)+
                    beq.b      lbC0038BA
                    addq.l     #1,d0
                    bra.b      lbC0038B2

lbC0038BA           rts

                    movem.l    d2/d3,-(sp)
                    move.l     (12,sp),d3
                    move.l     ($0010,sp),d2
                    move.l     d2,-(sp)
                    jsr        (_strlen,pc)
                    addq.l     #4,sp
                    move.l     d0,-(sp)
                    move.l     d2,-(sp)
                    move.l     d3,-(sp)
                    jsr        (_Text)
                    lea        (12,sp),sp
                    movem.l    (sp)+,d2/d3
                    rts

                    dc.w       0


;==============================================================================
; POSDIV / LONGDIV / ldivt / ulmodt / ulmult - 32-bit integer math helpers.
;
; The 68000 has no native 32-bit divide or signed-32-bit multiply, only
; 16/16 -> 32 (mulu/muls) and 32/16 -> 16-rem-16 (divu/divs). For full
; 32-bit math, Lattice C emits calls to these helpers:
;   POSDIV / LONGDIV   - unsigned long divide using shift-subtract
;   ldivt              - signed long divide (entry point)
;   lmodt              - signed long modulo
;   ulmodt             - unsigned long modulo
;   ulmult             - unsigned long multiply (32x32 -> low 32)
;
; Used heavily by _init_globe / _draw_globe for the sphere coordinate math.
;==============================================================================
                    SECTION    boing0038E8,CODE
POSDIV              cmp.l      #$0000FFFF,d2
                    bgt.b      LONGDIV
                    move.w     d1,a1
                    clr.w      d1
                    swap       d1
                    divu       d2,d1
                    move.l     d1,d0
                    swap       d1
                    move.w     a1,d0
                    divu       d2,d0
                    move.w     d0,d1
                    clr.w      d0
                    swap       d0
                    rts

LONGDIV             move.l     d1,d0
                    clr.w      d0
                    swap       d0
                    swap       d1
                    clr.w      d1
                    move.l     d2,a1
                    moveq      #15,d2
LABEL1              add.l      d1,d1
                    addx.l     d0,d0
                    cmp.l      d0,a1
                    bgt.b      LDEX
                    sub.l      a1,d0
                    addq.w     #1,d1
LDEX                dbra       d2,LABEL1
                    rts

ulmult              move.l     d2,-(sp)
                    move.l     d0,d2
                    mulu       d1,d2
                    move.l     d2,a0
                    move.l     d0,d2
                    swap       d2
                    mulu       d1,d2
                    swap       d1
                    mulu       d1,d0
                    add.l      d2,d0
                    swap       d0
                    clr.w      d0
                    add.l      d0,a0
                    move.l     a0,d0
                    move.l     (sp)+,d2
                    rts

ulmodt              move.l     d2,-(sp)
                    move.l     d1,d2
                    move.l     d0,d1
                    bsr.b      POSDIV
                    move.l     (sp)+,d2
                    rts

uldivt              move.l     d2,-(sp)
                    move.l     d1,d2
                    move.l     d0,d1
                    bsr.b      POSDIV
                    move.l     d1,d0
                    move.l     (sp)+,d2
                    rts

lmodt               move.l     d2,-(sp)
                    move.l     d1,d2
                    bge.b      lrem1
                    neg.l      d2
lrem1               move.l     d0,d1
                    moveq      #0,d0
                    tst.l      d1
                    bge.b      lrem2
                    neg.l      d1
                    not.l      d0
lrem2               move.l     d0,a0
                    bsr.w      POSDIV
                    move.w     a0,d2
                    beq.b      lremDONE
                    neg.l      d0
lremDONE            move.l     (sp)+,d2
                    rts

ldivt               move.l     d2,-(sp)
                    move.l     d0,a0
                    moveq      #0,d0
                    move.l     d1,d2
                    bge.b      ldiv1
                    neg.l      d2
                    not.l      d0
ldiv1               move.l     a0,d1
                    bge.b      ldiv2
                    neg.l      d1
                    not.l      d0
ldiv2               move.l     d0,a0
                    bsr.w      POSDIV
                    move.l     a0,d2
                    beq.b      ldivRET
                    neg.l      d1
ldivRET             move.l     d1,d0
                    move.l     (sp)+,d2
                    rts

                    dc.w       0


;==============================================================================
; dos.library wrappers. Each is a thin trampoline:
;   1. Save A6 on stack.
;   2. Load (_DOSBase) into A6.
;   3. Load arguments from stack into the D0/D1/D2/D3/A0/A1 slots the LVO
;      expects (per the .fd convention - see AMIGA-KNOWHOW.md G.1).
;   4. jsr (_LVOFunction, a6).
;   5. Restore A6, return.
;
; See AMIGA-KNOWHOW.md section H.5 for the LVO list.
;==============================================================================
                    SECTION    boing0039B0,CODE
_Open               movem.l    d2/a6,-(sp)
                    move.l     (_DOSBase),a6
                    movem.l    (12,sp),d1/d2
                    jsr        (_LVOOpen,a6)
                    movem.l    (sp)+,d2/a6
                    rts

                    dc.w       0

_Close              move.l     a6,-(sp)
                    move.l     (_DOSBase),a6
                    move.l     (8,sp),d1
                    jsr        (_LVOClose,a6)
                    move.l     (sp)+,a6
                    rts

_Read               movem.l    d2/d3/a6,-(sp)
                    move.l     (_DOSBase),a6
                    movem.l    ($0010,sp),d1-d3
                    jsr        (_LVORead,a6)
                    movem.l    (sp)+,d2/d3/a6
                    rts

                    dc.w       0

_Input              move.l     a6,-(sp)
                    move.l     (_DOSBase),a6
                    jsr        (_LVOInput,a6)
                    move.l     (sp)+,a6
                    rts

_Output             move.l     a6,-(sp)
                    move.l     (_DOSBase),a6
                    jsr        (_LVOOutput,a6)
                    move.l     (sp)+,a6
                    rts

_Lock               movem.l    d2/a6,-(sp)
                    move.l     (_DOSBase),a6
                    movem.l    (12,sp),d1/d2
                    jsr        (_LVOLock,a6)
                    movem.l    (sp)+,d2/a6
                    rts

                    dc.w       0

_UnLock             move.l     a6,-(sp)
                    move.l     (_DOSBase),a6
                    move.l     (8,sp),d1
                    jsr        (_LVOUnLock,a6)
                    move.l     (sp)+,a6
                    rts

_Examine            movem.l    d2/a6,-(sp)
                    move.l     (_DOSBase),a6
                    movem.l    (12,sp),d1/d2
                    jsr        (_LVOExamine,a6)
                    movem.l    (sp)+,d2/a6
                    rts

                    dc.w       0


;==============================================================================
; exec.library wrappers. Same trampoline pattern as the dos.library set,
; just loading _SysBase instead of _DOSBase.
;
; See AMIGA-KNOWHOW.md section G.2 for the LVO list.
;==============================================================================
                    SECTION    boing003A68,CODE
_Disable            move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    jsr        (_LVODisable,a6)
                    move.l     (sp)+,a6
                    rts

_Enable             move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    jsr        (_LVOEnable,a6)
                    move.l     (sp)+,a6
                    rts

_AllocMem           move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    movem.l    (8,sp),d0/d1
                    jsr        (_LVOAllocMem,a6)
                    move.l     (sp)+,a6
                    rts

                    dc.w       0

_FreeMem            move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    move.l     (8,sp),a1
                    move.l     (12,sp),d0
                    jsr        (_LVOFreeMem,a6)
                    move.l     (sp)+,a6
                    rts

_AddTail            move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    movem.l    (8,sp),a0/a1
                    jsr        (_LVOAddTail,a6)
                    move.l     (sp)+,a6
                    rts

                    dc.w       0

_Remove             move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    move.l     (8,sp),a1
                    jsr        (_LVORemove,a6)
                    move.l     (sp)+,a6
                    rts

_FindTask           move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    move.l     (8,sp),a1
                    jsr        (_LVOFindTask,a6)
                    move.l     (sp)+,a6
                    rts

_AllocSignal        move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    move.l     (8,sp),d0
                    jsr        (_LVOAllocSignal,a6)
                    move.l     (sp)+,a6
                    rts

_FreeSignal         move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    move.l     (8,sp),d0
                    jsr        (_LVOFreeSignal,a6)
                    move.l     (sp)+,a6
                    rts

_AddPort            move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    move.l     (8,sp),a1
                    jsr        (_LVOAddPort,a6)
                    move.l     (sp)+,a6
                    rts

_RemPort            move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    move.l     (8,sp),a1
                    jsr        (_LVORemPort,a6)
                    move.l     (sp)+,a6
                    rts

_GetMsg             move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    move.l     (8,sp),a0
                    jsr        (_LVOGetMsg,a6)
                    move.l     (sp)+,a6
                    rts

_ReplyMsg           move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    move.l     (8,sp),a1
                    jsr        (_LVOReplyMsg,a6)
                    move.l     (sp)+,a6
                    rts

_OpenDevice         move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    move.l     (8,sp),a0
                    movem.l    (12,sp),d0/a1
                    move.l     ($0014,sp),d1
                    jsr        (_LVOOpenDevice,a6)
                    move.l     (sp)+,a6
                    rts

                    dc.w       0

_CloseDevice        move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    move.l     (8,sp),a1
                    jsr        (_LVOCloseDevice,a6)
                    move.l     (sp)+,a6
                    rts

_DoIO               move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    move.l     (8,sp),a1
                    jsr        (_LVODoIO,a6)
                    move.l     (sp)+,a6
                    rts

_WaitIO             move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    move.l     (8,sp),a1
                    jsr        (_LVOWaitIO,a6)
                    move.l     (sp)+,a6
                    rts

_OpenLibrary        move.l     a6,-(sp)
                    move.l     (_SysBase),a6
                    move.l     (8,sp),a1
                    move.l     (12,sp),d0
                    jsr        (_LVOOpenLibrary,a6)
                    move.l     (sp)+,a6
                    rts


;==============================================================================
; _BeginIO - the one Exec call that does NOT route through _SysBase. It
; dispatches directly to the IORequest's owning device:
;     ((IORequest *)a1)->io_Device->dev_BeginIO(a1)
; This is the standard "device function vector" pattern.
;==============================================================================
                    SECTION    boing003BE4,CODE
_BeginIO            move.l     (4,sp),a1
                    move.l     a6,-(sp)
                    move.l     (IO_DEVICE,a1),a6
                    jsr        (DEV_BEGINIO,a6)
                    move.l     (sp)+,a6
                    rts

                    dc.w       0


;==============================================================================
; _NewList(list) - initialize an Exec list as empty.
; Standard Exec idiom:
;     list->lh_Head     = (Node *)&list->lh_Tail;
;     list->lh_Tail     = NULL;
;     list->lh_TailPred = (Node *)&list->lh_Head;
; The "tail predecessor points back to head" makes the empty-list check
; "head->ln_Succ == NULL || head == &lh_Tail" - the way _Boing checks
; the audio reply port for empty before Remove.
;==============================================================================
                    SECTION    boing003BF8,CODE
_NewList            move.l     (4,sp),a0
                    move.l     a0,(a0)                      ; lh_Head = &lh_Tail
                    addq.l     #4,(a0)
                    clr.l      (4,a0)                       ; lh_Tail = NULL
                    move.l     a0,(8,a0)                    ; lh_TailPred = &lh_Head
                    rts

                    dc.w       0


;==============================================================================
; _CreatePort(name, priority) - allocate a signal bit, allocate and init
; a MsgPort with that signal as its trigger, return the port. The
; full C implementation Exec doesn't provide - this is the standard
; Lattice C version. See exec/ports.h for the struct MsgPort layout.
;==============================================================================
                    SECTION    boing003C0C,CODE
_CreatePort         movem.l    d2-d7/a2,-(sp)
.L11                move.l     ($0020,sp),d4
                    move.b     ($0027,sp),d3
.L9                 move.l     #$FFFFFFFF,-(sp)
                    jsr        (_AllocSignal)
                    move.l     d0,d2
                    move.b     d2,d6
                    move.b     d6,d5
                    moveq      #0,d2
                    move.b     d6,d2
                    cmp.l      #$FFFFFFFF,d2
                    addq.l     #4,sp
                    bne.b      .L8
.L2                 moveq      #0,d0
                    bra.w      .L1

.L8                 move.l     #(MEMF_PUBLIC|MEMF_CLEAR),-(sp)
                    pea        (MP_SIZE).w
                    jsr        (_AllocMem)
                    move.l     d0,a2
                    exg        d7,a2
                    tst.l      d7
                    exg        d7,a2
                    addq.l     #8,sp
                    bne.b      .L7
.L3                 moveq      #0,d2
                    move.b     d5,d2
                    move.l     d2,-(sp)
                    jsr        (_FreeSignal)
                    moveq      #0,d0
                    addq.l     #4,sp
                    bra.b      .L1

.L7                 move.l     d4,(LN_NAME,a2)
                    move.b     d3,(LN_PRI,a2)
                    move.b     #NT_MSGPORT,(LN_TYPE,a2)
                    clr.b      (MP_FLAGS,a2)
                    move.b     d5,(MP_SIGBIT,a2)
                    clr.l      -(sp)
                    jsr        (_FindTask)
                    move.l     d0,(MP_SIGTASK,a2)
                    tst.l      d4
                    addq.l     #4,sp
                    beq.b      .L6
.L5                 move.l     a2,-(sp)                                                                 ;BUG: does AddPort before msglist is initialized!
                    jsr        (_AddPort)
                    addq.l     #4,sp
                    bra.b      .L4

.L6                 pea        (MP_MSGLIST,a2)
                    jsr        (_NewList)
                    addq.l     #4,sp
.L4                 move.l     a2,d0
.L1                 movem.l    (sp)+,d2-d7/a2
                    rts

_DeletePort         movem.l    d2/a2,-(sp)
.L17                move.l     (12,sp),a2
.L15                tst.l      (10,a2)
                    beq.b      .L13
.L14                move.l     a2,-(sp)
                    jsr        (_RemPort)
                    addq.l     #4,sp
.L13                move.b     #$FF,(LN_TYPE,a2)
                    moveq      #-1,d2
                    move.l     d2,(MP_MSGLIST,a2)
                    moveq      #0,d2
                    move.b     (MP_SIGBIT,a2),d2
                    move.l     d2,-(sp)
                    jsr        (_FreeSignal)
                    pea        (MP_SIZE).w
                    move.l     a2,-(sp)
                    jsr        (_FreeMem)
                    lea        (12,sp),sp
.L12                movem.l    (sp)+,d2/a2
                    rts


;==============================================================================
; graphics.library wrappers. Same trampoline pattern, loading _GfxBase.
; See AMIGA-KNOWHOW.md section J for the LVO list. Most heavily exercised
; functions in this demo: _Move, _Draw, _RectFill, _SetAPen, _SetBPen,
; _SetDrMd, _SetRGB4, _LoadRGB4, _BltClear, _AllocRaster, _FreeRaster,
; _InitArea, _InitBitMap, _InitTmpRas, _AreaMove, _AreaDraw, _AreaEnd,
; _SetRast, _WaitTOF.
;==============================================================================
                    SECTION    boing003CFC,CODE
_Text               move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (8,sp),a1
                    move.l     (12,sp),a0
                    move.l     ($0010,sp),d0
                    jsr        (_LVOText,a6)
                    move.l     (sp)+,a6
                    rts

_SetRast            move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (8,sp),a1
                    move.l     (12,sp),d0
                    jsr        (_LVOSetRast,a6)
                    move.l     (sp)+,a6
                    rts

_Move               move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (8,sp),a1
                    movem.l    (12,sp),d0/d1
                    jsr        (_LVOMove,a6)
                    move.l     (sp)+,a6
                    rts

                    dc.w       0

_Draw               move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (8,sp),a1
                    movem.l    (12,sp),d0/d1
                    jsr        (_LVODraw,a6)
                    move.l     (sp)+,a6
                    rts

                    dc.w       0

_AreaMove           move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (8,sp),a1
                    movem.l    (12,sp),d0/d1
                    jsr        (_LVOAreaMove,a6)
                    move.l     (sp)+,a6
                    rts

                    dc.w       0

_AreaDraw           move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (8,sp),a1
                    movem.l    (12,sp),d0/d1
                    jsr        (_LVOAreaDraw,a6)
                    move.l     (sp)+,a6
                    rts

                    dc.w       0

_AreaEnd            move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (8,sp),a1
                    jsr        (_LVOAreaEnd,a6)
                    move.l     (sp)+,a6
                    rts

_WaitTOF            move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    jsr        (_LVOWaitTOF,a6)
                    move.l     (sp)+,a6
                    rts

; _MrgCop(view) / _LoadView(view) - added for DEVIATION #2 (KS2.0+ frame-rate
; fix in main.s). They let the v36+ path commit a frame with a single WaitTOF
; instead of RethinkDisplay's two. graphics.library, view passed in a1.
_MrgCop             move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (8,sp),a1
                    jsr        (_LVOMrgCop,a6)
                    move.l     (sp)+,a6
                    rts

_LoadView           move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (8,sp),a1
                    jsr        (_LVOLoadView,a6)
                    move.l     (sp)+,a6
                    rts

_InitArea           move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    movem.l    (8,sp),a0/a1
                    move.l     ($0010,sp),d0
                    jsr        (_LVOInitArea,a6)
                    move.l     (sp)+,a6
                    rts

                    dc.w       0

_SetRGB4            movem.l    d2/d3/a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     ($0010,sp),a0
                    movem.l    ($0014,sp),d0-d3
                    jsr        (_LVOSetRGB4,a6)
                    movem.l    (sp)+,d2/d3/a6
                    rts

                    dc.w       0

_BltClear           move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (8,sp),a1
                    movem.l    (12,sp),d0/d1
                    jsr        (_LVOBltClear,a6)
                    move.l     (sp)+,a6
                    rts

                    dc.w       0

_RectFill           movem.l    d2/d3/a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     ($0010,sp),a1
                    movem.l    ($0014,sp),d0-d3
                    jsr        (_LVORectFill,a6)
                    movem.l    (sp)+,d2/d3/a6
                    rts

                    dc.w       0

_SetAPen            move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (8,sp),a1
                    move.l     (12,sp),d0
                    jsr        (_LVOSetAPen,a6)
                    move.l     (sp)+,a6
                    rts

_SetBPen            move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (8,sp),a1
                    move.l     (12,sp),d0
                    jsr        (_LVOSetBPen,a6)
                    move.l     (sp)+,a6
                    rts

_SetDrMd            move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (8,sp),a1
                    move.l     (12,sp),d0
                    jsr        (_LVOSetDrMd,a6)
                    move.l     (sp)+,a6
                    rts

_InitBitMap         movem.l    d2/a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (12,sp),a0
                    movem.l    ($0010,sp),d0-d2
                    jsr        (_LVOInitBitMap,a6)
                    movem.l    (sp)+,d2/a6
                    rts

                    dc.w       0

_InitTmpRas         move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    movem.l    (8,sp),a0/a1
                    move.l     ($0010,sp),d0
                    jsr        (_LVOInitTmpRas,a6)
                    move.l     (sp)+,a6
                    rts

                    dc.w       0

_AllocRaster        move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    movem.l    (8,sp),d0/d1
                    jsr        (_LVOAllocRaster,a6)
                    move.l     (sp)+,a6
                    rts

                    dc.w       0

_FreeRaster         move.l     a6,-(sp)
                    move.l     (_GfxBase),a6
                    move.l     (8,sp),a0
                    movem.l    (12,sp),d0/d1
                    jsr        (_LVOFreeRaster,a6)
                    move.l     (sp)+,a6
                    rts

                    dc.w       0


;==============================================================================
; intuition.library wrappers. Same trampoline pattern, loading
; _IntuitionBase. See AMIGA-KNOWHOW.md section I for the LVO list. Used by
; this demo for: _OpenScreen, _CloseScreen, _OpenWindow, _CloseWindow,
; _SetPointer, _ClearPointer, _ScreenToBack, _MakeScreen, _RethinkDisplay.
;==============================================================================
                    SECTION    boing003EF4,CODE
_ClearPointer       move.l     a6,-(sp)
                    move.l     (_IntuitionBase),a6
                    move.l     (8,sp),a0
                    jsr        (_LVOClearPointer,a6)
                    move.l     (sp)+,a6
                    rts

_CloseScreen        move.l     a6,-(sp)
                    move.l     (_IntuitionBase),a6
                    move.l     (8,sp),a0
                    jsr        (_LVOCloseScreen,a6)
                    move.l     (sp)+,a6
                    rts

_CloseWindow        move.l     a6,-(sp)
                    move.l     (_IntuitionBase),a6
                    move.l     (8,sp),a0
                    jsr        (_LVOCloseWindow,a6)
                    move.l     (sp)+,a6
                    rts

_OpenScreen         move.l     a6,-(sp)
                    move.l     (_IntuitionBase),a6
                    move.l     (8,sp),a0
                    jsr        (_LVOOpenScreen,a6)
                    move.l     (sp)+,a6
                    rts

_OpenWindow         move.l     a6,-(sp)
                    move.l     (_IntuitionBase),a6
                    move.l     (8,sp),a0
                    jsr        (_LVOOpenWindow,a6)
                    move.l     (sp)+,a6
                    rts

_ScreenToBack       move.l     a6,-(sp)
                    move.l     (_IntuitionBase),a6
                    move.l     (8,sp),a0
                    jsr        (_LVOScreenToBack,a6)
                    move.l     (sp)+,a6
                    rts

_SetPointer         movem.l    d2/d3/a6,-(sp)
                    move.l     (_IntuitionBase),a6
                    movem.l    ($0010,sp),a0/a1
                    movem.l    ($0018,sp),d0-d3
                    jsr        (_LVOSetPointer,a6)
                    movem.l    (sp)+,d2/d3/a6
                    rts

_MakeScreen         move.l     a6,-(sp)
                    move.l     (_IntuitionBase),a6
                    move.l     (8,sp),a0
                    jsr        (_LVOMakeScreen,a6)
                    move.l     (sp)+,a6
                    rts

_RethinkDisplay     move.l     a6,-(sp)
                    move.l     (_IntuitionBase),a6
                    jsr        (_LVORethinkDisplay,a6)
                    move.l     (sp)+,a6
                    rts


;==============================================================================
; mathffp.library + mathtrans.library wrappers, plus the dispatcher
; trampolines (jmp_so / jmp_do) that route the FFP calls.
;
; jmp_so = "jump single-operand": A0 has the LVO offset, _MathBase is added
;          to get the absolute function address, then jsr.
; jmp_do = "jump dual-operand": same but for two-operand FFP calls. The
;          second operand is fetched from $18(sp) and put in D1 before jsr.
;
; The ffixi / faddi / fsubi / fmuli / fdivi / fcmpi / fnegi / fflti entry
; points pre-load A0 with the appropriate LVO and call jmp_so / jmp_do.
;
; See AMIGA-KNOWHOW.md section K for the FFP format and call convention.
;==============================================================================
                    SECTION    boing003FB0,CODE
jmp_so              movem.l    d3-d7,-(sp)                  ; FFP scratch regs
                    add.l      (_MathBase),a0
                    jsr        (a0)
                    movem.l    (sp)+,d3-d7
                    rts

jmp_do              movem.l    d3-d7,-(sp)
                    add.l      (_MathBase),a0
                    move.l     ($0018,sp),d1                ; D1 = second operand
                    jsr        (a0)
                    movem.l    (sp)+,d3-d7/a0
                    lea        (8,sp),sp
                    jmp        (a0)

ffixi               lea        (_LVOSPFix),a0               ; FFP -> integer (truncate)
                    bra.b      jmp_so

fflti               lea        (_LVOSPFlt),a0
                    bra.b      jmp_so

fcmpi               lea        (_LVOSPCmp),a0
                    bra.b      jmp_do

ftsti               lea        (_LVOSPTst),a0
                    bra.b      jmp_do

_abs                move.l     (4,sp),d0
fabsi               lea        (_LVOSPAbs),a0
                    bra.b      jmp_so

fnegi               lea        (_LVOSPNeg),a0
                    bra.b      jmp_so

faddi               lea        (_LVOSPAdd),a0
                    bra.b      jmp_do

fsubi               lea        (_LVOSPSub),a0
                    bra.b      jmp_do

fmuli               lea        (_LVOSPMul),a0
                    bra.b      jmp_do

fdivi               lea        (_LVOSPDiv),a0
                    bra.b      jmp_do


;==============================================================================
; mathtrans.library wrappers - only SPSin and SPCos are referenced by the
; application (both used in _draw_globe for sphere geometry). Same
; trampoline pattern, loading _MathTransBase.
;==============================================================================
                    SECTION    boing004030,CODE
_SPSin              move.l     a6,-(sp)
                    move.l     (_MathTransBase),a6
                    move.l     (8,sp),d0
                    jsr        (_LVOSPSin,a6)
                    move.l     (sp)+,a6
                    rts

_SPCos              move.l     a6,-(sp)
                    move.l     (_MathTransBase),a6
                    move.l     (8,sp),d0
                    jsr        (_LVOSPCos,a6)
                    move.l     (sp)+,a6
                    rts

