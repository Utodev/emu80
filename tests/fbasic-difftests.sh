#!/bin/bash
# fbasic-difftests.sh <msxfree> <original roms folder>: assembles the test programs of the QUANTIKA ROMs'
# project (../quantika/tests) and runs each one (msxfree exec) on the original ROMs and on the QUANTIKA ones
# (roms/msx/QUANTIKA.ROM and QUANTIKA_SUB.ROM, copied to tests/build/freeroms with the originals' names): the
# screens and results must be the same. Neither folder has the disk ROM (the original disk ROM cannot run on
# the free main ROM); the disk tests at the end use two more folders, with the original disk ROM (when it is
# in the original folder: PHILIPSDISK.rom) and with QUANTIKA_DISK.ROM, and a test disk made by tests/mkdsk.py.
# MSX_TEST_TAPE: a .cas file for the cassette test (skipped without it). The BASIC tests named cas*.txt
# read the tape that tests/mkcas.py makes; the tests of tests/tapeout compare what is written to the tape.
# Exit code 1 when a test differs.
set -e
MSXFREE="$1"
ORIG="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERE="${QUANTIKA:-$ROOT/../quantika}"        # (the test programs: $HERE/tests; QUANTIKA: another folder)
OUT="$ROOT/tests/build/fbasic"               # (the assembled tests and the copy of the originals)
FREE="${FREE_ROMS:-$ROOT/tests/build/freeroms}"   # (FREE_ROMS: another copy of the free ROMs)
[ -d "$HERE/tests" ] || { echo "SKIP  $HERE/tests is not here: the QUANTIKA ROMs cannot be compared"; exit 0; }
mkdir -p "$OUT/orig/msx"
cp -f "$ORIG/msx/MSX2.rom" "$ORIG/msx/MSX2EXT.rom" "$OUT/orig/msx/"
if [ -z "$FREE_ROMS" ]; then
  mkdir -p "$FREE/msx"
  rm -f "$FREE/msx/PHILIPSDISK.rom"
  cp -f "$ROOT/roms/msx/QUANTIKA.ROM" "$FREE/msx/MSX2.rom"
  cp -f "$ROOT/roms/msx/QUANTIKA_SUB.ROM" "$FREE/msx/MSX2EXT.rom"
fi
FAILED=0

# name, assembler defines, frames, text typed, tape
run() {
  local NAME="$1" DEFS="$2" FRAMES="$3" TYPED="$4" TAPE="$5"
  ( mkdir -p "$HERE/out" && cd "$HERE/tests" && sjasmplus.exe --nologo $DEFS "$NAME.asm" > "$OUT/test-asm.log" 2>&1 ) || {
    cat "$OUT/test-asm.log"; exit 1; }
  local ARGS=()
  [ -n "$TYPED" ] && ARGS=(-type "$TYPED")
  [ -n "$TAPE" ] && ARGS+=(-tape "$TAPE")
  "$MSXFREE" exec "$OUT/orig" "$HERE/out/$NAME.bin" "$FRAMES" "${ARGS[@]}" > "$OUT/test-orig.txt"
  "$MSXFREE" exec "$FREE" "$HERE/out/$NAME.bin" "$FRAMES" "${ARGS[@]}" > "$OUT/test-free.txt"
  if diff "$OUT/test-orig.txt" "$OUT/test-free.txt" > "$OUT/test-diff.txt"; then
    echo "ok    free ROM test $NAME $DEFS"
  else
    echo "FAIL  free ROM test $NAME $DEFS: the free ROM differs from the original"
    cat "$OUT/test-diff.txt"
    FAILED=1
  fi
}

run console "" 100
run scroll "" 100
run screen1 "" 100
run wide "" 100
run keys "" 400 'Hello, World! 123 (x)+[]=_\n'
run intstate "" 50
run math "-DFIRST=0" 100
run math "-DFIRST=28" 100
for F in 0 16 32; do run fout "-DFIRST=$F" 100; done
for F in 0 16; do run fin "-DFIRST=$F" 100; done
# (by default one of the tapes of the test set, when it is there)
[ -z "$MSX_TEST_TAPE" ] && MSX_TEST_TAPE=$(ls "$ROOT"/to_be_ignored/MSX/games/tapes/Cobra*.cas 2>/dev/null | head -1)
if [ -n "$MSX_TEST_TAPE" ]; then
  run tapein "" 600 "" "$MSX_TEST_TAPE"     # any .cas with two blocks
else
  echo "SKIP  free ROM test tapein: set MSX_TEST_TAPE to a .cas file to run it"
