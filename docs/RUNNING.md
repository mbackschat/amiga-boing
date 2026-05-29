# RUNNING.md — building and running Boing under FS-UAE

How to build `src/boing.s` and watch it run on an emulated Amiga. Companion to the build-pipeline notes in the header of [`src/boing.s`](../src/boing.s).

## Quick start

```sh
git submodule update --init    # populate vendor/ (copyrighted; see below)
./scripts/build.sh             # assemble + link + stage the uae/ run target
./scripts/run.sh               # launch FS-UAE (builds first if stale)
```

`run.sh` alone is usually enough afterwards — it rebuilds if the sources changed, then launches. Close the FS-UAE window to quit.

## `vendor/` (required, copyrighted)

The build needs three third-party copyrighted components, kept in a separate **private** submodule (`vendor/`) so they're never redistributed from the public repo:

```
vendor/include/   Amiga 1.3 NDK assembler headers (*.i)
vendor/libs/      mathtrans.library
vendor/rom/       kick13.rom   (Kickstart 1.3,  r34.5)     <- required (the demo's native OS)
vendor/rom/       kick204.rom  (Kickstart 2.04, r37.175)   <- optional (becomes the default boot ROM when present)
```

`git submodule update --init` fetches them if you have access. Otherwise supply your own in that layout (NDK 1.3 + the Kickstart ROMs from Cloanto Amiga Forever — **1.3 required, 2.04 optional**; `mathtrans.library` from a Workbench 1.3 disk). `build.sh` requires the 1.3 ROM, and uses 2.04 as the default boot ROM when it's present (otherwise it falls back to 1.3); it reports exactly what's missing. **The ROMs live here** — there's no dependency on FS-UAE's own `Kickstarts/` folder.

## Toolchain

`scripts/build.sh` finds `vasmm68k_mot` + `vlink` on your `PATH`, otherwise falls back to the native binaries bundled with the VS Code **amiga-assembly** extension (`prb28.amiga-assembly`):

```
~/.vscode/extensions/prb28.amiga-assembly-*/resources/bin/<darwin|linux>/{vasmm68k_mot,vlink}
```

(The copies under the extension's `dist/wasm/` are WebAssembly and won't run from a normal shell — the script uses the `resources/bin/<platform>/` native ones.) Override with `VASM=/path VLINK=/path ./scripts/build.sh`.

## Build (what the script does)

```sh
# run from the repo root; INCDIR (vendor/include) + INCLUDE paths are repo-root-relative
vasmm68k_mot -m68000 -Fhunk -linedebug src/boing.s -o build/boing.o
vlink -bamigahunk -Bstatic build/boing.o -o uae/dh0/boing
```

`build.sh` then **stages the generated `uae/` run target** (git-ignored) from `src/assets/uae/` (skeleton: the `boing.fs-uae` and `boing.uae` configs, which are templates — `build.sh` substitutes the chosen default ROM filename for the `@@KICKSTART@@` token) + `vendor/` (ROMs → `uae/rom/` — `kick13.rom` always, `kick204.rom` if present; `mathtrans.library` → `uae/dh0/libs/`) + `src/assets/{boing.samples,Boing.info}` + the ~63 KB binary at `uae/dh0/boing`. (The assemble/link recipe is mirrored in `.vscode/tasks.json`, entrypoint `src/boing.s` — note that path expects `vendor/include` to exist.)

## Run (FS-UAE)

`scripts/run.sh` launches FS-UAE with `uae/boing.fs-uae` — a fully self-contained config (ROM, disk, and `LIBS:` all repo-relative via `$CONFIG`). It boots an **A500 / 68000 / OCS** machine. The default Kickstart is **2.04 when that ROM is available, otherwise the required 1.3** (chosen by `build.sh` at stage time and baked into the config). The only external requirement is **FS-UAE itself**. Close the window to quit.

Why 2.04 is preferred as the default: on Kickstart 2.0+ the boot shell is windowless, so the ball screen shows **immediately** (no Workbench/CLI screen to drag down — see the gotcha below), and the version-gated fix in [DEVIATIONS.md](DEVIATIONS.md) Deviation #2 keeps it at the full field rate. The original 1.3 environment is one flag away (next section).

Run by hand per OS:

```sh
# macOS
/Applications/FS-UAE.app/Contents/MacOS/fs-uae uae/boing.fs-uae      # or: fs-uae uae/boing.fs-uae
# Linux  (package: fs-uae)
fs-uae uae/boing.fs-uae
# Windows  (cmd / PowerShell; or use the FS-UAE Launcher GUI)
"C:\Program Files\FS-UAE\Windows\x86-64\fs-uae.exe" uae\boing.fs-uae
```

On Windows, `scripts/build.sh` / `run.sh` are bash — run them from **Git Bash** or **WSL** (or invoke `fs-uae.exe` on the staged `uae\boing.fs-uae` directly after building).

### Running on Kickstart 1.3 (the demo's native OS)

```sh
./scripts/run.sh 13     # boots uae/rom/kick13.rom instead of 2.04
```

