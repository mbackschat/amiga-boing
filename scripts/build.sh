#!/usr/bin/env bash
# Build the Boing demo and stage the runnable FS-UAE target in uae/.
#
#   1. assemble src/boing.s (INCDIR vendor/include) + link  -> uae/dh0/boing
#   2. stage uae/ from: src/assets/uae/ (skeleton) + vendor/ (ROM, mathtrans.library)
#      + src/assets/{boing.samples,Boing.info} + the built binary
#
# Run from anywhere; paths resolve relative to the repo root.
#
# Toolchain: vasmm68k_mot + vlink. Looked up on PATH first, otherwise the native
# binaries bundled with the VS Code "amiga-assembly" extension (prb28.amiga-assembly).
# Override with VASM=/path VLINK=/path.
#
# vendor/ holds copyrighted files (Amiga NDK includes, mathtrans.library, Kickstart
# ROM) and is a private git submodule. If it's empty, run:  git submodule update --init
# (or supply your own copies with the layout in vendor/README.md).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"   # INCDIR/INCLUDE paths in src/boing.s are repo-root-relative

# --- vendor presence check -------------------------------------------------
missing=()
[ -d vendor/include ]            || missing+=("vendor/include/ (Amiga NDK headers)")
[ -f vendor/libs/mathtrans.library ] || missing+=("vendor/libs/mathtrans.library")
[ -f vendor/rom/kick13.rom ]     || missing+=("vendor/rom/kick13.rom (Kickstart 1.3 - required, the demo's native OS)")
# vendor/rom/kick204.rom (Kickstart 2.04) is OPTIONAL - when present it becomes
# the default boot ROM (nicer on KS2.0+: ball shows immediately, full speed).
if [ ${#missing[@]} -ne 0 ]; then
  echo "error: vendor/ is not populated. Missing:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo "Run 'git submodule update --init', or supply your own copies (see vendor/README.md)." >&2
  exit 1
fi

# --- toolchain -------------------------------------------------------------
case "$(uname -s)" in
  Darwin) PLAT=darwin ;; Linux) PLAT=linux ;; *) PLAT=darwin ;;
esac
find_tool() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then command -v "$name"; return 0; fi
  local hit
  hit="$(ls -d "$HOME"/.vscode*/extensions/prb28.amiga-assembly-*/resources/bin/"$PLAT"/"$name" 2>/dev/null | sort -V | tail -1 || true)"
  [ -n "$hit" ] && { echo "$hit"; return 0; }
  return 1
}
VASM="${VASM:-$(find_tool vasmm68k_mot || true)}"
VLINK="${VLINK:-$(find_tool vlink || true)}"
if [ -z "$VASM" ] || [ -z "$VLINK" ]; then
  echo "error: vasmm68k_mot / vlink not found." >&2
  echo "  Install the VS Code 'amiga-assembly' extension, or set VASM= and VLINK=." >&2
  exit 1
fi

# --- 1. assemble + link ----------------------------------------------------
mkdir -p build uae/dh0/s uae/dh0/c uae/dh0/libs uae/rom
echo "==> assembling src/boing.s"
"$VASM" -m68000 -Fhunk -linedebug src/boing.s -o build/boing.o
echo "==> linking -> uae/dh0/boing"
"$VLINK" -bamigahunk -Bstatic build/boing.o -o uae/dh0/boing

# --- 2. stage the uae/ run target -----------------------------------------
echo "==> staging uae/ (skeleton + vendor + assets)"

# Pick the default boot ROM: Kickstart 2.04 if available, else the required 1.3.
# Both the FS-UAE and WinUAE configs are templates with a @@KICKSTART@@ token that
# we substitute here, so each stays valid for whatever ROMs vendor/ actually has.
if [ -f vendor/rom/kick204.rom ]; then DEFAULT_ROM=kick204.rom; else DEFAULT_ROM=kick13.rom; fi
echo "==> default Kickstart ROM: $DEFAULT_ROM ('scripts/run.sh 13' always forces 1.3)"

sed "s|@@KICKSTART@@|$DEFAULT_ROM|g" src/assets/uae/boing.fs-uae > uae/boing.fs-uae
sed "s|@@KICKSTART@@|$DEFAULT_ROM|g" src/assets/uae/boing.uae    > uae/boing.uae   # WinUAE (untested on macOS)
cp src/assets/uae/dh0/s/startup-sequence  uae/dh0/s/startup-sequence
cp src/assets/uae/dh0/c/UAEquit           uae/dh0/c/UAEquit
cp src/assets/boing.samples               uae/dh0/boing.samples
cp src/assets/Boing.info                  uae/dh0/Boing.info
cp vendor/libs/mathtrans.library          uae/dh0/libs/mathtrans.library
cp vendor/rom/kick13.rom                  uae/rom/kick13.rom           # required (native OS; `run.sh 13`)
# Kickstart 2.04 is optional - staged when present so it can be the default ROM.
if [ -f vendor/rom/kick204.rom ]; then cp vendor/rom/kick204.rom uae/rom/kick204.rom; fi

echo "==> done: $(ls -l uae/dh0/boing | awk '{print $5}') bytes at uae/dh0/boing; run with scripts/run.sh"