fi
for M in 1 2 3 4 5 6 7 8; do run modes "-DMODE=$M" 100; done
for M in 2 3 4 5 6 7 8; do run grpprt "-DMODE=$M" 150; run grpprt "-DMODE=$M -DONEPASS" 150; done
for M in 2 3 4 5 6 7 8; do run pixel "-DMODE=$M" 200; done
for M in 5 6 7 8; do run pixel "-DMODE=$M -DSUB" 200; done
for M in 5 8; do for OP in 0x0085 0x00C9 0x00CD; do run boxes "-DMODE=$M -DOP=$OP" 200; done; done
run queues "" 100
run blit "" 200
for OP in 0x0121 0x0125 0x0129; do run textops "-DOP=$OP" 100; done
run mathextra "" 100
run psginit "" 100
run beep "" 300
# BEEP's sound: the writes to the PSG (not their frames) of tests/beep.asm must be the same
MSXFREE_PSGLOG=1 "$MSXFREE" exec "$OUT/orig" "$HERE/out/beep.bin" 300 | grep "^psg" | cut -d' ' -f3 > "$OUT/test-orig.txt"
MSXFREE_PSGLOG=1 "$MSXFREE" exec "$FREE" "$HERE/out/beep.bin" 300 | grep "^psg" | cut -d' ' -f3 > "$OUT/test-free.txt"
if [ -s "$OUT/test-orig.txt" ] && diff "$OUT/test-orig.txt" "$OUT/test-free.txt" > "$OUT/test-diff.txt"; then
  echo "ok    free ROM test beep (the PSG's writes)"
else
  echo "FAIL  free ROM test beep: the PSG is written otherwise"
  head -20 "$OUT/test-diff.txt"
  FAILED=1
