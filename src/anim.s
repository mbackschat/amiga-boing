;==============================================================================
; src/anim.s -- Animation lifecycle and audio.device sample management
;==============================================================================
; Four routines plus the audio sample DATA section:
;
;   _Boing         -- The animation frame routine. Invoked from _main's main
;                     loop. Drives one frame of palette manipulation, screen
;                     refresh, and audio triggering. Contains the single
;                     surgical DMACON write in the demo (note: that write is
;                     actually in _main; this file handles the higher-level
;                     audio plumbing).
;
;   _initCleanup   -- Rollback helper used by _InitBoing. If allocation fails
;                     midway through audio-device setup, this function tears
;                     down whatever has already been allocated and returns to
;                     the caller. It is the "exception unwind" for the
;                     audio-init code path.
;
;   _InitBoing     -- Thin trampoline that calls _initCleanup(1) (which is the
;                     "initial allocation" code path; _initCleanup serves
;                     double duty as both init and rollback).
;
;   _CleanUp       -- Audio-channel teardown: deallocates audio.device
;                     channels and frees the sample buffer. Called from
;                     _GoodBye.
;
; The DATA,CHIP section that follows holds the audio.device IORequest and
; the loaded sample buffers (boing.samples). Everything in this section must
; be in chip RAM because Paula DMAs the samples directly from it.
;
; See AMIGA-KNOWHOW.md section F (Paula audio) and section L (audio.device)
; for the underlying chipset and device-driver references.
;
; Original line range in monolithic boing.s: 183..599.
; Public symbols defined: _Boing, _initCleanup, _InitBoing, _CleanUp,
;   plus audio data (boingsamples__MSG, PROGRAM_NAME__MSG, audiodevice__MSG,
;   _sound, _silent, _samples, _audioPort, _allocReq, _allocMap, _leftRight,
;   _sampleLength, _silentLength, _extraSamples, _maxDelay, _maxCCDelay,
;   _key, _freeList).
;==============================================================================

                    SECTION    boing00037C,CODE

;==============================================================================
; _Boing(period, volume, balance) - play the bounce sample.
;
; Called from _main's .audio_floor / .audio_left / .audio_right dispatch
; (audio trigger for floor / left-wall / right-wall bounce).
;
; Stack args (C calling convention):
;     +8   long  period   - Paula PER value (low pitch = higher PER)
;     +12  long  volume   - 0..63 in low byte
;     +16  long  balance  - signed; sign indicates pan direction,
;                           magnitude scales the "louder" side's volume
;
; Strategy: ALLOCATE channel mask via ADCMD_ALLOCATE (per-impact, not held
; long-term - this lets other audio-producing tasks compete), play the
; sample on TWO channels (one left, one right) with different volumes to
; produce stereo balance, then CMD_START both channels SIMULTANEOUSLY so
; the two halves of the sample play in phase.
;
; The "extra samples" / silent-prefix trick:
;   To make the impact appear to come from one side, we don't just lower
;   the volume on the other side - we also DELAY it by a few samples. The
;   demo loads boing.samples + 256 bytes of preceding silence, then for the
;   delayed channel sets ioa_Data = _samples - N (pointing N samples BEFORE
;   the real start, into the silence). When that channel plays, the first
;   N samples are silence; the real waveform arrives N samples late.
;   That delay produces an inter-aural time difference - a stronger spatial
;   cue than volume alone.
;==============================================================================
_Boing              link       a6,#-6                       ; locals: -2..-6 (just one word at -4)
                    movem.l    d2-d6/a2-a5,-(sp)
.entry                move.w     (10,a6),d6                   ; D6 = period       (arg +8 low word)
                    move.b     (15,a6),d5                   ; D5 = volume       (arg +12 low byte)
                    move.w     ($0012,a6),d4                ; D4 = balance hi-word (arg +16 hi-word)
                    move.l     #_allocReq,a2                ; A2 -> &_allocReq (= &IOAudio*)
                    move.l     #_DoIO,a4                    ; A4 = &_DoIO (cached for speed)
                    move.l     #_extraSamples,(-4,a6)       ; local -4 = &_extraSamples
.check_sound                tst.b      (_sound)                     ; sound init was successful?
                    beq.w      .boing_exit                          ; no -> just return silently

