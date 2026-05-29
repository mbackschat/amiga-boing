# AMIGA-KNOWHOW.md — Amiga 1000 Hardware and OS Reference

Reference companion to [DEMO-BACKGROUND.md](DEMO-BACKGROUND.md). Scope is **focused on what `boing.s` in this repository actually uses**: the Kickstart 1.x libraries (`exec`, `graphics`, `intuition`, `dos`, `mathffp`, `mathtrans`), the `audio.device`, the OS startup pattern, and just enough hardware background to understand what the libraries do under the hood. An appendix briefly covers the rest of the chipset, blitter modes, CIA, and 68000 details that the demo does *not* touch directly.

> **Why this scope?** A structural scan of `boing.s` found it touches `$DFF000` register space only **once** (a `DMACON` write near `boing.s:1776`); everything else goes through the OS libraries. The ball is rendered as filled polygons by `graphics.library` area-fill (`AreaMove` / `AreaDraw` / `AreaEnd`) over a 5-bitplane Intuition screen, sphere vertices come from `mathtrans.library` `SPSin`/`SPCos`, and the three bounce sounds play through `audio.device`. Hardware sprites, the Copper, and the Blitter are *not* directly used by the demo — they are managed by `graphics.library` on its behalf.

---

## Table of contents

- [A. System overview](#a-system-overview)
- [B. Memory map and chip RAM](#b-memory-map-and-chip-ram)
- [C. The custom chip register window `$DFF000`](#c-the-custom-chip-register-window-dff000)
- [D. Agnus, Denise, Paula — at a glance](#d-agnus-denise-paula--at-a-glance)
- [E. Display: bitplanes, BPLCON0, color palette (used by the Intuition screen)](#e-display-bitplanes-bplcon0-color-palette-used-by-the-intuition-screen)
- [F. Paula audio (used by `audio.device` for the boing samples)](#f-paula-audio-used-by-audiodevice-for-the-boing-samples)
- [G. Exec — library calling convention, memory, tasks, interrupts](#g-exec--library-calling-convention-memory-tasks-interrupts)
- [H. dos.library and the CLI/Workbench startup pattern (demo uses this)](#h-doslibrary-and-the-cliworkbench-startup-pattern-demo-uses-this)
- [I. intuition.library (demo opens a Screen and Window)](#i-intuitionlibrary-demo-opens-a-screen-and-window)
- [J. graphics.library (demo uses area-fill, RastPort, etc.)](#j-graphicslibrary-demo-uses-area-fill-rastport-etc)
- [K. mathffp.library and mathtrans.library (FFP floats; SPSin/SPCos sphere math)](#k-mathffplibrary-and-mathtranslibrary-ffp-floats-spsinspcos-sphere-math)
- [L. audio.device (demo plays three samples)](#l-audiodevice-demo-plays-three-samples)
- [M. Putting it together: the `boing.s` runtime picture](#m-putting-it-together-the-boings-runtime-picture)
- [N. Appendix — not used by this demo](#n-appendix--not-used-by-this-demo)
- [References](#references)

---

## A. System overview

**Machine.** Commodore Amiga 1000. Launched **July 23, 1985** at the Vivian Beaumont Theater, Lincoln Center, New York City — the first Amiga model and the only one bearing the Commodore "checkmark" logo. ([Wikipedia: Amiga 1000](https://en.wikipedia.org/wiki/Amiga_1000))

**CPU.** Motorola **MC68000**, 16/32-bit CISC, 16-bit external data bus, 24-bit address bus.
- NTSC clock: **7.159 MHz** (master video clock 28.636 MHz ÷ 4).
- PAL clock: **7.094 MHz** (master 28.375 MHz ÷ 4).
- No MMU, no on-chip caches. Supervisor/user modes; not virtualisable (MOVE-from-SR is unprivileged). ([Wikipedia: Motorola 68000](https://en.wikipedia.org/wiki/Motorola_68000))

**RAM.** 256 KB of chip RAM on the motherboard, expandable to 512 KB via the front-panel "Chip Memory" daughterboard; up to ~8.5 MB total with Zorro-II side-car. ([Wikipedia: Amiga 1000](https://en.wikipedia.org/wiki/Amiga_1000))

**Custom chipset.** The Original Chip Set (**OCS**): **Agnus** (DMA + Copper + Blitter), **Denise** (display + sprites + palette), **Paula** (audio + floppy + serial + interrupts). ([Wikipedia: Original Chip Set](https://en.wikipedia.org/wiki/Original_Chip_Set))

**Operating system.** **Kickstart 1.0 / 1.1 / 1.2 / 1.3** — multitasking microkernel (Exec) plus libraries and devices. On the A1000, Kickstart sits in **WCS** (Writable Control Store, 256 KB of RAM that an 8 KB bootstrap ROM loads from a Kickstart floppy and then write-protects). Every later Amiga moves Kickstart to mask ROM. ([Wikipedia: Kickstart (Amiga)](https://en.wikipedia.org/wiki/Kickstart_(Amiga)))

---

## B. Memory map and chip RAM

Per the *Amiga Hardware Reference Manual*, Appendix D ([mirror at theflatnet `hard_d.html`](https://www.theflatnet.de/pub/cbm/amiga/AmigaDevDocs/)):

| Range | Contents |
|---|---|
| `$00 0000`–`$03 FFFF` | 256 KB chip RAM (A1000 base) |
| `$04 0000`–`$07 FFFF` | second 256 KB chip RAM, when fitted |
| `$08 0000`–`$1F FFFF` | extended chip RAM (Fat Agnus only, not A1000) |
| `$20 0000`–`$9F FFFF` | Zorro / autoconfig (Fast RAM, cards) |
| `$BF D000`–`$BF DF00` | **CIA-B** (8520-B) |
| `$BF E001`–`$BF EF01` | **CIA-A** (8520-A) |
| `$DF F000`–`$DF FFFF` | **custom chip registers** (Agnus/Denise/Paula) |
| `$E8 0000`–`$EF FFFF` | autoconfig probe / 64 KB I/O boards |
| `$FC 0000`–`$FF FFFF` | 256 KB system ROM (Kickstart) — **WCS on A1000** |

### B.1 Chip RAM vs Fast RAM

**Chip RAM** is the only memory the custom chips can DMA from. Anything the chipset must read autonomously — bitplane data, sprite data, audio sample buffers, copper lists, blitter buffers — **must live in chip RAM**. This is enforced by Exec's allocator: pass `MEMF_CHIP` to `AllocMem()` when you want chip-DMA-able memory. Fast RAM (`MEMF_FAST`) is CPU-side only.

`boing.s` allocates its audio sample buffers and any per-frame work buffers with `MEMF_CHIP`. The screen bitmap is allocated by `intuition.library`/`graphics.library` on the demo's behalf via `OpenScreen()` — those bitmaps are always in chip RAM.

### B.2 ExecBase at `$00000004`

> "The address of the exec.library from location 4 is the only absolute memory location in the system."
>
> — *Amiga Hardware Reference Manual*, Appendix D

Every other system pointer is reached by dereferencing through `ExecBase`:

```
move.l   4.w,a6           ; A6 = ExecBase (canonical idiom)
```

The `.w` annotation tells the assembler to use the 16-bit absolute-short addressing mode — `4` fits in a sign-extended word, so the instruction is 4 bytes shorter than `move.l $00000004,a6`. Every Amiga program starts with some variant of this.

---

## C. The custom chip register window `$DFF000`

Every chipset register has a 12-bit offset from `$DFF000`. Examples used (or relevant) in `boing.s`:

| Offset | Name | Function |
|---|---|---|
| `$002` | DMACONR | Read DMA control + blitter status |
| `$096` | **DMACON** | Write DMA control. `boing.s:1776` writes here (sole direct chipset poke). |
| `$09A` | INTENA | Interrupt mask |
| `$09C` | INTREQ | Interrupt request |
| `$09E` | ADKCON | Audio/disk control |

The Copper sees the same 12-bit offsets in its MOVE instructions — but `boing.s` does **not** install a custom copper list. The graphics.library builds and maintains the copper list for the Intuition screen on the demo's behalf.

### C.1 DMACON / DMACONR — the one register `boing.s` does write

`DMACON` (`$DFF096`, write-only) and `DMACONR` (`$DFF002`, read companion). Bit layout ([*Amiga Hardware Reference Manual* ch. 7](https://www.theflatnet.de/pub/cbm/amiga/AmigaDevDocs/)):

| Bit | Name | Meaning |
|---|---|---|
| 15 | **SET/CLR** | Write: 1 = "set the 1-bits below"; 0 = "clear the 1-bits below". Bits written as 0 are untouched. |
| 14 | BBUSY (read-only) | Blitter busy |
| 13 | BZERO (read-only) | Blitter result was all zeros |
| 10 | **BLTPRI** | Blitter "nasty" — Blitter takes every free cycle |
| 9 | **DMAEN** | Master DMA enable — every other DMA bit is gated by this |
| 8 | **BPLEN** | Bitplane DMA |
| 7 | **COPEN** | Copper DMA |
| 6 | **BLTEN** | Blitter DMA |
| 5 | **SPREN** | Sprite DMA |
| 4 | **DSKEN** | Disk DMA |
| 3..0 | **AUD3EN..AUD0EN** | Audio channel DMA enables |

The SET/CLR convention is key: writing `$8200` *sets* DMAEN (bit 9); writing `$0200` *clears* DMAEN. This is why one register can both enable and disable individual subsystems without read-modify-write.

Why `boing.s` pokes DMACON directly: most plausibly to **disable audio DMA briefly during a sample setup**, or to **re-enable the channels** after `audio.device` finishes a write. (The exact reason will become clear when the source is commented in a later pass.) The write does not constitute a system takeover; it's a surgical adjustment to one audio-channel bit.

### C.2 What the demo does **not** write to `$DFF000`

- `INTENA` / `INTREQ` — interrupt control stays with Exec.
- `COP1LC` / `COP2LC` / `COPJMP1` — copper list belongs to graphics.library.
- `BPL1PT`–`BPL5PT`, `BPLCONx`, `DDFSTRT`, `DIWSTRT` — bitplane setup belongs to graphics.library.
- `AUDxLC` / `AUDxLEN` / `AUDxPER` / `AUDxVOL` — Paula audio register pokes happen inside `audio.device`, not in `boing.s`.
- `SPRxPT` / `SPRxCTL` — no hardware sprites used.

This is what "polite Amiga code" looks like: the program lets the OS own the chipset and only talks to it through library calls.

---

## D. Agnus, Denise, Paula — at a glance

Brief because the demo doesn't poke them directly; included for context.

### D.1 Agnus

Bus master and DMA controller. Arbitrates **25 DMA channels** in strict priority: blitter > copper > audio > sprites > disk > refresh. Also contains:

- **Copper** — a tiny coprocessor that executes a list of MOVE/WAIT/SKIP instructions synchronized to the video beam. Lets you change any chip register at a specific raster line. graphics.library uses the Copper to install bitplane pointers, palette, and bitplane-control register values once per frame (this is the OS-owned "system copper list").
- **Blitter** — a 4-channel DMA engine for fast bitplane operations (copy, fill, line draw, area fill, logical combinations of three source planes A/B/C into destination D via a programmable minterm). graphics.library uses it for `BltClear`, `ScrollRaster`, line drawing, area fill — exactly the operations `boing.s` requests.
- **Beam counters** — `VPOSR` / `VHPOSR` give the current raster Y/X.

Agnus on the A1000 addresses up to 512 KB of chip RAM. ([Wikipedia: MOS Technology Agnus](https://en.wikipedia.org/wiki/MOS_Technology_Agnus))

### D.2 Denise

The display chip. Receives bitplane data from Agnus's DMA stream and serializes it onto the screen via the 32-entry color palette. Contains the 8 hardware sprites' serializers and the playfield-priority logic. Detailed in §E.

### D.3 Paula

Audio + floppy + serial + interrupts:

- **4 hardware DMA audio channels**, each an 8-bit signed PCM stream. Channels 0/3 are wired to one stereo output, 1/2 to the other (the L/R assignment varies between sources and machine revisions; see §F.1 footnote).
- The disk controller — MFM encode/decode, sync-word detection.
- The serial UART — `SERDAT` / `SERDATR` / `SERPER`.
- **The interrupt request matrix** — every chipset interrupt feeds into Paula's INTREQ register, even though many events are generated by Agnus or Denise.

For `boing.s`, only the audio path is relevant.

---

## E. Display: bitplanes, BPLCON0, color palette (used by the Intuition screen)

`boing.s` opens an **Intuition screen with 5 bitplanes** at 320 × 200 (standard lo-res NTSC) — or 320 × 256 PAL — giving 2⁵ = **32 colors**. Intuition + graphics.library translate that into the appropriate `BPLCON0` bits, allocate 5 chip-RAM bitplane buffers, set up a system copper list, and start bitplane DMA. The demo never writes `BPLCON0` itself, but understanding what graphics.library is doing makes the code easier to read.

### E.1 Bitplanes — the Amiga's display model

Every pixel's color index is built bit-by-bit by stacking N **bitplanes** (1-bit-deep bitmaps the size of the screen). Plane 0 contributes the low bit, plane 1 the next, and so on. With 5 planes, each pixel picks one of 32 palette entries.

The display DMA reads one bit from each plane per pixel, assembles them into the index, and looks up the color. All 5 planes must live in chip RAM at addresses pointed to by `BPL1PT..BPL5PT`.

### E.2 BPLCON0 (`$DFF100`) — playfield mode

[github.com/prb28/vscode-amiga-assembly — DFF100_BPLCON0](https://github.com/prb28/vscode-amiga-assembly)

| Bit | Name | Meaning |
|---|---|---|
| 15 | **HIRES** | 1 = 640-wide hi-res; 0 = 320-wide lo-res |
| 14..12 | **BPU2..BPU0** | number of bitplanes (000 = blank, 001 = 1, …, 110 = 6) |
| 11 | **HOMOD/HAM** | Hold-And-Modify (only with BPU=110) |
| 10 | **DBLPF** | dual-playfield mode |
| 9 | **COLOR** | enable color-burst output |
| 8 | GAUD | genlock audio enable |
| 2 | LACE | interlace (doubles vertical resolution) |
| 1 | ERSY | external resync (genlock) |

For the demo, graphics.library would write `BPU = 101` (5 planes), `HIRES = 0`, `DBLPF = 0`, `COLOR = 1`.

**Rules to remember.** BPU=101 gives a true 32-color screen. BPU=110 either gives **Extra Half-Brite** (HAM=0, 64 colors via half-brightness in plane 6) or **HAM6** (HAM=1, video compression via per-pixel deltas to the previous pixel's R/G/B). The demo uses neither — vanilla 5-plane 32-color.

### E.3 The color palette (`$DFF180`–`$DFF1BE`)

32 registers `COLOR00`..`COLOR31`, each 16 bits wide (lower 12 used): `0000 RRRR GGGG BBBB`. So `$0F00` = pure red, `$0FFF` = white, `$0000` = black, `$0888` = mid grey. 4 bits per channel = **4096 displayable colors**, 32 simultaneous (in the lo-res non-HAM case).

The Intuition screen comes up with a default palette; `boing.s` overrides it with a `LoadRGB4()` call (graphics.library) so the ball and floor have the colors it wants. Per the original-demo lore (§6.1 of [DEMO-BACKGROUND.md](DEMO-BACKGROUND.md)), the ball's "rotation" in the **1984 CES original** is produced by cycling these palette registers. **This OS-friendly source `boing.s` does not do palette cycling** — it redraws the ball each frame as filled polygons.

### E.4 Bitplane pointers and modulos

| Register | Offset | Purpose |
|---|---|---|
| BPL1PTH/L | `$DFF0E0`/`$0E2` | bitplane 1 base address (longword) |
| BPL2PTH/L | `$DFF0E4`/`$0E6` | bitplane 2 |
| BPL3PTH/L | `$DFF0E8`/`$0EA` | bitplane 3 |
| BPL4PTH/L | `$DFF0EC`/`$0EE` | bitplane 4 |
| BPL5PTH/L | `$DFF0F0`/`$0F2` | bitplane 5 |
| **BPL1MOD** | `$DFF108` | bytes added to *odd* planes (1, 3, 5) after each scanline |
| **BPL2MOD** | `$DFF10A` | bytes added to *even* planes (2, 4, 6) after each scanline |

Modulo lets the displayed bitmap be **smaller than the underlying plane width**, supporting smooth scroll without re-blitting. Set both modulos equal in single-playfield mode.

graphics.library populates all of these via the **system copper list** that fires every vertical blank.

### E.5 Display window (`DIWSTRT`/`DIWSTOP`) and data fetch (`DDFSTRT`/`DDFSTOP`)

These define *where* the bitplane data appears on screen and *when* during each scanline the data-fetch DMA runs.

Standard NTSC lo-res:
- `DIWSTRT = $2C81` (V = 0x2C, H = 0x81)
- `DIWSTOP = $F4C1`
- `DDFSTRT = $0038`
- `DDFSTOP = $00D0`

Standard PAL is similar with extended V range. Values are color-clocks (1 color clock = 2 lo-res pixels).

graphics.library sets these in the system copper list. `boing.s` never touches them.

---

## F. Paula audio (used by `audio.device` for the boing samples)

`boing.s` plays three sound effects through `audio.device`. The device opens Paula's audio channels and does the per-register pokes on the demo's behalf. To understand what the device is doing, you need a baseline of Paula's audio path.

### F.1 The audio path

- 4 channels, each an independent 8-bit signed PCM DMA stream from chip RAM.
- Stereo wiring: **channels 0 and 3 → one output, channels 1 and 2 → the other**. The L/R assignment is sometimes printed as "0+3 = left, 1+2 = right" (most retro references) and sometimes the reverse (some editions of the Amiga Hardware Reference Manual). When `audio.device` allocates channels, you pass a channel-mask preference list and accept whichever the device grants — see §L.
- Sample format: **signed 8-bit two's complement**, –128 to +127.
- 65 volume steps per channel (0 to 64). 64 is unity.
- Per-channel maximum DMA rate ≈ **28,867 samples/s** NTSC, 28,837 PAL.
- A built-in 6 dB/oct low-pass filter (~5 kHz cutoff with the power-LED filter switch on) follows the DAC.

([Wikipedia: Original Chip Set — Sound](https://en.wikipedia.org/wiki/Original_Chip_Set); [Amiga Hardware Reference Manual, Audio chapter](https://www.theflatnet.de/pub/cbm/amiga/AmigaDevDocs/))

### F.2 Per-channel registers (channel 0 shown; 1/2/3 follow at +$10 each)

| Register | Offset (ch.0) | Meaning |
|---|---|---|
| AUD0LCH | `$DFF0A0` | high word of sample base address |
| AUD0LCL | `$DFF0A2` | low word — **must be word-aligned, in chip RAM** |
| AUD0LEN | `$DFF0A4` | length in **words** (so byte length / 2) |
| AUD0PER | `$DFF0A6` | period (ticks/sample); min ≈ 124 NTSC |
| AUD0VOL | `$DFF0A8` | 0..64 |
| AUD0DAT | `$DFF0AA` | direct sample-byte write (rarely used) |

Channels 1/2/3 are at `$DFF0B0`, `$DFF0C0`, `$DFF0D0` respectively.

### F.3 Sample-rate math

**Frequency (Hz) = ClockConstant / Period**, where

- NTSC: clock constant = **3,579,545 Hz**
- PAL: clock constant = **3,546,895 Hz**

So PER=428 on PAL → ~8,287 Hz (ProTracker's middle-C base). PER=124 ≈ 28.86 kHz (maximum playable rate). ([open-amiga-sampler — Sample rates deep dive](https://github.com/echolevel/open-amiga-sampler/wiki/Appendix-A:-Sample-rates-deep-dive))

### F.4 Starting and stopping a channel (what `audio.device` does for you)

1. Place sample bytes in **chip RAM**, word-aligned.
2. Write `AUDxLC` (long), `AUDxLEN`, `AUDxPER`, `AUDxVOL`.
3. Set the corresponding `AUDxEN` bit in `DMACON` (with `DMAEN` bit 9 already on).
4. Paula latches `LC`/`LEN` at the start of each block. When the block finishes, **an `AUDx` interrupt fires** (INTREQ bits 7..10). Inside the ISR, you can write *new* `AUDxLC`/`AUDxLEN` to chain — Paula has already started reading from the previously latched pointer, so you have one block's worth of grace.
5. To stop, clear the `AUDxEN` bit in DMACON.

This is exactly the lifecycle `audio.device` manages internally. The reason `boing.s` reaches into `DMACON` once (see §C.1) is most likely to enforce a channel-state precondition that audio.device's API doesn't expose directly.

### F.5 ADKCON — audio modulation (not used by Boing)

Brief mention only. `ADKCON` bits 0..7 attach one channel's stream to modulate the *period* or *volume* of the next-higher channel — the mechanism behind classic Amiga AM/FM synthesis. The demo uses straight PCM playback; ADKCON's audio bits are zero.

---

## G. Exec — library calling convention, memory, tasks, interrupts

Exec is Carl Sassenrath's **preemptive multitasking microkernel**, the heart of Kickstart 1.x. It schedules tasks, allocates memory, manages interrupts, opens libraries and devices, and brokers messages. ([Wikipedia: Carl Sassenrath](https://en.wikipedia.org/wiki/Carl_Sassenrath))

### G.1 The library calling convention

Every Amiga library is a block of memory whose **base address** points to a struct. The actual entry-point jump table sits at **negative offsets** from the base. To call a function:

```
move.l  4.w,a6                  ; A6 = ExecBase
lea     dosname(pc),a1          ; A1 = library-name string
moveq   #0,d0                   ; D0 = min version (0 = any)
jsr     _LVOOpenLibrary(a6)     ; LVO = -552
move.l  d0,_DOSBase             ; D0 returns the library base
```

Then to call into the new library, load **its** base into A6 and `jsr` to the appropriate negative offset:

```
move.l  _DOSBase(pc),a6
move.l  fileName(pc),d1
move.l  #MODE_NEWFILE,d2
jsr     _LVOOpen(a6)            ; LVO = -30
```

- **Library base must be in A6** for every `jsr _LVOxxx(a6)` call.
- **Return value in D0.** D0/D1/A0/A1 are scratch. D2-D7/A2-A6 are preserved by the callee.
- LVOs ("Library Vector Offsets") are documented per library in the `.fd` files shipped with Kickstart developer kits and the autodocs in the *RKM Libraries* manual.

`src/boing.s`'s include files (`vendor/include/exec/exec_lib.i`, `vendor/include/graphics/graphics_lib.i`, etc.) define these LVOs as assembler equates.

### G.2 Selected Exec LVOs `boing.s` uses

| Function | LVO | Notes |
|---|---|---|
| OpenLibrary | -552 | `(libName.a1, version.d0) → d0` |
| CloseLibrary | -414 | `(library.a1)` |
| OpenDevice | -444 | `(devName.a0, unit.d0, ioReq.a1, flags.d1) → d0(error)` |
| CloseDevice | -450 | `(ioReq.a1)` |
| DoIO | -456 | `(ioReq.a1) → d0` synchronous I/O |
| SendIO | -462 | `(ioReq.a1)` asynchronous I/O |
| WaitIO | -474 | `(ioReq.a1) → d0` |
| AllocMem | -198 | `(size.d0, attrs.d1) → d0` |
| FreeMem | -210 | `(addr.a1, size.d0)` |
| FindTask | -294 | `(name.a1) → d0`; NULL → current task |
| WaitPort | -384 | `(port.a0) → d0=first message` |
| GetMsg | -372 | `(port.a0) → d0=message or NULL` |
| ReplyMsg | -378 | `(message.a1)` |
| Forbid | -132 | suspend task scheduling (counted) |
| Permit | -138 | resume scheduling |
| Disable | -120 | mask all maskable interrupts (counted, implies Forbid) |
| Enable | -126 | unmask interrupts |
| AllocSignal | -330 | reserve a signal bit |
| FreeSignal | -336 | release one |
| Wait | -318 | block on a signal mask |
| Signal | -324 | send a signal to another task |

[`exec.doc` autodoc, mirror](http://www.theflatnet.de/pub/cbm/amiga/AmigaDevDocs/lib_17.html)

### G.3 `AllocMem` flags

| Flag | Value | Meaning |
|---|---|---|
| MEMF_ANY | `$00000000` | any memory |
| MEMF_PUBLIC | `$00000001` | non-swap / non-volatile — required when other tasks or interrupts touch the block |
| **MEMF_CHIP** | `$00000002` | **chip RAM** — required for bitmaps, copperlists, sprites, **audio samples**, blitter buffers |
| MEMF_FAST | `$00000004` | fast RAM only |
| MEMF_CLEAR | `$00010000` | zero the block |

For Boing's sample buffers: `AllocMem(size, MEMF_CHIP|MEMF_CLEAR)` is the canonical call.

### G.4 Forbid / Permit / Disable / Enable

- `Forbid()` increments `TDNestCnt`; while non-zero, no task switching. **Interrupts still run.**
- `Permit()` decrements it; reaching zero may trigger an immediate re-schedule.
- `Disable()` increments `IDNestCnt` and **also** Forbids; while non-zero, IPL-maskable interrupts are blocked.
- **Never `Wait()` while Disabled** — guaranteed deadlock.

`boing.s` uses Forbid/Permit/Disable/Enable around critical sections that touch shared state — for example, while the audio.device sample buffers are being swapped, or during the brief moment the DMACON write happens.

### G.5 Tasks and signals

`FindTask(NULL)` returns the current `struct Task *`. For programs launched from CLI or Workbench it's actually a `struct Process`, a superset with `pr_CLI`, `pr_MsgPort`, `pr_CurrentDir`, etc. (see [`dos/dosextens.i`]). The canonical idiom:

```
sub.l   a1,a1
jsr     _LVOFindTask(a6)
move.l  d0,a4                   ; A4 = (struct Process *) self
```

A4 is callee-saved across library calls, so a program-level "this is me" pointer often lives there.

### G.6 Interrupts and the 68000 autovector table

Brief because `boing.s` does not install custom interrupt handlers. The 68000 has 7 autovector levels; the Amiga maps INTENA bits onto them as follows ([wiki.amigaos.net — Exec Interrupts](https://wiki.amigaos.net/wiki/Exec_Interrupts)):

| 68k level | Vector | INTENA bits | Typical handler |
|---|---|---|---|
| 1 | `$64` | TBE, DSKBLK, SOFT | serial TX, floppy block, software int |
| 2 | `$68` | PORTS | CIA-A (keyboard, parallel) |
| 3 | `$6C` | COPER, **VERTB**, BLIT | per-frame work, copper/blitter done |
| 4 | `$70` | AUD0..AUD3 | audio block done — refill |
| 5 | `$74` | RBF, DSKSYNC | serial RX, floppy sync |
| 6 | `$78` | EXTER | CIA-B (timers, parallel, floppy step) |
| 7 | `$7C` | NMI | nonmaskable |

The demo relies on `graphics.library`'s `WaitTOF()` (vertical-blank wait) for per-frame timing rather than installing its own VBI handler.

---

## H. dos.library and the CLI/Workbench startup pattern (demo uses this)

`boing.s` opens `dos.library` early (`openDOS` subroutine, near top of source) and contains the classic CLI-vs-Workbench startup logic visible in `boing.s:21–105`.

### H.1 The two launch contexts

A well-behaved Amiga binary supports both:

- **CLI launch.** The user types `boing` at a Shell prompt. The current Process structure has a non-zero `pr_CLI` BCPL pointer; `pr_CLI->cli_CommandLine` points to the command-line tail; `_stdin` / `_stdout` / `_stderr` are valid file handles.
- **Workbench launch.** The user double-clicks the program's icon. `pr_CLI` is **NULL**, but a `WBStartup` message is already sitting in `pr_MsgPort`. The program must `WaitPort` + `GetMsg` to retrieve it, then `ReplyMsg` at exit so Workbench can unload the program.

### H.2 The decision rule

```asm
        move.l   4.w,a6                  ; ExecBase
        sub.l    a1,a1
        jsr      _LVOFindTask(a6)
        move.l   d0,a4                   ; A4 = (struct Process *) self

        tst.l    pr_CLI(a4)              ; pr_CLI == 0 ?
        beq.w    fromWorkbench
fromCLI: ...
fromWorkbench:
        bsr.w    waitmsg                 ; WaitPort + GetMsg on pr_MsgPort
        move.l   d0,(returnMsg)          ; save the WBStartup
        ...
```

`boing.s` does exactly this at `boing.s:25–32`.

### H.3 The CLI command-line parsing

The CLI puts the tail of the typed command (everything after the program name) into a buffer; the address is in `pr_CLI->cli_CommandLine`, the byte length is in D0 on entry, and the buffer address is in A0. The standard pattern (visible at `boing.s:32–75`):

1. Find the command name length via `cli_CommandName` (a BSTR — BCPL string with leading length byte).
2. Allocate space for `argvBuffer` and `argvArray`.
3. Walk the command tail, splitting at whitespace into argv-style strings.
4. Push `argc`, `argv` onto the stack and call `_main`.

The BSTR/BPTR conventions: a **BPTR** is a BCPL pointer — a byte offset divided by 4. To convert to a CPU pointer you `lsl.l #2, d` it (the `add.l a0,a0 / add.l a0,a0` you see twice in succession in `boing.s:36–38` is exactly this: shift-left-by-1 done twice).

### H.4 Clean exit

```asm
        move.l   WBMessage(pc),d0
        beq.s    .exit_cli
        move.l   4.w,a6
        jsr      _LVOForbid(a6)           ; prevent unload mid-instruction
        move.l   WBMessage(pc),a1
        jsr      _LVOReplyMsg(a6)
.exit_cli:
        moveq    #0,d0                    ; return code
        rts
```

`Forbid` before `ReplyMsg` is mandatory on the Workbench path: once Workbench receives the reply it considers the program file free to unload, and a task switch between `ReplyMsg` and `RTS` would unload the code under the running CPU. The implicit Permit when the task exits cleans up. ([wiki.amigaos.net — Workbench Library](https://wiki.amigaos.net/wiki/Workbench_Library); [*RKM Libraries* ch. 14](http://www.theflatnet.de/pub/cbm/amiga/AmigaDevDocs/))

### H.5 Selected dos.library LVOs

| Function | LVO | Notes |
|---|---|---|
| Open | -30 | `(name.d1, mode.d2) → d0=fh` |
| Close | -36 | `(fh.d1)` |
| Read | -42 | `(fh.d1, buffer.d2, len.d3)` |
| Write | -48 | `(fh.d1, buffer.d2, len.d3)` |
| Input | -54 | → current stdin fh |
| Output | -60 | → current stdout fh |
| Delay | -198 | sleep N ticks (50 Hz) |
| Lock | -84 | open by path → BPTR lock |
| UnLock | -90 | release |
| CurrentDir | -126 | set current dir (BPTR) |
| Exit | -144 | terminate Process (CLI launches only) |

Open modes:
- `MODE_OLDFILE = 1005` — open existing.
- `MODE_NEWFILE = 1006` — create / truncate.
- `MODE_READWRITE = 1004` — shared, create if missing.

`boing.s` uses `Open`/`Read`/`Close` to load `boing.samples` (the on-disk sound bank) into chip RAM.

---

## I. intuition.library (demo opens a Screen and Window)

Intuition is Kickstart 1.x's window manager and GUI primitive layer. `boing.s` uses it to:

1. Open a **Screen** (5-bitplane lo-res custom screen, distinct from Workbench's screen).
2. Open a **Window** on that screen for IDCMP event delivery (mouse click / key press → quit).
3. Set a pointer / handle close-gadget messages.
4. Close it all on exit.

### I.1 Selected LVOs

| Function | LVO | Notes |
|---|---|---|
| OpenScreen | -198 | `(newScreen.a0) → d0=Screen *` |
| CloseScreen | -66 | `(screen.a0)` |
| OpenWindow | -204 | `(newWindow.a0) → d0=Window *` |
| CloseWindow | -72 | `(window.a0)` |
| SetPointer | -270 | `(window.a0, data.a1, h, w, xo, yo)` |
| ClearPointer | -60 | restore default pointer |
| DisplayBeep | -96 | flash the screen |
| WaitTOF | (graphics, -270) | wait for next vertical blank (used for frame pacing) |

[`intuition.doc` autodoc; wiki.amigaos.net — Intuition Screens](https://wiki.amigaos.net/wiki/Intuition_Screens)

### I.2 The `NewScreen` struct

A `NewScreen` initialises a custom screen:

```c
struct NewScreen {
    WORD  LeftEdge, TopEdge, Width, Height, Depth;   // 320, 200, 5
    UBYTE DetailPen, BlockPen;
    UWORD ViewModes;          // 0 = lo-res NTSC; HIRES, LACE, etc. ORed
    UWORD Type;               // CUSTOMSCREEN, etc.
    struct TextAttr *Font;
    UBYTE *DefaultTitle;
    struct Gadget *Gadgets;
    struct BitMap *CustomBitMap;
};
```

For Boing the depth is 5; ViewModes likely 0 (lo-res NTSC) or `PAL` if PAL-targeted; Type = `CUSTOMSCREEN`. graphics.library allocates 5 chip-RAM bitplanes for the screen automatically.

### I.3 The `NewWindow` struct (IDCMP)

```c
struct NewWindow {
    WORD  LeftEdge, TopEdge, Width, Height;
    UBYTE DetailPen, BlockPen;
    ULONG IDCMPFlags;          // VANILLAKEY, MOUSEBUTTONS, CLOSEWINDOW, RAWKEY...
    ULONG Flags;               // BORDERLESS, BACKDROP, SIMPLE_REFRESH, ACTIVATE...
    struct Gadget *FirstGadget;
    struct Image *CheckMark;
    UBYTE *Title;
    struct Screen *Screen;
    struct BitMap *BitMap;
    WORD  MinWidth, MinHeight, MaxWidth, MaxHeight;
    UWORD Type;
};
```

For Boing, the Window is most likely **borderless backdrop** (fills the screen, no decoration), with IDCMP flags for `MOUSEBUTTONS` and `VANILLAKEY` so any input quits.

### I.4 IDCMP message loop

The Window has a `UserPort` of type `struct MsgPort`. Each user event becomes an `IntuiMessage` posted to that port. Wait pattern:

```asm
move.l   _IntuitionBase(pc),a6
move.l   Window(pc),a0
move.l   wd_UserPort(a0),a0
jsr      _LVOWaitPort(a6)              ; block until a message arrives
move.l   wd_UserPort(a0),a0            ; re-fetch port
jsr      _LVOGetMsg(a6)                ; D0 = IntuiMessage *
; inspect im_Class — VANILLAKEY, MOUSEBUTTONS, etc. — and react
move.l   d0,a1
jsr      _LVOReplyMsg(a6)              ; (Exec call; A6 = ExecBase needed)
```

(There are subtleties around switching A6 between IntuitionBase and ExecBase across the loop — the source will show how `boing.s` handles it.)

---

## J. graphics.library (demo uses area-fill, RastPort, etc.)

`graphics.library` is the chipset-aware drawing layer that Intuition sits on. The Explore agent's structural scan found **19+ distinct graphics.library calls** in `boing.s` — this is the demo's primary drawing API.

### J.1 The drawing context: BitMap → RastPort

- A `struct BitMap` describes a multi-plane chip-RAM bitmap (5 plane pointers, width in bytes, height in rows, depth).
- A `struct RastPort` is the **drawing context**: it points at a `BitMap`, holds the current foreground/background pen, line pattern, area fill pattern, AreaInfo work area, TmpRas blitter scratch, draw mode (JAM1/JAM2/COMPLEMENT/INVERSVID), and current cursor position.
- Most drawing functions take a `RastPort *` in A1.

When you `OpenScreen()`, Intuition gives you a `Screen` whose `sc_RastPort` is already set up. When you `OpenWindow()` on a `SMART_REFRESH` window, you get a per-window `RastPort` you can draw into.

### J.2 Selected graphics.library LVOs `boing.s` uses

| Function | LVO | Purpose |
|---|---|---|
| InitBitMap | -390 | `(bitmap.a0, depth.d0, width.d1, height.d2)` — set up a BitMap struct |
| AllocRaster | -492 | `(width.d0, height.d1) → d0=BPTR` — allocate one chip-RAM bitplane |
| FreeRaster | -498 | `(raster.a0, width.d0, height.d1)` |
| InitRastPort | -198 | `(rastport.a1)` |
| InitArea | -282 | `(areainfo.a1, buffer.a2, maxvtx.d0)` — set up vertex buffer for AreaMove/Draw |
| AreaMove | -252 | `(rp.a1, x.d0, y.d1) → d0` — start a polygon at (x,y) |
| AreaDraw | -258 | `(rp.a1, x.d0, y.d1) → d0` — add vertex to polygon |
| AreaEnd | -264 | `(rp.a1) → d0` — close polygon and fill it via blitter |
| **BltClear** | -300 | `(memptr.a1, size.d0, flags.d1)` — blitter-clear a chip-RAM region |
| RectFill | -306 | `(rp.a1, xMin.d0, yMin.d1, xMax.d2, yMax.d3)` |
| Move | -240 | `(rp.a1, x.d0, y.d1)` — move pen |
| Draw | -246 | `(rp.a1, x.d0, y.d1)` — draw line from pen to (x,y) |
| SetAPen | -342 | `(rp.a1, pen.d0)` — set foreground pen |
| SetBPen | -348 | set background pen |
| SetDrMd | -354 | set draw mode (JAM1/JAM2/COMPLEMENT/INVERSVID) |
| LoadRGB4 | -192 | `(viewport.a0, colors.a1, count.d0)` — replace palette |
| WaitTOF | -270 | wait for top-of-frame (vertical blank) |
| WaitBlit | -228 | spin until BBUSY = 0 |
| OwnBlitter | -456 | claim exclusive blitter access |
| DisownBlitter | -462 | release blitter |

[`graphics.doc` autodoc; wiki.amigaos.net — Classic Graphics Primitives](https://wiki.amigaos.net/wiki/Classic_Graphics_Primitives)

### J.3 How area-fill renders the ball

`graphics.library`'s area-fill pipeline is the foundation of Boing's rendering loop:

1. Set up an `AreaInfo` with `InitArea`, pointing at a vertex buffer with capacity for the maximum number of polygon vertices.
2. Set the foreground pen with `SetAPen`.
3. For each polygon: `AreaMove(rp, x0, y0)` to start, then `AreaDraw(rp, x1, y1)`, `AreaDraw(rp, x2, y2)`, … and finally `AreaEnd(rp)`.
4. `AreaEnd` runs the blitter in **area-fill mode**: it draws the polygon outline into a temporary mask in `tmpras` (a chip-RAM scratch buffer the program allocates and attaches to the RastPort), then floods the interior in the foreground pen, then ORs the result into the RastPort's BitMap.

For Boing, the **ball is tessellated into polygons** — the sphere is sliced into latitude bands and each band into longitude facets. The vertex positions are computed each frame from `sin`/`cos` tables (or live `SPSin`/`SPCos` calls — see §K), the polygons are issued to AreaMove/AreaDraw/AreaEnd, and the result is the painted ball.

This is why the ball's silhouette is perfectly smooth despite no anti-aliasing: it's a tight polygon mesh, not a single bitmap.

### J.4 Frame pacing — `WaitTOF`

`WaitTOF()` blocks until the next vertical blank interrupt. Calling it once at the top of each frame loop synchronises drawing to ~60 Hz (NTSC) / 50 Hz (PAL) and avoids tearing — because by the time `WaitTOF` returns, the display has just finished rendering and the new frame's drawing has a full field-time before the raster reaches the upper bitplanes.

`boing.s` uses `WaitTOF()` as its frame heartbeat — no custom VBI handler needed.

### J.5 Blitter housekeeping

`BltClear(addr, size, flags)` runs the blitter in fill-with-zero mode to clear a bitmap or scratch buffer at high speed (~16 MB/s on a stock A1000 — much faster than CPU `clr.l` loops).

`WaitBlit()` spins until BBUSY clears. **Call it before issuing a new blit if you suspect another task may have been blitting concurrently**, and before reading bitmap memory that a previous blit wrote.

`OwnBlitter` / `DisownBlitter` are advisory locks — used in code that mixes raw blitter pokes with library blits — but a well-behaved demo like this one uses library calls exclusively and doesn't need them often.

---

## K. mathffp.library and mathtrans.library (FFP floats; SPSin/SPCos sphere math)

Boing's sphere geometry is computed in **floating point** because integer math at this resolution would lose precision in the corner cases (sphere normals near poles, and the sub-pixel Y arc near the apex where the ball advances less than a pixel per frame). The 68000 has no FPU, so Amiga 1.x uses two libraries for software floating point:

- **mathffp.library** — basic arithmetic in Motorola Fast Floating Point (FFP) format.
- **mathtrans.library** — transcendentals (sin, cos, sqrt, log, exp, atan).

Both use the same FFP value format and the same calling convention (FFP value in **D0**, second operand in **D1**, result in D0).

### K.1 The FFP format

A 32-bit longword. **Not** IEEE 754. Layout:

```
bit 31 ----------------------------- bit 8  bit 7  bits 6..0
+-------------------------------------+------+----------+
|   MANTISSA  (24 bits, fraction)     | SIGN | EXPONENT |
+-------------------------------------+------+----------+
        bits 31..8                       7      6..0
```

- **Mantissa** 24 bits, **always with implicit leading 1 in bit 31** for any nonzero value. Represents a value in [0.5, 1.0).
- **Sign** bit 7. 0 = +, 1 = –.
- **Exponent** bits 6..0, **excess-64 bias**. So stored `$40` = exponent 0, `$00` = exponent –64, `$7F` = exponent +63.
- **Zero** is the all-bits-zero longword (a special-case representation; the leading-1 invariant is broken on purpose).

Range: approximately **±9.22 × 10¹⁸** down to **±5.42 × 10⁻²⁰**, with about **7 decimal digits of precision** (one fewer than IEEE 754 single because FFP uses 24 mantissa bits with no hidden bit, vs. IEEE's 23 + hidden = 24 effective; the difference is in normalization edge cases). ([*RKM Libraries* ch. 35 — FFP Floating Point Data Format](http://www.theflatnet.de/pub/cbm/amiga/AmigaDevDocs/lib_35.html); [wiki.amigaos.net — Math Libraries](https://wiki.amigaos.net/wiki/Math_Libraries))

### K.2 Why FFP instead of IEEE 754?

1. **No FPU on the bare 68000.** The 68881 wasn't a standard option until the 68020 era.
2. **No denormals, no infinities, no NaN.** FFP can be implemented in a few hundred 68000 cycles per operation. Software IEEE 754 single is several times slower.
3. **Mantissa always normalized with explicit leading 1.** Simplifies the inner loop of arithmetic kernels — no hidden-bit shenanigans.

For Boing's needs (sphere coordinate transforms, bounce physics), FFP is more than enough precision and is the fastest option short of fixed point.

### K.3 mathffp.library LVOs

`OpenLibrary("mathffp.library", 0)` gives you a base; load it into A6 to call:

| Function | LVO | Operation |
|---|---|---|
| SPFix | -30 | FFP → 32-bit signed integer (truncate) |
| SPFlt | -36 | integer → FFP |
| SPCmp | -42 | compare D0 vs D1, set CCR |
| SPTst | -48 | test D0 vs 0 |
| SPAbs | -54 | absolute value |
| SPNeg | -60 | negate |
| **SPAdd** | -66 | D0 + D1 → D0 |
| **SPSub** | -72 | D0 – D1 → D0 |
| **SPMul** | -78 | D0 × D1 → D0 |
| **SPDiv** | -84 | D0 / D1 → D0 |
| SPFloor | -90 | floor |
| SPCeil | -96 | ceil |

[`mathffp.doc` autodoc; vscode-amiga-assembly mathffp docs](https://github.com/prb28/vscode-amiga-assembly/tree/master/docs/libs/mathffp)

### K.4 mathtrans.library LVOs

`OpenLibrary("mathtrans.library", 0)` similarly:

| Function | LVO | Operation |
|---|---|---|
| **SPSin** | -36 | sin(x), x in radians |
| **SPCos** | -42 | cos(x), x in radians |
| SPTan | -48 | tan(x) |
| SPSincos | -30 | sin & cos simultaneously |
| SPAsin | -54 | arcsin |
| SPAcos | -60 | arccos |
| SPAtan | -66 | arctan |
| SPLog | -72 | natural log |
| SPLog10 | -84 | log base 10 |
| SPExp | -78 | e^x |
| SPSqrt | -96 | square root |
| SPPow | -90 | x^y |
| SPSinh / SPCosh / SPTanh | -108 / -114 / -120 | hyperbolics |
| SPTieee | -126 | FFP → IEEE single |
| SPFieee | -132 | IEEE single → FFP |

(Exact LVOs from `mathtrans.fd` in Kickstart 1.3 SDK; cross-check `vendor/include/math/mathtrans_lib.i` for the canonical equates.)

### K.5 How Boing uses these

The structural scan found `boing.s` builds **sphere geometry tables** (`boing.s:601–850`) using `SPSin`/`SPCos`. Conceptually:

- Pick N latitude bands (rows from south pole to north pole) and M longitude steps per band.
- For each (band, step) compute the vertex `(x, y, z)` on the unit sphere as `(sin(lat)·cos(lon), cos(lat), sin(lat)·sin(lon))`.
- Multiply by the ball radius to get screen-space vertices.
- Cache the resulting table for fast per-frame access; only the ball's *rotation matrix* changes per frame.

Per-frame work then becomes: multiply each vertex by the current rotation matrix, project to 2D (just take x,y for an orthographic projection — the ball doesn't change perspective as it bounces), and issue AreaMove/AreaDraw/AreaEnd per polygon. The polygon's foreground pen is picked from a small palette based on facet orientation, giving the classic checkered "red on this band, white on that" pattern.

This is straightforward 3D rasterization done with software FFP — feasible on a 7 MHz 68000 because the sphere mesh is small (a few hundred polygons) and projection is orthographic.

---

## L. audio.device (demo plays three samples)

`audio.device` is the Exec-style device that arbitrates Paula's 4 audio channels among multiple tasks. The structural scan found `boing.s` opens it once, allocates channels, and plays three sound effects (most likely: bounce-on-floor, bounce-on-wall, and a third — perhaps a startup tone or a different impact pitch).

### L.1 Why use audio.device instead of poking Paula

In a multitasking system, two tasks could fight for the same audio channel. `audio.device` arbitrates: each task requests channels with a *preference list* of acceptable channel-mask combinations, and the device grants one based on availability and priority. A polite program that wants stereo sound asks for "channels 0+1 or 0+2 or 1+3 or 2+3" and accepts whatever comes back.

For a demo that wants the entire chipset to itself, raw Paula pokes are fine. For a friendly demo that wants to coexist with whatever else is playing — say, a Workbench notification sound — `audio.device` is the correct path. `boing.s` is the friendly version.

### L.2 The IOAudio request struct

`audio.device` operations use `struct IOAudio`, an extension of `IORequest`:

```c
struct IOAudio {
    struct IORequest ioa_Request;     // mn_Node, io_Device, io_Unit, io_Command, io_Flags, io_Error
    UWORD            ioa_AllocKey;    // filled in by ADCMD_ALLOCATE; identifies your grant
    UBYTE           *ioa_Data;        // pointer to sample (CMD_WRITE) or channel-mask list (ALLOCATE)
    ULONG            ioa_Length;      // sample length in bytes / mask-list length
    UWORD            ioa_Period;      // Paula period (124..65535)
    UWORD            ioa_Volume;      // 0..64
    UWORD            ioa_Cycles;      // number of plays; 0 = forever
    struct Message   ioa_WriteMsg;    // filled by device; usually ignored
};
```

- `io_Unit` is **a bitmask of channels**, not a small int. Bit 0 = channel 0, bit 1 = channel 1, etc.
- `ioa_Data` is overloaded: for `ADCMD_ALLOCATE` it points to a list of acceptable channel masks; for `CMD_WRITE` it points to the sample bytes in chip RAM.

### L.3 Allocation mask list

For `ADCMD_ALLOCATE`, `ioa_Data` is a `UBYTE *` to a list of channel-mask candidates and `ioa_Length` is the count. Common patterns:

| Mask | Channels | Use case |
|---|---|---|
| `1` | ch.0 only | mono on one side |
| `2`, `4`, `8` | each single channel | mono on each respective side |
| `3` | ch.0+ch.1 | stereo (one channel each side) |
| `5`, `10`, `12` | other stereo pairings | alternate stereo pairings |

The list is presented in priority order; the device grants the first one it can satisfy. For Boing playing one mono "boing" sample with pan, a list like `{1, 2, 4, 8}` ("any single channel") is common — the program then picks the channel based on impact side and re-allocates if necessary.

### L.4 Commands

| Command | Code | Purpose |
|---|---|---|
| **CMD_RESET** | 1 | reset device state |
| **CMD_READ** | 2 | return pointer to currently-playing block |
| **CMD_WRITE** | 3 | play sample |
| **CMD_STOP** | 5 | pause playback |
| **CMD_START** | 6 | resume |
| **CMD_FLUSH** | 8 | purge pending writes |
| **ADCMD_FINISH** | 7 | abort current write |
| **ADCMD_LOCK** | 8 | request notification if channels get stolen |
| **ADCMD_ALLOCATE** | 9 | reserve channels |
| **ADCMD_SETPREC** | 10 | change precedence |
| **ADCMD_FREE** | 11 | release channels |
| **ADCMD_WAITCYCLE** | 14 | signal when current cycle ends |
| **ADCMD_PERVOL** | 15 | change period & volume mid-play |

Flags in `io_Flags`:
- `ADIOF_PERVOL` — apply period/volume immediately on CMD_WRITE.
- `ADIOF_SYNCCYCLE` — wait for current cycle to end before applying.
- `ADIOF_NOWAIT` — ADCMD_ALLOCATE returns immediately if unavailable.
- `IOF_QUICK` — try to complete synchronously, avoiding the message round-trip.

[`audio.device` autodoc; wiki.amigaos.net — Audio Device](https://wiki.amigaos.net/wiki/Audio_Device)

### L.5 Typical lifecycle

```
; --- once at startup ---
OpenDevice("audio.device", 0, &io, 0)
io.ioa_Data    = allocmap; io.ioa_Length = sizeof(allocmap)
io.ioa_Request.io_Command = ADCMD_ALLOCATE
DoIO(&io)                       ; ioa_AllocKey & io_Unit now valid

; --- on each impact ---
io.ioa_Data    = sampleptr      ; in chip RAM
io.ioa_Length  = samplebytes
io.ioa_Period  = period         ; e.g. 428 for ~8 kHz playback
io.ioa_Volume  = 64
io.ioa_Cycles  = 1              ; one-shot
io.ioa_Request.io_Command = CMD_WRITE
io.ioa_Request.io_Flags   = ADIOF_PERVOL
SendIO(&io)                     ; async; the demo doesn't have to wait

; --- on quit ---
io.ioa_Request.io_Command = ADCMD_FREE
DoIO(&io)
CloseDevice(&io)
```

`boing.s` does this three times, once per sample, with three separate IOAudio requests and three separate sample buffers loaded from `boing.samples`.

### L.6 Why the single DMACON poke

The Explore agent found a `DMACON` write at `boing.s:1776`. The most plausible reason: **during a sample-buffer swap or initial allocation, the demo temporarily disables the audio channel directly to avoid an audible click**, or **re-enables it after audio.device's CMD_FLUSH leaves it disabled**. This is a known idiom in audio-device-using code — the device's state model doesn't always leave DMACON in exactly the desired state on every transition.

Confirmation needs reading the surrounding context when annotating; the takeaway for now is that this is *not* a hardware takeover, just a single surgical bit-twiddle.

---

## M. Putting it together: the `boing.s` runtime picture

Combining what the Explore agent found with the library reference above, the demo's runtime picture is:

### M.1 Startup phase (`boing.s:1–1175`)

1. Save stack, save CLI command-line buffer, find self via `FindTask(NULL)` into A4.
2. Open `dos.library`. CLI vs Workbench startup test on `pr_CLI(a4)`. Either parse argv (CLI) or wait for and stash WBStartup (WB).
3. Open `intuition.library`, `graphics.library`, `mathffp.library`, `mathtrans.library`.
4. Open `audio.device` and allocate channels.
5. Load `boing.samples` from disk via `dos.library` Open/Read.
6. Compute sphere vertex tables using `SPSin`/`SPCos` (boing.s:601–850).
7. Initialize physics constants (gravity, restitution, initial position/velocity) via `SPFlt`/`SPMul`/`SPAdd` etc.
8. `OpenScreen()` — 5 bitplanes, 320×200 lo-res — and `OpenWindow()` on it.
9. Initialize a `RastPort` with `InitArea`, `InitRastPort`, etc.

### M.2 Main loop

Per frame (`src/main.s` `.nomsg` → `.frame_done`):

1. Poll the Window's UserPort for IDCMP messages (quit on the close gadget; a click toggles pause).
2. Rotate the palette — rewrite the 14 cycled colour registers (`COLOR02..15` + `COLOR18..31`) to spin the ball. The ball bitmap is **never** redrawn; it was drawn once at startup.
3. Y physics (FFP gravity arc) + X physics (integer ±1 px, wall bounce); set the audio trigger on a floor/wall hit.
4. Write the ViewPort `RxOffset`/`RyOffset` (ball motion) and swap the staggered background bitplane pointer (keeps the wireframe room visually fixed).
5. `MakeScreen` + `RethinkDisplay` — commit the new palette/scroll to the system copperlist.
6. If a bounce occurred, `CMD_WRITE` the sample to `audio.device`.
7. Loop.

> Frame pacing is the `WaitTOF` *inside* `RethinkDisplay` (RKRM: "RethinkDisplay … also does a WaitTOF()") — one vblank per frame → the video field rate. The running loop adds **no** explicit `WaitTOF`; don't add one, it would double the wait and halve the rate. See [ANIMATION-DETAILS.md](ANIMATION-DETAILS.md) §1 and [DEVIATIONS.md](DEVIATIONS.md).

### M.3 Cleanup (`boing.s:1144–1175`)

1. `ADCMD_FREE` + `CloseDevice(audio.device)`.
2. `CloseWindow`, `CloseScreen`.
3. `FreeMem` everything allocated with `AllocMem`.
4. `CloseLibrary` everything opened (in reverse order).
5. WB path: `Forbid` + `ReplyMsg` to the saved WBStartup.
6. `RTS`.

### M.4 What the Amiga chipset is doing in parallel

While `boing.s` runs the main loop, the OCS chipset is independently:

- Streaming 5 bitplanes from chip RAM to Denise via DMA → producing the displayed image.
- Streaming sample data from chip RAM to Paula via DMA when audio.device has a CMD_WRITE in flight.
- Servicing the system Copper list each frame to load BPLxPTR / palette / BPLCONx.
- Servicing the Blitter for each `AreaEnd` polygon fill (and any `BltClear` calls).
- Generating vertical-blank interrupts that wake `WaitTOF()` and any other VBI-waiting task.

The 68000 spends its time in `SPSin`/`SPCos`/`SPMul` calls for sphere math, and in the AreaMove/AreaDraw/AreaEnd call sequence. The chipset does the actual pixel work.

That, in essence, is the Amiga's headline performance trick: **specialised DMA chips do the heavy lifting, leaving the CPU free for application logic and other tasks**.

---

## N. Appendix — not used by this demo

Included briefly for completeness; reference URLs in §References.

### N.1 The Copper (in detail)

Two-instruction-format coprocessor: MOVE (write a 16-bit immediate to a custom register) and WAIT (block until raster reaches a Y/X position). Used by graphics.library to install the per-frame display config, but `boing.s` never writes its own copper list.

Encoding:
- MOVE: IR1 bits 8..1 = register offset (8-bit, so addresses `$00`-`$1FE`); IR2 = 16-bit data; IR1 bit 0 = 0.
- WAIT: IR1 bits 15..8 = VP, 7..1 = HP; bit 0 = 1; IR2 bit 15 = BFD (ignore blitter), 14..8 = VE mask, 7..1 = HE mask, bit 0 = 0.
- End of list: `dc.w $FFFF,$FFFE` (a WAIT that can never satisfy).

Control registers: `COP1LCH/L` ($DFF080/$082), `COP2LCH/L` ($DFF084/$086), `COPJMP1/2` ($DFF088/$08A), `COPCON` ($DFF02E — CDANG bit allows blitter reg writes).

### N.2 The Blitter (in detail)

4 DMA channels (A, B, C source; D destination); 256 minterm functions of A/B/C; modes include logical copy, area fill, line draw, and inclusive/exclusive ascending/descending. graphics.library uses it for `BltClear`, `AreaEnd`, line drawing, etc.

Registers: BLTCON0/1 (minterm + shifts + masks), BLTAFWM/BLTALWM (first/last word masks), BLTAPT/BPT/CPT/DPT (source/dest pointers), BLTAMOD/BMOD/CMOD/DMOD (modulos), BLTAFDAT/BFDAT/CFDAT (first-word data registers, internal), BLTSIZE (the "go" register — writing it starts the blit).

[*AHRM* ch. 6 — Blitter Hardware, mirror](https://www.theflatnet.de/pub/cbm/amiga/AmigaDevDocs/)

### N.3 Hardware sprites (in detail)

8 sprite DMA channels. Each sprite is 16 px wide × arbitrary height, 2 bpp (3 visible colors + transparent). Color mapping per pair: SPR0/1 use COLOR17-19, SPR2/3 use COLOR21-23, SPR4/5 use COLOR25-27, SPR6/7 use COLOR29-31. Attached pairs (set ATTACH in odd-sprite CTL) give 4 bpp / 15-color sprites. Registers: SPRxPT, SPRxPOS, SPRxCTL, SPRxDATA, SPRxDATB. Not used by `boing.s` — the ball is too big for a sprite anyway.

### N.4 CIA-A / CIA-B chips

Two MOS 8520 Complex Interface Adapters:
- **CIA-A at `$BFE001`** — keyboard serial in, parallel port handshake, mouse/joystick fire buttons, drive LED, two 16-bit timers (Timer A, Timer B), 24-bit Time-Of-Day counter (50/60 Hz line frequency). Generates **INT2 (PORTS)**.
- **CIA-B at `$BFD000`** — parallel data port, serial handshake (RTS/CTS/DSR/DTR/DCD), floppy step/sel signals, two more timers, TOD counter clocked by hsync. Generates **INT6 (EXTER)**.

Register stride is `$100` (the 8520s are wired to A8–A15). `boing.s` does not touch them.

### N.5 68000 CPU details not used by `boing.s`

- 8 data registers D0–D7, 8 address registers A0–A7 (A7 = SSP/USP). All internally 32-bit; `.B`/`.W`/`.L` size suffixes select operand width.
- 24-bit address bus → 16 MB physical space.
- No MMU, no caches. Chip RAM is contended with chipset DMA: at high bitplane DMA loads the CPU runs at ~80% nominal; "nasty" blitter takes every free slot.
- Supervisor vs user mode: bit 13 of SR. User mode can't change IPL mask or use privileged instructions (STOP, RTE, MOVE-to-SR, MOVE USP). `boing.s` runs as a user-mode Exec task — never enters supervisor mode.
- Status register: bit 15 T (trace), bit 13 S (supervisor), bits 10–8 IPL mask, bits 4–0 XNZVC condition codes.
- `STOP #imm` halts the CPU until an interrupt of higher priority arrives. Useful for low-power-wait, but the demo uses `WaitTOF()` instead.

### N.6 Hard-takeover idiom (`LoadView(NULL)`)

For completeness, a "real" hardware-takeover demo (which `boing.s` is **not**) does this:

```asm
move.l   _GfxBase(pc),a6
move.l   gb_ActiView(a6),OldView    ; save current view
sub.l    a1,a1
jsr      _LVOLoadView(a6)           ; LoadView(NULL) — kill OS display
jsr      _LVOWaitTOF(a6)            ; let it take effect
jsr      _LVOWaitTOF(a6)
jsr      _LVOOwnBlitter(a6)
jsr      _LVOWaitBlit(a6)
; save DMACONR, INTENAR, ADKCONR, COP1LC, COP2LC into local vars
; install custom copper list, custom interrupt handlers, etc.
; ...
; on exit, restore the saved state and LoadView(OldView)
```

This is the 1984-CES-Boing style. The OS-friendly Boing in this repo deliberately avoids the hard takeover so it can run as a normal multitasking application.

---

## References

Primary hardware:

- [Amiga Hardware Reference Manual (3rd ed., Addison-Wesley) — online at theflatnet.de mirror](https://www.theflatnet.de/pub/cbm/amiga/AmigaDevDocs/) — chapters `hard_2.html` (Copper), `hard_3.html` (Playfield), `hard_4.html` (Sprites), `hard_5.html` (Audio), `hard_6.html` (Blitter), `hard_7.html` (System Control: DMA/Interrupts), `hard_d.html` (Memory Map), `hard_f.html` (CIA).
- [AHRM at amigadev.elowar.com (canonical online edition)](http://amigadev.elowar.com/read/ADCD_2.1/Hardware_Manual_guide/)
- [AHRM mirror at bastya.net](https://bastya.net/AmigaDevDocs/) — convenient when other mirrors are flaky.

Primary OS:

- [Amiga ROM Kernel Reference Manuals — Libraries (online)](http://amigadev.elowar.com/read/ADCD_2.1/Libraries_Manual_guide/) — ch. 14 (Workbench Startup), 17 (Intro to Exec), 18 (Adding a Library), 20 (Memory Allocation), 21 (Tasks), 26 (Exec Interrupts), 35 (Math Libraries / FFP format).
- [RKM Libraries mirror at theflatnet.de](http://www.theflatnet.de/pub/cbm/amiga/AmigaDevDocs/) — chapter files `lib_17.html` etc.
- [AmigaOS Documentation Wiki — Math Libraries](https://wiki.amigaos.net/wiki/Math_Libraries) — FFP format reference.
- [AmigaOS Documentation Wiki — Audio Device](https://wiki.amigaos.net/wiki/Audio_Device) — IOAudio command list.
- [AmigaOS Documentation Wiki — Exec Interrupts](https://wiki.amigaos.net/wiki/Exec_Interrupts) — autovector mapping.
- [AmigaOS Documentation Wiki — Exec Memory Allocation](https://wiki.amigaos.net/wiki/Exec_Memory_Allocation) — MEMF_CHIP semantics.
- [AmigaOS Documentation Wiki — Classic Graphics Primitives](https://wiki.amigaos.net/wiki/Classic_Graphics_Primitives) — LoadView, WaitTOF, OwnBlitter usage.
- [AmigaOS Documentation Wiki — Intuition Screens](https://wiki.amigaos.net/wiki/Intuition_Screens) — NewScreen/NewWindow.
- [AmigaOS Documentation Wiki — Workbench Library](https://wiki.amigaos.net/wiki/Workbench_Library) — WBStartup message protocol.

Encyclopedic:

- [Wikipedia — Amiga 1000](https://en.wikipedia.org/wiki/Amiga_1000)
- [Wikipedia — Original Chip Set](https://en.wikipedia.org/wiki/Original_Chip_Set)
- [Wikipedia — MOS Technology Agnus](https://en.wikipedia.org/wiki/MOS_Technology_Agnus)
- [Wikipedia — Motorola 68000](https://en.wikipedia.org/wiki/Motorola_68000)
- [Wikipedia — Kickstart (Amiga)](https://en.wikipedia.org/wiki/Kickstart_(Amiga))

Per-register reference / community-maintained:

- [amiga-dev Wikidot — Hardware index](http://amiga-dev.wikidot.com/information:hardware) — pages for BPLCON0, BPLCON2, DMACONR, INTENAR, ADKCONR, BPLxMOD, DDFSTRT, etc.
- [Coppershade — Custom Chip Register List](http://coppershade.org/articles/Code/Reference/Custom_Chip_Register_List/) and [INTENA notes](http://coppershade.org/articles/Code/Reference/INTENA/) — community-curated complete register offsets.
- [vscode-amiga-assembly hardware/LVO docs (github.com/prb28)](https://github.com/prb28/vscode-amiga-assembly/tree/master/docs) — clean Markdown extracts of register and LVO definitions.

Modern walk-throughs:

- [Mark Wrobel — Amiga Machine Code letters](https://www.markwrobel.dk/) — modern tutorials (Letter III: Copper; Letter IV: DMA; Letter X: Memory) with worked assembly examples.
- [Bumbershoot Software — Amiga 500: How Libraries Work](https://bumbershootsoft.wordpress.com/2022/06/12/amiga-500-how-libraries-work-and-how-to-use-them/) and [Drawing a Bitmap on the Bare Metal](https://bumbershootsoft.wordpress.com/2024/06/22/amiga-500-drawing-a-bitmap-on-the-bare-metal/) — modern walk-through of the same APIs `boing.s` uses.
- [jvaltane "Howtocode" — Copper](http://jvaltane.kapsi.fi/amiga/howtocode/copper.html) and [Blitter](http://jvaltane.kapsi.fi/amiga/howtocode/blitter.html) — concise hands-on hardware.
- [Codetapper — Palette](https://codetapper.com/amiga/maptapper/documentation/gfx/gfx-palette/) and [sprite-tricks pages](https://codetapper.com/amiga/sprite-tricks/) — practical analysis of how shipped games used copper, sprites, palette.
- [Sakura-IT — Amiga Programming Examples (asm/MiniStartup)](https://github.com/Sakura-IT/Amiga-programming-examples/blob/master/ASM/MiniStartup/startup.s) — minimal CLI/WB-aware assembly startup.
- [open-amiga-sampler — Sample rates deep dive (Appendix A)](https://github.com/echolevel/open-amiga-sampler/wiki/Appendix-A:-Sample-rates-deep-dive) — period/rate math, NTSC vs PAL clock constants.

Demo-specific:

- See [DEMO-BACKGROUND.md](DEMO-BACKGROUND.md) §11 for Boing-Ball-specific references and primary-source URLs, and §7 for the variant-lineage analysis (including the byte-level identification of this repo's `boing.s` as Harry Sintonen's disassembly of the AMICUS Disk 9 binary).

---

*The next pass on this codebase will add comments to `boing.s` showing how each call into these libraries achieves a specific visible effect in the demo. See [DEMO-BACKGROUND.md](DEMO-BACKGROUND.md) §6 for the high-level technical hooks and this document for the underlying API reference.*
