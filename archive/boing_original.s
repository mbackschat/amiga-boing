                    INCDIR     "include"
                    INCLUDE    "exec/types.i"
                    INCLUDE    "exec/exec.i"
                    INCLUDE    "exec/exec_lib.i"
                    INCLUDE    "graphics/graphics_lib.i"
                    INCLUDE    "hardware/custom.i"
                    INCLUDE    "libraries/dos.i"
                    INCLUDE    "intuition/intuition.i"
                    INCLUDE    "intuition/intuition_lib.i"
                    INCLUDE    "math/mathffp_lib.i"
                    INCLUDE    "math/mathtrans_lib.i"
                    INCLUDE    "libraries/dosextens.i"
                    INCLUDE    "libraries/dos_lib.i"
                    INCLUDE    "exec/alerts.i"
                    INCLUDE    "devices/audio.i"
                    INCLUDE    "hardware/dmabits.i"
                    INCLUDE    "exec/io.i"

custom = $dff000

                    move.l     sp,(initialSP)
                    move.l     d0,(dosCmdLen)
                    move.l     a0,(dosCmdBuf)
                    clr.l      (returnMsg)
                    move.l     (4),a6
                    move.l     a6,(_SysBase)
                    sub.l      a1,a1
                    jsr        (_LVOFindTask,a6)
                    move.l     d0,a4
                    tst.l      (pr_CLI,a4)
                    beq.w      fromWorkbench
fromCLI             bsr.w      openDOS
                    move.l     (pr_CLI,a4),a0
                    add.l      a0,a0
                    add.l      a0,a0
                    move.l     (cli_CommandName,a0),a0
                    add.l      a0,a0
                    add.l      a0,a0
                    movem.l    d2/a2/a3,-(sp)
                    lea        (argvBuffer),a2
                    lea        (argvArray),a3
                    moveq      #1,d2
                    moveq      #0,d0
                    move.b     (a0)+,d0
                    move.l     a2,(a3)+
                    bra.b      1$

2$                  move.b     (a0)+,(a2)+
1$                  dbra       d0,2$
                    clr.b      (a2)+
                    move.l     (dosCmdLen),d0
                    move.l     (dosCmdBuf),a0
3$                  move.b     (a0)+,d1
                    subq.l     #1,d0
                    ble.b      parmExit
                    cmp.b      #$20,d1
                    ble.b      3$
                    addq.l     #1,d2
                    move.l     a2,(a3)+
                    bra.b      5$

4$                  move.b     (a0)+,d1
                    subq.l     #1,d0
                    cmp.b      #$20,d1
                    ble.b      6$
5$                  move.b     d1,(a2)+
                    bra.b      4$

6$                  clr.b      (a2)+
                    bra.b      3$

parmExit            clr.b      (a2)+
                    clr.l      (a3)+
                    move.l     d2,d0
                    movem.l    (sp)+,d2/a2/a3
                    pea        (argvArray)
                    move.l     d0,-(sp)
                    jsr        (_Input)
                    move.l     d0,(_stdin)
                    jsr        (_Output)
                    move.l     d0,(_stdout)
                    move.l     d0,(_stderr)
                    jsr        (_main)
                    moveq      #0,d0
                    move.l     (initialSP),sp
                    rts

fromWorkbench       bsr.w      openDOS
                    bsr.w      waitmsg
                    move.l     d0,(returnMsg)
                    clr.l      -(sp)
                    move.l     d0,-(sp)
                    move.l     d0,a2
                    move.l     ($0024,a2),d0
                    beq.b      docons
                    move.l     (_DOSBase),a6
                    move.l     d0,a0
                    move.l     (0,a0),d1
                    jsr        (_LVOCurrentDir,a6)
docons              move.l     ($0020,a2),d1
                    beq.b      domain
                    move.l     #MODE_OLDFILE,d2
                    jsr        (_LVOOpen,a6)
                    move.l     d0,(_stdin)
                    move.l     d0,(_stdout)
                    move.l     d0,(_stderr)
                    beq.b      domain
                    lsl.l      #2,d0
                    move.l     d0,a0
                    move.l     (fh_Type,a0),(pr_ConsoleTask,a4)
domain              jsr        (_main)
                    moveq      #0,d0
                    bra.b      exit2

_exit               move.l     (4,sp),d0
exit2               move.l     (initialSP),sp
                    move.l     d0,-(sp)
                    move.l     (4),a6
                    move.l     (_DOSBase),d0
                    beq.b      1$
                    move.l     d0,a1
1$                  jsr        (_LVOCloseLibrary,a6)
                    tst.l      (returnMsg)
                    beq.b      exitToDOS
                    jsr        (_LVOForbid,a6)
                    move.l     (returnMsg),a1
                    jsr        (_LVOReplyMsg,a6)
exitToDOS           move.l     (sp)+,d0
                    rts

noDOS               movem.l    d7/a5/a6,-(sp)
                    move.l     #(AT_Recovery|AG_OpenLib|AO_DOSLib),d7
                    move.l     (4).w,a6
                    jsr        (_LVOAlert,a6)
                    movem.l    (sp)+,d7/a5/a6
                    moveq      #100,d0
                    bra.b      exit2

waitmsg             lea        (pr_MsgPort,a4),a0
                    jsr        (_LVOWaitPort,a6)
                    lea        (pr_MsgPort,a4),a0
                    jsr        (_LVOGetMsg,a6)
                    rts

openDOS             clr.l      (_DOSBase)
                    lea        (DOSName),a1
                    move.l     #30,d0
                    jsr        (_LVOOpenLibrary,a6)
                    move.l     d0,(_DOSBase)
                    beq.b      noDOS
                    rts

                    dc.w       0

                    SECTION    boing0001C4,DATA
VerRev              dc.w       1
                    dc.w       0
_SysBase            dc.l       0
_DOSBase            dc.l       0
_errno              dc.l       0
_stdin              dc.l       0
_stdout             dc.l       0
_stderr             dc.l       0
initialSP           dc.l       0
returnMsg           dc.l       0
dosCmdLen           dc.l       0
dosCmdBuf           dc.l       0
argvArray           dc.b       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.b       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.b       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.b       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
argvBuffer          dc.b       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.b       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.b       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.b       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.b       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.b       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.b       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.b       0,0,0,0,0,0,0,0,0,0,0
DOSName             dc.b       'dos.library',0


                    SECTION    boing00037C,CODE
_Boing              link       a6,#-6
                    movem.l    d2-d6/a2-a5,-(sp)
.L31                move.w     (10,a6),d6
                    move.b     (15,a6),d5
                    move.w     ($0012,a6),d4
                    move.l     #_allocReq,a2
                    move.l     #_DoIO,a4
                    move.l     #_extraSamples,(-4,a6)
.L29                tst.b      (_sound)
                    beq.w      .L4
.L27                move.l     (_audioPort),a0                                                          ;check if list is empty
                    lea        (MP_MSGLIST+LH_TAIL,a0),a1
                    move.l     a1,d2
                    move.l     (_audioPort),a0
                    move.l     (MP_MSGLIST,a0),d3
                    move.l     d3,a3
                    cmp.l      d3,d2
                    beq.b      .L26
.L3                 jsr        (_Disable)                                                               ;remove the message
                    move.l     a3,-(sp)
                    jsr        (_Remove)
                    jsr        (_Enable)
                    moveq      #CMD_WRITE,d2                                                            ;was it write?
                    cmp.w      (IOAudio+IO_COMMAND,a3),d2
                    addq.l     #4,sp
                    bne.b      .L1
.L2                 move.w     #ADCMD_FREE,(IOAudio+IO_COMMAND,a3)
                    move.l     a3,-(sp)
                    jsr        (a4)
                    addq.l     #4,sp
.L1                 move.l     a3,-(sp)
                    pea        (_freeList)
                    jsr        (_AddTail)
                    addq.l     #8,sp
                    bra.b      .L27

.L26                move.l     (a2),a0                                                                  ;alloc audio channels
                    move.b     #$F6,(IOAudio+MN+LN_PRI,a0)
                    move.l     (a2),a0
                    move.w     #ADCMD_ALLOCATE,(IOAudio+IO_COMMAND,a0)
                    move.l     (a2),a0
                    move.b     #$41,(IOAudio+IO_FLAGS,a0)
                    move.l     (a2),a0
                    clr.w      (ioa_AllocKey,a0)
                    move.l     (a2),-(sp)
                    jsr        (_BeginIO)
                    move.l     (a2),-(sp)
                    jsr        (_WaitIO)
                    tst.l      d0
                    addq.l     #8,sp
                    bne.w      .L4
.L25                clr.w      (-6,a6)
.L24                move.l     (a2),a0
                    moveq      #0,d2
                    move.b     (IOAudio+IO_UNIT+3,a0),d2                                                ;what did we get?
                    moveq      #1,d0
                    move.b     (-5,a6),d1
                    asl.l      d1,d0
                    and.l      d0,d2
                    beq.b      .L21
.L23                move.w     (-6,a6),d0
                    add.w      d0,d0
                    move.l     #_key,a0
                    move.l     (a2),a1
                    move.w     (ioa_AllocKey,a1),(a0,d0.w)