;------------------------------------------------------------------------------
; Drain the audio reply port: any messages sitting there are completed I/O
; requests from previous _Boing calls. Move each one off the port and onto
; _freeList for reuse. We also issue ADCMD_FREE for any completed CMD_WRITE
; requests so the channel allocation is released back to the OS.
;
; Critical-section: Disable/Enable around Remove because the audio.device
; interrupt could otherwise add to the port mid-removal.
;------------------------------------------------------------------------------
.drain_replies                move.l     (_audioPort),a0              ;check if list is empty
                    lea        (MP_MSGLIST+LH_TAIL,a0),a1
                    move.l     a1,d2                        ; D2 = &MsgList.lh_Tail (sentinel)
                    move.l     (_audioPort),a0
                    move.l     (MP_MSGLIST,a0),d3
                    move.l     d3,a3                        ; A3 = first message
                    cmp.l      d3,d2
                    beq.b      .alloc_channels                         ; list empty -> proceed to allocate
.remove_msg                 jsr        (_Disable)                   ;remove the message
                    move.l     a3,-(sp)
                    jsr        (_Remove)
                    jsr        (_Enable)
                    moveq      #CMD_WRITE,d2                ;was it write?
                    cmp.w      (IOAudio+IO_COMMAND,a3),d2
                    addq.l     #4,sp
                    bne.b      .recycle_ioa                          ; not CMD_WRITE -> just recycle
.free_channel                 move.w     #ADCMD_FREE,(IOAudio+IO_COMMAND,a3)
                    move.l     a3,-(sp)
                    jsr        (a4)                         ; DoIO(ADCMD_FREE) - release the channel
                    addq.l     #4,sp
.recycle_ioa                 move.l     a3,-(sp)
                    pea        (_freeList)
                    jsr        (_AddTail)                   ; recycle onto _freeList
                    addq.l     #8,sp
                    bra.b      .drain_replies                         ; loop until port drained

;------------------------------------------------------------------------------
; Allocate audio channels. _allocReq points to the master IOAudio whose
; ioa_Data was already set up by _initCleanup to &_allocMap[]:
;   _allocMap = $03050A0C => four channel-mask candidates:
;     $03 = ch0+ch1   (one stereo pair)
;     $05 = ch0+ch2
;     $0A = ch1+ch3
;     $0C = ch2+ch3
; ioa_Length = 4 (number of candidates). audio.device picks the first one
; available and returns it in io_Unit.
;
; LN_PRI = -10 (= $F6 as signed byte). Polite low-priority allocation;
; any other audio task can preempt us.
; IO_FLAGS = $41 = IOF_QUICK | ADIOF_NOWAIT.
;------------------------------------------------------------------------------
.alloc_channels                move.l     (a2),a0                      ;alloc audio channels
                    move.b     #$F6,(IOAudio+MN+LN_PRI,a0)  ; allocation priority = -10
                    move.l     (a2),a0
                    move.w     #ADCMD_ALLOCATE,(IOAudio+IO_COMMAND,a0)
                    move.l     (a2),a0
                    move.b     #$41,(IOAudio+IO_FLAGS,a0)   ; IOF_QUICK | ADIOF_NOWAIT
                    move.l     (a2),a0
                    clr.w      (ioa_AllocKey,a0)
                    move.l     (a2),-(sp)
                    jsr        (_BeginIO)
                    move.l     (a2),-(sp)
                    jsr        (_WaitIO)
                    tst.l      d0                           ; allocation failed?
                    addq.l     #8,sp
                    bne.w      .boing_exit                          ; yes -> bail, ball still bounces silently
;------------------------------------------------------------------------------
; Inspect IO_UNIT (the granted channel mask) and record the AllocKey for
; each channel bit set, in _key[0..3]. Used later by _initCleanup at exit
; to ADCMD_FREE the right channels.
;------------------------------------------------------------------------------
.save_keys_init                clr.w      (-6,a6)                      ; loop counter 0..3
.save_keys_loop                move.l     (a2),a0
                    moveq      #0,d2
                    move.b     (IOAudio+IO_UNIT+3,a0),d2    ;what did we get?  (low byte of unit mask)
                    moveq      #1,d0
                    move.b     (-5,a6),d1                   ; D1 = counter (channel index 0..3)
                    asl.l      d1,d0                        ; D0 = 1 << channel
                    and.l      d0,d2
                    beq.b      .next_key                         ; bit not set -> skip
