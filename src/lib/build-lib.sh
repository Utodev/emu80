#!/bin/sh
# Builds the native library (ochentalib.dll on Windows, libochenta.so on Linux)
# into build/lib. From WSL the Windows one is made with the Windows compiler
# of Lazarus (LAZARUS_DIR, default /mnt/c/lazarus), 32 bits as that one is:
# the host program must be 32 bits too (a 64-bit DLL needs a Win64 FPC).
#   src/lib/build-lib.sh          Windows DLL if the Windows compiler is there, else Linux
#   src/lib/build-lib.sh linux    the Linux library
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/build/lib"
mkdir -p "$OUT/units"
LAZARUS_DIR=${LAZARUS_DIR:-/mnt/c/lazarus}
FPCW="$LAZARUS_DIR/fpc/3.2.2/bin/i386-win32/fpc.exe"
if [ "$1" != "linux" ] && [ -x "$FPCW" ]; then
  W() { wslpath -w "$1"; }
  "$FPCW" -O2 -Mobjfpc -Sh -Fu"$(W "$ROOT/src")" -Fu"$(W "$ROOT/src/lib")" -FU"$(W "$OUT/units")" \
    -FE"$(W "$OUT")" "$(W "$ROOT/src/lib/ochentalib.lpr")" | grep -E "Error|Fatal|Linking" || true
  ls "$OUT/ochentalib.dll"
else
  fpc -O2 -Mobjfpc -Sh -Fu"$ROOT/src" -Fu"$ROOT/src/lib" -FU"$OUT/units" -FE"$OUT" -olibochenta.so "$ROOT/src/lib/ochentalib.lpr" |
    grep -E "Error|Fatal|Linking" || true
  ls "$OUT/libochenta.so"
fi