.L21                addq.w     #1,(-6,a6)
                    moveq      #4,d2
                    cmp.w      (-6,a6),d2
                    bgt.b      .L24
.L20                move.l     (a2),a0
                    moveq      #0,d2
                    move.w     d6,d2
                    neg.l      d2
                    lsr.l      #4,d2
                    move.b     d2,(9,a0)
                    move.l     (a2),a0
                    move.w     #ADCMD_SETPREC,(IOAudio+IO_COMMAND,a0)
                    move.l     (a2),-(sp)
                    jsr        (a4)
                    move.l     (a2),a0
                    move.w     #CMD_STOP,(IOAudio+IO_COMMAND,a0)
                    move.l     (a2),-(sp)
                    jsr        (a4)
                    clr.w      (-6,a6)
                    addq.l     #8,sp
.L19                move.l     #lbL00090E,d2
                    move.l     (_freeList),d3
                    move.l     d3,a3
                    cmp.l      d3,d2
                    beq.b      .L18
.L15                move.l     a3,-(sp)
                    jsr        (_Remove)
                    addq.l     #4,sp
                    bra.b      .L14

.L18                move.l     #(MEMF_PUBLIC|MEMF_CLEAR),-(sp)
                    pea        (ioa_SIZEOF).w
                    jsr        (_AllocMem)
                    move.l     d0,a3
                    cmp.w      #0,a3
                    addq.l     #8,sp
                    bne.b      .L17
.L16                jsr        (_CleanUp)
                    bra.w      .L4

.L17                move.l     (a2),a0
                    move.l     (IOAudio+MN_REPLYPORT,a0),(IOAudio+MN_REPLYPORT,a3)
                    move.l     (a2),a0
                    move.l     (IOAudio+IO_DEVICE,a0),(IOAudio+IO_DEVICE,a3)
                    move.w     #1,(ioa_Cycles,a3)
.L14                tst.w      (-6,a6)
                    beq.w      .L13
.L12                moveq      #0,d0
                    tst.w      d4
                    sge        d0
                    neg.b      d0
                    move.l     #_leftRight,a0
                    moveq      #0,d2
                    move.b     (a0,d0.l),d2
                    move.l     (a2),a1
                    and.l      (IOAudio+IO_UNIT,a1),d2
                    move.l     d2,(IOAudio+IO_UNIT,a3)
                    tst.w      d4
                    bge.b      .L10
.L11                move.w     d4,d0
                    ext.l      d0
                    neg.l      d0
                    move.w     d0,d4
.L10                move.w     d4,d1
                    move.l     (_maxCCDelay),d0
                    divu       d6,d0
                    mulu       d0,d1
                    move.l     d1,d3
                    moveq      #15,d0
                    lsr.l      d0,d3
                    move.w     d3,d0
                    move.l     (-4,a6),a5
                    move.w     d0,(a5)
                    move.l     (_samples),d2
                    moveq      #0,d3
                    move.l     (-4,a6),a5
                    move.w     (a5),d3
                    sub.l      d3,d2
                    move.l     d2,(ioa_Data,a3)
                    moveq      #0,d2
                    move.l     (-4,a6),a5
                    move.w     (a5),d2
                    add.l      (_sampleLength),d2
                    move.l     d2,(ioa_Length,a3)
                    move.w     #54613,d0
                    sub.w      d4,d0
                    moveq      #0,d1
                    move.b     d5,d1
                    mulu       d1,d0
                    divu       #54613,d0
                    move.w     d0,(ioa_Volume,a3)
                    bra.b      .L9

.L13                moveq      #0,d0
                    tst.w      d4
                    slt        d0
                    neg.b      d0
                    move.l     #_leftRight,a0
                    moveq      #0,d2
                    move.b     (a0,d0.l),d2
                    move.l     (a2),a1
                    and.l      (IOAudio+IO_UNIT,a1),d2
                    move.l     d2,(IOAudio+IO_UNIT,a3)
                    move.l     (_samples),(ioa_Data,a3)
                    move.l     (_sampleLength),(ioa_Length,a3)
                    moveq      #0,d0
                    move.b     d5,d0
                    move.w     d0,(ioa_Volume,a3)
.L9                 move.w     #3,(IOAudio+IO_COMMAND,a3)
                    move.b     #ADIOF_PERVOL,(IOAudio+IO_FLAGS,a3)
                    move.w     d6,(ioa_Period,a3)
                    move.l     (a2),a0
                    move.w     (ioa_AllocKey,a0),(ioa_AllocKey,a3)
                    move.l     a3,-(sp)
                    jsr        (_BeginIO)
                    addq.l     #4,sp
.L8                 addq.w     #1,(-6,a6)
                    moveq      #2,d2
                    cmp.w      (-6,a6),d2
                    bgt.w      .L19
.L7                 move.l     (a2),a0                                                                  ;start audio!
                    move.w     #CMD_START,(IOAudio+IO_COMMAND,a0)
                    move.l     (a2),-(sp)
                    jsr        (a4)
                    addq.l     #4,sp
.L4                 movem.l    (sp)+,d2-d6/a2-a5
                    unlk       a6
                    rts

_initCleanup        link       a6,#-2
                    movem.l    d2-d5/a2-a5,-(sp)
.L77                move.l     (8,a6),d0
                    clr.w      (-2,a6)
                    move.l     #_allocReq,a2
                    move.l     #_audioPort,a3
                    move.l     #_silentLength,a4
.L71                tst.l      d0
                    beq.w      .L46
.L70                moveq      #0,d2
                    move.w     (_maxDelay),d2
                    muls       #3580,d2
                    move.l     d2,(_maxCCDelay)
                    move.l     d2,d3
                    divu       #100,d3
                    move.w     d3,d2
                    and.w      #$FFFE,d2
                    move.w     d2,(a4)
                    move.l     #$FFFFFFFE,-(sp)
                    pea        (boingsamples__MSG)
                    jsr        (_Lock)
                    move.l     d0,d5
                    addq.l     #8,sp
                    beq.w      .L55
.L68                move.l     #MEMF_CLEAR,-(sp)
                    pea        (fib_SIZEOF).w
                    jsr        (_AllocMem)
                    move.l     d0,d4
                    addq.l     #8,sp
                    beq.w      .L56
.L66                move.l     d4,-(sp)
                    move.l     d5,-(sp)
                    jsr        (_Examine)
                    tst.l      d0
                    addq.l     #8,sp
                    beq.w      .L57
.L65                move.l     #(MEMF_CHIP|MEMF_CLEAR),-(sp)
                    moveq      #0,d2
                    move.w     (a4),d2
                    move.l     d4,a5
                    move.l     (fib_Size,a5),d3
                    subq.l     #2,d3
                    move.l     d3,(_sampleLength)
                    add.l      d3,d2
                    move.l     d2,-(sp)
                    jsr        (_AllocMem)
                    move.l     d0,(_silent)
                    addq.l     #8,sp
                    beq.b      .L57
.L63                pea        (MODE_OLDFILE).w
                    pea        (boingsamples__MSG0)
                    jsr        (_Open)
                    move.l     d0,d3
                    addq.l     #8,sp
                    beq.b      .L57
.L61                pea        (2).w
                    pea        (-2,a6)
                    move.l     d3,-(sp)
                    jsr        (_Read)
                    move.l     (_sampleLength),-(sp)
                    moveq      #0,d2
                    move.w     (a4),d2
                    add.l      (_silent),d2
                    move.l     d2,(_samples)
                    move.l     d2,-(sp)
                    move.l     d3,-(sp)
                    jsr        (_Read)
                    move.l     d3,-(sp)
                    jsr        (_Close)
                    moveq      #2,d2
                    cmp.w      (-2,a6),d2
                    lea        ($001C,sp),sp
                    bne.w      .L57
.L57                pea        (fib_SIZEOF).w
                    move.l     d4,-(sp)
                    jsr        (_FreeMem)
                    addq.l     #8,sp
.L56                move.l     d5,-(sp)
                    jsr        (_UnLock)
                    addq.l     #4,sp
.L55                moveq      #2,d2
                    cmp.w      (-2,a6),d2
                    bne.w      .L36
.L54                clr.l      -(sp)
                    pea        (PROGRAM_NAME__MSG)
                    jsr        (_CreatePort)
                    move.l     d0,(a3)
                    addq.l     #8,sp
                    beq.w      .L36
.L52                move.l     #(MEMF_PUBLIC|MEMF_CLEAR),-(sp)
                    pea        (ioa_SIZEOF).w
                    jsr        (_AllocMem)
                    move.l     d0,(a2)
                    addq.l     #8,sp
                    beq.w      .L38
.L50                pea        (_freeList)
                    jsr        (_NewList)
                    clr.l      -(sp)
                    move.l     (a2),-(sp)
                    clr.l      -(sp)
                    pea        (audiodevice__MSG)
                    jsr        (_OpenDevice)
                    tst.l      d0
                    lea        ($0014,sp),sp
                    bne.w      .L42
