;==============================================================================
; src/startup.s -- Lattice C startup module (CLI / Workbench entry boilerplate)
;==============================================================================
; This file is NOT application code. It is the standard Lattice C 5.02 `c.o`
; startup module that prepends every Amiga executable compiled with that
; toolchain. It contains:
;
;   - The binary's entry point (move.l sp,(initialSP) at the top of this file).
;   - The CLI vs Workbench detection idiom: FindTask(NULL) -> Process *,
;     then tst.l pr_CLI(a4) to branch to fromCLI or fromWorkbench.
;   - The fromCLI path: BSTR-walk cli_CommandName, then build an argv-style
;     array by splitting the command tail on whitespace, then call (_main).
;   - The fromWorkbench path: WaitPort + GetMsg on pr_MsgPort for the
;     WBStartup message, save it, and on exit Forbid + ReplyMsg so Workbench
;     can unload the program.
;   - openDOS: open dos.library (required for stdin/stdout/stderr setup).
;   - The shared exit paths (_exit, exit2, exitToDOS, noDOS).
;
; The accompanying DATA section holds startup-only globals (initialSP,
; returnMsg, dosCmdLen, dosCmdBuf, argvArray, argvBuffer, DOSName) and the
; library-base pointers (_SysBase, _DOSBase, _stdin, _stdout, _stderr,
; _errno) that the C runtime consults at runtime.
;
; See AMIGA-KNOWHOW.md section H (dos.library) for the canonical CLI/WB
; startup pattern and the BSTR / BPTR conventions used here.
;
; Original line range in monolithic boing.s: 21..182.
; Public symbols defined: fromCLI, parmExit, fromWorkbench, docons, domain,
;   _exit, exit2, exitToDOS, noDOS, waitmsg, openDOS, VerRev, _SysBase,
;   _DOSBase, _errno, _stdin, _stdout, _stderr, initialSP, returnMsg,
;   dosCmdLen, dosCmdBuf, argvArray, argvBuffer, DOSName.
;==============================================================================

;------------------------------------------------------------------------------
; Program entry point (executed by AmigaDOS when the binary is launched).
;
; On entry (per Amiga loader convention):
;   D0   = length in bytes of the command-line tail (CLI launch only)
;   A0   = pointer to the command-line tail (CLI launch only)
;   SP   = supervisor stack (user mode); initially set up by the OS
;
; The flow below is the classic Lattice C startup. See AMIGA-KNOWHOW.md §H.2
; for the canonical CLI vs Workbench startup pattern.
;------------------------------------------------------------------------------
                    move.l     sp,(initialSP)               ; remember SP so we can RTS back to AmigaDOS
                    move.l     d0,(dosCmdLen)               ; stash D0 = command-tail byte count
                    move.l     a0,(dosCmdBuf)               ; stash A0 = command-tail pointer
                    clr.l      (returnMsg)                  ; no WBStartup yet (CLI default)
                    move.l     (4),a6                       ; A6 = ExecBase (absolute long $4)
                    move.l     a6,(_SysBase)                ; cache it for the C runtime
                    sub.l      a1,a1                        ; A1 = NULL  (FindTask(NULL) = self)
                    jsr        (_LVOFindTask,a6)            ; D0 = struct Process *self
                    move.l     d0,a4                        ; A4 = self  (callee-saved across calls)
                    tst.l      (pr_CLI,a4)                  ; pr_CLI == 0  ?  -> launched by Workbench
                    beq.w      fromWorkbench                ; (CLI launch keeps pr_CLI non-NULL)

;------------------------------------------------------------------------------
; CLI launch path -- parse the command-line tail into a C-style argv[]
;
; The tail is parsed in two phases:
;   1) Copy the program's own name (the BSTR at cli_CommandName) into
;      argvBuffer as argv[0] - a NUL-terminated C string.
;   2) Walk dosCmdBuf splitting on spaces (ASCII $20) to produce
;      argv[1] .. argv[N], writing NUL terminators between tokens.
; Then push (argc, argv) onto the stack and call _main().
;
; Note: the AmigaDOS BCPL pointer convention encodes pointers as byte-offsets
; divided by 4. To convert a BPTR to a CPU pointer you shift left by 2.
; The compiler emits this as TWO consecutive  add.l a0,a0  instructions
; (= shift-left by 1, twice = shift-left by 2 = multiply by 4).
;------------------------------------------------------------------------------
fromCLI             bsr.w      openDOS                      ; open dos.library, cache _DOSBase

                    ; Walk pr_CLI: BPTR -> struct CommandLineInterface *
                    move.l     (pr_CLI,a4),a0               ; A0 = BPTR to CLI struct
                    add.l      a0,a0                        ; \ shift BPTR left by 2
                    add.l      a0,a0                        ; /  -> A0 = CPU pointer to CLI struct
                    move.l     (cli_CommandName,a0),a0      ; A0 = BPTR to program name (BSTR)
                    add.l      a0,a0                        ; \ shift BPTR left by 2
                    add.l      a0,a0                        ; /  -> A0 = CPU pointer to BSTR

                    movem.l    d2/a2/a3,-(sp)               ; preserve callee-saved regs
                    lea        (argvBuffer),a2              ; A2 = argv string buffer cursor
                    lea        (argvArray),a3               ; A3 = argv pointer-array cursor
                    moveq      #1,d2                        ; D2 = argc (start at 1: program name)
                    moveq      #0,d0                        ;
                    move.b     (a0)+,d0                     ; D0 = BSTR length byte (0..255)
                    move.l     a2,(a3)+                     ; argv[0] = current buffer cursor
                    bra.b      1$                           ; jump into the dbra loop

                    ; Copy program-name characters from BSTR (length+chars) into argvBuffer.
