# CLAUDE.md — working in amiga-boing

Buildable, annotated 68000 assembly of the AMICUS Disk 9 "polite" Amiga Boing Ball demo (Kickstart 1.x / OCS), plus analysis docs. See [README.md](README.md) for the overview and [docs/](docs/) for depth.

## Build & run

- **Prereq:** `vendor/` (private submodule) must be populated — `git submodule update --init`. It holds copyrighted files the build needs: `vendor/include/` (Amiga NDK 1.3 headers), `vendor/libs/mathtrans.library`, `vendor/rom/kick13.rom` (**required**, the demo's native OS) and `vendor/rom/kick204.rom` (**optional**, becomes the default boot ROM when present). `build.sh` checks and errors clearly if a required file is missing.
- **Build:** `./scripts/build.sh` → assembles `src/boing.s` (INCDIR `vendor/include`), links, and **stages the generated `uae/` run target** from `src/assets/uae/` + `vendor/` + `src/assets/{boing.samples,Boing.info}` + the built binary.
- **Run:** `./scripts/run.sh` → launches FS-UAE on the **default Kickstart** (2.04 if `vendor/` has it, else the required 1.3; rebuilds first if sources changed); `./scripts/run.sh 13` forces the original **Kickstart 1.3**. GUI window; close it to quit. (WinUAE: the build also stages `uae/boing.uae` — untested on macOS; see [docs/RUNNING.md](docs/RUNNING.md).)
- `uae/` is **generated and git-ignored** — never commit it; rebuild instead. The committed inputs are `src/assets/uae/` (skeleton: `boing.fs-uae`, `boing.uae`, `dh0/s/startup-sequence`, `dh0/c/UAEquit`) plus `vendor/` and `src/assets/{boing.samples,Boing.info}`.
- Toolchain `vasmm68k_mot` + `vlink` (amiga-assembly extension or `PATH`); `build.sh` locates them. `INCDIR`/`INCLUDE` paths in `src/boing.s` are **repo-root-relative** — always assemble from the repo root (the scripts `cd` there).
- Verifying a change: `build.sh` must succeed; for visible behavior, `run.sh` and look at the window (screen capture is typically blocked here, so describe what should appear rather than asserting a screenshot).

## Layout

`src/` = the demo (entry `boing.s` + five `.s` files + `assets/`, incl. `assets/uae/` run-target skeleton). `vendor/` = copyrighted NDK includes + `mathtrans.library` + Kickstart ROM (**private submodule**). `uae/` = generated FS-UAE run target (git-ignored). `docs/` = analysis. `archive/` = unmodified originals. `scripts/` = build/run. `build/` = output (git-ignored).

## Things to know before editing

- **This is a preservation repo.** `src/` matches `archive/boing_original.s` closely, with **two deliberate deviations** — auto-start, and a KS2.0+ frame-rate fix that adds a small version-gated commit block (so it's no longer strictly byte-identical) — see [docs/DEVIATIONS.md](docs/DEVIATIONS.md) for what/where/why and how to re-verify. (Screen handling is original: the ball screen sits in the background with no gadgets; making it visible is an environment concern, kept out of `boing`.) Don't "tidy" the disassembly's quirks (overlapping globals, dead flags) into oblivion — they're the point. `archive/` is read-only reference; **never edit it**.
- **Don't trust labels/comments as variable boundaries.** Several disassembly globals overlap (`_y`/`_y_lower` are one longword; `_sstept` and `_dampy` are dead — never written). The damping is inert (`_dampy=0` ⇒ elastic, perpetual bounce). The animation loop runs at the **video field rate** — one step per field (50 Hz PAL / 60 Hz NTSC), paced by the `WaitTOF` *inside* `RethinkDisplay` — the running path adds no explicit `WaitTOF` (don't add one: a second `WaitTOF` per frame would halve the rate). The KS2.0+ frame-rate fix (Deviation #2) works in these field units, so it is **PAL/NTSC-agnostic** — it gates on `graphics.library` version, not on display standard, and restores one-step-per-field on both (only PAL is testable here, since FS-UAE forces PAL for this A500/KS1.3 config). Details: [docs/ANIMATION-DETAILS.md](docs/ANIMATION-DETAILS.md) §1, [docs/DEVIATIONS.md](docs/DEVIATIONS.md).
- **Boot environment:** the configs (`src/assets/uae/boing.fs-uae` and the WinUAE `boing.uae`) are **templates** — `build.sh` substitutes a `@@KICKSTART@@` token for the default ROM filename when staging into `uae/` (2.04 if present, else 1.3). They're self-contained — repo-relative paths (`$CONFIG` for FS-UAE), and they mount `dh0/libs` as a drive labelled `LIBS` so `LIBS:mathtrans.library` resolves without the Workbench `Assign` command (`startup-sequence` is just `sys:boing`). `run.sh 13` overrides to `kick13.rom`. No dependency on the user's personal FS-UAE Kickstarts folder. FS-UAE forces **PAL** for this OCS A500 — `ntsc=1` is ignored; don't chase it. The WinUAE `boing.uae` is staged too but is **untested on macOS** (path-resolution caveat in [docs/RUNNING.md](docs/RUNNING.md)).
- **Math is FFP** (Motorola Fast Float) via `mathffp`/`mathtrans`; integer divides go through `ldivt`/`POSDIV` in `src/runtime.s` (mind the dividend/divisor order — it bit us once).

## Docs map (one canonical home per topic)

**Convention to keep:** each topic lives in exactly one doc; everything else *links* to it rather than restating it. When you add or change a fact, edit its canonical doc and link from the rest — don't copy prose between docs (that's how they drift out of sync).

- `README.md` — overview, layout, quick start (summaries only; links out for detail).
- `CLAUDE.md` — this file: how to work in the repo.
- `docs/RUNNING.md` — build & run, toolchain, `vendor/`, the boot gotcha.
- `docs/DEVIATIONS.md` — the changes vs the original AMICUS source (auto-start; KS2.0+ frame-rate fix) + re-verify steps. **Canonical**; README/CLAUDE/RUNNING/ANIMATION-DETAILS only link here.
- `docs/ANIMATION-DETAILS.md` — measured motion/timing/distances.
- `docs/BOING-ANALYSIS.md` — per-function source analysis.
- `docs/AMIGA-KNOWHOW.md` — Amiga hardware/OS reference.
- `docs/DEMO-BACKGROUND.md` — history & variant lineage.
- `docs/BOING-AMICUS(S)-VS-MAHER(C).md` — vs Jimmy Maher's C reconstruction.
- `archive/boing-c/README.md` — provenance of Maher's vendored C files.
- `specs/` — browser-port handoff spec.