.save_key                move.w     (-6,a6),d0
                    add.w      d0,d0                        ; D0 = index*2 (word stride)
                    move.l     #_key,a0
                    move.l     (a2),a1
                    move.w     (ioa_AllocKey,a1),(a0,d0.w)  ; _key[index] = ioa_AllocKey
.next_key                addq.w     #1,(-6,a6)
                    moveq      #4,d2
                    cmp.w      (-6,a6),d2
                    bgt.b      .save_keys_loop

;------------------------------------------------------------------------------
; Set audio precedence (priority) = -(period/16) so longer-period (lower-
; pitch) sounds win arbitration over higher-pitch ones. Then CMD_STOP both
; channels so we can queue up two synchronized CMD_WRITEs.
;------------------------------------------------------------------------------
.setprec_and_stop                move.l     (a2),a0
                    moveq      #0,d2
                    move.w     d6,d2                        ; D2 = period
                    neg.l      d2
                    lsr.l      #4,d2                        ; D2 = -period/16
                    move.b     d2,(9,a0)                    ; ln_Pri = -period/16
                    move.l     (a2),a0
                    move.w     #ADCMD_SETPREC,(IOAudio+IO_COMMAND,a0)
                    move.l     (a2),-(sp)
                    jsr        (a4)                         ; DoIO(ADCMD_SETPREC)
                    move.l     (a2),a0
                    move.w     #CMD_STOP,(IOAudio+IO_COMMAND,a0)
                    move.l     (a2),-(sp)
                    jsr        (a4)                         ; DoIO(CMD_STOP) - pause both channels
                    clr.w      (-6,a6)                      ; counter = 0 (loop over 2 voices below)
                    addq.l     #8,sp
;------------------------------------------------------------------------------
; .voice_loop - Voice setup loop. Repeats twice (once per stereo channel).
; First either pulls a recycled IOAudio from _freeList, or AllocMems a new
; one (rare path - only the first call ever takes this branch since the
; recycled list grows after the first cleanup of completed I/O).
;------------------------------------------------------------------------------
.voice_loop                move.l     #lbL00090E,d2                ; D2 = list-sentinel address
                    move.l     (_freeList),d3
                    move.l     d3,a3                        ; A3 = head of free list
                    cmp.l      d3,d2
                    beq.b      .alloc_new_ioa                         ; list empty -> AllocMem path
.got_recycled_ioa                move.l     a3,-(sp)
                    jsr        (_Remove)                    ; unlink from _freeList
                    addq.l     #4,sp
                    bra.b      .voice_pick_side                         ; got a recycled IOAudio in A3

.alloc_new_ioa                ; cold path: allocate a new IOAudio
                    move.l     #(MEMF_PUBLIC|MEMF_CLEAR),-(sp)
                    pea        (ioa_SIZEOF).w
                    jsr        (_AllocMem)
                    move.l     d0,a3
                    cmp.w      #0,a3
                    addq.l     #8,sp
                    bne.b      .init_new_ioa                         ; alloc OK
.oom_cleanup                jsr        (_CleanUp)                   ; OOM -> tear down audio entirely
                    bra.w      .boing_exit

.init_new_ioa                ; copy reply port + device from the master IOAudio
                    move.l     (a2),a0
                    move.l     (IOAudio+MN_REPLYPORT,a0),(IOAudio+MN_REPLYPORT,a3)
                    move.l     (a2),a0
                    move.l     (IOAudio+IO_DEVICE,a0),(IOAudio+IO_DEVICE,a3)
                    move.w     #1,(ioa_Cycles,a3)           ; play once (no loop)

;------------------------------------------------------------------------------
; .voice_pick_side - decide which channel side (left or right) this voice plays on.
;
; _leftRight (DATA section) = $0609 i.e. two bytes [$06, $09]:
;     index 0 -> $06 = ch1|ch2 (the "one side" pair of channels)
;     index 1 -> $09 = ch0|ch3 (the "other side" pair)
;
; (-6,a6) is the voice counter; when 0 we're on the first voice. The slt/sge
; tricks below compute (balance < 0) or (balance > 0) and use the boolean as
; an index into _leftRight, so positive balance picks one side and negative
; the other.
;
; The AND with IO_UNIT of the master allocReq restricts us to channels we
; actually got granted - in case audio.device gave us a non-stereo mask.
;------------------------------------------------------------------------------
.voice_pick_side                tst.w      (-6,a6)                      ; voice 0 or 1?
                    beq.w      .voice0_lead                         ; voice 0 -> the "delayed" side
