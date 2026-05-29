# DEMO-BACKGROUND.md — The Amiga Boing Ball

Companion to [AMIGA-KNOWHOW.md](AMIGA-KNOWHOW.md). This document covers the **history and cultural context** of the famous bouncing-ball demo, plus a high-level enumeration of the Amiga hardware features it advertised. Deep register/library reference lives in the companion file.

---

## 1. Executive summary

The "Boing Ball" was a short tech demo written by **Dale Luck** and **R. J. Mical** for the **1984 Winter Consumer Electronics Show** in Las Vegas (Jan 7–10, 1984). It showed a red-and-white checkered ball bouncing and apparently rotating across a wireframe room while a sampled metallic "BOING!" clang played in stereo, panned to whichever side of the screen the ball impacted. The point was to prove that the unannounced "Lorraine" prototype — what would become the Commodore Amiga 1000 — could do **smooth full-color animation with synchronized stereo digital audio while leaving the CPU free**, at a time when no other affordable microcomputer could put any one of those three things on screen, let alone all three at once.

Boing became Amiga's defining symbol. The original engineering team wanted it adopted as the corporate logo; Commodore overruled them in favor of the rainbow checkmark, but Boing kept reappearing on splash screens, screensavers and merchandise for the next 40+ years. ([Wikipedia: Amiga](https://en.wikipedia.org/wiki/Amiga); [GenerationAmiga: Story of the Boing Ball](https://www.generationamiga.com/2020/04/14/amiga-history-the-story-of-the-boing-ball/))

> **Important note about *this* source file.** The `boing.s` in this repository is **not** the original 1984 CES code — that source has never been publicly released and appears to be lost (§7.2). What this file *is*, verified by byte-level diff: **Harry Sintonen's disassembly of the "polite" Boing binary distributed on AMICUS Disk 9** (a late-1980s Amiga PD compilation), redistributed via Aminet as [`misc/antiq/boing.lha`](https://aminet.net/package/misc/antiq/boing). The AMICUS binary is itself a Commodore-Amiga internal re-implementation that uses `graphics.library` polygon fill (`AreaMove`/`AreaDraw`/`AreaEnd`) and `mathtrans.library` `SPSin`/`SPCos` for sphere geometry to author the ball **once at startup**, then runs the **same per-frame animation pipeline as the lost 1984 CES original** — static ball bitmap with palette-register cycling for rotation, ViewPort `RxOffset`/`RyOffset` for motion, and `audio.device` `CMD_WRITE` with inter-aural time delay for the stereo bounce samples. It opens an Intuition screen, multi-tasks cleanly under Workbench, exits cleanly on user input, and touches `$DFF000` register space exactly once (a `DMACON` write). The "polite" / *didactic* label refers to the library-driven setup, the multitasking-friendly OS scaffolding, and the programmatic (vs. raw-poke) graphics calls — **not** to a different animation technique. §7 of this document maps the full variant lineage; [BOING-ANALYSIS.md](BOING-ANALYSIS.md) has the full per-function reading.

---

## 2. Origin story

### 2.1 When and where

The demo's public debut was the **1984 Winter Consumer Electronics Show**, held **January 7–10, 1984, at the Las Vegas Convention Center**. CES then ran twice yearly — Winter CES in Las Vegas, Summer CES in Chicago. Several secondary sources conflate the two; Boing premiered in **Las Vegas in January 1984**, and a polished version was shown again at Summer CES in **Chicago in June 1984**. ([Wikipedia: Consumer Electronics Show](https://en.wikipedia.org/wiki/Consumer_Electronics_Show); [Wikipedia: History of the Amiga](https://en.wikipedia.org/wiki/History_of_the_Amiga); [Commodore International Historical Society: 1984 Winter CES](https://commodore.international/2024/04/28/commodore-behind-the-scenes-at-1984-winter-ces/))

The most-repeated internal date for Boing's completion is **the night of January 4, 1984** — finished hours before the show floor opened. ([XScreenSaver `boing(6)` man page by Jamie Zawinski](https://man.archlinux.org/man/extra/xscreensaver/boing.6.en); [GenerationAmiga](https://www.generationamiga.com/2020/04/14/amiga-history-the-story-of-the-boing-ball/))

### 2.2 The prototype it ran on

