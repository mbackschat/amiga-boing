#!/usr/bin/env bash
# Launch the Boing demo in FS-UAE using uae/boing.fs-uae (A500 / 68000 / OCS).
# Close the FS-UAE window to quit.
#
# Builds first if uae/dh0/boing is missing or older than the sources.
# Requires: FS-UAE installed. The ROM is self-contained (staged into uae/rom/
# from vendor/); no machine-specific FS-UAE setup needed. FS-UAE forces PAL for
# this OCS A500 (see docs/RUNNING.md).
#
# Kickstart selection:
#   scripts/run.sh        -> the default ROM baked into the staged config by
#                            build.sh: Kickstart 2.04 if vendor/ has it (ball shows
#                            immediately, full speed), otherwise the required 1.3.
#   scripts/run.sh 13     -> force the original Kickstart 1.3 (ball opens behind
#                            the boot screen; requires kick13.rom).
# Any extra args are passed through to FS-UAE (e.g. --kickstart_file=... for another ROM).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Easy Kickstart switch: a leading "13" / "1.3" / "--ks13" boots the original 1.3 ROM.
KS_OVERRIDE=()
case "${1:-}" in
  13|1.3|--ks13)
    if [ ! -f "$REPO/uae/rom/kick13.rom" ]; then
      echo "error: uae/rom/kick13.rom not staged (vendor/rom/kick13.rom missing?)." >&2
      exit 1
    fi
    KS_OVERRIDE=(--kickstart_file="$REPO/uae/rom/kick13.rom")
    shift ;;
esac

# (re)build if the binary is stale
if [ ! -f "$REPO/uae/dh0/boing" ] || [ -n "$(find "$REPO/src" -name '*.s' -newer "$REPO/uae/dh0/boing" -print -quit)" ]; then
  echo "==> building (binary missing or out of date)"
  "$REPO/scripts/build.sh"
fi

FSUAE="$(command -v fs-uae || true)"
if [ -z "$FSUAE" ] && [ -x "/Applications/FS-UAE.app/Contents/MacOS/fs-uae" ]; then
  FSUAE="/Applications/FS-UAE.app/Contents/MacOS/fs-uae"
fi
if [ -z "$FSUAE" ]; then
  echo "error: fs-uae not found (install FS-UAE, or put fs-uae on PATH)." >&2
  exit 1
fi

echo "==> launching FS-UAE"
exec "$FSUAE" "$REPO/uae/boing.fs-uae" ${KS_OVERRIDE[@]+"${KS_OVERRIDE[@]}"} "$@"