;------------------------------------------------------------------------------
; .voice1_delayed - VOICE 1: the "delayed/softer" side. Compute the inter-aural time
; delay in samples = (balance * maxCCDelay) / (period * 32768), and offset
; ioa_Data BACKWARD into the silent prefix of the buffer. Volume is reduced
; proportionally to |balance|: vol_out = vol * (54613 - balance) / 54613.
; (54613 is the max balance magnitude; volume falls linearly to 0 there.)
;------------------------------------------------------------------------------
.voice1_delayed                moveq      #0,d0
                    tst.w      d4                           ; balance >= 0 ?
                    sge        d0                           ; D0 = (balance>=0) ? -1 : 0
                    neg.b      d0                           ; D0 = (balance>=0) ? 1 : 0
                    move.l     #_leftRight,a0
                    moveq      #0,d2
                    move.b     (a0,d0.l),d2                 ; pick $06 or $09 channel mask
                    move.l     (a2),a1
                    and.l      (IOAudio+IO_UNIT,a1),d2      ; mask with what we allocated
                    move.l     d2,(IOAudio+IO_UNIT,a3)      ; voice's unit = chosen side
                    tst.w      d4
                    bge.b      .compute_delay
.bal_abs                move.w     d4,d0                        ; |balance|
                    ext.l      d0
                    neg.l      d0
                    move.w     d0,d4
.compute_delay                move.w     d4,d1                        ; D1 = |balance|
                    move.l     (_maxCCDelay),d0
                    divu       d6,d0                        ; D0 = maxCCDelay / period
                    mulu       d0,d1                        ; D1 = |balance| * (maxCCDelay/period)
                    move.l     d1,d3
                    moveq      #15,d0
                    lsr.l      d0,d3                        ; D3 = D1 >> 15 = sample delay
                    move.w     d3,d0
                    move.l     (-4,a6),a5
                    move.w     d0,(a5)                      ; _extraSamples = delay count
                    move.l     (_samples),d2
                    moveq      #0,d3
                    move.l     (-4,a6),a5
                    move.w     (a5),d3
                    sub.l      d3,d2                        ; D2 = _samples - delay (point into silence)
                    move.l     d2,(ioa_Data,a3)
                    moveq      #0,d2
                    move.l     (-4,a6),a5
                    move.w     (a5),d2
                    add.l      (_sampleLength),d2           ; length = real + delay padding
                    move.l     d2,(ioa_Length,a3)
                    move.w     #54613,d0
                    sub.w      d4,d0
                    moveq      #0,d1
                    move.b     d5,d1
                    mulu       d1,d0
                    divu       #54613,d0                    ; D0 = vol * (54613 - |bal|) / 54613
                    move.w     d0,(ioa_Volume,a3)           ; reduced volume on this side
                    bra.b      .queue_write

;------------------------------------------------------------------------------
; .voice0_lead - VOICE 0: the "lead/full" side. Plays the sample at full volume from
; its real start (no leading silence). Channel mask uses the OPPOSITE side
; of _leftRight from voice 1.
;------------------------------------------------------------------------------
.voice0_lead                moveq      #0,d0
                    tst.w      d4
                    slt        d0                           ; D0 = (balance<0) ? -1 : 0
                    neg.b      d0                           ; D0 = (balance<0) ? 1 : 0
                    move.l     #_leftRight,a0
                    moveq      #0,d2
                    move.b     (a0,d0.l),d2
                    move.l     (a2),a1
                    and.l      (IOAudio+IO_UNIT,a1),d2
                    move.l     d2,(IOAudio+IO_UNIT,a3)
                    move.l     (_samples),(ioa_Data,a3)     ; real sample start
                    move.l     (_sampleLength),(ioa_Length,a3)
                    moveq      #0,d0
                    move.b     d5,d0
                    move.w     d0,(ioa_Volume,a3)           ; full volume

;------------------------------------------------------------------------------
; .queue_write - common tail: set command = CMD_WRITE ($3), flags = ADIOF_PERVOL
; (apply period/volume on start), copy period and AllocKey, BeginIO.
; Channel will be queued (not yet playing - CMD_STOP earlier paused it).
;------------------------------------------------------------------------------
.queue_write                 move.w     #3,(IOAudio+IO_COMMAND,a3)   ; CMD_WRITE
                    move.b     #ADIOF_PERVOL,(IOAudio+IO_FLAGS,a3)
                    move.w     d6,(ioa_Period,a3)
                    move.l     (a2),a0
                    move.w     (ioa_AllocKey,a0),(ioa_AllocKey,a3)
                    move.l     a3,-(sp)
                    jsr        (_BeginIO)                   ; queue this voice's write
                    addq.l     #4,sp