fi
# BASIC: the text of tests/basic/*.txt typed on both (after WIDTH 37 and CLS, so the screens match);
# NAME.frames: more frames than 400; cas*.txt: with the files' tape in the recorder. The bottom row is left out:
# the original shows the function keys there, the free ROM the date and time
python3 "$ROOT/tests/mkcas.py" "$OUT/files.cas"
for T in "$HERE"/tests/basic/*.txt; do
  NAME=$(basename "$T" .txt)
  TEXT="width 37\ncls\n$(cat "$T")"
  FRAMES=400
  [ -f "${T%.txt}.frames" ] && FRAMES=$(cat "${T%.txt}.frames")
  ARGS=()
  case "$NAME" in cas*) ARGS=(-tape "$OUT/files.cas") ;; esac
  "$MSXFREE" basic "$OUT/orig" "$TEXT" $FRAMES "${ARGS[@]}" | sed 's/ *$//; /^24|/d' > "$OUT/test-orig.txt"
  "$MSXFREE" basic "$FREE" "$TEXT" $FRAMES "${ARGS[@]}" | sed 's/ *$//; /^24|/d' > "$OUT/test-free.txt"
  if diff "$OUT/test-orig.txt" "$OUT/test-free.txt" > "$OUT/test-diff.txt"; then
    echo "ok    free ROM BASIC test $NAME"
  else
    echo "FAIL  free ROM BASIC test $NAME: the free ROM differs from the original"
    cat "$OUT/test-diff.txt"
    FAILED=1
  fi
done
# the tape: what the text of tests/tapeout/*.txt writes must be the same bytes, block by block
for T in "$HERE"/tests/tapeout/*.txt; do
  NAME=$(basename "$T" .txt)
  "$MSXFREE" tapeout "$OUT/orig" "$(cat "$T")" 2500 > "$OUT/test-orig.txt"
  "$MSXFREE" tapeout "$FREE" "$(cat "$T")" 2500 > "$OUT/test-free.txt"
  if [ -s "$OUT/test-orig.txt" ] && diff "$OUT/test-orig.txt" "$OUT/test-free.txt" > "$OUT/test-diff.txt"; then
    echo "ok    free ROM tape test $NAME"
  else
    echo "FAIL  free ROM tape test $NAME: the free ROM writes something else"
    cat "$OUT/test-diff.txt"
    FAILED=1
  fi
done
# the disk ROM: the disk driver's entries (DSKIO, DSKCHG, GETDPB) on a test disk, with the original disk ROM and
# QUANTIKA_DISK.ROM: the same results (fast disk access and at real speed). PAGE1 (a transfer into page 1's RAM)
# and the 40-track media bytes only on QUANTIKA_DISK.ROM (the original does neither).
if [ -f "$ORIG/msx/PHILIPSDISK.rom" ] && [ -f "$ROOT/roms/msx/QUANTIKA_DISK.ROM" ]; then
  mkdir -p "$OUT/origdisk/msx" "$OUT/freedisk/msx"
  cp -f "$ORIG/msx/MSX2.rom" "$ORIG/msx/MSX2EXT.rom" "$ORIG/msx/PHILIPSDISK.rom" "$OUT/origdisk/msx/"
  cp -f "$FREE/msx/MSX2.rom" "$FREE/msx/MSX2EXT.rom" "$OUT/freedisk/msx/"
  cp -f "$ROOT/roms/msx/QUANTIKA_DISK.ROM" "$OUT/freedisk/msx/PHILIPSDISK.rom"
  python3 "$ROOT/tests/mkdsk.py" "$OUT/test.dsk" HELLO.TXT=1000 DATA.BIN=5000 EMPTY.DAT=0
  # name, assembler defines, frames, the lines of the results to compare (a grep pattern)
  rundisk() {
    local NAME="$1" DEFS="$2" FRAMES="$3" LINES="$4" TIMED
    ( mkdir -p "$HERE/out" && cd "$HERE/tests" && sjasmplus.exe --nologo $DEFS "$NAME.asm" > "$OUT/test-asm.log" 2>&1 ) || {
      cat "$OUT/test-asm.log"; exit 1; }
    for TIMED in "" 1; do
      MSXFREE_TIMED=$TIMED "$MSXFREE" exec "$OUT/origdisk" "$HERE/out/$NAME.bin" "$FRAMES" -disk "$OUT/test.dsk" |
        grep "$LINES" > "$OUT/test-orig.txt"
      MSXFREE_TIMED=$TIMED "$MSXFREE" exec "$OUT/freedisk" "$HERE/out/$NAME.bin" "$FRAMES" -disk "$OUT/test.dsk" |
        grep "$LINES" > "$OUT/test-free.txt"
      if diff "$OUT/test-orig.txt" "$OUT/test-free.txt" > "$OUT/test-diff.txt"; then
        echo "ok    free disk ROM test $NAME $DEFS${TIMED:+ (real speed)}"
      else
        echo "FAIL  free disk ROM test $NAME $DEFS${TIMED:+ (real speed)}: the free disk ROM differs from the original"
        cat "$OUT/test-diff.txt"
        FAILED=1
      fi
    done
  }
  rundisk dskio "" 500 "^D000"
  rundisk dskio "-DWRITE" 500 "^D000"
  rundisk dskio "-DDPB" 500 "^D0[0-5CE]"
  # PAGE1: sectors 7 and 8 must come back from page 1's RAM (A, B, carry 0, then their sums)
  ( cd "$HERE/tests" && sjasmplus.exe --nologo -DPAGE1 dskio.asm > "$OUT/test-asm.log" 2>&1 ) || { cat "$OUT/test-asm.log"; exit 1; }
  SUMS=$(python3 -c "import sys; d=open(sys.argv[1],'rb').read(); print(' '.join('%02X %02X' % (s & 255, s >> 8) for s in (sum(d[i*512:(i+1)*512]) & 65535 for i in (7, 8))))" "$OUT/test.dsk")
  if "$MSXFREE" exec "$OUT/freedisk" "$HERE/out/dskio.bin" 500 -disk "$OUT/test.dsk" | grep -q "^D000: 00 00 00 $SUMS"; then
    echo "ok    free disk ROM test dskio -DPAGE1 (QUANTIKA_DISK.ROM only)"
  else
    echo "FAIL  free disk ROM test dskio -DPAGE1: the sectors read into page 1 are not in its RAM"
    FAILED=1
  fi
else
  echo "SKIP  free disk ROM tests: the original PHILIPSDISK.rom is not in $ORIG/msx"
fi
# graphics: the pictures of tests/graphics/*.txt typed on both must be the same
for T in "$HERE"/tests/graphics/*.txt; do
  NAME=$(basename "$T" .txt)
  FRAMES=4500                         # (NAME.frames: more for a slow picture)
  [ -f "${T%.txt}.frames" ] && FRAMES=$(cat "${T%.txt}.frames")
  RESULT=$("$MSXFREE" picdiff "$OUT/orig" "$FREE" $FRAMES -type "$(cat "$T")")
  case "$RESULT" in
    "0.0%"*) echo "ok    free ROM graphics test $NAME" ;;
    *) echo "FAIL  free ROM graphics test $NAME: $RESULT"; FAILED=1 ;;
  esac
done
exit $FAILED