.L48                move.l     (a2),a0
                    move.l     (a3),(IOAudio+MN_REPLYPORT,a0)
                    move.l     (a2),a0
                    move.l     #_allocMap,(ioa_Data,a0)
                    move.l     (a2),a0
                    moveq      #4,d2
                    move.l     d2,(ioa_Length,a0)
                    move.l     (a2),a0
                    move.w     #1,(ioa_Cycles,a0)
                    move.b     #1,(_sound)
                    bra.w      .L33

.L46                moveq      #0,d4
.L45                move.l     (a2),a0
                    moveq      #1,d3
                    move.b     d4,d2
                    asl.l      d2,d3
                    move.l     d3,(IOAudio+IO_UNIT,a0)
                    move.l     (a2),a0
                    move.w     d4,d2
                    add.w      d2,d2
                    move.l     #_key,a1
                    move.w     (a1,d2.w),(ioa_AllocKey,a0)
                    move.l     (a2),a0
                    move.w     #ADCMD_FREE,(IOAudio+IO_COMMAND,a0)
                    move.l     (a2),-(sp)
                    jsr        (_DoIO)
                    addq.l     #4,sp
.L44                addq.l     #1,d4
                    moveq      #4,d2
                    cmp.l      d4,d2
                    bgt.b      .L45
.L43                move.l     (a2),-(sp)
                    jsr        (_CloseDevice)
                    addq.l     #4,sp
.L42                move.l     (a2),-(sp)
                    pea        (_freeList)
                    jsr        (_AddTail)
                    addq.l     #8,sp
.L41                move.l     (a3),a0
                    lea        (IOAudio+IO_UNIT,a0),a1
                    move.l     a1,d3
                    move.l     (a3),a0
                    move.l     (IOAudio+IO_DEVICE,a0),d2
                    move.l     d2,d4
                    cmp.l      d2,d3
                    bne.w      .L32
.L40                move.l     #lbL00090E,d3
                    move.l     (_freeList),d2
                    move.l     d2,d4
                    cmp.l      d2,d3
                    beq.b      .L38
.L32                move.l     d4,-(sp)
                    jsr        (_Remove)
                    pea        ($44).w
                    move.l     d4,-(sp)
                    jsr        (_FreeMem)
                    lea        (12,sp),sp
                    bra.b      .L41

.L38                move.l     (a3),-(sp)
                    jsr        (_DeletePort)
                    addq.l     #4,sp
.L36                tst.l      (_silent)
                    beq.b      .L34
.L35                moveq      #0,d2
                    move.w     (a4),d2
                    add.l      (_sampleLength),d2
                    move.l     d2,-(sp)
                    move.l     (_silent),-(sp)
                    jsr        (_FreeMem)
                    addq.l     #8,sp
.L34                clr.b      (_sound)
.L33                movem.l    (sp)+,d2-d5/a2-a5
                    unlk       a6
                    rts

_InitBoing          pea        (1).w
                    jsr        (_initCleanup,pc)
                    addq.l     #4,sp
.L78                rts

_CleanUp            tst.b      (_sound)
                    beq.b      .L82
.L84                clr.l      -(sp)
                    jsr        (_initCleanup,pc)
                    addq.l     #4,sp
.L82                rts

                    dc.w       0

                    SECTION    boing0008A4,DATA,CHIP
boingsamples__MSG   dc.b       'boing.samples',0
boingsamples__MSG0  dc.b       'boing.samples',0
PROGRAM_NAME__MSG   dc.b       'PROGRAM_NAME',0,0
audiodevice__MSG    dc.b       'audio.device',0,0
_sound              dc.b       0
                    dc.b       0
_silent             dc.l       0
_samples            dc.l       0
_audioPort          dc.l       0
_allocReq           dc.l       0
_allocMap           dc.l       $03050A0C
_leftRight          dc.w       $0609
_sampleLength       dc.l       0
_silentLength       dc.w       0
_extraSamples       dc.w       0
_maxDelay           dc.w       10
_maxCCDelay         dc.l       0
_key                dc.l       0
                    dc.l       0
_freeList           dc.l       0
lbL00090E           dc.l       0
                    dc.l       0
                    dc.w       0


                    SECTION    boing000918,CODE
_init_globe         link       a6,#-4
                    movem.l    d2-d7/a2/a3,-(sp)
.L10                move.l     #_globe,a2
                    moveq      #8,d4
.L7                 move.l     d4,d2
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
                    jsr        (_Sine16)
                    move.w     d0,d6
                    ext.l      d6
                    move.l     d4,d2
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
                    move.w     d0,(-2,a6)
                    move.l     (-4,a6),d7
                    ext.l      d7
                    move.l     d7,(-4,a6)
                    moveq      #$37,d5
                    addq.l     #8,sp
.L6                 move.l     d6,d3
                    move.l     d5,d2
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
                    jsr        (_Cosine16)
                    move.l     d3,d1
                    ext.l      d0
                    jsr        (ulmult)
                    move.l     d0,d3
                    moveq      #$10,d0
                    asr.l      d0,d3
                    move.w     d3,(a2)
                    move.l     d6,d3
                    move.l     d5,d2
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
                    jsr        (_Sine16)
                    move.l     d3,d1
                    ext.l      d0
                    jsr        (ulmult)
                    move.l     d0,d3
                    moveq      #$10,d0
                    asr.l      d0,d3
                    move.w     d3,(2,a2)
                    move.l     (-4,a6),d0
                    asr.l      #1,d0
                    move.w     d0,(4,a2)
                    move.l     a2,a3
                    moveq      #12,d2
                    add.l      d2,a2
                    move.l     d4,d2
                    moveq      #1,d0
                    and.l      d0,d2
                    move.l     d2,d1
                    add.l      d2,d2
                    move.l     d2,d0
                    add.l      d2,d2
                    add.l      d0,d2
                    add.l      d1,d2
                    add.l      d5,d2
                    moveq      #14,d1
                    move.l     d2,d0
                    jsr        (lmodt)
                    addq.w     #2,d0
                    move.w     d0,(10,a3)
                    addq.l     #8,sp
.L5                 subq.l     #1,d5
                    tst.l      d5
                    bge.w      .L6
.L3                 subq.l     #1,d4
                    tst.l      d4
                    bge.w      .L7
.L1                 movem.l    (sp)+,d2-d7/a2/a3
                    unlk       a6
                    rts

_draw_globe         link       a6,#-$010C
                    movem.l    d2-d7/a2-a4,-(sp)
.L46                move.l     (8,a6),d6
                    move.l     #_AreaDraw,a4
                    move.l     #_srad,a2
                    move.l     #_yoff,a3
.L44                moveq      #$37,d2
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
.L43                tst.w      d4
                    beq.w      .L42
.L41                clr.l      -(sp)
                    move.l     #$8CCCCD41,-(sp)
                    move.l     d5,d0
                    moveq      #0,d1
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.w     d4,d2
                    ext.l      d2
                    move.l     d2,d0
                    jsr        (fflti)
                    move.l     d1,(-$00C8,a6)
                    move.l     d0,(-$00CC,a6)
                    jsr        (fmuli)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (-$0014,a6),d0
                    moveq      #0,d1
                    jsr        (faddi)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    jsr        (_SPSin)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (a2),d0
                    jsr        (fflti)
                    move.l     d1,(-$00D0,a6)
                    move.l     d0,(-$00D4,a6)
                    jsr        (fmuli)
                    addq.l     #8,sp
                    jsr        (fdivi)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (a3),d2
                    moveq      #$64,d0
                    add.l      d0,d2
                    move.l     d2,d0
                    jsr        (fflti)
                    move.l     d1,(-$00D8,a6)
                    move.l     d0,(-$00DC,a6)
                    jsr        (faddi)
                    jsr        (ffixi)
                    move.l     d0,-(sp)
                    move.l     d5,d0
                    moveq      #0,d1
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.w     d4,d0
                    ext.l      d0
                    jsr        (fflti)
                    move.l     d1,(-$0100,a6)
                    move.l     d0,(-$0104,a6)
                    jsr        (fmuli)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (-$0014,a6),d0
                    moveq      #0,d1
                    jsr        (faddi)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    jsr        (_SPCos)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (a2),d0
                    jsr        (fflti)
                    move.l     d1,(-$0108,a6)
                    move.l     d0,(-$010C,a6)
                    jsr        (fmuli)
                    addq.l     #8,sp
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    moveq      #0,d1
                    move.l     #$B9000048,d0
                    jsr        (faddi)
                    jsr        (ffixi)
                    move.l     d0,-(sp)
                    move.l     d6,-(sp)
                    jsr        (a4)
                    lea        (12,sp),sp
                    bra.w      .L39