.next_voice                 addq.w     #1,(-6,a6)
                    moveq      #2,d2
                    cmp.w      (-6,a6),d2
                    bgt.w      .voice_loop                         ; loop for second voice

;------------------------------------------------------------------------------
; Both voices queued - now issue CMD_START on the master to unpause both
; channels simultaneously. The two writes start playing in sync, producing
; the stereo effect.
;------------------------------------------------------------------------------
.start_audio                 move.l     (a2),a0                      ;start audio!
                    move.w     #CMD_START,(IOAudio+IO_COMMAND,a0)
                    move.l     (a2),-(sp)
                    jsr        (a4)                         ; DoIO(CMD_START)
                    addq.l     #4,sp
.boing_exit                 movem.l    (sp)+,d2-d6/a2-a5
                    unlk       a6
                    rts

;==============================================================================
; _initCleanup(do_init) - dual-purpose init/teardown for the audio subsystem.
;
; Argument:
;     do_init == 1  ->  set up everything (called from _InitBoing).
;     do_init == 0  ->  tear everything down (called from _CleanUp).
;
; Init path (.init_compute_delay ... .ic_exit):
;   1. Compute _maxCCDelay = _maxDelay * 3580 (the per-sample delay in
;      Paula color-clock units for the maximum balance shift).
;   2. _silentLength = (_maxCCDelay / 100) & ~1  - the number of silent
;      bytes to prepend to the sample buffer for the stereo delay trick.
;   3. Lock("boing.samples", READ) + AllocMem(FileInfoBlock) + Examine
;      to discover the file size, then AllocMem the sample buffer in
;      CHIP RAM (must be DMA-able by Paula).
;   4. Open + Read the file: 2 bytes header (must equal 2), then the
;      remaining bytes are the raw 8-bit signed PCM sample.
;   5. CreatePort(_audioPort) for audio.device reply messages.
;   6. AllocMem(IOAudio struct) -> _allocReq, fill in alloc map (= 4-byte
;      channel-preference list at _allocMap), OpenDevice("audio.device").
;   7. Set _sound = 1 to indicate "audio works".
;
; Cleanup path (.teardown_loop ... .ic_exit):
;   1. For each of 4 channels: send ADCMD_FREE with the saved _key[i]
;      AllocKey, then CloseDevice on the IOAudio.
;   2. FreeMem every IOAudio on _freeList; DeletePort the audio port.
;   3. FreeMem _silent (sample + silence buffer).
;==============================================================================
_initCleanup        link       a6,#-2                       ; local: -2 = "init succeeded so far" flag
                    movem.l    d2-d5/a2-a5,-(sp)
.ic_entry                move.l     (8,a6),d0                    ; D0 = do_init
                    clr.w      (-2,a6)
                    move.l     #_allocReq,a2                ; A2 -> &_allocReq
                    move.l     #_audioPort,a3               ; A3 -> &_audioPort
                    move.l     #_silentLength,a4            ; A4 -> &_silentLength
.ic_dispatch                tst.l      d0
                    beq.w      .teardown_loop                         ; do_init == 0 -> teardown path

;------------------------------------------------------------------------------
; Init path begins here. Compute the stereo-delay parameters first.
;
; The Paula color clock is ~3.579545 MHz NTSC (or 3.546895 PAL); the demo
; assumes NTSC for the constant 3580. _maxDelay (= 10) is in some demo-
; specific unit; _maxCCDelay = _maxDelay * 3580 measures the delay in
; color-clock units that audio.device understands.
;
; The audio.device's stereo balance is implemented by playing the OTHER
; channel from a sample buffer that starts a few bytes EARLIER (in the
; silent prefix). Those few bytes are pure silence (0x00 = signed zero),
; so the OTHER channel starts producing the actual waveform a few samples
; later than the LEAD channel - phase-shifted in time, the way real-world
; stereo works through the speed-of-sound difference between speaker and
; ear.
;------------------------------------------------------------------------------
.init_compute_delay                moveq      #0,d2
                    move.w     (_maxDelay),d2               ; _maxDelay = 10 (DATA section default)
                    muls       #3580,d2                     ; D2 = 10 * 3580 = 35800 cc per max-delay
                    move.l     d2,(_maxCCDelay)
                    move.l     d2,d3
                    divu       #100,d3                      ; D3 = 358  (silence bytes)
                    move.w     d3,d2
                    and.w      #$FFFE,d2                    ; round to even (word alignment)
                    move.w     d2,(a4)                      ; _silentLength = 358 (rounded)

                    ; --- Lock("boing.samples", ACCESS_READ) ---
                    move.l     #$FFFFFFFE,-(sp)             ; ACCESS_READ = -2
                    pea        (boingsamples__MSG)
                    jsr        (_Lock)
                    move.l     d0,d5                        ; D5 = file lock (BPTR)
                    addq.l     #8,sp
                    beq.w      .init_check_loaded                         ; lock failed -> fall through to teardown