2$                  move.b     (a0)+,(a2)+                  ; copy one byte
1$                  dbra       d0,2$                        ; dbra: loop while D0 >= 0
                    clr.b      (a2)+                        ; NUL-terminate argv[0]

                    ; Parse the command tail into argv[1..N]. State machine:
                    ;   3$ = skipping spaces, looking for next token start
                    ;   4$/5$ = inside a token, copying characters
                    ;   6$ = end of token, NUL-terminate and look for next
                    move.l     (dosCmdLen),d0               ; D0 = bytes remaining in tail
                    move.l     (dosCmdBuf),a0               ; A0 = tail cursor
3$                  move.b     (a0)+,d1                     ; read one byte
                    subq.l     #1,d0                        ; -- remaining count
                    ble.b      parmExit                     ; end of tail -> done
                    cmp.b      #$20,d1                      ; is it space-or-below ?
                    ble.b      3$                           ; yes: skip whitespace
                    addq.l     #1,d2                        ; non-space: new argv entry
                    move.l     a2,(a3)+                     ; argv[D2-1] = current buffer pos
                    bra.b      5$                           ; first char already in D1

                    ; Inside-token loop.
4$                  move.b     (a0)+,d1                     ; next byte
                    subq.l     #1,d0                        ;
                    cmp.b      #$20,d1                      ;
                    ble.b      6$                           ; space -> end of token
5$                  move.b     d1,(a2)+                     ; copy char into buffer
                    bra.b      4$

6$                  clr.b      (a2)+                        ; NUL-terminate this argv string
                    bra.b      3$                           ; resume looking for next token

;------------------------------------------------------------------------------
; CLI exit: call (argc, argv) C main, set up stdin/stdout/stderr, then RTS.
;------------------------------------------------------------------------------
parmExit            clr.b      (a2)+                        ; NUL-terminate final string
                    clr.l      (a3)+                        ; NULL-terminate argv pointer array
                    move.l     d2,d0                        ; D0 = argc
                    movem.l    (sp)+,d2/a2/a3               ; restore callee-saved
                    pea        (argvArray)                  ; push argv
                    move.l     d0,-(sp)                     ; push argc
                    jsr        (_Input)                     ; D0 = stdin file handle (BPTR)
                    move.l     d0,(_stdin)
                    jsr        (_Output)                    ; D0 = stdout
                    move.l     d0,(_stdout)
                    move.l     d0,(_stderr)                 ; stderr -> stdout (no separate handle)
                    jsr        (_main)                      ; <<< call into the application
                    moveq      #0,d0                        ; return code 0
                    move.l     (initialSP),sp               ; restore initial SP
                    rts                                     ; return to AmigaDOS

;------------------------------------------------------------------------------
; Workbench launch path. pr_CLI is NULL; a WBStartup message is sitting in
; pr_MsgPort waiting to be retrieved. We:
;   1) Open dos.library (still required).
;   2) WaitPort + GetMsg to retrieve the WBStartup message; cache in returnMsg
;      so the exit path can ReplyMsg back.
;   3) If wb_sm_ArgList is non-NULL, CurrentDir() to the first argument's lock
;      so the program runs in the directory of its icon.
;   4) If wb_sm_ToolWindow is non-NULL, Open() it as our console (stdout etc).
;   5) Call _main with NO argv (Workbench-launched programs see argc=0).
;------------------------------------------------------------------------------
fromWorkbench       bsr.w      openDOS                      ; open dos.library
                    bsr.w      waitmsg                      ; D0 = WBStartup message *
                    move.l     d0,(returnMsg)               ; remember for ReplyMsg at exit
                    clr.l      -(sp)                        ; push NULL argv
                    move.l     d0,-(sp)                     ; push WBStartup as argc/argv (C-side
                                                            ;   sees argv=WBStartup when argc=0)
                    move.l     d0,a2                        ; A2 = WBStartup *
                    move.l     ($0024,a2),d0                ; sm_ArgList (WBArg *)
                    beq.b      docons                       ; none -> skip CurrentDir
                    move.l     (_DOSBase),a6                ; A6 = _DOSBase for library call
                    move.l     d0,a0
                    move.l     (0,a0),d1                    ; D1 = wa_Lock of first WBArg
                    jsr        (_LVOCurrentDir,a6)          ; set CD to the icon's directory