.L42                clr.l      -(sp)
                    move.l     #$8CCCCD41,-(sp)
                    move.l     d5,d0
                    moveq      #0,d1
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.w     d4,d2
                    ext.l      d2
                    move.l     d2,d0
                    jsr        (fflti)
                    move.l     d1,(-$0058,a6)
                    move.l     d0,(-$005C,a6)
                    jsr        (fmuli)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (-$0014,a6),d0
                    moveq      #0,d1
                    jsr        (faddi)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    jsr        (_SPSin)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (a2),d0
                    jsr        (fflti)
                    move.l     d1,(-$0060,a6)
                    move.l     d0,(-$0064,a6)
                    jsr        (fmuli)
                    addq.l     #8,sp
                    jsr        (fdivi)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (a3),d2
                    moveq      #$64,d0
                    add.l      d0,d2
                    move.l     d2,d0
                    jsr        (fflti)
                    move.l     d1,(-$0068,a6)
                    move.l     d0,(-$006C,a6)
                    jsr        (faddi)
                    jsr        (ffixi)
                    move.l     d0,-(sp)
                    move.l     d5,d0
                    moveq      #0,d1
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.w     d4,d0
                    ext.l      d0
                    jsr        (fflti)
                    move.l     d1,(-$0090,a6)
                    move.l     d0,(-$0094,a6)
                    jsr        (fmuli)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (-$0014,a6),d0
                    moveq      #0,d1
                    jsr        (faddi)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    jsr        (_SPCos)
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (a2),d0
                    jsr        (fflti)
                    move.l     d1,(-$0098,a6)
                    move.l     d0,(-$009C,a6)
                    jsr        (fmuli)
                    addq.l     #8,sp
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    moveq      #0,d1
                    move.l     #$B9000048,d0
                    jsr        (faddi)
                    jsr        (ffixi)
                    move.l     d0,-(sp)
                    move.l     d6,-(sp)
                    jsr        (_AreaMove)
                    lea        (12,sp),sp
.L39                addq.w     #1,d4
                    moveq      #$10,d2
                    cmp.w      d4,d2
                    bgt.w      .L43
.L38                move.l     d6,-(sp)
                    jsr        (_AreaEnd)
                    move.l     #_bperiod,a2
                    moveq      #8,d4
                    addq.l     #4,sp
.L37                moveq      #$37,d5
.L36                moveq      #12,d2
                    sub.l      d2,a2
                    move.w     (4,a2),d3
                    ext.l      d3
                    asr.l      #1,d3
                    move.w     (a2),d2
                    ext.l      d2
                    asl.l      #1,d2
                    move.w     (a2),(-10,a6)
                    move.l     (-12,a6),d7
                    ext.l      d7
                    move.l     d7,(-12,a6)
                    move.l     (-12,a6),d7
                    asr.l      #2,d7
                    move.l     d7,(-12,a6)
                    move.l     (-12,a6),a0
                    sub.l      a0,d2
                    move.w     (a2),(-14,a6)
                    move.l     (-$0010,a6),d7
                    ext.l      d7
                    move.l     d7,(-$0010,a6)
                    move.l     (-$0010,a6),d7
                    asr.l      #4,d7
                    move.l     d7,(-$0010,a6)
                    move.l     (-$0010,a6),a0
                    sub.l      a0,d2
                    add.l      d2,d3
                    moveq      #9,d2
                    asr.l      d2,d3
                    move.w     d3,a0
                    move.l     a0,d7
                    add.w      #$00A0,d7
                    move.w     d7,(6,a2)
                    move.w     (2,a3),a0
                    move.l     a0,d7
                    add.w      #$0064,d7
                    move.w     d7,a0
                    move.w     (4,a2),d3
                    ext.l      d3
                    asr.l      #1,d3
                    move.w     (4,a2),d2
                    ext.l      d2
                    add.l      d2,d3
                    move.w     (4,a2),d2
                    ext.l      d2
                    asr.l      #4,d2
                    sub.l      d2,d3
                    move.w     (a2),d2
                    ext.l      d2
                    asr.l      #1,d2
                    sub.l      d2,d3
                    moveq      #9,d2
                    asr.l      d2,d3
                    move.w     d3,d2
                    sub.w      d2,a0
                    move.w     a0,(8,a2)
.L35                subq.w     #1,d5
                    tst.w      d5
                    bge.w      .L36
.L33                subq.w     #1,d4
                    tst.w      d4
                    bge.w      .L37
.L32                move.l     #_bperiod,a0
                    move.l     a0,a2
                    move.l     a0,d7
                    sub.l      #672,d7
                    move.l     d7,a3
                    moveq      #7,d4
.L31                moveq      #$37,d5
.L30                moveq      #12,d2
                    sub.l      d2,a2
                    moveq      #12,d2
                    sub.l      d2,a3
                    tst.w      d4
                    ble.b      .L29
.L25                tst.w      d5
                    ble.b      .L24
.L23                move.l     a3,a0
                    moveq      #12,d3
                    sub.l      d3,a0
                    move.w     (a0),(-2,a6)
                    move.l     (-4,a6),d7
                    ext.l      d7
                    move.l     d7,(-4,a6)
                    bra.b      .L22

.L24                move.l     a2,a0
                    moveq      #12,d3
                    sub.l      d3,a0
                    move.w     (a0),(-2,a6)
                    move.l     (-4,a6),d7
                    ext.l      d7
                    move.l     d7,(-4,a6)
.L22                moveq      #0,d3
                    move.w     (a3),d2
                    ext.l      d2
                    cmp.l      (-4,a6),d2
                    sgt        d3
                    neg.b      d3
                    bra.b      .L21

.L29                tst.w      d5
                    ble.b      .L28
.L27                move.l     a2,a0
                    moveq      #12,d3
                    sub.l      d3,a0
                    move.w     (a0),(-6,a6)
                    move.l     (-8,a6),d7
                    ext.l      d7
                    move.l     d7,(-8,a6)
                    bra.b      .L26

.L28                move.l     a2,d7
                    add.l      #672,d7
                    move.l     d7,a0
                    moveq      #12,d2
                    sub.l      d2,a0
                    move.w     (a0),(-6,a6)
                    move.l     (-8,a6),d7
                    ext.l      d7
                    move.l     d7,(-8,a6)
.L26                moveq      #0,d3
                    move.w     (a2),d2
                    ext.l      d2
                    cmp.l      (-8,a6),d2
                    sgt        d3
                    neg.b      d3
.L21                tst.l      d3
                    beq.w      .L15
.L20                move.w     (10,a2),d3
                    ext.l      d3
                    move.l     d3,-(sp)
                    move.l     d6,-(sp)
                    jsr        (_SetAPen)
                    move.w     (8,a2),d3
                    ext.l      d3
                    move.l     d3,-(sp)
                    move.w     (6,a2),d2
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     d6,-(sp)
                    jsr        (_AreaMove)
                    move.w     (8,a3),d3
                    ext.l      d3
                    move.l     d3,-(sp)
                    move.w     (6,a3),d2
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     d6,-(sp)
                    jsr        (a4)
                    tst.w      d5
                    lea        ($0020,sp),sp
                    ble.b      .L19
.L18                move.l     a3,a0
                    moveq      #12,d2
                    sub.l      d2,a0
                    move.w     (8,a0),d2
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     a3,a0
                    moveq      #12,d2
                    sub.l      d2,a0
                    move.w     (6,a0),d2
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     d6,-(sp)
                    jsr        (a4)
                    move.l     a2,a0
                    moveq      #12,d2
                    sub.l      d2,a0
                    move.w     (8,a0),d2
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     a2,a0
                    moveq      #12,d2
                    sub.l      d2,a0
                    move.w     (6,a0),d2
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     d6,-(sp)
                    jsr        (a4)
                    lea        ($0018,sp),sp
                    bra.b      .L17

.L19                move.l     a2,a0
                    moveq      #12,d2
                    sub.l      d2,a0
                    move.w     (8,a0),d2
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     a2,a0
                    moveq      #12,d2
                    sub.l      d2,a0
                    move.w     (6,a0),d2
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     d6,-(sp)
                    jsr        (a4)
                    move.l     a2,d2
                    add.l      #672,d2
                    move.l     d2,a0
                    moveq      #12,d2
                    sub.l      d2,a0
                    move.w     (8,a0),d2
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     a2,d2
                    add.l      #672,d2
                    move.l     d2,a0
                    moveq      #12,d2
                    sub.l      d2,a0
                    move.w     (6,a0),d2
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.l     d6,-(sp)
                    jsr        (a4)
                    lea        ($0018,sp),sp
.L17                move.l     d6,-(sp)
                    jsr        (_AreaEnd)
                    addq.l     #4,sp
.L15                subq.w     #1,d5
                    tst.w      d5
                    bge.w      .L30
.L13                subq.w     #1,d4
                    tst.w      d4
                    bge.w      .L31
.L11                movem.l    (sp)+,d2-d7/a2-a4
                    unlk       a6
                    rts

_GoodBye            movem.l    d2/d3,-(sp)
.L51                pea        (200).w
                    pea        (320).w
                    move.l     (_arearas),-(sp)
                    jsr        (_FreeRaster)
                    move.l     (_Window),-(sp)
                    jsr        (_ClearPointer)
                    move.l     (_Window),-(sp)
                    jsr        (_CloseWindow)
                    move.l     (_myScreen),-(sp)
                    jsr        (_CloseScreen)
                    moveq      #0,d3
                    lea        ($0018,sp),sp
.L50                pea        (216).w
                    pea        (336).w
                    move.w     d3,d2
                    asl.w      #2,d2
                    move.l     #_bgptr,a0
                    move.l     (a0,d2.w),-(sp)
                    jsr        (_FreeRaster)
                    lea        (12,sp),sp
.L49                addq.l     #1,d3
                    moveq      #$10,d0
                    cmp.l      d3,d0
                    bgt.b      .L50