.init_alloc_fib                ; --- AllocMem(FileInfoBlock) so we can call Examine() ---
                    move.l     #MEMF_CLEAR,-(sp)
                    pea        (fib_SIZEOF).w
                    jsr        (_AllocMem)
                    move.l     d0,d4                        ; D4 = FileInfoBlock *
                    addq.l     #8,sp
                    beq.w      .init_unlock
.init_examine                ; --- Examine(lock, fib) to discover file size ---
                    move.l     d4,-(sp)
                    move.l     d5,-(sp)
                    jsr        (_Examine)
                    tst.l      d0
                    addq.l     #8,sp
                    beq.w      .init_free_fib
.init_alloc_samples                ; --- AllocMem(silentLength + (fib_Size-2), MEMF_CHIP|MEMF_CLEAR) ---
                    ; The buffer layout is:
                    ;   _silent  -> [silence bytes...][actual sample bytes...]
                    ;   _samples -> _silent + silentLength (= start of real audio)
                    ; MEMF_CHIP is mandatory: Paula DMAs directly from this buffer.
                    move.l     #(MEMF_CHIP|MEMF_CLEAR),-(sp)
                    moveq      #0,d2
                    move.w     (a4),d2                      ; D2 = silentLength
                    move.l     d4,a5
                    move.l     (fib_Size,a5),d3
                    subq.l     #2,d3                        ; D3 = fib_Size - 2 (skip 2-byte header)
                    move.l     d3,(_sampleLength)           ; cache for later
                    add.l      d3,d2                        ; total = silence + sample
                    move.l     d2,-(sp)
                    jsr        (_AllocMem)
                    move.l     d0,(_silent)                 ; head of buffer (silence region)
                    addq.l     #8,sp
                    beq.b      .init_free_fib
.init_open_file                ; --- Open("boing.samples", MODE_OLDFILE) ---
                    pea        (MODE_OLDFILE).w
                    pea        (boingsamples__MSG0)
                    jsr        (_Open)
                    move.l     d0,d3                        ; D3 = file handle
                    addq.l     #8,sp
                    beq.b      .init_free_fib
.init_read_data                ; --- Read 2-byte header into local -(2,a6) ---
                    pea        (2).w
                    pea        (-2,a6)
                    move.l     d3,-(sp)
                    jsr        (_Read)
                    ; --- Read sampleLength bytes into (_silent + silentLength) ---
                    move.l     (_sampleLength),-(sp)
                    moveq      #0,d2
                    move.w     (a4),d2                      ; offset = silentLength
                    add.l      (_silent),d2                 ; D2 = &buffer[silentLength]
                    move.l     d2,(_samples)                ; cache _samples = start of audio
                    move.l     d2,-(sp)
                    move.l     d3,-(sp)
                    jsr        (_Read)
                    move.l     d3,-(sp)
                    jsr        (_Close)
                    moveq      #2,d2
                    cmp.w      (-2,a6),d2                   ; header magic check: must be 2
                    lea        ($001C,sp),sp
                    bne.w      .init_free_fib
.init_free_fib                ; --- FreeMem the FileInfoBlock, UnLock the file ---
                    pea        (fib_SIZEOF).w
                    move.l     d4,-(sp)
                    jsr        (_FreeMem)
                    addq.l     #8,sp
.init_unlock                move.l     d5,-(sp)
                    jsr        (_UnLock)
                    addq.l     #4,sp
.init_check_loaded                moveq      #2,d2
                    cmp.w      (-2,a6),d2                   ; sample-loaded-OK flag was set?
                    bne.w      .teardown_check_silent                         ; no -> skip audio.device setup