docons              move.l     ($0020,a2),d1                ; sm_ToolWindow ("CON:..." or similar)
                    beq.b      domain                       ; none -> proceed without console
                    move.l     #MODE_OLDFILE,d2
                    jsr        (_LVOOpen,a6)                ; open the tool window as a file
                    move.l     d0,(_stdin)
                    move.l     d0,(_stdout)
                    move.l     d0,(_stderr)
                    beq.b      domain                       ; open failed -> proceed anyway
                    lsl.l      #2,d0                        ; BPTR -> CPU ptr
                    move.l     d0,a0
                    move.l     (fh_Type,a0),(pr_ConsoleTask,a4)  ; route console writes correctly
domain              jsr        (_main)                      ; <<< call into the application
                    moveq      #0,d0                        ; return code 0
                    bra.b      exit2                        ; fall through to clean-exit path

;------------------------------------------------------------------------------
; Exit paths. _exit(code) is callable from C; exit2 is the shared tail.
;
; CLI exit just CloseLibrary(dos) and RTS.
; WB exit additionally Forbid()s and ReplyMsg()s the saved WBStartup so
; Workbench can unload us cleanly (see AMIGA-KNOWHOW.md §H.4 - the Forbid is
; mandatory: without it, a task switch between ReplyMsg and RTS could unload
; this code mid-instruction).
;------------------------------------------------------------------------------
_exit               move.l     (4,sp),d0                    ; D0 = exit code from C caller
exit2               move.l     (initialSP),sp               ; restore original SP
                    move.l     d0,-(sp)                     ; save exit code across cleanup
                    move.l     (4),a6                       ; A6 = ExecBase
                    move.l     (_DOSBase),d0                ; close dos.library if opened
                    beq.b      1$
                    move.l     d0,a1
1$                  jsr        (_LVOCloseLibrary,a6)
                    tst.l      (returnMsg)                  ; were we launched from Workbench?
                    beq.b      exitToDOS                    ; no: just return to DOS
                    jsr        (_LVOForbid,a6)              ; lock task scheduler before ReplyMsg
                    move.l     (returnMsg),a1
                    jsr        (_LVOReplyMsg,a6)            ; tell WB we're done; safe to unload
exitToDOS           move.l     (sp)+,d0                     ; restore exit code
                    rts                                     ; return to AmigaDOS

;------------------------------------------------------------------------------
; noDOS - emergency exit if OpenLibrary("dos.library") failed.
; Calls exec.Alert() with a recoverable "can't open dos.library" code. Most
; systems will never hit this since dos.library is always resident.
;------------------------------------------------------------------------------
noDOS               movem.l    d7/a5/a6,-(sp)
                    move.l     #(AT_Recovery|AG_OpenLib|AO_DOSLib),d7  ; alert number
                    move.l     (4).w,a6                     ; A6 = ExecBase
                    jsr        (_LVOAlert,a6)               ; show flashing-red alert
                    movem.l    (sp)+,d7/a5/a6
                    moveq      #100,d0                      ; exit code 100 (failure)
                    bra.b      exit2

;------------------------------------------------------------------------------
; waitmsg - WaitPort(pr_MsgPort) then GetMsg() to retrieve the WBStartup.
; Returns D0 = first message in our process's port. Used by the WB launch path.
;------------------------------------------------------------------------------
waitmsg             lea        (pr_MsgPort,a4),a0
                    jsr        (_LVOWaitPort,a6)            ; block until a message arrives
                    lea        (pr_MsgPort,a4),a0
                    jsr        (_LVOGetMsg,a6)              ; D0 = the message
                    rts

;------------------------------------------------------------------------------
; openDOS - cache _DOSBase = OpenLibrary("dos.library", 30). The version 30
; requirement implies Kickstart 1.2 or later. On failure, branch to noDOS.
;------------------------------------------------------------------------------
openDOS             clr.l      (_DOSBase)                   ; default to NULL in case open fails
                    lea        (DOSName),a1                 ; "dos.library"
                    move.l     #30,d0                       ; minimum version
                    jsr        (_LVOOpenLibrary,a6)         ; D0 = library base or NULL
                    move.l     d0,(_DOSBase)
                    beq.b      noDOS                        ; NULL -> emergency exit
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