.L48                move.l     (_bigbytesgot),-(sp)
                    move.l     (_bigmem),-(sp)
                    jsr        (_FreeMem)
                    jsr        (_exit)
                    addq.l     #8,sp
.L47                movem.l    (sp)+,d2/d3
                    rts

_main               link       a6,#-$00B2
                    movem.l    d2-d7/a2-a5,-(sp)
.L187               move.l     #_x,a4
                    move.l     #_Move,d6
                    move.l     #_bitmap,(-4,a6)
.L174               pea        (31).w
                    pea        (graphicslibra__MSG)
                    jsr        (_OpenLibrary)
                    move.l     d0,(_GfxBase)
                    addq.l     #8,sp
                    bne.b      .L172
.L173               pea        (1).w
                    jsr        (_exit)
                    addq.l     #4,sp
.L172               pea        (31).w
                    pea        (intuitionlibr__MSG)
                    jsr        (_OpenLibrary)
                    move.l     d0,(_IntuitionBase)
                    addq.l     #8,sp
                    bne.b      .L170
.L171               pea        (1).w
                    jsr        (_exit)
                    addq.l     #4,sp
.L170               pea        (31).w
                    pea        (mathffplibrar__MSG)
                    jsr        (_OpenLibrary)
                    move.l     d0,(_MathBase)
                    addq.l     #8,sp
                    bne.b      .L168
.L169               pea        (1).w
                    jsr        (_exit)
                    addq.l     #4,sp
.L168               pea        (31).w
                    pea        (mathtranslibr__MSG)
                    jsr        (_OpenLibrary)
                    move.l     d0,(_MathTransBase)
                    addq.l     #8,sp
                    bne.b      .L166
.L167               pea        (1).w
                    jsr        (_exit)
                    addq.l     #4,sp
.L166               move.w     #1,(_firsttime)
                    move.w     #$0FDD,(-10,a6)
                    moveq      #-$50,d2
                    move.l     d2,(_left)
                    moveq      #$68,d2
                    move.l     d2,(_right)
                    move.l     (-4,a6),a5
                    move.l     #_mybitmap,(a5)
                    pea        (200).w
                    pea        (320).w
                    pea        (5).w
                    move.l     (-4,a6),a5
                    move.l     (a5),-(sp)
                    jsr        (_InitBitMap)
                    pea        (50).w
                    pea        (_areavect)
                    pea        (-$002A,a6)
                    jsr        (_InitArea)
                    move.l     #$000011B8,(_bytesneeded)
                    add.l      #$00008DC0,(_bytesneeded)
                    move.l     (_bytesneeded),(_bigbytesgot)
                    pea        (2).w
                    move.l     (_bytesneeded),-(sp)
                    jsr        (_AllocMem)
                    move.l     d0,(_bigmem)
                    lea        ($0024,sp),sp
                    bne.b      .L164
.L165               jsr        (_exit)
.L164               clr.l      -(sp)
                    move.l     (_bytesneeded),-(sp)
                    move.l     (_bigmem),-(sp)
                    jsr        (_BltClear)
                    pea        (216).w
                    pea        (336).w
                    pea        (5).w
                    move.l     (-4,a6),a5
                    move.l     (a5),-(sp)
                    jsr        (_InitBitMap)
                    move.l     #$000011B8,(_bytesneeded)
                    move.l     (-4,a6),a5
                    move.l     (a5),a0
                    move.l     (_bytesneeded),a1
                    add.l      (_bigmem),a1
                    move.l     a1,(8,a0)
                    move.l     #$00002370,(_bytesneeded)
                    move.l     (-4,a6),a5
                    move.l     (a5),a0
                    move.l     (_bytesneeded),a1
                    move.l     (-4,a6),a5
                    move.l     (a5),a2
                    add.l      (8,a2),a1
                    move.l     a1,(12,a0)
                    move.l     (-4,a6),a5
                    move.l     (a5),a0
                    move.l     (_bytesneeded),a1
                    move.l     (-4,a6),a5
                    move.l     (a5),a2
                    add.l      (12,a2),a1
                    move.l     a1,($0010,a0)
                    move.l     (-4,a6),a5
                    move.l     (a5),a0
                    move.l     (_bytesneeded),a1
                    move.l     (-4,a6),a5
                    move.l     (a5),a2
                    add.l      ($0010,a2),a1
                    move.l     a1,($0014,a0)
                    moveq      #0,d4
                    lea        ($001C,sp),sp
.L163               move.w     d4,d2
                    asl.w      #2,d2
                    move.l     #_bgptr,a2
                    pea        ($D8).w
                    pea        ($0150).w
                    jsr        (_AllocRaster)
                    move.l     d0,(a2,d2.w)
                    addq.l     #8,sp
                    bne.b      .L160
.L162               pea        (1).w
                    jsr        (_exit)
                    addq.l     #4,sp
.L160               addq.l     #1,d4
                    moveq      #$10,d2
                    cmp.l      d4,d2
                    bgt.b      .L163
.L159               move.l     (-4,a6),a5
                    move.l     (a5),a0
                    move.l     (_bgptr),($0018,a0)
                    move.l     #topaz__MSG,(-$0012,a6)
                    move.w     #8,(-14,a6)
                    clr.b      (-12,a6)
                    clr.b      (-11,a6)
                    clr.w      (-$0082,a6)
                    clr.w      (-$0080,a6)
                    move.w     #$0140,(-$007E,a6)
                    move.w     #$00C8,(-$007C,a6)
                    move.w     #5,(-$007A,a6)
                    move.b     #$FF,(-$0078,a6)
                    move.b     #$FF,(-$0077,a6)
                    move.w     #$4000,(-$0076,a6)
                    move.w     #$004F,(-$0074,a6)
                    lea        (-$0012,a6),a0
                    move.l     a0,(-$0072,a6)
                    clr.l      (-$006E,a6)
                    clr.l      (-$006A,a6)
                    move.l     #_mybitmap,(-$0066,a6)
                    pea        (-$0082,a6)
                    jsr        (_OpenScreen)
                    move.l     d0,(_myScreen)
                    addq.l     #4,sp
                    beq.w      .L157
.L157               clr.w      (-$0062,a6)
                    clr.w      (-$0060,a6)
                    move.w     #$0140,(-$005E,a6)
                    move.w     #$00C8,(-$005C,a6)
                    move.b     #$FF,(-$005A,a6)
                    move.b     #$FF,(-$0059,a6)
                    move.l     #$00000208,(-$0058,a6)
                    move.l     #$00011808,(-$0054,a6)
                    clr.l      (-$0050,a6)
                    clr.l      (-$004C,a6)
                    clr.l      (-$0048,a6)
                    move.l     (_myScreen),(-$0044,a6)
                    clr.l      (-$0040,a6)
                    clr.w      (-$003C,a6)
                    clr.w      (-$0038,a6)
                    clr.w      (-$003A,a6)
                    clr.w      (-$0036,a6)
                    move.w     #15,(-$0034,a6)
                    pea        (-$0062,a6)
                    jsr        (_OpenWindow)
                    move.l     d0,(_Window)
                    addq.l     #4,sp
                    beq.w      .L155
.L155               move.l     (_myScreen),-(sp)
                    jsr        (_ScreenToBack)
                    move.l     (_myScreen),a0
                    lea        (sc_RastPort,a0),a1                                                      ;poking screen rastport.. nasty
                    move.l     a1,a3
                    move.l     a1,(_wact_ras)
                    move.l     (_myScreen),a0
                    lea        (sc_ViewPort,a0),a2
                    move.l     a2,(_viewport)
                    lea        (-$002A,a6),a0
                    move.l     a0,(rp_AreaInfo,a3)
                    pea        (200).w
                    pea        (320).w
                    jsr        (_AllocRaster)
                    move.l     d0,(_arearas)
                    pea        (8000).w
                    move.l     (_arearas),-(sp)
                    pea        (-$0032,a6)
                    jsr        (_InitTmpRas)
                    move.l     d0,(rp_TmpRas,a3)
                    move.l     (_viewport),a0
                    move.l     (vp_ColorMap,a0),(_cm)
                    move.l     (_cm),a0
                    move.l     (cm_ColorTable,a0),(_ct)
                    move.b     #$10,(rp_Mask,a3)
                    move.b     #15,(rp_Mask,a3)
                    clr.l      -(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetRast)
                    jsr        (_init_globe,pc)
                    move.l     a3,-(sp)
                    jsr        (_draw_globe,pc)
                    move.b     #$10,(rp_Mask,a3)
                    clr.l      (-8,a6)
                    lea        ($0024,sp),sp
.bgrenderloop       move.l     (rp_BitMap,a3),a0                                                        ;poking screen bitmap pointer.. even nastier
                    move.w     (-6,a6),d2
                    asl.w      #2,d2
                    move.l     #_bgptr,a2
                    move.l     (a2,d2.w),(bm_Planes+16,a0)
                    pea        (1).w
                    move.l     a3,-(sp)
                    jsr        (_SetDrMd)
                    clr.l      -(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetAPen)
                    clr.l      -(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetBPen)
                    pea        (215).w
                    pea        (335).w
                    clr.l      -(sp)
                    clr.l      -(sp)
                    move.l     a3,-(sp)
                    jsr        (_RectFill)
                    move.l     #$FFFFFFFF,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetAPen)
                    moveq      #$30,d4
                    lea        ($0034,sp),sp