;------------------------------------------------------------------------------
; Audio sample loaded successfully. Now build the message port + IOAudio
; allocation request + OpenDevice("audio.device").
;------------------------------------------------------------------------------
.init_create_port                clr.l      -(sp)
                    pea        (PROGRAM_NAME__MSG)
                    jsr        (_CreatePort)                ; signal-allocating MsgPort
                    move.l     d0,(a3)                      ; _audioPort = port
                    addq.l     #8,sp
                    beq.w      .teardown_check_silent
.init_alloc_ioa                move.l     #(MEMF_PUBLIC|MEMF_CLEAR),-(sp)
                    pea        (ioa_SIZEOF).w
                    jsr        (_AllocMem)
                    move.l     d0,(a2)                      ; _allocReq = IOAudio struct
                    addq.l     #8,sp
                    beq.w      .teardown_delete_port
.init_open_device                pea        (_freeList)
                    jsr        (_NewList)                   ; init _freeList as empty Exec list
                    ; --- OpenDevice("audio.device", 0, _allocReq, 0) ---
                    clr.l      -(sp)
                    move.l     (a2),-(sp)
                    clr.l      -(sp)
                    pea        (audiodevice__MSG)
                    jsr        (_OpenDevice)
                    tst.l      d0
                    lea        ($0014,sp),sp
                    bne.w      .teardown_recycle_master                         ; open failed -> teardown
.init_fill_master_ioa                ; Fill in the master IOAudio with reply port, channel-mask list,
                    ; "play once" cycle. _allocMap = $03050A0C - the 4 candidate
                    ; stereo channel masks (see _Boing's allocation comment for the
                    ; bit layout).
                    move.l     (a2),a0
                    move.l     (a3),(IOAudio+MN_REPLYPORT,a0)
                    move.l     (a2),a0
                    move.l     #_allocMap,(ioa_Data,a0)
                    move.l     (a2),a0
                    moveq      #4,d2
                    move.l     d2,(ioa_Length,a0)           ; 4 candidate masks
                    move.l     (a2),a0
                    move.w     #1,(ioa_Cycles,a0)           ; play sample once (no loop)
                    move.b     #1,(_sound)                  ; audio is ready
                    bra.w      .ic_exit

;------------------------------------------------------------------------------
; .teardown_loop - TEARDOWN PATH. For each of 4 audio channels, send ADCMD_FREE with
; the AllocKey we saved during _Boing's allocation. Then CloseDevice on the
; master IOAudio, FreeMem every IOAudio sitting on _freeList, DeletePort
; the reply port, FreeMem the sample buffer, clear _sound.
;------------------------------------------------------------------------------
.teardown_loop                moveq      #0,d4                        ; channel index 0..3
.teardown_free_ch                move.l     (a2),a0
                    moveq      #1,d3
                    move.b     d4,d2
                    asl.l      d2,d3                        ; D3 = 1 << channel
                    move.l     d3,(IOAudio+IO_UNIT,a0)      ; target channel
                    move.l     (a2),a0
                    move.w     d4,d2
                    add.w      d2,d2
                    move.l     #_key,a1
                    move.w     (a1,d2.w),(ioa_AllocKey,a0)  ; AllocKey saved by _Boing
                    move.l     (a2),a0
                    move.w     #ADCMD_FREE,(IOAudio+IO_COMMAND,a0)
                    move.l     (a2),-(sp)
                    jsr        (_DoIO)                      ; release channel
                    addq.l     #4,sp
.teardown_next_ch                addq.l     #1,d4
                    moveq      #4,d2
                    cmp.l      d4,d2
                    bgt.b      .teardown_free_ch
.teardown_close_dev                move.l     (a2),-(sp)
                    jsr        (_CloseDevice)
                    addq.l     #4,sp
.teardown_recycle_master                move.l     (a2),-(sp)
                    pea        (_freeList)
                    jsr        (_AddTail)                   ; put _allocReq back on _freeList
                    addq.l     #8,sp
.teardown_freelist                ; Walk _freeList and FreeMem each IOAudio struct (ioa_SIZEOF = $44).
                    move.l     (a3),a0
                    lea        (IOAudio+IO_UNIT,a0),a1
                    move.l     a1,d3
                    move.l     (a3),a0
                    move.l     (IOAudio+IO_DEVICE,a0),d2
                    move.l     d2,d4
                    cmp.l      d2,d3
                    bne.w      .teardown_free_ioa