`13` (also `1.3` / `--ks13`) is shorthand `run.sh` translates into `--kickstart_file=…/uae/rom/kick13.rom`; any other args still pass through to FS-UAE. On 1.3 the ball screen opens **behind** the boot Workbench/CLI screen — drag that screen's title bar down to reveal it (this is the original "polite" behaviour; see the gotcha below). `kick13.rom` is the required ROM, so it's always staged into `uae/rom/`. (If 2.04 isn't present it's already the default, and `13` is a no-op.)

## Run (WinUAE, Windows)

For Windows users who prefer **WinUAE**, the build also stages `uae/boing.uae` — a WinUAE counterpart to the FS-UAE config (same A500 / OCS machine, same default-ROM selection, and the same two directory hard drives). Load it via **File → Load configuration…**, or:

```bat
winuae.exe -f uae\boing.uae
```

> **Untested here.** This repo is developed on macOS (FS-UAE), so `boing.uae` is provided best-effort and hasn't been run under WinUAE. The likely sticking point is **paths**: WinUAE resolves relative paths against *its own* working directory, not the config file. If it can't find the ROM or drives, either start WinUAE with the `uae\` folder as the working directory, or edit the `kickstart_rom_file` and `uaehf0`/`uaehf1` lines in `boing.uae` to **absolute** paths (`uae\rom\kick204.rom`, `uae\dh0`, `uae\dh0\libs`). For Kickstart 1.3, point `kickstart_rom_file` at `rom\kick13.rom`. Reports of what works are welcome.

## What the bare boot drive needs (gotcha)

A bare directory hard drive only gets `SYS:` from Kickstart (1.3 or 2.x) — not `LIBS:`. Without `LIBS:`, `OpenLibrary("mathtrans.library")` fails and `boing` silently `_exit(1)`s. So `uae/boing.fs-uae` mounts `dh0/libs` **as a second drive labelled `LIBS`** (`hard_drive_1` / `hard_drive_1_label = LIBS`), which makes `LIBS:mathtrans.library` resolve — the startup-sequence is then just `sys:boing`, with no Amiga `Assign` command needed. (`mathffp.library` is **ROM-resident** on 1.3, so only `mathtrans.library` needs to be on disk.)

## Deviations from the original AMICUS source

`src/` stays close to the original disassembly with **two deliberate changes** — auto-start (the original starts paused) and a Kickstart 2.0+ frame-rate fix (keeps the demo at the native field rate — 50 Hz PAL / 60 Hz NTSC — on later OSes; KS1.x runs the original code path). The screen handling is original, so the ball screen opens in the **background**: drag the front CLI/Workbench screen's title bar down to reveal it. Rationale, exact locations, and how to re-verify: **[DEVIATIONS.md](DEVIATIONS.md)**.

## Symptom → cause cheat-sheet

- **Boots to `AmigaDOS … Release 1.3` prompt, no ball** → expected: the ball screen opens in the **background**. Drag the CLI/Workbench screen's title bar **down** to reveal it. If dragging down shows an empty/garbage screen instead of the ball, then `boing` exited during init — check the `LIBS` mount in `uae/boing.fs-uae` (so `mathtrans.library` loads).
  - **Why some setups show the ball directly (no Workbench in front):** `boing` always calls `ScreenToBack` on its screen, so it's visible only when **no other screen is open in front** of it. On a normal KS1.3 boot the startup shell's Workbench/CLI screen stays up front (hence "drag down to reveal"); a setup with nothing held in front (e.g. some A4000/KS3.x boots) shows boing immediately. It's the boot environment, not `boing` — the binary's *screen ordering* is identical either way. Bringing the ball forward is an environment concern, deliberately kept out of `boing`. (Animation *speed* is a separate matter: on KS2.0+ the demo would run at half rate without the version-gated fix in [DEVIATIONS.md](DEVIATIONS.md) Deviation #2.)
- **`Illegal instruction: 4e7b at 00FCxxxx` in the FS-UAE log** → harmless. That's the Kickstart ROM's CPU-detection probe (`MOVEC`), not your code.
- **Emulator quits instantly** → something ran `UAEquit` (`dh0/c/UAEquit`, a UAE helper that quits the emulator). The current `startup-sequence` is just `sys:boing` and does **not** call it; `boing` detaches from the CLI, so any command placed after `sys:boing` would execute immediately — don't put `UAEquit` there.
- **Want NTSC (60 Hz) instead of PAL?** FS-UAE **forces PAL** for this A500 / KS1.3 setup — its model region quickstart overrides `ntsc = 1` (whether set in the config or as `--ntsc=1`), so the emulated Agnus stays PAL (227×312, 50 Hz). Don't chase the `ntsc=1` dead end. A genuine NTSC run would need an NTSC-region model (e.g. an A1000, which needs a bootstrap/WCS ROM we don't have). For timing work, record at PAL: the demo runs at the PAL field rate (~50 Hz, one step per field); a true NTSC run would be ~17 % faster (60/50) with identical per-step constants — see [ANIMATION-DETAILS.md](ANIMATION-DETAILS.md) §1.