.L153               clr.l      -(sp)
                    move.l     d4,d3
                    add.l      (-8,a6),d3
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5                                                                    ;a5 = Move
                    jsr        (a5)
                    pea        ($C0).w
                    move.l     d4,d3
                    add.l      (-8,a6),d3
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_Draw)
                    lea        ($0018,sp),sp
.L152               moveq      #$10,d2
                    add.l      d2,d4
                    cmp.l      #300,d4
                    blt.b      .L153
.L151               moveq      #0,d4
.L150               move.l     d4,-(sp)
                    move.l     (-8,a6),d3
                    moveq      #$30,d2
                    add.l      d2,d3
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)
                    move.l     d4,-(sp)
                    move.l     (-8,a6),d3
                    add.l      #288,d3
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_Draw)
                    lea        ($0018,sp),sp
.L149               moveq      #$10,d2
                    add.l      d2,d4
                    cmp.l      #200,d4
                    ble.b      .L150
.L148               moveq      #$30,d4
.L147               pea        ($C0).w
                    move.l     d4,d3
                    add.l      (-8,a6),d3
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)
                    pea        (215).w
                    clr.l      -(sp)
                    move.l     #$A0000041,-(sp)
                    move.l     d4,d0
                    sub.l      #$000000A0,d0
                    jsr        (fflti)
                    move.l     d1,(-$008E,a6)
                    move.l     d0,(-$0092,a6)
                    jsr        (fmuli)
                    jsr        (ffixi)
                    move.l     d0,d3
                    move.l     (-8,a6),d2
                    add.l      #$000000A0,d2
                    add.l      d2,d3
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_Draw)
                    lea        ($0018,sp),sp
.L146               moveq      #$10,d2
                    add.l      d2,d4
                    cmp.l      #$0000012C,d4
                    blt.b      .L147
.L145               moveq      #$15,d4
                    move.l     #$000000D8,d3
                    sub.l      d4,d3
                    subq.l     #1,d3
                    move.l     d3,-(sp)
                    move.l     (-8,a6),d2
                    moveq      #$30,d0
                    add.l      d0,d2
                    moveq      #$18,d3
                    sub.l      d4,d3
                    asl.l      #2,d3
                    move.l     d3,d0
                    asl.l      #3,d3
                    sub.l      d0,d3
                    moveq      #$18,d1
                    move.l     d3,d0
                    jsr        (ldivt)
                    move.l     d0,d3
                    sub.l      d3,d2
                    move.l     d2,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)
                    move.l     #216,d3
                    sub.l      d4,d3
                    subq.l     #1,d3
                    move.l     d3,-(sp)
                    moveq      #$18,d0
                    sub.l      d4,d0
                    asl.l      #5,d0
                    moveq      #$18,d1
                    jsr        (ldivt)
                    move.l     d0,d2
                    move.l     (-8,a6),d3
                    add.l      #$0000011F,d3
                    add.l      d3,d2
                    move.l     d2,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_Draw)
                    moveq      #$12,d4
                    move.l     #216,d3
                    sub.l      d4,d3
                    subq.l     #1,d3
                    move.l     d3,-(sp)
                    move.l     (-8,a6),d2
                    moveq      #$30,d0
                    add.l      d0,d2
                    moveq      #$18,d3
                    sub.l      d4,d3
                    asl.l      #2,d3
                    move.l     d3,d0
                    asl.l      #3,d3
                    sub.l      d0,d3
                    moveq      #$18,d1
                    move.l     d3,d0
                    jsr        (ldivt)
                    move.l     d0,d3
                    sub.l      d3,d2
                    move.l     d2,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)
                    move.l     #$000000D8,d3
                    sub.l      d4,d3
                    subq.l     #1,d3
                    move.l     d3,-(sp)
                    moveq      #$18,d0
                    sub.l      d4,d0
                    asl.l      #5,d0
                    moveq      #$18,d1
                    jsr        (ldivt)
                    move.l     d0,d2
                    move.l     (-8,a6),d3
                    add.l      #$0000011F,d3
                    add.l      d3,d2
                    move.l     d2,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_Draw)
                    moveq      #14,d4
                    move.l     #$000000D8,d3
                    sub.l      d4,d3
                    subq.l     #1,d3
                    move.l     d3,-(sp)
                    move.l     (-8,a6),d2
                    moveq      #$30,d0
                    add.l      d0,d2
                    moveq      #$18,d3
                    sub.l      d4,d3
                    asl.l      #2,d3
                    move.l     d3,d0
                    asl.l      #3,d3
                    sub.l      d0,d3
                    moveq      #$18,d1
                    move.l     d3,d0
                    jsr        (ldivt)
                    move.l     d0,d3
                    sub.l      d3,d2
                    move.l     d2,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)
                    move.l     #$000000D8,d3
                    sub.l      d4,d3
                    subq.l     #1,d3
                    move.l     d3,-(sp)
                    moveq      #$18,d0
                    sub.l      d4,d0
                    asl.l      #5,d0
                    moveq      #$18,d1
                    jsr        (ldivt)
                    move.l     d0,d2
                    move.l     (-8,a6),d3
                    add.l      #$0000011F,d3
                    add.l      d3,d2
                    move.l     d2,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_Draw)
                    moveq      #8,d4
                    move.l     #$000000D8,d3
                    sub.l      d4,d3
                    subq.l     #1,d3
                    move.l     d3,-(sp)
                    move.l     (-8,a6),d2
                    moveq      #$30,d0
                    add.l      d0,d2
                    moveq      #$18,d3
                    sub.l      d4,d3
                    asl.l      #2,d3
                    move.l     d3,d0
                    asl.l      #3,d3
                    sub.l      d0,d3
                    moveq      #$18,d1
                    move.l     d3,d0
                    jsr        (ldivt)
                    move.l     d0,d3
                    sub.l      d3,d2
                    move.l     d2,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)
                    move.l     #$000000D8,d3
                    sub.l      d4,d3
                    subq.l     #1,d3
                    move.l     d3,-(sp)
                    moveq      #$18,d0
                    sub.l      d4,d0
                    asl.l      #5,d0
                    moveq      #$18,d1
                    jsr        (ldivt)
                    move.l     d0,d2
                    move.l     (-8,a6),d3
                    add.l      #$0000011F,d3
                    add.l      d3,d2
                    move.l     d2,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_Draw)
                    pea        ($D7).w
                    move.l     (-8,a6),d3
                    add.l      #$000000A0,d3
                    add.l      #$FFFFFF74,d3
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)
                    pea        ($D7).w
                    move.l     (-8,a6),d3
                    add.l      #$000000A0,d3
                    add.l      #$0000009F,d3
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_Draw)
                    clr.l      -(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetAPen)
                    moveq      #-2,d4
                    lea        ($0080,sp),sp
.L144               moveq      #-2,d5
.L143               move.l     d5,d3
                    moveq      #$3C,d2
                    add.l      d2,d3
                    move.l     d3,-(sp)
                    move.l     (-8,a6),d3
                    moveq      #$6E,d2
                    add.l      d2,d3
                    add.l      d4,d3
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)
                    lea        (12,sp),sp
.L142               addq.l     #1,d5
                    moveq      #2,d2
                    cmp.l      d5,d2
                    bge.b      .L143
.L140               addq.l     #1,d4
                    moveq      #2,d2
                    cmp.l      d4,d2
                    bge.b      .L144
.L139               move.l     #$FFFFFFFF,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetAPen)
                    pea        ($3C).w
                    move.l     (-8,a6),d3
                    moveq      #$6E,d2
                    add.l      d2,d3
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)
                    clr.l      -(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetAPen)
                    moveq      #-2,d4
                    lea        ($001C,sp),sp
.L138               moveq      #-2,d5
.L137               move.l     d5,d3
                    moveq      #$7C,d2
                    add.l      d2,d3
                    move.l     d3,-(sp)
                    move.l     (-8,a6),d3
                    moveq      #$4E,d2
                    add.l      d2,d3
                    add.l      d4,d3
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)
                    lea        (12,sp),sp
.L136               addq.l     #1,d5
                    moveq      #2,d2
                    cmp.l      d5,d2
                    bge.b      .L137
.L134               addq.l     #1,d4
                    moveq      #2,d2
                    cmp.l      d4,d2
                    bge.b      .L138
.L133               move.l     #$FFFFFFFF,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetAPen)
                    pea        ($7C).w
                    move.l     (-8,a6),d3
                    moveq      #$4E,d2
                    add.l      d2,d3
                    move.l     d3,-(sp)
                    move.l     a3,-(sp)
                    move.l     d6,a5
                    jsr        (a5)
                    lea        ($0014,sp),sp
.L132               addq.l     #1,(-8,a6)                                                               ;16 loops
                    moveq      #16,d2
                    cmp.l      (-8,a6),d2
                    bgt.w      .bgrenderloop