The hardware shown at CES 1984 was the **"Lorraine" breadboard** — Jay Miner's not-yet-fabricated custom chips substituted by **four boards' worth of TTL logic**. Workbench/Intuition were not stable enough to demo as a finished product, so Amiga Corp built short standalone vignettes that exercised one capability at a time — Boing being the loudest of them. The team kept the breadboard in **a small enclosed gray room** at the booth and gave private demos. ([Jeremy Reimer, *A History of the Amiga*, josh8 mirror](https://josh8.com/mirror/amiga.html); [Low End Mac: The Amiga Story](https://lowendmac.com/2016/the-amiga-story-conceived-at-atari-born-at-commodore/))

### 2.3 The "Joe Pillow" anecdote — corrected

A long-standing legend says Amiga Corp bought their fragile prototype its own airline seat under the name "Joe Pillow" for the flight to CES. **Dale Luck himself debunked the timing in 2025:**

> "Joe Pillow was created by RJ Mical and I on a flight from New Orleans to San Jose in February of 1984."
>
> — Dale Luck, quoted on [AmigaMeditation.guru: Will the real Joe Pillow please stand up?](https://amigameditation.guru/2025/05/03/will-the-real-joe-pillow-please-stand-up/)

Joe Pillow originated as a prank on a return flight from **SoftCon in New Orleans**, weeks *after* Winter CES, not on the trip to it. The Lorraine prototype *was* extremely fragile and *was* flown carefully to CES — but probably not under the Joe Pillow name. Cite that anecdote carefully; Wikipedia's *History of the Amiga* still repeats the older conflated version.

### 2.4 Was it really written overnight?

In essence, yes — but built from prototyped pieces. The canonical retelling, originating in **Jeremy Reimer's *A History of the Amiga*** and propagated through nearly every Amiga history since:

> "The marketing guys took the technical staff out for Italian food. Everyone got drunk and wandered back to the exhibit hall to work some more on demos. **Late that night, in their drunken stupor, Dale and RJ put the finishing touches on what would become the canonical Amiga demo, _Boing_.**"
>
> — [Reimer / josh8 mirror](https://josh8.com/mirror/amiga.html)

The constituent ideas — the sphere bitmap math, the sampled clang, the bitplane scroll trick — had been prototyped for some time before. CES night finished the integration.

---

## 3. The people

Four names recur across every credible source:

### 3.1 R. J. Mical (Robert J. Mical)

Software/Intuition lead at Amiga Corp. Came from **Williams Electronics**, where he had worked on coin-op classics including *Defender* and *Sinistar*. Wrote much of Boing's code and most of the Intuition/Workbench UI. Later co-founded the **3DO Company** and the **Game Boy Advance / PSP-era SCE Studio Liverpool**. ([Wikipedia: RJ Mical](https://en.wikipedia.org/wiki/RJ_Mical))

### 3.2 Dale Luck

Software engineer; became Amiga's graphics.library expert. Designed the color-cycling palette trick that gives the ball its rotation illusion (see §6.1). Co-author with Mical of the original Boing. Later co-founded **GfxBase** and worked on Amiga-derivative platforms through the 1990s and 2000s. ([Amiga Graphics Archive — Dale Luck](https://amiga.lychesis.net/artists/DaleLuck.html))

### 3.3 Sam Dicker

Another Williams Electronics alumnus (*Defender*, *Sinistar*, *Robotron*) who joined Amiga Corp with Mical. Most often credited with the **audio-playback engine** that streams the boing sample through Paula's DMA channels. ([The Retro Hour EP427 — interview with Sam Dicker](https://theretrohour.com/williams-electronics-and-designing-the-amiga-with-sam-dicker-the-retro-hour-ep427/))

### 3.4 Bob Pariseau

Amiga's chief of software design under Jay Miner. **Did not author Boing's code**, but **is the source of the actual "boing" sound** — he hit an aluminum garage door with a foam baseball bat (the team kept those around the office for whacking each other awake during long sessions) while an Apple II digitized the result from inside the garage:

> "The booming noise of the ball was Bob Pariseau hitting an aluminium garage door with one of those foam bats, and an Apple II digitised it from inside the garage."
>
> — [Reimer / josh8 mirror](https://josh8.com/mirror/amiga.html), corroborated by the [Chester County Press profile of Pariseau](https://www.chestercounty.com/2018/06/06/174738/making-sense-of-high-tech)

Pariseau later MC'd the Boing reprise at the 1985 Lincoln Center Amiga 1000 launch (§5.2).

### 3.5 Adjacent contributors who enabled Boing without being credited as authors

- **Jay Miner** — designed the Agnus/Denise/Paula custom chips that make Boing possible. The original analog-and-digital architect of the entire Amiga; previously designed the Atari 2600's TIA and the Atari 8-bit's ANTIC/GTIA. ([Wikipedia: Jay Miner](https://en.wikipedia.org/wiki/Jay_Miner))
- **Carl Sassenrath** — wrote **Exec**, the preemptive multitasking microkernel that lets Boing coexist with Workbench in the demo's later pitch. **Not a Boing author.** ([Wikipedia: Carl Sassenrath](https://en.wikipedia.org/wiki/Carl_Sassenrath))

---

## 4. What people saw and heard

### 4.1 Visual

- A **red-and-white checkered ball**, roughly 140 × 100 pixels at 320 × 200 (NTSC) lo-res, bouncing up and down across the screen. ([Amiga Graphics Archive: AmigaBoingBall](https://amiga.lychesis.net/applications/AmigaBoingBall.html); [pouët.net: Boing](https://www.pouet.net/prod.php?which=27096)) (This widely-cited "~140×100" is the general-folklore figure; *this repo's* AMICUS variant measures ~**111 × 96 px** in a UAE capture — see [ANIMATION-DETAILS.md](ANIMATION-DETAILS.md) §6.)
- The ball **appears to rotate** as it travels — but the rotation is *not* a 3D rendering. It's a palette trick (see §6.1).
- A **shadow** lies under/behind the ball, projected onto a **wireframe grid floor**. The shadow uses a dedicated bitplane whose palette duplicates the grid's colors but darker, so where the shadow overlaps the grid the grid appears darkened without redrawing it.
- The ball **deforms slightly on impact and recovers** — a squash effect — driven by simple per-frame physics calculated on the 68000.
- Five bitplanes total: 3 for the ball (8 colors of red/white/highlight/shading), 1 for the grid, 1 for the shadow. ([Amiga Graphics Archive](https://amiga.lychesis.net/applications/AmigaBoingBall.html))

### 4.2 Audio — the "BOING!"

A **sampled metallic clang**, played through Paula's hardware DMA audio channels, **panned with the ball's horizontal position** so the impact appears to come from the side of the screen the ball hits. Stereo panning and a deeper "boom" version were refined shortly after the first CES showing — the very first Winter CES version had a less developed audio mix. ([Amiga Graphics Archive](https://amiga.lychesis.net/applications/AmigaBoingBall.html))

The sample played through Paula in 8-bit signed PCM, streamed from chip RAM by DMA at essentially **zero CPU cost** — the CPU set up the channel registers once and the chip kept playing.

### 4.3 The reaction

In January 1984 no other affordable microcomputer could do anything close. Compare:

| Machine | Color | Sound | Hardware acceleration | Multitasking |
|---|---|---|---|---|
| IBM PC + CGA | 4 colors | PC speaker beep | none | no |
| Apple II | 6 lo-res / 16 hi-res | 1-bit toggle | none | no |
| Macintosh (announced Jan 24 1984, 9 days later) | 1-bit monochrome | 4-bit DAC | none | no (Switcher came later) |
| Atari 800 / C64 | up to 16/16 colors with raster tricks | SID/POKEY tones + 4-bit samples | sprites, raster IRQ | no |
| **Amiga "Lorraine"** | **32 of 4096** | **4-ch stereo 8-bit PCM** | **Copper, Blitter, hw sprites** | **yes (Exec)** |

Hence the now-iconic anecdote, repeated across nearly every Amiga history:

> "Because the bouncing ball animation was so fast and smooth, attendees did not believe the Amiga prototype was really doing the rendering. **Suspecting a trick, they began looking around the booth for a hidden computer or VCR.**"
>
> — original wording from [Reimer / josh8 mirror](https://josh8.com/mirror/amiga.html); quoted in [Wikipedia: Amiga](https://en.wikipedia.org/wiki/Amiga), [GenerationAmiga](https://www.generationamiga.com/2020/04/14/amiga-history-the-story-of-the-boing-ball/), and [Amiga Graphics Archive](https://amiga.lychesis.net/applications/AmigaBoingBall.html).

Some retellings add that visitors **lifted the table skirt** looking for the "real" computer.

---

## 5. The 1985 reprise and corporate fallout

### 5.1 Steve Jobs and the Tramiel/Atari maneuver

Before Commodore acquired Amiga Corp, several other suitors saw the demo:

- **Steve Jobs** was shown the Lorraine and dismissed it: he said "**there was too much hardware**" — despite the redesigned board being just three custom silicon chips (the breadboard he saw was much larger). The Macintosh debuted nine days after CES with no comparable capabilities. ([Wikipedia: History of the Amiga](https://en.wikipedia.org/wiki/History_of_the_Amiga))
- **Atari** (then pre-Tramiel) offered Amiga Corp **not equity but a $500,000 bridge loan** in exchange for rights to the Lorraine motherboard design — the financial squeeze that ultimately forced Amiga Corp into Commodore's arms in August 1984.
- **Jack Tramiel** (forming Tramel Technology, soon to be Atari Corp) reportedly told Amiga staff he was "interested in the chipset but not the staff" — accelerating the deal with Commodore.

### 5.2 The Lincoln Center launch — July 23, 1985

Commodore officially launched the **Amiga 1000 at the Vivian Beaumont Theater, Lincoln Center, in New York City on July 23, 1985** — the famous gala where Andy Warhol painted Debbie Harry live on stage using the Amiga. Boing was used as the **closing demo / grand finale**, with **Bob Pariseau MC'ing the demo portion**. ([Wikipedia: Amiga 1000](https://en.wikipedia.org/wiki/Amiga_1000); [The Digital Antiquarian: The 68000 Wars, Part 3](https://www.filfre.net/2015/04/the-68000-wars-part-3-we-made-amiga-they-fucked-it-up/))

By this point the demo's pitch had broadened: it now *also* showed that the Amiga's **preemptive multitasking** worked. You could drag the Workbench screen down to reveal Boing bouncing in the background, push it back up, and both kept running smoothly. RJ Mical's later talks routinely make this point — the OS and the chipset were doing their jobs simultaneously.

---

## 6. How the original (1984) demo worked — high-level technical hooks

This section enumerates the Amiga features Boing *advertised*. Each one is described in full in [AMIGA-KNOWHOW.md](AMIGA-KNOWHOW.md).

### 6.1 The ball is a static bitmap; "rotation" is palette cycling

The single most important technical insight about Boing: **the ball is drawn once into chip RAM at startup; the pixels never change during the demo**. Apparent rotation is produced by rotating the **palette registers** (`COLOR00`–`COLOR31`) by one slot every few frames. The ball's checker stripes are drawn in colors that, when cycled, make the stripes appear to march around the sphere.

> "Color cycling was used for the rotation using clever math to create the faceted ball object. The motion was accomplished by simply changing the horizontal and vertical fetch and display start for the boing ball."
>
> — [pouët.net technical comment on Boing](https://www.pouet.net/prod.php?which=27096)

Cost: about **8 word writes per frame** to swap palette entries. The CPU is essentially idle.

This palette trick is documented in detail (per-bitplane mapping, color count, shading scheme) in Jimmy Maher's *The Future Was Here* chapter ["Boing" — Stage Two: Rotation](https://direct.mit.edu/books/book/4417/chapter/189199/Boing) (MIT Press Platform Studies, 2012) — the most rigorous published technical analysis of the demo.

### 6.2 Motion is bitplane scroll, not blitting

The ball is **not** redrawn or blitted to its next position each frame. Instead, the **bitplane data-fetch and display-start registers** (`DDFSTRT` / `DIWSTRT` and the bitplane pointers `BPL1PT`..`BPL5PT`) are modified per frame so that the static ball bitmap appears at the new position. The CPU only computes the next-frame bounce velocity and the new offsets.

> "The motion of the ball is done by moving the scroll positions of the different bitplanes. … The CPU sets up the custom chipset, and once set up, the chipset runs by itself."
>
> — [pouët.net](https://www.pouet.net/prod.php?which=27096); reinforced by [Amiga Graphics Archive](https://amiga.lychesis.net/applications/AmigaBoingBall.html) and [Maher, *The Future Was Here*, "Boing" chapter](https://direct.mit.edu/books/book/4417/chapter/189199/Boing)

This is why the **Blitter is barely used** in the original Boing — there is no per-frame ball blit. Some later reimplementations (XScreenSaver `boing(6)`, "Boing 2", browser ports) do blit each frame; **the original 1984 demo does not**.

### 6.3 Copper for per-scanline orchestration

The **Copper** (Agnus's video-synchronized coprocessor; see [AMIGA-KNOWHOW.md §C](AMIGA-KNOWHOW.md)) executes the per-scanline color changes that produce the horizon gradient on the floor and, in later versions, the wireframe room's depth shading. It also synchronizes the palette-cycling rotation to the raster, so the rotation step happens at a consistent point in the frame.

### 6.4 Paula DMA audio with stereo panning

The boing sample is held in chip RAM and played by Paula's 4-channel hardware DMA audio. The CPU pokes the channel pointer/length/period/volume once per impact and Paula streams the sample out at the right pitch with the right volume on the right side, without further CPU involvement. Pan is achieved by routing the trigger to channel 0/3 (one stereo side) or channel 1/2 (the other) depending on the ball's screen position. See [AMIGA-KNOWHOW.md §E](AMIGA-KNOWHOW.md) for the per-register details.

### 6.5 Exec multitasking

While Boing's chipset tricks run, the **Exec multitasking microkernel** keeps Workbench, Intuition and any other launched processes running on the same 68000. Boing's CPU footprint is so low (palette cycling + scroll-register updates + bounce physics + audio triggering) that there's spare 68000 time for the whole OS — proving the platform's headline pitch about *real* preemptive multitasking on a home computer.

### 6.6 Five bitplanes, dual-purpose

The ball uses 3 bitplanes (8 colors); the floor grid uses 1 bitplane; the shadow uses 1 bitplane with a palette deliberately overlapping the grid's colors but darker. Five planes × 320 × 200 = the standard NTSC lo-res 32-color setup, but Boing **partitions the bitplanes by content**, not by color-index range. Subtractive shadow rendering through palette overlap is the kind of trick that wins demoscene awards for the next decade.

### 6.7 What the original demo did **not** use

- **No hardware sprites.** The ball is a playfield bitmap, not an 8-sprite arrangement (32×whatever isn't large enough for a 140 px ball anyway).
- **No Blitter per-frame draw.** The ball never moves bits.
- **No interrupt handlers besides the standard VBI.** The whole demo runs from one VBI hook plus the chipset's autonomous DMA.

---

## 7. Variants of the Boing source code

The Boing Ball has been reimplemented dozens of times across four decades. The implementations differ in *fundamental* ways — rendering technique, motion model, audio path, degree of hardware exploitation — because each variant exists for a different reason. This section answers two questions: **(a) what variants of the source actually exist as public code?**, and **(b) why are they so different from each other?**

### 7.1 Lineage map at a glance

```
                          Dale Luck + RJ Mical, Jan 1984
                          ┌───────────────────────────────┐
                          │   ORIGINAL CES BOING SOURCE   │  ← lost; no public copy known
                          │   (Lorraine breadboard hack)  │
                          └───────────────┬───────────────┘
                                          │ conceptual descent only
                                          ▼
                          ┌───────────────────────────────┐
                          │  AMICUS DISK 9 "POLITE" BOING │  ← author unattributed in primary sources
                          │  (~1985–1987, OS-friendly bin)│     ("Probably Amiga/Commodore-Amiga Inc.")
                          └───────────────┬───────────────┘
                                          │ binary preserved as
                                          ▼  Aminet misc/antiq/boing.lha (1994)
                                          │
                                          │  disassembled by
                                          ▼  Harry "Piru" Sintonen
                          ┌───────────────────────────────┐
                          │  SINTONEN DISASSEMBLY (.asm)  │ ─ mirrored at filfre.net
                          └───────────────┬───────────────┘
                                          │ lightly preprocessed
                                          ▼ for vasm/PhxAss
                          ┌───────────────────────────────┐
                          │   THIS REPO'S boing.s         │
                          └───────────────────────────────┘

(Independent reimplementations — no shared code lineage with above:)

    • Maher reconstruction (C, 2009–2010)           — boing1.c … boing5.c
    • XScreenSaver boing(6) (jwz, 2005)             — OpenGL C
    • Sintonen 1k Boing (FAP 2013)                  — 68k asm; coords scraped from polite binary
    • AROS / quizno50 BoingDemo                     — SDL C, pre-rendered PNG frames
    • BoingNES (Brad Smith, 2021)                   — 6502 asm + C harness
    • OpenGL/GLFW examples/boing.c                  — bundled GLFW smoke-test
    • ESP32, Delphi, Pygame, browser/canvas, Vectrex, SpecBAS …
```

### 7.2 The original 1984 CES Boing — never publicly released

To the best of available evidence, **no public copy of the original CES code exists**, and there is no credible reason to believe one survives in a tractable form. This is an absence-of-evidence claim and should be hedged that way; the supporting reasoning:

- **Exhaustive negative-evidence search.** Every venue an Amiga historian would check — [Aminet](https://aminet.net/search?query=boing), [Demozoo](https://demozoo.org/productions/151545/), [pouët.net](https://www.pouet.net/prod.php?which=27096), [Amiga Graphics Archive](https://amiga.lychesis.net/applications/AmigaBoingBall.html), [Maher's MIT-Press companion site](http://amiga.filfre.net/?page_id=5), Wikipedia, the standard Amiga history monographs — contains no source labelled or attributable as the CES code. Every "Boing source" in circulation is either a disassembly of a later binary, a from-scratch reimplementation, or Maher's explicit reconstruction.
- **The single strongest indirect evidence.** Jimmy Maher — writing the peer-reviewed *The Future Was Here* (MIT Press Platform Studies, 2012) with direct access to surviving Amiga insiders — **wrote a five-stage C reconstruction in 2009–2010** rather than reprint the original code. The source header of [boing5.c](http://amiga.filfre.net/misc/Chapter2/boing5.c) states explicitly: *"This version was coded by Jimmy Maher in 2009 to 2010, and may be freely distributed."* If anyone had the original source it would have appeared in that book.
- **Physical plausibility for loss.** The CES demo was developed on a four-board TTL **breadboard** substituting for the not-yet-fabricated custom chips, with cross-assembly from a Sage IV / Sun host ([Reimer, *A History of the Amiga* — josh8 mirror](https://josh8.com/mirror/amiga.html)). The breadboard was retired after Commodore's August 1984 acquisition; Amiga Corp's source control was informal personal-floppy backups; the code targeted **prototype register addresses that did not match production silicon** ([Maher, Chapter 2 commentary](http://amiga.filfre.net/?page_id=5)). Even if a tape survived, it would not assemble against production Amiga 1000 hardware without modification. There was no marketing or technical reason to preserve it cleanly after Summer CES 1984.
- **No on-the-record testimony from the authors.** Despite searching the Sam Dicker [Retro Hour EP427 interview](https://theretrohour.com/williams-electronics-and-designing-the-amiga-with-sam-dicker-the-retro-hour-ep427/), Dale Luck's recent public posts (e.g. the [2025 Joe Pillow correction](https://amigameditation.guru/2025/05/03/will-the-real-joe-pillow-please-stand-up/)), and the standard Amiga historical archives, **I have not found a Luck/Mical/Dicker quote saying "we lost it" or "I still have it."** That specific testimony is not in print as far as I can determine. State it as "no public release is known" rather than "Luck confirmed it was lost."

What the original *did* — palette-cycling rotation, bitplane-scroll motion, dedicated-bitplane shadow, Paula DMA audio with stereo pan — is well-documented in third-party technical analysis (Maher Ch. 2; [pouët.net comments](https://www.pouet.net/prod.php?which=27096); [Amiga Graphics Archive](https://amiga.lychesis.net/applications/AmigaBoingBall.html)). What we don't have is the actual `MOVE.W #$0F00,$DFF182` lines that did it.

### 7.3 The AMICUS Disk 9 "polite" Boing — and how it became `boing.s` in this repo

The **only Boing binary widely circulating in the Amiga PD ecosystem** is the executable that appeared on **AMICUS Disk 9**, a late-1980s public-domain disk compilation. It was redistributed via [Aminet `misc/antiq/boing.lha`](https://aminet.net/package/misc/antiq/boing) in 1994. The Aminet [`.readme`](https://aminet.net/misc/antiq/boing.readme) attributes the binary only to *"Probably Amiga/Commodore-Amiga Inc."* — the uploader was not certain.

**This is not the CES code.** It is a Commodore-Amiga internal re-implementation that:

- Opens `intuition.library`, `graphics.library`, `mathffp.library`, `mathtrans.library` via `OpenLibrary`.
- Calls `OpenScreen` then `OpenWindow` — an Intuition application, not a hardware takeover.
- Computes the ball bitmap ONCE at startup via sphere math (`_init_globe` + `_draw_globe`, using `mathtrans.library` `SPSin`/`SPCos`) and renders it as filled polygons via `AreaMove`/`AreaDraw`/`AreaEnd`. After that the bitmap is static; rotation/motion are done via palette cycling and ViewPort offsets just like the original CES demo. See [BOING-ANALYSIS.md](BOING-ANALYSIS.md) for the full per-function analysis.
- Plays the boing sample via `audio.device` (`ADCMD_ALLOCATE`, `CMD_WRITE`).
- Touches `$DFF000` exactly once (a `DMACON` raster-DMA bit nudge — `boing.s:1776`).

**Provenance chain to this repo:**

1. **AMICUS Disk 9 binary** (Boing! + Boing.samples + Boing!.info icon), ~1985–1987 Commodore-Amiga internal.
2. → **Aminet [misc/antiq/boing.lha](https://aminet.net/package/misc/antiq/boing)**, uploaded 1994-03-27.
3. → **Harry "Piru" Sintonen disassembles the binary** with an IRA-style disassembler. Result mirrored at [sintonen.fi/temp/boing.asm](https://sintonen.fi/temp/boing.asm) and at [filfre.net Chapter 2 boing.asm](http://amiga.filfre.net/misc/Chapter2/boing.asm).
4. → **This repo's `boing.s`** is byte-identical to that Sintonen disassembly except for four cosmetic preprocessing changes (`INCDIR "include"` block prepended for vasm/PhxAss; `_custom` renamed to `custom = $dff000`; `.` characters in labels replaced with `__` because some assemblers reject them; one redundant `SECTION` directive removed). All Sintonen-style address-suffixed section names (`boing000000,CODE`, `boing0001C4,DATA`, `boing00037C,CODE`) and all `_LVO*` calls are preserved verbatim. The section-name format is a disassembler artefact and would not appear in any hand-written file — that alone is sufficient identification.

**Authorship of the polite binary remains a gap.** It is widely *believed* to be Luck/Mical retargeted to OS calls, but no primary source confirms who at Commodore-Amiga produced the OS-friendly redistribution. The Carolyn Scheppner / CATS (Commodore Amiga Technical Support) team is the plausible institutional home — they produced the developer samples that taught "good Amiga programming style" — but I found no document naming the specific engineer responsible.

### 7.4 Maher's five-stage C reconstruction (2009–2010, MIT Press)

The most rigorous published reconstruction — and the only publicly available implementation that captures the **original CES demo's technique** rather than the polite OS-friendly variant. Worth reading alongside this repo's `boing.s` because it shows, in short readable C, the exact tricks the AMICUS polite binary deliberately abandoned.

#### 7.4.1 What it is

Jimmy Maher, an academic computing historian, wrote a sequence of five short Amiga C programs in 2009–2010 that incrementally re-create the visual and auditory behaviour of the 1984–1985 demo. Each file adds **one** custom-chip technique to the previous one. The files grow gracefully — 573 → 610 → 653 → 712 → 903 lines — as each stage layers on a single new feature, which makes them ideal for study one stage at a time. All five live on Maher's *Filfre* companion site under [amiga.filfre.net/?page_id=5](http://amiga.filfre.net/?page_id=5):

| Stage | File (size) | Screen | Adds | Custom-chip / OS features exercised |
|---|---|---|---|---|
| 1 | [boing1.c](http://amiga.filfre.net/misc/Chapter2/boing1.c) (573 lines) | 320×200×**4** (16 colors) | Opens an Intuition screen, clears it, draws the static ball image | `OpenScreen`, `CUSTOMSCREEN\|CUSTOMBITMAP`, `__chip` qualifier for chip-RAM data, manual `BitMap` setup, ball bitmap as inline `UWORD __chip` array |
| 2 | [boing2.c](http://amiga.filfre.net/misc/Chapter2/boing2.c) (610 lines) | 320×200×4 | **"The rotation animation to the ball, which is accomplished through palette color cycling only"** (Maher's own header text) | `LoadRGB4`, the canonical color-register trick — the ball pixels never change; only the palette rotates |
| 3 | [boing3.c](http://amiga.filfre.net/misc/Chapter2/boing3.c) (653 lines) | 320×200×4 | **"The horizontal and vertical bouncing motion to the ball, which is accomplished entirely through manipulating the X and Y offsets of the viewport"** (Maher's header) | `ViewPort` `DxOffset`/`DyOffset`, `MakeVPort`, `MrgCop`, `LoadView` — the ball bitmap is never blitted to a new position |
| 4 | [boing4.c](http://amiga.filfre.net/misc/Chapter2/boing4.c) (712 lines) | 320×200×**5** (32 colors) | The static, non-scrolling wireframe background. **This is where the 5th bitplane appears** — one extra plane lets the background sit fixed while the ball plane scrolls in front of it | dual-bitmap composition; the 5th plane's bit toggles between low (colors 0–15) and high (colors 16–31) palette halves |
| 5 | [boing5.c](http://amiga.filfre.net/misc/Chapter2/boing5.c) (903 lines) | 320×200×5 | The sampled "boom" sound on impact, panned to the impact side | `OpenDevice("audio.device")`, `IOAudio`, channel-mask allocation, `CMD_WRITE` |

#### 7.4.2 The canonical attribution (verbatim from every file's header)

The opening comment of every file in the set is essentially identical, modulo the stage number and the "adds X" sentence. From the verbatim text of [boing5.c](http://amiga.filfre.net/misc/Chapter2/boing5.c) lines 1–10:

> ```
> File: boing5.c
>
> What follows is the fifth of five stages of a reconstruction of the original
> Amiga Boing demo that was written by Dale Luck and R.J. Mical in 1984 to 1985.
> This version was coded by Jimmy Maher in 2009 to 2010, and may be freely
> distributed.
>
> This program was developed with Lattice C 5.02 running under KickStart and
> Workbench 1.3, and therefore should be certain compile successfully in that
> environment. Your milage may vary with other environments.
>
> This final stage of the reconstruction adds the sampled "boom" sound.
> ```

Note two precise points from this header that are useful for citation:

1. **"Dale Luck and R.J. Mical in 1984 to 1985"** — Maher dates the original's authorship as a **two-year span**, not just CES night 1984. This corroborates the broader history: the CES version evolved into the Summer-CES-1984 version, the Chicago June 1984 version, and again into the polished 1985 Lincoln Center version. "The original Boing" is not one source file but a small family of incremental refinements over 18 months.
2. **"may be freely distributed"** — a permissive disclaimer rather than an OSI-approved license, but functionally equivalent to public-domain / "do whatever you want" for hobby and educational reuse.

#### 7.4.3 Why Maher chose to reconstruct rather than reprint

The reconstruction is the practical companion to *The Future Was Here: The Commodore Amiga* (MIT Press, 2012) — the second volume in the **MIT Press Platform Studies** series edited by Ian Bogost and Nick Montfort, following *Racing the Beam* (Bogost & Montfort's own study of the Atari 2600). The series' methodological commitment is that *you cannot understand a platform without understanding its hardware constraints*, which the book makes good on by structuring its Chapter 2 — titled simply "Boing" — around the same five stages: *Stage One: Ball / Stage Two: Rotation / Stage Three: Bounce / Stage Four: Background / Step 5: Boom*, plus framing sections "Enter Boing", "Introducing Sound", "Lessons from the Boing Demo", and "A Computing Icon". Prose explanation lives in the chapter; the runnable C is in the companion files.

The pedagogical move is unmistakeable: rather than describe palette cycling in the abstract, Maher wants the reader to compile `boing2.c`, run it on a real or emulated Amiga 1000 under Kickstart 1.3, and *see* the rotation happen with the bitmap unchanged. Same for the viewport-offset bounce in `boing3.c` — see it, then read why it's cheaper than blitting.

The corollary: if the Luck/Mical source were available, Maher could not use it for this purpose anyway. The original is a *monolithic standalone hack that exercises every chipset feature at once*. The five-stage reconstruction is **didactically separable** — each stage exercises one feature in isolation so the reader can study it independently. The series-wide editorial constraint forced a clean, decomposable reimplementation.

The fact remains, however: that a professional Amiga historian with direct access to the surviving Amiga team chose to write new code from scratch rather than reprint preserved source is the strongest publicly available indirect evidence that **no Luck/Mical original source is in any archive he could reach.** See §7.2 for the full chain of reasoning.

#### 7.4.4 Technical fidelity to the original — point by point

The reconstruction is the implementation closest in **technique** to the lost CES original. Specifically:

- **Static bitmap, palette cycling for rotation (Stage 2).** Maher confirms this in his own header: *"the rotation animation to the ball, which is accomplished through palette color cycling **only**."* The ball pixels are written once into a `UWORD __chip ball_bitplanes[]` array at file scope and never written again. Each frame the program rotates entries in `COLOR00..COLOR15`. CPU cost ≈ a dozen lines of C in the main loop. This is the canonical *color-register trick* and is the single most important behaviour to preserve when reconstructing the original.
- **Viewport-offset motion (Stage 3).** Again from Maher's own header: *"accomplished **entirely** through manipulating the X and Y offsets of the viewport."* The ball is never blitted to its next position; instead the program rewrites the `ViewPort`'s `DxOffset` and `DyOffset` each frame and calls `MakeVPort` / `MrgCop` / `LoadView` to rebuild the copper list. This is the higher-level graphics.library equivalent of the original CES demo's likely direct `DDFSTRT` / `DIWSTRT` / `BPL1MOD` / `BPL2MOD` register pokes — equivalent visible result, slightly higher abstraction.
- **The fifth bitplane for the background (Stage 4).** Stages 1–3 use 4 bitplanes (16 colors) for the ball alone. Stage 4 adds a 5th plane (32 colors) and uses the high bit as a low-vs-high palette selector — bits 5 = 0 picks colors 0–15 (the moving ball plane), bit 5 = 1 picks colors 16–31 (the static background plane). The actual palette in `boing5.c` shows this pattern explicitly: indices 0 and 1 differ between halves (grey-grid vs magenta-shadow), while indices 2–15 are duplicated identically — so the background can "tint" two specific entries without disturbing the ball's red-and-white colour scheme. This is precisely the "subtractive shadow rendering through palette overlap" the [Amiga Graphics Archive](https://amiga.lychesis.net/applications/AmigaBoingBall.html) attributes to the original.
- **Paula audio via `audio.device` (Stage 5).** Maher uses the device-driver path rather than direct `AUDxLC`/`LEN`/`PER`/`VOL` register pokes. This is one place where the reconstruction is *less* faithful to the inferred original — the CES demo plausibly poked Paula directly — but it preserves the user-visible behavior (panned mono sample triggered on impact) and matches what a 1989-era Amiga programmer reading the reconstruction would actually have written.

Read end-to-end, `boing1.c` through `boing5.c` are the closest thing in existence to **executable archaeology** of the 1984–1985 demo.

#### 7.4.5 Toolchain — what it targets and how to build it today

Per the source headers, the reconstruction was developed with:

- **Lattice C 5.02** — the standard late-1980s Amiga C compiler, also the dev environment for much of Workbench 1.3-era third-party software.
- **Kickstart and Workbench 1.3** — earlier Kickstart versions lack some of the `audio.device` APIs Stage 5 uses.
- The standard Amiga 1.x header set: `<exec/types.h>`, `<exec/memory.h>`, `<intuition/intuition.h>`, `<graphics/gfxbase.h>`, `<dos.h>`, `<devices/audio.h>`.

To build today, two practical paths:

1. **Native vintage toolchain.** Boot Workbench 1.3 in [FS-UAE](https://fs-uae.net/) or [WinUAE](https://www.winuae.net/) with a Kickstart 1.3 ROM image, install Lattice C 5.02 from its original disks, copy boingN.c to the emulated disk, `lc -L boingN.c`, run.
2. **Modern cross-compiler.** [Bebbo's amiga-gcc cross-toolchain](https://github.com/bebbo/amiga-gcc) targets Amiga 1.x APIs with modern gcc; the Maher sources compile cleanly with minor warnings.

#### 7.4.6 Why this matters for reading this repo's `boing.s`

This repo's `boing.s` uses the original CES animation technique — a static ball bitmap, no per-frame polygon redraw (see [BOING-ANALYSIS.md](BOING-ANALYSIS.md)). The actual situation:

- The **AMICUS source DOES use the original CES animation technique** — static ball bitmap + palette-register cycling + ViewPort offset writes for motion. Per-frame CPU work is minimal.
- The **only difference** between AMICUS and Maher's reconstruction is **how the static ball bitmap is *authored*** at startup:
  - **AMICUS** computes it programmatically from sphere geometry via `_init_globe` (sin/cos vertex table) and `_draw_globe` (polygon fill into the bitplanes). This takes a few seconds at startup and is the "considerable delay" Maher mentions in his `boing5.c` header.
  - **Maher's reconstruction** pre-bakes the bitmap into a `__chip` byte array in source, skipping the startup compute.
- After the bitmap exists, **both implementations animate identically**: palette cycling for rotation, ViewPort offsets for motion, background-plane-pointer compensation, audio.device for stereo bounces.

So the AMICUS source is actually **closer to the lost 1984 original** than Maher's reconstruction is — both in the per-frame animation pipeline AND in the programmatic bitmap authoring. Maher's deviation is exactly the one he flagged: pre-baking the bitmap "for the sake of clarity and simplicity" because by 2009 paint programs exist.

When you read this repo's source and want to compare with Maher's:

- For the **rotation question**, [boing2.c](http://amiga.filfre.net/misc/Chapter2/boing2.c) and `src/main.s` `.palette_step` show the same color-register-cycling loop, just in C vs. 68k asm.
- For the **motion question**, [boing3.c](http://amiga.filfre.net/misc/Chapter2/boing3.c) and `src/main.s` `.scroll_apply` both write ViewPort `DxOffset`/`DyOffset` (Maher) / `RxOffset`/`RyOffset` (AMICUS).
- For the **background-plus-ball compositing**, [boing4.c](http://amiga.filfre.net/misc/Chapter2/boing4.c) and the AMICUS `.bgrenderloop` both render the wireframe room into 16 staggered copies of bitplane 5 and select the appropriate copy per frame.
- For the **audio path**, [boing5.c](http://amiga.filfre.net/misc/Chapter2/boing5.c) and `src/anim.s` `_Boing` both use audio.device CMD_WRITE; the AMICUS version adds an inter-aural time delay trick (silence prefix) that Maher's version omits.
- For the **sphere geometry**, only AMICUS has it — `src/globe.s` `_init_globe` and `_draw_globe`. Maher's pre-baked bitmap has no equivalent code path.

See [BOING-ANALYSIS.md](BOING-ANALYSIS.md) for the full per-function reading.

### 7.5 XScreenSaver `boing(6)` — Jamie Zawinski, 2005

The most-distributed modern reimplementation. Pure C with OpenGL, runs on X11/Wayland/macOS/iOS/Android. Source at [github.com/Zygo/xscreensaver](https://github.com/Zygo/xscreensaver) (`hacks/boing.c`); manpage at [boing(6)](https://man.archlinux.org/man/extra/xscreensaver/boing.6.en).

> "This is a clone of the first graphics demo for the Amiga 1000, which was written by Dale Luck and RJ Mical at a Consumer Electronics Show in the early 1980s."
>
> — XScreenSaver `boing(6)` manpage by Jamie Zawinski

Permissive jwz-style license. Configurable parallels/meridians, optional smooth/lit/scanline/wireframe modes. **No code lineage to any Amiga implementation** — a clean rewrite to OpenGL.

### 7.6 Sintonen's 1k Boing (FAP 2013)

Harry Sintonen's 1024-byte assembly entry for the Finnish Amiga Party 2013. Source at [sintonen.fi/src/1kboing/1kboing.asm](https://sintonen.fi/src/1kboing/1kboing.asm). Curious lineage: Sintonen extracted the ball's `AreaMove`/`AreaDraw` coordinate data **by patching the AMICUS binary to dump coordinates at runtime**, then re-compressed the stream to 2 bits per coordinate. So the geometry is downstream of the polite binary, not the original CES code.

### 7.7 Other public reimplementations (non-exhaustive)

| Name | Author / year | Platform | Notes |
|---|---|---|---|
| **BoingNES** | Brad Smith, 2021 | NES (6502 + C harness) | CC-BY-4.0. Combines Amiga Boing and Atari ST BOINK on one cart. [Repo](https://github.com/bbbradsmith/boingnes) |
| **AROS BoingDemo** | quizno50, 2014 → AROS port 2021 | SDL 1.2 / C / GPL-2.0 | Pre-rendered PNG frames, not real-time sphere rendering. [Aminet](https://aminet.net/package/demo/intro/boingdemo.i386-aros) |
| **ESP32-AmigaBoingBall** | tobozo | ESP32 + TFT_eSPI | [Repo](https://github.com/tobozo/ESP32-AmigaBoingBall) |
| **AmigaBoingBall (Delphi)** | gbegreg | Windows / Delphi | Visual-builder rebuild. [Repo](https://github.com/gbegreg/AmigaBoingBall) |
| **opengl_boingball** | geekychris | OpenGL / C++ | Multi-platform desktop. [Repo](https://github.com/geekychris/opengl_boingball) |
| **GLFW `examples/boing.c`** | GLFW maintainers | GLFW / OpenGL | Library smoke-test demo. [Source](https://github.com/glfw/glfw/blob/master/examples/boing.c) |
| **stanchak.github.io/boing** | stanchak | Browser canvas | [Live demo](https://stanchak.github.io/boing/) |
| **thomasrunge/boing** | Thomas Runge | Python + Pygame | [Repo](https://github.com/thomasrunge/boing) |
| **aaboing** | Chris Green, 1993 | Amiga AGA (A1200/A4000) | C source on Aminet [dev/misc/aaboing.lha](https://aminet.net/package/dev/misc/aaboing). Unrelated lineage — demonstrates AGA blitter rather than OCS palette cycling. |
| **BasicBoing** | anon, 1987 | AmigaBASIC | Earliest tribute on Aminet. Aminet `dev/basic/BasicBoing.lha`. |

### 7.8 Why are the variants so different from each other?

Three forces pull the implementations apart:

#### (a) The original was a hard-takeover hack incompatible with multitasking.

The 1984 CES code wrote `BPLxMOD` / `BPLCON1` / `DIWSTRT` / palette registers directly; it almost certainly bypassed graphics.library's `LoadView` machinery (the demo predates a stable Kickstart) and used its own copper list. **Such code is fundamentally incompatible with the Amiga's headline pitch from the 1985 Lincoln Center launch onward — preemptive multitasking on a $1,295 home computer.** Shipping a Boing sample binary that single-tasked the chipset would have demonstrated exactly the kind of takeover the Amiga was supposed to obsolete. Hence Commodore-Amiga produced a *new, OS-respectful* implementation for distribution (the AMICUS binary in §7.3).

#### (b) The original wouldn't run on shipped hardware anyway.

Lorraine breadboard register addresses didn't match production OCS silicon (per Maher's Chapter 2 commentary; Reimer's history). A faithful redistribution would have required line-by-line retargeting — which is *more work* than rewriting in idiomatic OS-friendly style and serves no purpose, because Commodore-Amiga's target audience for sample code was developers learning to write *production* Amiga software, not historians.

#### (c) Modern reimplementations target environments where the Amiga chipset doesn't exist.

XScreenSaver, GLFW, the browser ports, the NES port, the ESP32 port — none of these has a Copper, a Paula, hardware sprites, or DMA-driven bitplane DMA. They have a frame buffer and a clock. The whole *point* of Boing's original implementation — using palette cycling and bitplane scroll to push CPU work to near zero — is meaningless on a platform where you have a GPU that does 60 fps polygon rasterisation as a baseline. So modern variants reimplement Boing as a software-physics + per-frame redraw program, which is the *opposite* of the original's design philosophy. They preserve the visual identity (red/white sphere, wireframe room, "BOING!" sound) and abandon the technique.

This is why the variants form three families:

- **Hardware-exploit family** — the lost CES original. Static bitmap, palette cycling, scroll-register motion, direct chipset register pokes. Visible only through reconstructions (Maher) and third-party technical analysis (pouët, Amiga Graphics Archive).
- **OS-respectful family** — AMICUS Disk 9 polite binary and its disassembly (this repo's `boing.s`). Uses graphics.library, audio.device, intuition.library; multi-tasks under Workbench. Note: this family *still* uses palette cycling + ViewPort offset for per-frame animation (same as the CES original) — the "OS-respectful" label refers to the library-driven *setup* phase (`OpenScreen`/`OpenWindow`/`AllocMem`/`audio.device`) and the *one-time* programmatic ball-bitmap rendering via graphics.library polygons, not to the animation pipeline. The "didactic Boing."
- **Cross-platform-reimplementation family** — XScreenSaver, GLFW, NES, ESP32, browser, etc. Visual homage; no chipset semantics preserved.

Reading the source in this repo, you are looking at the **OS-respectful** family. It is *historically* descended from the Luck/Mical original in concept and (probably) in some shared internal authorship at Commodore-Amiga, but mechanically it is a different program. See [AMIGA-KNOWHOW.md](AMIGA-KNOWHOW.md) for what the libraries it uses actually do under the hood.

### 7.9 Comparison table — what each variant actually does

| Variant | Rendering | Motion | Audio | Chipset access | OS interaction |
|---|---|---|---|---|---|
| **Original 1984 CES** (lost; behaviour inferred) | Static bitmap, **palette cycling** for rotation | **Bitplane scroll registers** (`BPLxMOD`, `BPLCON1`, `DIWSTRT`) | Direct Paula register pokes (`AUDxLC`/`LEN`/`PER`/`VOL`/`DMACON`) | **Hard takeover** of OCS chipset | Likely none; presumed `LoadView(NULL)`-equivalent or earlier than that |
| **AMICUS polite Boing** (= this repo's `boing.s`) | **Tessellated polygon mesh, 504 vertices in 9×56 lat/lon grid, ~392 visible quad facets after back-face culling. Drawn ONCE at startup** via per-facet `AreaMove`/`AreaDraw`/`AreaEnd`; per-vertex color `((band & 1) * 7 + longitude) mod 14 + 2` gives a half-cycle phase offset between adjacent bands → diagonal-stripe spiral. **Palette cycling rotates the spiral**. See [BOING-ANALYSIS.md §4.4](BOING-ANALYSIS.md). | **ViewPort `RxOffset`/`RyOffset` writes** + bg-plane-pointer compensation across 16 staggered planes | `audio.device` `CMD_WRITE` with inter-aural time delay (silence prefix) for stereo balance | **One** `DMACON` poke; nothing else. Note: the 5th bitplane is also used as a **palette-half-toggle transparency channel** (see BOING-ANALYSIS.md §8.10) | Full Intuition app: `OpenScreen` + `OpenWindow`, IDCMP, multitasks under Workbench |
| **Maher reconstruction `boing5.c`** | Static bitmap (chip-RAM `__chip` arrays), **palette cycling** | `graphics.library` viewport X/Y offset (higher-level than scroll regs) | `devices/audio.h` `CMD_WRITE` | Direct chip-RAM allocation; otherwise OS calls | Intuition screen, Lattice C / KickStart 1.3 |
| **XScreenSaver `boing(6)`** | Per-frame OpenGL sphere rasterisation | Software physics → `glTranslate`/`glRotate` | None by default | N/A (modern OS) | X11/GL screensaver hack window |
| **Sintonen 1k Boing** | `AreaMove`/`AreaDraw` driven by **coordinate data scraped from the AMICUS binary** | OS scroll + software physics | `audio.device` | Polite | Multi-tasks; size-coded |
| **AROS BoingDemo (quizno50)** | SDL software blit of pre-rendered PNG frames | Software physics in C | SDL_mixer | N/A | SDL window |
| **BoingNES** | NES PPU nametable + sprite layer | 6502 software physics | NES APU triangle/noise channels | N/A | None (NES, no OS) |

### 7.10 Research gaps in this section

In the spirit of "don't fake a citation":

- **No Luck / Mical / Dicker quote about the CES source's disposition** has surfaced in print. The "it's lost" claim is *structural* (Maher had to reconstruct) rather than *testimonial* (no one has said so on the record). The Retro Hour Sam Dicker interview is audio-only and may contain such a statement; a future research pass listening to the full episode could close this gap.
- **Authorship of the AMICUS polite binary is "Probably Amiga/Commodore-Amiga Inc."** per the Aminet readme — the uploader was not sure. The CATS / Carolyn Scheppner attribution is plausible by role but unconfirmed by primary source.
- **Carolyn Scheppner DevCon disks** (1986–1988) might contain an earlier or alternative Boing — I checked the [3rd European Amiga DevCon memo on archive.org](https://archive.org/details/3rd-european-amiga-dev-con-memo) and did not find one, but did not exhaustively search the U.S. DevCon disk catalogue.
- **The EAB threads** [#34083](https://eab.abime.net/showthread.php?t=34083) and [#117716](https://eab.abime.net/showthread.php?t=117716) are gated behind anti-bot protection and could not be automatically fetched; community summaries suggest Sintonen identified bugs in the AMICUS binary and that a 1996 variant exists. Worth manual reading by an Amiga researcher.

---

## 8. Cultural legacy

### 8.1 The logo controversy

The original Amiga engineering team **wanted Boing Ball adopted as the Amiga corporate logo**. Commodore overruled them in favor of the rainbow checkmark. Yet —

> "Although it was never adopted as a trademark by Commodore, the 'Boing Ball' has been synonymous with Amiga since its launch."
>
> — [Wikipedia: Amiga](https://en.wikipedia.org/wiki/Amiga)

After Commodore's 1994 bankruptcy, the Boing Ball was effectively rehabilitated as the platform's symbol. **AmigaOS 3.5, 3.9, 4.0 and 4.1** put it back into release art, boot animations and splash screens. AmigaOne hardware vendors revived it on decals and packaging. ([GenerationAmiga](https://www.generationamiga.com/2020/04/14/amiga-history-the-story-of-the-boing-ball/); [Amiga Wiki: Amiga Logos](https://www.amigawiki.org/doku.php?id=de%3Amisc%3Aamiga_logos))

### 8.2 Modern reimplementations

- **XScreenSaver** ships `boing(6)`, "a clone of the first graphics demo for the Amiga 1000," explicitly attributed to Dale Luck and RJ Mical in the man page. ([boing(6) by Jamie Zawinski](https://man.archlinux.org/man/extra/xscreensaver/boing.6.en))
- A **Windows 10/11 screensaver port** by Sinphaltimus exists. ([GitHub: Amiga-Boing-Ball-Screensaver-for-Windows-10-and-11](https://github.com/Sinphaltimus/Amiga-Boing-Ball-Screensaver-for-Windows-10-and-11); [amiga-news.de coverage](https://www.amiga-news.de/en/news/AN-2025-12-00039-EN.html))
- Browser/JS/WebGL implementations, Vectrex and SpecBAS ports are catalogued in the retrocomputing press.
- **OpenGL's classic `glxgears` and SGI's `bouncing-ball` SGI demo** drew direct visual inspiration; both Silicon Graphics and Sun Microsystems used Boing-style bouncing balls in their own marketing in the late 1980s.
- The **MIT Press Platform Studies series** opens its Amiga volume (*The Future Was Here*, Jimmy Maher, 2012) with an entire chapter dissecting Boing as Exhibit A of why the Amiga mattered. ([MIT Press](https://direct.mit.edu/books/book/4417/The-Future-Was-HereThe-Commodore-Amiga); [chapter "Boing"](https://direct.mit.edu/books/book/4417/chapter/189199/Boing))

### 8.3 As an educational reference implementation

Commodore and third-party publishers distributed Boing-style demos as developer documentation throughout the late 1980s. The most widely-redistributed of these is the AMICUS Disk 9 binary discussed in §7.3 — the source of which now lives in this repository as `boing.s` (via Sintonen's disassembly). It is the polite, OS-friendly Boing, written to demonstrate *good Amiga programming style* (multitasking-friendly, `OpenScreen`/`OpenWindow`, `OpenLibrary`/`CloseLibrary`, audio.device for sound, mathffp/mathtrans for floating-point sphere geometry, `AllocMem` with `MEMF_CHIP`, IDCMP message loop, clean shutdown). The bouncing ball is the same, and — as the source-level analysis in [BOING-ANALYSIS.md](BOING-ANALYSIS.md) shows — the per-frame animation pipeline is the same as the 1984 original: palette-register cycling for rotation, ViewPort `RxOffset`/`RyOffset` writes for motion, audio.device for stereo bounces. What differs from the original is the *scaffolding*: graphics.library calls for setup instead of raw chipset pokes, an Intuition screen instead of a hardware-takeover view, polite `MEMF_CHIP` allocations instead of hard-coded chip-RAM addresses, IDCMP for user input instead of raw vector hooks. See §7 above for the variant lineage and [AMIGA-KNOWHOW.md](AMIGA-KNOWHOW.md) for the libraries it uses.

---

## 9. Quotable lines (for documentation, slide decks, etc.)

```
"Because the bouncing ball animation was so fast and smooth, attendees did
 not believe the Amiga prototype was really doing the rendering. Suspecting
 a trick, they began looking around the booth for a hidden computer or VCR."
   — Jeremy Reimer, A History of the Amiga
```

```
"Late that night, in their drunken stupor, Dale and RJ put the finishing
 touches on what would become the canonical Amiga demo, Boing."
   — Jeremy Reimer, A History of the Amiga
```

```
"The booming noise of the ball was Bob Pariseau hitting an aluminium
 garage door with one of those foam bats, and an Apple II digitised it
 from inside the garage."
   — Jeremy Reimer, A History of the Amiga
```

```
"boing is a clone of the first graphics demo for the Amiga 1000, which
 was written by Dale Luck and RJ Mical during a break at the 1984
 Consumer Electronics Show (or so the legend goes)."
   — Jamie Zawinski, XScreenSaver boing(6) man page
```

```
"Joe Pillow was created by RJ Mical and I on a flight from New Orleans
 to San Jose in February of 1984."
   — Dale Luck, 2025 (correcting the CES Joe-Pillow folklore)
```

---

## 10. Watch-outs / common source errors

When citing Boing history, be careful of these recurring mistakes:

- **CES venue.** Older summaries (including stretches of Wikipedia's *History of the Amiga*) say "CES in Chicago, January 1984." Wrong. Winter CES January 1984 was **Las Vegas**; Summer CES June 1984 was **Chicago**. The Lorraine was shown at both.
- **Joe Pillow timing.** The plane-seat-to-CES version is folklore (see §2.3). Dale Luck has corrected the timeline.
- **Author of the sound.** Bob Pariseau **produced the foley** (the garage-door hit recorded by Apple II); Sam Dicker (and/or Luck/Mical) **wrote the playback engine** that drove Paula. Both credits are needed; either alone is misleading.
- **Color cycling vs. blitter.** The **original 1984 Boing** uses bitplane-scroll + palette-cycle. **Modern reimplementations** (XScreenSaver `boing(6)`, this repo's `boing.s`, browser ports) typically blit / area-fill each frame. Don't conflate. See §7 for the full variant table.
- **"Apple-II-digitised" sound.** Yes, the Apple II had digitiser cards (e.g. the Mountain Computer Music System) in 1983–84. The story is plausible and well-attested.
- **Carl Sassenrath as Boing author.** No. He wrote **Exec**, the multitasking kernel that lets Boing co-exist with Workbench. He is not credited as a Boing code author by any primary source.
- **"This is Luck and Mical's original assembly."** Not exactly. The AMICUS Disk 9 binary (= the source in this repo) is *conceptually* descended from Luck/Mical's original — same authors at the same company at the same time — but it's a separate, OS-friendly re-implementation, not the literal CES code. The CES source is not publicly available. See §7.2 and §7.3.
- **"Boing source is on the Workbench 1.x developer disks."** I haven't been able to confirm this in any DevCon/CATS disk catalogue I could check. The most-circulated public Boing source is Sintonen's disassembly of the AMICUS Disk 9 binary, not a Commodore-Amiga-supplied `.asm` listing. Treat the "DevCon source" claim as unconfirmed unless a specific disk is cited.

---

## 11. References

Primary academic / book sources:

- Jimmy Maher, *The Future Was Here: The Commodore Amiga* (MIT Press Platform Studies, 2012) — [book page](https://direct.mit.edu/books/book/4417/The-Future-Was-HereThe-Commodore-Amiga); [chapter "Boing"](https://direct.mit.edu/books/book/4417/chapter/189199/Boing). The most rigorous published technical and historical analysis.
- Jeremy Reimer, *A History of the Amiga* (Ars Technica, multi-part series) — [mirror at josh8.com](https://josh8.com/mirror/amiga.html). Source of most reproduced anecdotes.
- Brian Bagnall, *Commodore: A Company on the Edge* and *Commodore: The Amiga Years* — long-form business history with CES coverage.

Encyclopedic:

- [Wikipedia: Amiga](https://en.wikipedia.org/wiki/Amiga)
- [Wikipedia: History of the Amiga](https://en.wikipedia.org/wiki/History_of_the_Amiga)
- [Wikipedia: Amiga 1000](https://en.wikipedia.org/wiki/Amiga_1000)
- [Wikipedia: Amiga Corporation](https://en.wikipedia.org/wiki/Amiga_Corporation)
- [Wikipedia: RJ Mical](https://en.wikipedia.org/wiki/RJ_Mical)
- [Wikipedia: Jay Miner](https://en.wikipedia.org/wiki/Jay_Miner)
- [Wikipedia: Carl Sassenrath](https://en.wikipedia.org/wiki/Carl_Sassenrath)
- [Wikipedia: Consumer Electronics Show](https://en.wikipedia.org/wiki/Consumer_Electronics_Show)

Technical writeups specifically about Boing:

- [Amiga Graphics Archive: AmigaBoingBall](https://amiga.lychesis.net/applications/AmigaBoingBall.html) — bitplane/palette/shadow breakdown.
- [Amiga Graphics Archive: Dale Luck](https://amiga.lychesis.net/artists/DaleLuck.html)
- [pouët.net: Boing by Dale Luck & RJ Mical](https://www.pouet.net/prod.php?which=27096) — release record with technical commentary.
- [randelshofer.ch — RJ Mical Boing Ball ILBM page](https://www.randelshofer.ch/animations/anims/robert_j_mical/boing3.ilbm.html) — frame visual reference.
- [XScreenSaver boing(6) man page](https://man.archlinux.org/man/extra/xscreensaver/boing.6.en) — modern attribution.

Interviews / primary-source video and audio:

- [The Retro Hour EP427 — Sam Dicker on Amiga and Boing Ball](https://theretrohour.com/williams-electronics-and-designing-the-amiga-with-sam-dicker-the-retro-hour-ep427/)
- RJ Mical at Assembly 2001 (YouTube — multiple uploads)
- *Amiga Addict Magazine* issue 42 — RJ Mical extended interview
- [Chester County Press — Bob Pariseau profile](https://www.chestercounty.com/2018/06/06/174738/making-sense-of-high-tech)
- [AmigaMeditation.guru — Joe Pillow myth correction by Dale Luck, 2025](https://amigameditation.guru/2025/05/03/will-the-real-joe-pillow-please-stand-up/)

Period and retrospective context:

- [Commodore International Historical Society — Behind the Scenes at 1984 Winter CES](https://commodore.international/2024/04/28/commodore-behind-the-scenes-at-1984-winter-ces/)
- [The Digital Antiquarian — The 68000 Wars, Part 3](https://www.filfre.net/2015/04/the-68000-wars-part-3-we-made-amiga-they-fucked-it-up/)
- [Low End Mac — The Amiga Story](https://lowendmac.com/2016/the-amiga-story-conceived-at-atari-born-at-commodore/)
- [GenerationAmiga — Story of the Boing Ball](https://www.generationamiga.com/2020/04/14/amiga-history-the-story-of-the-boing-ball/)
- [Amiga Wiki — Amiga Logos](https://www.amigawiki.org/doku.php?id=de%3Amisc%3Aamiga_logos)
- [Floodgap — Secret Weapons of Commodore: Lorraine](https://www.floodgap.com/retrobits/ckb/secret/lorraine.html)

Variant lineage / source code (see §7):

- [Aminet `misc/antiq/boing.lha`](https://aminet.net/package/misc/antiq/boing) and its [readme](https://aminet.net/misc/antiq/boing.readme) — the canonical AMICUS Disk 9 polite Boing binary.
- [Harry Sintonen — disassembly of the AMICUS binary](https://sintonen.fi/temp/boing.asm); [filfre.net mirror](http://amiga.filfre.net/misc/Chapter2/boing.asm) — the byte-level source of this repo's `boing.s`.
- [Harry Sintonen — 1k Boing for FAP 2013](https://sintonen.fi/src/1kboing/1kboing.asm).
- [Filfre / Maher Chapter 2 companion (file index)](http://amiga.filfre.net/?page_id=5) — Maher's 5-stage C reconstruction.
- [boing5.c source header](http://amiga.filfre.net/misc/Chapter2/boing5.c) — Maher's "freely distributable" attribution.
- [Aminet `dev/misc/aaboing.lha`](https://aminet.net/package/dev/misc/aaboing) — Chris Green's 1993 AGA Boing.
- [Aminet `demo/intro/boingdemo.i386-aros.lha`](https://aminet.net/package/demo/intro/boingdemo.i386-aros) — quizno50 AROS/SDL port.
- [Aminet search: "boing"](https://aminet.net/search?query=boing) — full Aminet Boing index.

Modern code / reimplementation references:

- [Zygo/xscreensaver GitHub mirror — `hacks/boing.c`](https://github.com/Zygo/xscreensaver) — Jamie Zawinski's XScreenSaver `boing(6)` source.
- [github.com/bbbradsmith/boingnes](https://github.com/bbbradsmith/boingnes) — NES port, Brad Smith, CC-BY-4.0.
- [github.com/quizno50/BoingDemo](https://github.com/quizno50/BoingDemo) — SDL Boing.
- [github.com/tobozo/ESP32-AmigaBoingBall](https://github.com/tobozo/ESP32-AmigaBoingBall) — ESP32 port.
- [github.com/gbegreg/AmigaBoingBall](https://github.com/gbegreg/AmigaBoingBall) — Delphi port.
- [github.com/geekychris/opengl_boingball](https://github.com/geekychris/opengl_boingball) — OpenGL/C++.
- [github.com/glfw/glfw `examples/boing.c`](https://github.com/glfw/glfw/blob/master/examples/boing.c) — GLFW smoke-test demo.
- [stanchak.github.io/boing](https://stanchak.github.io/boing/) — browser canvas implementation.
- [github.com/thomasrunge/boing](https://github.com/thomasrunge/boing) — Python + Pygame.
- [GitHub: Amiga-Boing-Ball-Screensaver-for-Windows-10-and-11](https://github.com/Sinphaltimus/Amiga-Boing-Ball-Screensaver-for-Windows-10-and-11)
- [Demozoo prod 151545](https://demozoo.org/productions/151545/)

---

*For the per-register, per-library technical reference that explains how the Amiga hardware actually achieves these effects, see [AMIGA-KNOWHOW.md](AMIGA-KNOWHOW.md).*