.teardown_list_done                move.l     #lbL00090E,d3
                    move.l     (_freeList),d2
                    move.l     d2,d4
                    cmp.l      d2,d3
                    beq.b      .teardown_delete_port
.teardown_free_ioa                move.l     d4,-(sp)
                    jsr        (_Remove)
                    pea        ($44).w                      ; sizeof(IOAudio) = $44
                    move.l     d4,-(sp)
                    jsr        (_FreeMem)
                    lea        (12,sp),sp
                    bra.b      .teardown_freelist

.teardown_delete_port                move.l     (a3),-(sp)
                    jsr        (_DeletePort)                ; close reply port
                    addq.l     #4,sp
.teardown_check_silent                tst.l      (_silent)                    ; sample buffer was allocated?
                    beq.b      .teardown_clear_sound
.teardown_free_buf                moveq      #0,d2
                    move.w     (a4),d2
                    add.l      (_sampleLength),d2           ; full buffer size
                    move.l     d2,-(sp)
                    move.l     (_silent),-(sp)
                    jsr        (_FreeMem)                   ; free silence+sample buffer
                    addq.l     #8,sp
.teardown_clear_sound                clr.b      (_sound)                     ; audio is no longer ready
.ic_exit                movem.l    (sp)+,d2-d5/a2-a5
                    unlk       a6
                    rts

;==============================================================================
; _InitBoing - call _initCleanup(1) to set up audio at startup. Called
; from _main Phase 12.
;==============================================================================
_InitBoing          pea        (1).w
                    jsr        (_initCleanup,pc)
                    addq.l     #4,sp
.ib_exit                rts

;==============================================================================
; _CleanUp - call _initCleanup(0) to tear down audio at shutdown. Called
; from _GoodBye (in src/main.s). Idempotent: skip teardown if audio init
; failed (_sound == 0).
;==============================================================================
_CleanUp            tst.b      (_sound)                     ; was audio successfully initialized?
                    beq.b      .cu_exit                         ; no -> nothing to clean up
.cu_invoke                clr.l      -(sp)
                    jsr        (_initCleanup,pc)            ; _initCleanup(0)
                    addq.l     #4,sp
.cu_exit                rts

                    dc.w       0

;==============================================================================
; Audio data. CHIP RAM because _silent/_samples will be DMA'd by Paula.
; (The pointer variables _silent and _samples don't strictly need CHIP RAM
;  but the buffer they point to does, and the disassembler kept them all
;  in the same section.)
;==============================================================================
                    SECTION    boing0008A4,DATA,CHIP
boingsamples__MSG   dc.b       'boing.samples',0            ; sample filename (relative path)
boingsamples__MSG0  dc.b       'boing.samples',0            ; (duplicate; both Lock and Open use one)
PROGRAM_NAME__MSG   dc.b       'PROGRAM_NAME',0,0           ; name for CreatePort
audiodevice__MSG    dc.b       'audio.device',0,0           ; device name for OpenDevice
_sound              dc.b       0                            ; 1 if audio is ready, 0 otherwise
                    dc.b       0                            ; padding
_silent             dc.l       0                            ; head of sample buffer (silence prefix)
_samples            dc.l       0                            ; &_silent[silentLength] (real audio start)
_audioPort          dc.l       0                            ; audio.device reply MsgPort
_allocReq           dc.l       0                            ; master IOAudio for channel allocation
_allocMap           dc.l       $03050A0C                    ; channel mask candidates ($03,$05,$0A,$0C)
_leftRight          dc.w       $0609                        ; [$06,$09] = the two stereo side masks
_sampleLength       dc.l       0                            ; size of real audio data (bytes)
_silentLength       dc.w       0                            ; size of leading silence buffer (bytes)
_extraSamples       dc.w       0                            ; per-call delay (samples) for one side
_maxDelay           dc.w       10                           ; max inter-aural delay (demo units)
_maxCCDelay         dc.l       0                            ; max delay in Paula color clocks (= _maxDelay*3580)
_key                dc.l       0                            ; [4 x word] AllocKey per channel
                    dc.l       0                            ;   (padding to round up to 8 bytes)
_freeList           dc.l       0                            ; Exec list head of recycled IOAudio buffers
lbL00090E           dc.l       0                            ; _freeList tail node + initial sentinel
                    dc.l       0
                    dc.w       0