.L131               move.l     (-4,a6),a5
                    move.l     (a5),a0
                    move.l     (_bgptr),(bm_Planes+16,a0)
                    pea        (10).w                                                                   ;set colours
                    pea        (10).w
                    pea        (10).w
                    clr.l      -(sp)
                    move.l     (_viewport),-(sp)
                    jsr        (_SetRGB4)
                    pea        (6).w
                    pea        (6).w
                    pea        (6).w
                    pea        (1).w
                    move.l     (_viewport),-(sp)
                    jsr        (_SetRGB4)
                    pea        (10).w
                    clr.l      -(sp)
                    pea        (10).w
                    pea        ($10).w
                    move.l     (_viewport),-(sp)
                    jsr        (_SetRGB4)
                    pea        (6).w
                    clr.l      -(sp)
                    pea        (6).w
                    pea        ($11).w
                    move.l     (_viewport),-(sp)
                    jsr        (_SetRGB4)
                    clr.l      (a4)
                    move.l     #$80000041,(_fy)
                    moveq      #3,d2
                    move.l     d2,(_y)
                    moveq      #1,d2
                    move.l     d2,(_vx)
                    clr.l      (_vy)
                    clr.l      (_ax)
                    moveq      #1,d2
                    move.l     d2,(_ay)
                    clr.l      (_icount)
                    jsr        (_InitBoing)
                    move.l     #$FFFFFFFF,-(sp)
                    move.l     a3,-(sp)
                    jsr        (_SetAPen)
                    move.l     #_fillpat,(rp_AreaPtrn,a3)
                    move.b     #4,(rp_AreaPtSz,a3)
                    move.b     #$10,(rp_Mask,a3)
                    move.w     #DMAF_RASTER||DMAF_SETCLR,(custom+dmacon)

                    clr.l      (_sstep)
                    lea        ($0058,sp),sp
.mainloop           move.l     (_Window),a2
                    move.l     (wd_UserPort,a2),-(sp)
                    jsr        (_GetMsg)
                    move.l     d0,a0
                    cmp.w      #0,a0
                    addq.l     #4,sp
                    beq.b      .nomsg
.L64                move.l     (im_Class,a0),d2
                    move.w     (im_Code,a0),d3
                    move.l     a0,-(sp)
                    jsr        (_ReplyMsg)
                    move.l     d2,a0
                    addq.l     #4,sp
                    cmp.w      #MOUSEBUTTONS,a0
                    blt.b      .mainloop
                    bgt.b      .L185
                    bra.b      .L62

.L185               cmp.w      #CLOSEWINDOW,a0
                    bne.b      .mainloop
.L63                jsr        (_GoodBye,pc)
.L62                moveq      #SELECTDOWN,d2                                                           ;LMB?
                    cmp.w      d3,d2
                    beq.w      .L60
.L61                moveq      #MENUDOWN,d2                                                             ;RMB?
                    cmp.w      d3,d2
                    bne.b      .mainloop                                                                ;change rates
.L60                tst.l      (_sstep)
                    beq.b      .L59
.L58                clr.l      (_sstep)
                    bra.b      .mainloop

.L59                moveq      #1,d2
                    move.l     d2,(_sstep)
                    bra.b      .mainloop

.nomsg              tst.l      (_sstep)
                    beq.b      .L124
.L126               jsr        (_WaitTOF)                                                               ;sync to vbl
                    tst.l      (_sstept)
                    beq.b      .mainloop
.L125               clr.l      (_sstept)
.L124               tst.l      (_vx)
                    bge.b      .L123
.L122               addq.l     #1,d4
                    bra.b      .L121

.L123               subq.l     #1,d4
.L121               moveq      #-1,d2
                    cmp.l      d4,d2
                    bne.b      .L119
.L120               moveq      #13,d4
.L119               moveq      #14,d2
                    cmp.l      d4,d2
                    bne.b      .L117
.L118               moveq      #0,d4
.L117               moveq      #0,d0
.L116               move.l     d0,d2
                    add.l      d4,d2
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .L115
.L114               move.l     d0,d1
                    add.l      d4,d1
                    addq.l     #2,d1
                    bra.b      .L113

.L115               move.l     d0,d1                                                                    ;poking colortable directly.. again nasty
                    add.l      d4,d1
                    moveq      #12,d2
                    sub.l      d2,d1
.L113               move.l     d1,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     #$0FFF,(a1)
                    move.l     d0,d2
                    add.l      d4,d2
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .L112
.L111               move.l     d0,d1
                    add.l      d4,d1
                    addq.l     #2,d1
                    moveq      #$10,d2
                    add.l      d2,d1
                    bra.b      .L110

.L112               move.l     d0,d1
                    add.l      d4,d1
                    moveq      #12,d2
                    sub.l      d2,d1
                    moveq      #$10,d3
                    add.l      d3,d1
.L110               move.l     d1,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     #$0FFF,(a1)
.L109               addq.l     #1,d0
                    moveq      #7,d2
                    cmp.l      d0,d2
                    bgt.b      .L116
.L108               tst.l      (_vx)
                    bge.b      .L107
.L100               move.l     d4,d2
                    addq.l     #6,d2
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .L99
.L98                move.l     d4,d0
                    addq.l     #6,d0
                    addq.l     #2,d0
                    bra.b      .L97

.L99                move.l     d4,d0
                    addq.l     #6,d0
                    moveq      #12,d2
                    sub.l      d2,d0
.L97                move.l     d0,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     (-10,a6),(a1)
                    move.l     d4,d2
                    addq.l     #6,d2
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .L96
.L95                move.l     d4,d0
                    addq.l     #6,d0
                    addq.l     #2,d0
                    moveq      #$10,d2
                    add.l      d2,d0
                    bra.b      .L94

.L96                move.l     d4,d0
                    addq.l     #6,d0
                    moveq      #12,d2
                    sub.l      d2,d0
                    moveq      #$10,d3
                    add.l      d3,d0
.L94                move.l     d0,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     (-10,a6),(a1)
                    bra.b      .L93

.L107               move.l     d4,d2
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .L106
.L105               move.l     d4,d0
                    addq.l     #2,d0
                    bra.b      .L104

.L106               move.l     d4,d0
                    moveq      #12,d2
                    sub.l      d2,d0
.L104               move.l     d0,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     (-10,a6),(a1)
                    move.l     d4,d2
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .L103
.L102               move.l     d4,d0
                    addq.l     #2,d0
                    moveq      #$10,d2
                    add.l      d2,d0
                    bra.b      .L101

.L103               move.l     d4,d0
                    moveq      #12,d2
                    sub.l      d2,d0
                    moveq      #$10,d3
                    add.l      d3,d0
.L101               move.l     d0,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     (-10,a6),(a1)
.L93                moveq      #7,d0
.L92                move.l     d0,d2
                    add.l      d4,d2
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .L91
.L90                move.l     d0,d1
                    add.l      d4,d1
                    addq.l     #2,d1
                    bra.b      .L89

.L91                move.l     d0,d1
                    add.l      d4,d1
                    moveq      #12,d2
                    sub.l      d2,d1
.L89                move.l     d1,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     #$0F00,(a1)
                    move.l     d0,d2
                    add.l      d4,d2
                    moveq      #14,d3
                    cmp.l      d2,d3
                    ble.b      .L88
.L87                move.l     d0,d1
                    add.l      d4,d1
                    addq.l     #2,d1
                    moveq      #$10,d2
                    add.l      d2,d1
                    bra.b      .L86

.L88                move.l     d0,d1
                    add.l      d4,d1
                    moveq      #12,d2
                    sub.l      d2,d1
                    moveq      #$10,d3
                    add.l      d3,d1
.L86                move.l     d1,d3
                    add.l      d3,d3
                    move.l     d3,a1
                    add.l      (_ct),a1
                    move.w     #$0F00,(a1)
.L85                addq.l     #1,d0
                    moveq      #14,d2
                    cmp.l      d0,d2
                    bgt.b      .L92
.L84                moveq      #10,d1
                    move.l     (_vy),d0
                    jsr        (ldivt)
                    jsr        (fflti)
                    moveq      #0,d1
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    move.l     (_fy),d0
                    moveq      #0,d1
                    jsr        (faddi)
                    move.l     d0,(_fy)
                    clr.l      -(sp)
                    move.l     #$80000040,-(sp)
                    move.l     (_fy),d0
                    moveq      #0,d1
                    jsr        (faddi)
                    jsr        (ffixi)
                    move.l     d0,d3
                    bgt.b      .L82
.L83                move.l     (_fy),d0
                    moveq      #0,d1
                    jsr        (fnegi)
                    move.l     d0,(_fy)
                    move.l     (_vy),d2
                    neg.l      d2
                    move.l     d2,(_vy)
.L82                clr.l      -(sp)
                    move.l     #$C0000047,-(sp)
                    move.l     (_fy),d0
                    moveq      #0,d1
                    jsr        (fcmpi)
                    ble.b      .L78
.L81                move.w     #1,(_boing)
                    move.l     (_fy),d0
                    moveq      #0,d1
                    move.l     d1,-(sp)
                    move.l     d0,-(sp)
                    moveq      #0,d1
                    move.l     #$C0000048,d0
                    jsr        (fsubi)
                    move.l     d0,(_fy)
                    move.l     (_vy),d1
                    move.l     (_dampy),d0
                    jsr        (ldivt)
                    move.l     d0,d3
                    move.l     (_vy),d2
                    neg.l      d2
                    add.l      d2,d3
                    move.l     d3,(_vy)
                    blt.b      .L78
.L80                clr.l      (_vy)
                    move.l     #$80000041,(_fy)
.L78                clr.l      -(sp)
                    move.l     #$80000040,-(sp)
                    move.l     (_fy),d0
                    moveq      #0,d1
                    jsr        (faddi)
                    jsr        (ffixi)
                    move.l     d0,(_y)
                    move.l     (_vx),d2
                    add.l      d2,(a4)
                    move.l     (_ax),d2
                    add.l      d2,(_vx)
                    move.l     (a4),d2
                    cmp.l      (_left),d2
                    bge.b      .L76
.L77                move.w     #2,(_boing)
                    move.l     (_left),d2
                    add.l      d2,d2
                    sub.l      (a4),d2
                    move.l     d2,(a4)
                    move.l     (_vx),d2
                    neg.l      d2
                    move.l     d2,(_vx)
.L76                move.l     (a4),d2
                    cmp.l      (_right),d2
                    ble.b      .L74
.L75                move.w     #3,(_boing)
                    move.l     (_right),d2
                    add.l      d2,d2
                    sub.l      (a4),d2
                    move.l     d2,(a4)
                    move.l     (_vx),d2
                    neg.l      d2
                    move.l     d2,(_vx)
.L74                move.l     (_viewport),a0                                                           ;do the scrolling
                    move.l     (vp_RasInfo,a0),a2
                    clr.w      d2
                    sub.w      (_y_lower),d2
                    move.w     d2,(ri_RyOffset,a2)
                    move.l     (_viewport),a0
                    move.l     (vp_RasInfo,a0),a2
                    move.w     (2,a4),(ri_RxOffset,a2)
                    move.l     (_viewport),a0
                    move.l     (vp_RasInfo,a0),a2
                    move.l     (ri_BitMap,a2),a2
                    move.l     (a4),d3
                    moveq      #15,d2                                                                   ;pick correct background pointer for the amount
                    and.l      d2,d3                                                                    ;of scroll, this way the bg doesn't move along
                    move.w     d3,d2
                    asl.w      #2,d2
                    move.l     #_bgptr,a0
                    move.l     (a0,d2.w),a1
                    move.l     (a4),d2
                    asr.l      #4,d2
                    add.l      d2,d2
                    sub.l      d2,a1
                    move.l     a1,(bm_Planes+16,a2)
                    move.l     (_viewport),a0
                    move.l     (vp_RasInfo,a0),a2
                    move.l     (ri_BitMap,a2),a2
                    moveq      #0,d3
                    sub.l      (_y),d3
                    move.l     (_wact_ras),a0
                    move.l     (rp_BitMap,a0),a0
                    move.l     d3,d2
                    mulu       (bm_BytesPerRow,a0),d3
                    swap       d2
                    mulu       (bm_BytesPerRow,a0),d2
                    swap       d2
                    clr.w      d2
                    add.l      d2,d3
                    move.l     d3,d7
                    sub.l      d7,(bm_Planes+16,a2)
                    move.l     (_ay),d2
                    add.l      d2,(_vy)
                    move.l     (_myScreen),-(sp)
                    jsr        (_MakeScreen)                                                            ;rebuild display, forcing system to rebuild
                    jsr        (_RethinkDisplay)                                                        ;and reload the copper list
                    move.w     (_boing),d2
                    ext.l      d2
                    addq.l     #4,sp
                    exg        d2,a5
                    cmp.w      #1,a5
                    exg        d2,a5
                    blt.w      .L69
                    bgt.b      .L182
                    bra.b      .L73

.L182               exg        d2,a5
                    cmp.w      #2,a5
                    exg        d2,a5
                    bne.b      .L183
                    bra.b      .L72

.L183               exg        d2,a5
                    cmp.w      #3,a5
                    exg        d2,a5
                    bne.w      .L69
                    bra.b      .L71

.L73                move.l     (a4),d3
                    neg.l      d3
                    asl.l      #7,d3
                    move.l     (a4),d2
                    neg.l      d2
                    asl.l      #8,d2
                    add.l      d2,d3
                    move.l     d3,-(sp)
                    move.w     (_bvolume),d2
                    ext.l      d2
                    move.l     d2,-(sp)
                    move.w     (_bperiod),d2
                    ext.l      d2
                    move.l     d2,-(sp)
                    jsr        (_Boing)
                    lea        (12,sp),sp
                    bra.b      .L69

.L72                pea        ($7530).w
                    move.w     (_svolume),d3
                    ext.l      d3
                    move.l     d3,-(sp)
                    move.w     (_speriod),d2
                    ext.l      d2
                    move.l     d2,-(sp)
                    jsr        (_Boing)
                    lea        (12,sp),sp
                    bra.b      .L69

.L71                move.l     #$FFFF8AD0,-(sp)
                    move.w     (_svolume),d3
                    ext.l      d3
                    move.l     d3,-(sp)
                    move.w     (_speriod),d2
                    ext.l      d2
                    move.l     d2,-(sp)
                    jsr        (_Boing)
                    lea        (12,sp),sp
.L69                clr.w      (_boing)
                    tst.w      (_firsttime)
                    beq.w      .mainloop
.L68                moveq      #1,d2
                    move.l     d2,(_sstep)
                    clr.w      (_firsttime)
                    clr.l      -(sp)
                    clr.l      -(sp)
                    pea        ($10).w
                    pea        (1).w
                    pea        (_DotPointer)
                    move.l     (_Window),-(sp)
                    jsr        (_SetPointer)
                    lea        ($0018,sp),sp
                    bra.w      .mainloop


                    SECTION    boing001DA0,DATA,CHIP
graphicslibra__MSG  dc.b       'graphics.library',0,0
intuitionlibr__MSG  dc.b       'intuition.library',0
mathffplibrar__MSG  dc.b       'mathffp.library',0
mathtranslibr__MSG  dc.b       'mathtrans.library',0
topaz__MSG          dc.b       'topaz',0
_wact_ras           dc.l       0
_angoff             dc.l       0
_srad               dc.l       0
_yoff               dc.l       0
_sstep              dc.l       0
_sstept             dc.l       0
_bytesneeded        dc.l       0
_bigbytesgot        dc.l       0
_cm                 dc.l       0
_ct                 dc.l       0
_firsttime          dc.w       0
_myScreen           dc.l       0
_viewport           dc.l       0
_view               dc.l       0
_bitmap             dc.l       0
_mybitmap           dc.w       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
_Window             dc.l       0
_arearas            dc.l       0
_DotPointer         dc.w       0,0,$8000,0,0,0
_left               dc.l       0
_right              dc.l       0
_fillpat            dc.w       $FFFF,$8000,$8000,$8000,$8000,$8000,$8000,$8000,$8000,$8000,$8000
                    dc.w       $8000,$8000,$8000,$8000,$8000
_seed               dc.w       $B807,$C324,$9E87,$32B5,$E509,$57BC
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
_bperiod            dc.w       255
_bvolume            dc.w       63
_speriod            dc.w       160
_svolume            dc.w       40
_boing              dc.w       0
_pattern            dc.w       $AAAA,$5555
_bgptr              dc.l       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
_bckgnd             dc.l       0,0
_areavect           dc.w       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.w       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.w       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                    dc.w       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
_x                  dc.l       0
_y                  dc.w       0
_y_lower            dc.w       0
_vx                 dc.l       0
_vy                 dc.l       0
_ax                 dc.l       0
_ay                 dc.l       0
_dampy              dc.l       0
_fy                 dc.l       0
_vb                 dc.w       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
_icount             dc.l       0
_GfxBase            dc.l       0
_IntuitionBase      dc.l       0
_MathBase           dc.l       0
_MathTransBase      dc.l       0
_bigmem             dc.l       0


                    SECTION    boing0037DC,CODE
_Cosine16           add.w      #$4000,(6,sp)
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


                    SECTION    boing003BE4,CODE
_BeginIO            move.l     (4,sp),a1
                    move.l     a6,-(sp)
                    move.l     (IO_DEVICE,a1),a6
                    jsr        (DEV_BEGINIO,a6)
                    move.l     (sp)+,a6
                    rts

                    dc.w       0


                    SECTION    boing003BF8,CODE
_NewList            move.l     (4,sp),a0
                    move.l     a0,(a0)
                    addq.l     #4,(a0)
                    clr.l      (4,a0)
                    move.l     a0,(8,a0)
                    rts

                    dc.w       0


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


                    SECTION    boing003FB0,CODE
jmp_so              movem.l    d3-d7,-(sp)
                    add.l      (_MathBase),a0
                    jsr        (a0)
                    movem.l    (sp)+,d3-d7
                    rts

jmp_do              movem.l    d3-d7,-(sp)
                    add.l      (_MathBase),a0
                    move.l     ($0018,sp),d1
                    jsr        (a0)
                    movem.l    (sp)+,d3-d7/a0
                    lea        (8,sp),sp
                    jmp        (a0)

ffixi               lea        (_LVOSPFix),a0
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

                    end