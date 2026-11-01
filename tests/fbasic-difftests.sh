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
  rundisk dskio "-DPHYDIO" 500 "^D000"
  rundisk dskio "-DWRITE -DPHYDIO" 500 "^D000"
  # search first / next with bit 7 of the FCB's drive byte set (the DTA's bytes as an FCB has them)
  rundisk srch80 "" 600 "^D0[0-9]"
  # the kernel (BDOS, F37Dh): the files made, written, read, renamed and deleted by tests/bdos.asm on a fresh
  # disk each time: the same results and the same files on the disk afterwards (tests/dskfiles.py: the names,
  # sizes, bytes and free clusters; not the dates)
  ( cd "$HERE/tests" && sjasmplus.exe --nologo bdos.asm > "$OUT/test-asm.log" 2>&1 ) || { cat "$OUT/test-asm.log"; exit 1; }
  for TIMED in "" 1; do
    for W in orig free; do
      python3 "$ROOT/tests/mkdsk.py" "$OUT/bdos-$W.dsk" HELLO.TXT=1000 DATA.BIN=5000 EMPTY.DAT=0
      MSXFREE_TIMED=$TIMED MSXFREE_SAVEDISK="$OUT/bdos-$W.out.dsk" "$MSXFREE" exec "$OUT/${W}disk" "$HERE/out/bdos.bin" 700 \
        -disk "$OUT/bdos-$W.dsk" | grep "^D0[0-7]" > "$OUT/test-$W.txt"
      python3 "$ROOT/tests/dskfiles.py" "$OUT/bdos-$W.out.dsk" >> "$OUT/test-$W.txt"
    done
    if grep -q " AA 00" "$OUT/test-orig.txt" && diff "$OUT/test-orig.txt" "$OUT/test-free.txt" > "$OUT/test-diff.txt"; then
      echo "ok    free disk ROM test bdos${TIMED:+ (real speed)}"
    else
      echo "FAIL  free disk ROM test bdos${TIMED:+ (real speed)}: the free disk ROM differs from the original"
      cat "$OUT/test-diff.txt"
      FAILED=1
    fi
  done
  # the boot (when the disks of the test set are there, in to_be_ignored/MSX: never in the repository): the
  # disk operating system's own system file and command interpreter from a disk (the screen and the disk
  # after some commands the same, dates left out), a disk whose boot program finds no system file (BASIC
  # starts), two games that boot from their boot sector (the same screen mode) and a disk with its own
  # system file and AUTOEXEC.BAT (the same picture)
  TESTSET="$ROOT/to_be_ignored/MSX"
  bootdisk() {
    local NAME="$1" DISK="$2" FRAMES="$3" TEXT="$4" W
    for W in orig free; do
      rm -f "$OUT/boot-$W.dsk"; cp "$DISK" "$OUT/boot-$W.dsk"; chmod u+w "$OUT/boot-$W.dsk"
      MSXFREE_SAVEDISK="$OUT/boot-$W.out.dsk" "$MSXFREE" screen "$OUT/${W}disk" "$FRAMES" -disk "$OUT/boot-$W.dsk" \
        ${TEXT:+-type "$TEXT"} > "$OUT/test-$W.full"
      grep "^[0-9][0-9]|" "$OUT/test-$W.full" | grep -v "^24|" > "$OUT/test-$W.txt"
      python3 "$ROOT/tests/dskfiles.py" "$OUT/boot-$W.out.dsk" >> "$OUT/test-$W.txt" 2>&1
    done
  }
  if [ -f "$TESTSET/msxdos1.dsk" ]; then
    bootdisk dos "$TESTSET/msxdos1.dsk" 2500 'DIR/W\nCOPY CLS.COM X.COM\nDIR X.COM/W\nDIR CL*.*/W\n'
    if grep -q "1 file copied" "$OUT/test-orig.txt" && diff "$OUT/test-orig.txt" "$OUT/test-free.txt" > "$OUT/test-diff.txt"; then
      echo "ok    free disk ROM boot: the disk operating system from a disk, DIR and COPY"
    else
      echo "FAIL  free disk ROM boot: the disk operating system from a disk differs"
      cat "$OUT/test-diff.txt"
      FAILED=1
    fi
    # a disk error under it (drive B: has no disk): abort, then the command interpreter goes on (the free ROM
    # only: the original reads an empty drive as a disk of an unknown media type, and asks nothing)
    rm -f "$OUT/boot-free.dsk"; cp "$TESTSET/msxdos1.dsk" "$OUT/boot-free.dsk"; chmod u+w "$OUT/boot-free.dsk"
    if MSXFREE_KEYS='1000=A|1300=DIR CLS.COM/W\n' "$MSXFREE" screen "$OUT/freedisk" 1900 -disk "$OUT/boot-free.dsk" \
      -type 'DIR B:\n' | grep -A1 "Not ready error reading drive B" | grep -q "Abort, Retry, Ignore? A" &&
      MSXFREE_KEYS='1000=A|1300=DIR CLS.COM/W\n' "$MSXFREE" screen "$OUT/freedisk" 1900 -disk "$OUT/boot-free.dsk" \
      -type 'DIR B:\n' | grep -q "1 file .*bytes free"; then
      echo "ok    free disk ROM boot: a disk error under the disk operating system, aborted (QUANTIKA_DISK.ROM only)"
    else
      echo "FAIL  free disk ROM boot: a disk error under the disk operating system"
      FAILED=1
    fi
    # the boot program of that disk, on a disk with no system file: BASIC starts
    python3 "$ROOT/tests/mkdsk.py" "$OUT/nosys.dsk" HELLO.TXT=1000
    python3 -c "import sys; b = open(sys.argv[1], 'rb').read()[:512]; d = bytearray(open(sys.argv[2], 'rb').read()); d[:512] = b; open(sys.argv[2], 'wb').write(d)" \
      "$TESTSET/msxdos1.dsk" "$OUT/nosys.dsk"
    if "$MSXFREE" screen "$OUT/freedisk" 1200 -disk "$OUT/nosys.dsk" | grep -q "^04|  QUANTIKA Disk BASIC extension" && "$MSXFREE" screen "$OUT/freedisk" 1200 -disk "$OUT/nosys.dsk" | grep -q "^05|  Ok"; then
      echo "ok    free disk ROM boot: a boot program with no system file goes back to BASIC"
    else
      echo "FAIL  free disk ROM boot: a boot program with no system file does not go back to BASIC"
      FAILED=1
    fi
  fi
  for G in TETRIS COLUMNS; do
    [ -f "$TESTSET/games/$G.DSK" ] || continue
    bootdisk "$G" "$TESTSET/games/$G.DSK" 1500 ""
    MODES="$(grep -o "^mode=[0-9]*" "$OUT/test-orig.full") $(grep -o "^mode=[0-9]*" "$OUT/test-free.full")"
    if [ "${MODES% *}" = "${MODES#* }" ] && [ "${MODES% *}" != "mode=2" ]; then
      echo "ok    free disk ROM boot: $G.DSK boots (the same screen mode: ${MODES% *})"
    else
      echo "FAIL  free disk ROM boot: $G.DSK: $MODES"
      FAILED=1
    fi
  done
  if [ -f "$TESTSET/DAADMSX1.DSK" ]; then
    rm -f "$OUT/boot-free.dsk"; cp "$TESTSET/DAADMSX1.DSK" "$OUT/boot-free.dsk"; chmod u+w "$OUT/boot-free.dsk"
    if "$MSXFREE" picdiff "$OUT/origdisk" "$OUT/freedisk" 2000 -disk "$OUT/boot-free.dsk" | grep -q "^0.0% "; then
      echo "ok    free disk ROM boot: DAADMSX1.DSK (its own system file and AUTOEXEC.BAT): the same picture"
    else
      echo "FAIL  free disk ROM boot: DAADMSX1.DSK: the picture differs"
      FAILED=1
    fi
  fi
  # PAGE1: sectors 7 and 8 must come back from page 1's RAM (A, B, carry 0, then their sums)
  ( cd "$HERE/tests" && sjasmplus.exe --nologo -DPAGE1 dskio.asm > "$OUT/test-asm.log" 2>&1 ) || { cat "$OUT/test-asm.log"; exit 1; }
  SUMS=$(python3 -c "import sys; d=open(sys.argv[1],'rb').read(); print(' '.join('%02X %02X' % (s & 255, s >> 8) for s in (sum(d[i*512:(i+1)*512]) & 65535 for i in (7, 8))))" "$OUT/test.dsk")
  if "$MSXFREE" exec "$OUT/freedisk" "$HERE/out/dskio.bin" 500 -disk "$OUT/test.dsk" | grep -q "^D000: 00 00 00 $SUMS"; then
    echo "ok    free disk ROM test dskio -DPAGE1 (QUANTIKA_DISK.ROM only)"
  else
    echo "FAIL  free disk ROM test dskio -DPAGE1: the sectors read into page 1 are not in its RAM"
    FAILED=1
  fi
  # INIT: the drives in DRVTBL (FB21h) and H.PHYD (FFA7h): 2 and RST 30h; with CTRL held at boot 1 (both disk ROMs; the
  # original looks at the keys later, after its logo); with SHIFT held no disk system (QUANTIKA_DISK.ROM: the hook stays RET)
  drives() { "$MSXFREE" basic "$1" '?PEEK(&HFB21);HEX$(PEEK(&HFFA7))\n' 300 | grep -A1 "  ?PEEK" | tail -1 | cut -c4- | tr -s ' '; }
  for CASE in ":2 F7:2 F7" "ctrl:1 F7:1 F7" "shift::0 C9"; do
    IFS=: read -r HOLD WANT_ORIG WANT_FREE <<<"$CASE"
    GOT_FREE=$(MSXFREE_HOLD=$HOLD drives "$OUT/freedisk")
    GOT_ORIG="$WANT_ORIG"
    [ -n "$WANT_ORIG" ] && GOT_ORIG=$(MSXFREE_HOLD=$HOLD MSXFREE_HOLDFRAMES=700 drives "$OUT/origdisk")
    if [ "$GOT_FREE" = " $WANT_FREE" ] && { [ -z "$WANT_ORIG" ] || [ "$GOT_ORIG" = " $WANT_ORIG" ]; }; then
      echo "ok    free disk ROM INIT${HOLD:+ with $HOLD held}: DRVTBL and H.PHYD as they should be"
    else
      echo "FAIL  free disk ROM INIT${HOLD:+ with $HOLD held}: '$GOT_FREE' (original '$GOT_ORIG'), not '$WANT_FREE'"
      FAILED=1
    fi
  done
  # disk BASIC: sessions typed on a fresh disk (tests/mkdsk.py, with the files given): the screen (not the banner
  # nor the bottom line) and the files on the disk afterwards (tests/dskfiles.py; the original leaves the media
  # byte out of the second FAT of a disk it formats: that line is left out) must be the same. KEYS: more keys
  # typed later (MSXFREE_KEYS: both ROMs lose some of the keys typed while a disk is formatted, not the same ones)
  diskbasic() {
    local NAME="$1" FRAMES="$2" TEXT="$3" W
    shift 3
    for W in orig free; do
      python3 "$ROOT/tests/mkdsk.py" "$OUT/basic-$W.dsk" "$@"
      MSXFREE_KEYS="$KEYS" MSXFREE_SAVEDISK="$OUT/basic-$W.out.dsk" "$MSXFREE" screen "$OUT/${W}disk" "$FRAMES" \
        -disk "$OUT/basic-$W.dsk" -type "$TEXT" \
        | sed 's/ *$//' | grep "^[0-9][0-9]|" | grep -v "^0[1-4]|\|^24|" > "$OUT/test-$W.txt"
      python3 "$ROOT/tests/dskfiles.py" "$OUT/basic-$W.out.dsk" 2>&1 | grep -v "FAT copies differ" >> "$OUT/test-$W.txt"
    done
    if diff "$OUT/test-orig.txt" "$OUT/test-free.txt" > "$OUT/test-diff.txt"; then
      echo "ok    free disk ROM BASIC: $NAME"
    else
      echo "FAIL  free disk ROM BASIC: $NAME"
      cat "$OUT/test-diff.txt"
      FAILED=1
    fi
  }
  diskbasic "SAVE, SAVE ,A, LOAD, MERGE, RUN, FILES" 2500 \
    '10 PRINT "HI";A\n20 A=A+5\nSAVE "PROG"\nSAVE "PROGA.BAS",A\nNEW\nLOAD "PROG"\nLIST\n30 PRINT "MORE"\nSAVE "M.ASC",A\nNEW\n10 A=7\nMERGE "M.ASC"\nRUN\nRUN "PROG"\nLOAD "PROGA",R\nFILES\n'
  diskbasic "BSAVE, BLOAD (an offset, R, S)" 2500 \
    'FOR I=0 TO 255:POKE &HC000+I,I:NEXT:POKE &HC010,201\nBSAVE "B.BIN",&HC000,&HC0FF,&HC010\nFOR I=0 TO 255:POKE &HC000+I,0:NEXT\nBLOAD "B.BIN"\nPRINT PEEK(&HC005);PEEK(&HC0FF)\nBLOAD "B.BIN",&H100\nPRINT PEEK(&HC105)\nBLOAD "B.BIN",R\nVPOKE 5,65:VPOKE 6,66\nBSAVE "V.BIN",0,255,S\nVPOKE 5,0\nBLOAD "V.BIN",S\nPRINT VPEEK(5);VPEEK(6)\nFILES\n'
  diskbasic "NAME, COPY, KILL, DSKF, FILES with wildcards" 3000 \
    'FILES\nNAME "A.TXT" AS "C.TXT"\nCOPY "B.TXT" TO "D.TXT"\n\w\wCOPY "*.TXT" TO "*.BAK"\n\w\w\wKILL "B.TXT"\nNAME "*.BAK" AS "*.OLD"\nFILES\nFILES "?.OLD"\nPRINT DSKF(0);DSKF(1)\n' \
    A.TXT=100 B.TXT=3000 LONGNAME.DAT=700
  diskbasic "the errors" 2500 \
    'LOAD "NONE"\nKILL "NONE"\nNAME "A.TXT" AS "B.TXT"\nNAME "A.TXT" AS "B:C.TXT"\nLOAD "Z:X"\nSAVE "A*"\nSAVE "X.Y.Z"\nCOPY "A.TXT" TO "A.TXT"\nBSAVE "X",&H100,&H200\nBLOAD "PROG"\nFILES "NONE"\nCALL SYSTEM\nCALL NOSUCH\n' \
    A.TXT=100 B.TXT=200
  # the names: TOOLONGNAME is TOOLONGN.AME, AB.CDEF and AB.CDE.F are AB.CDE, ABCDEFGHI.TX and X.Y.Z are bad
  diskbasic "the file names (long ones, dots, wildcards)" 2000 \
    'SAVE "TOOLONGNAME"\nSAVE "ABCDEFGHI.TX"\nSAVE "AB.CDEF"\nSAVE "ABCDEFGHIJKLMNOP"\nSAVE "ABCDEFGHIJ.K"\nSAVE "AB.CDE.F"\nSAVE "ABCDEFG*.X"\nSAVE ".X"\nFILES "A*.*.*"\nFILES "*.C*"\nFILES "AB*CD.*"\nFILES "AB?"\nFILES\n'
  KEYS='700=A1 |3500=FILES\nPRINT DSKF(0)\n' diskbasic "CALL FORMAT one side" 4000 'call format\n'
  KEYS='700=A2 |4000=FILES\nPRINT DSKF(0)\n' diskbasic "CALL FORMAT two sides" 4500 'call format\n'
  KEYS='700=X|750=a|800=0|850=9|900= ' diskbasic "CALL FORMAT: a drive not there, a format not offered" 1500 'call format\n'
  # disk BASIC's files: a program on the disk (P.BAS, text) run with RUN "P.BAS" (the record a random file has
  # never written is not compared: the original writes what its buffer had there)
  diskprog() {
    local NAME="$1" FRAMES="$2" PROG="$3"
    shift 3
    diskbasic "$NAME" "$FRAMES" 'RUN "P.BAS"\n' "P.BAS:$PROG" "$@"
  }
  diskprog "files: OUTPUT, INPUT, APPEND, INPUT #, LINE INPUT #, INPUT$, EOF, LOC, LOF" 1500 \
    '10 OPEN "T" FOR OUTPUT AS 1:PRINT #1,"AB,CD":PRINT #1,12;-3:CLOSE\n20 OPEN "T" FOR INPUT AS 1:PRINT LOC(1);LOF(1);EOF(1)\n30 INPUT #1,A$,B$,X,Y:PRINT A$;B$;X;Y;LOC(1);EOF(1)\n40 CLOSE:OPEN "T" FOR APPEND AS 1:PRINT #1,"Z":PRINT LOC(1);LOF(1):CLOSE\n50 OPEN "T" FOR INPUT AS 1:PRINT INPUT$(5,1):LINE INPUT #1,A$:PRINT A$:LINE INPUT#1,A$:PRINT A$\n60 PRINT EOF(1):CLOSE\n70 OPEN "L" FOR OUTPUT AS 1:FOR I=1 TO 100:PRINT #1,I:NEXT:PRINT LOC(1):CLOSE\n80 OPEN "L" FOR INPUT AS 1:FOR I=1 TO 60:INPUT #1,A:NEXT:PRINT A;LOC(1);LOF(1)\n90 IF NOT EOF(1) THEN INPUT #1,A:GOTO 90\n100 PRINT A;LOC(1);EOF(1)'
  diskprog "files: random (LEN, FIELD, LSET, RSET, PUT, GET), MKI$ / CVI and the like" 1500 \
    '5 MAXFILES=2\n10 OPEN "R" AS 1 LEN=10\n20 FIELD 1,4 AS A$,6 AS B$\n30 FOR I=1 TO 3:LSET A$=STR$(I):RSET B$="X"+CHR$(64+I):PUT 1,I:NEXT\n40 PRINT LOC(1);LOF(1)\n50 GET 1,2:PRINT "[";A$;"][";B$;"]";LOC(1)\n60 GET 1:PRINT "[";A$;"][";B$;"]";LOC(1)\n70 PUT 1,4:PRINT LOF(1):CLOSE\n80 OPEN "R" AS 1 LEN=10:FIELD 1,10 AS C$:GET 1,4:PRINT ASC(C$);LOC(1)\n90 PRINT LOF(1)\n100 PRINT CVI(MKI$(-2));CVS(MKS$(1.5));CVD(MKD$(1/3));LEN(MKD$(1))\n110 A$=MKI$(258):PRINT ASC(A$);ASC(MID$(A$,2))\n120 LSET C$="LONGER THAN TEN":PRINT "[";C$;"]":RSET C$="AB":PRINT "[";C$;"]"\n130 CLOSE:OPEN "S" AS 2:FIELD 2,200 AS D$,56 AS E$:PRINT LEN(D$);LEN(E$):LSET D$="Q":PUT 2:PUT 2:PRINT LOF(2);LOC(2):CLOSE\n140 OPEN "S" AS 2 LEN=256:FIELD 2,128 AS D$:GET 2,2:PRINT ASC(D$);LOC(2):CLOSE'
  diskprog "files: the errors" 1500 \
    '5 MAXFILES=3:ON ERROR GOTO 1000\n10 N=10:OPEN "NONE" FOR INPUT AS 1\n20 N=20:OPEN "X" FOR OUTPUT AS 1:OPEN "X" FOR OUTPUT AS 2\n30 N=30:OPEN "X" FOR INPUT AS 2\n40 N=40:INPUT #1,A$\n50 N=50:GET 1,1\n60 N=60:KILL "X"\n70 N=70:NAME "X" AS "Y"\n80 N=80:CLOSE:OPEN "X" FOR INPUT AS 1:PRINT #1,"A"\n90 N=90:FIELD 1,10 AS A$\n100 N=100:CLOSE:OPEN "R" AS 1 LEN=20:FIELD 1,15 AS A$,6 AS B$\n110 N=110:PUT 1,0\n120 N=120:GET 1,1\n130 N=130:PRINT LOF(3)\n140 N=140:PRINT EOF(3)\n150 N=150:OPEN "R" AS 2\n160 N=160:OPEN "X" FOR INPUT AS 3:PRINT INPUT$(3,3)\n170 N=170:OPEN "Z:X" FOR OUTPUT AS 3\n180 N=180:OPEN "X" FOR OUTPUT AS 0\n200 N=200:FIELD 1,300 AS A$\n210 N=210:CLOSE:OPEN "X" FOR INPUT AS 1 LEN=10:PRINT LOC(1);LOF(1)\n220 N=220:OPEN "E" FOR OUTPUT AS 2:CLOSE 2:OPEN "E" FOR INPUT AS 2:PRINT EOF(2);LOF(2);LOC(2)\n230 N=230:LINE INPUT #2,A$\n240 N=240:OPEN "E" FOR APPEND AS 3\n250 N=250:PRINT "END":END\n1000 PRINT N;ERR;"|";:RESUME NEXT'
  diskprog "files: DSKI$, DSKO$, LOF and LOC of a long file" 1500 \
    '10 A$=DSKI$(0,0):PRINT LEN(A$);\n20 S=PEEK(&HF351)+256*PEEK(&HF352):PRINT PEEK(S);PEEK(S+21);PEEK(S+511)\n30 A$=DSKI$(0,14):PRINT PEEK(S);PEEK(S+1):POKE S,65:POKE S+1,66:DSKO$ 0,14\n40 OPEN "BIG" FOR INPUT AS 1:PRINT LOF(1);LOC(1):A$=INPUT$(60,1):PRINT LOC(1):CLOSE\n50 ON ERROR GOTO 100\n80 N=80:DSKO$ 1\n90 N=90:OPEN "CRT:" FOR OUTPUT AS 1 LEN=10:CLOSE\n99 PRINT "END":END\n100 PRINT N;ERR;"|";:RESUME NEXT' A.TXT=100 BIG=70000
  diskprog "files: PRINT # USING, an open file and KILL, CON, LOC of a random file" 1500 \
    '5 MAXFILES=3:ON ERROR GOTO 900\n10 OPEN "U" FOR OUTPUT AS #2:PRINT #2,USING "##.## !";3.14159;"XY":PRINT #2,"""Q"",W";-1.5E+20:CLOSE #2\n20 OPEN "U" FOR INPUT AS 3:LINE INPUT #3,A$:PRINT A$:INPUT #3,B$,C$,D:PRINT B$;"/";C$;"/";D:CLOSE\n30 OPEN "U" FOR INPUT AS 1:OPEN "U" FOR INPUT AS 2\n40 KILL "*.*"\n50 CLOSE:OPEN "R" AS 1 LEN=7:FIELD 1,2 AS I$,5 AS S$\n60 FOR K=1 TO 3:LSET I$=MKI$(K*100):LSET S$=MKS$(K/3):PUT #1:NEXT\n70 FOR K=3 TO 1 STEP -1:GET #1,K:PRINT CVI(I$);CVS(S$);LOC(1);:NEXT:PRINT LOF(1)\n80 PRINT LOF(1):CLOSE\n90 OPEN "P" FOR OUTPUT AS 1:PRINT #1,"A":OPEN "CON" FOR OUTPUT AS 2:PRINT #2,"TO CON":CLOSE 2\n100 OPEN "Q" FOR OUTPUT AS 3:PRINT #3,"B":CLOSE 1,3\n110 OPEN "R" AS 1 LEN=10:FIELD 1,10 AS Z$:GET 1,4:PRINT LEN(Z$);LOC(1);ASC(Z$)\n120 GET 1:PRINT LOC(1)\n800 PRINT "END":END\n900 PRINT ERL;ERR;"|";:RESUME NEXT'
  diskprog "files: what closes them (MAXFILES, CLEAR, END)" 1500 \
    '10 ON ERROR GOTO 900:OPEN "M" FOR OUTPUT AS 1:PRINT #1,"HI":MAXFILES=2\n20 OPEN "N" FOR OUTPUT AS 2:PRINT #2,"HO":CLEAR 300\n30 OPEN "O" FOR OUTPUT AS 1:PRINT #1,"HU":CLEAR\n40 OPEN "Q" FOR OUTPUT AS 1:PRINT #1,"HE":PRINT #1,"X"\n50 MAXFILES=2:OPEN "M" FOR INPUT AS 1:OPEN "N" FOR INPUT AS 2:LINE INPUT #1,A$:LINE INPUT #2,B$:PRINT A$;B$:CLOSE\n60 OPEN "S" FOR OUTPUT AS 2:PRINT #2,"END";:END\n900 PRINT ERL;ERR;"|";:RESUME NEXT'
  Q300=$(printf 'Q%.0s' $(seq 300)); Q256=${Q300:0:256}; EOF1A=$(printf '\x1a')
  diskprog "files: APPEND's place (no 1Ah)" 900 \
    '10 OPEN "A.TXT" FOR APPEND AS 1:PRINT #1,"Z";:CLOSE\n20 OPEN "C.TXT" FOR APPEND AS 1:PRINT #1,"Z";:CLOSE\n30 OPEN "D.TXT" FOR APPEND AS 1:PRINT #1,"Z";:CLOSE\n40 OPEN "E.TXT" FOR APPEND AS 1:PRINT #1,"Z";:CLOSE\n50 OPEN "F.TXT" FOR APPEND AS 1:PRINT #1,"Z";:CLOSE\n' \
    "A.TXT:$Q300" "C.TXT:${Q300:0:100}" "D.TXT:$Q256" "E.TXT:${Q300:0:257}" "F.TXT:"
  diskprog "files: APPEND's place (a 1Ah), APPEND of no file" 900 \
    '10 OPEN "A.TXT" FOR APPEND AS 1:PRINT #1,"Z";:CLOSE\n20 OPEN "C.TXT" FOR APPEND AS 1:PRINT #1,"Z";:CLOSE\n30 OPEN "D.TXT" FOR APPEND AS 1:PRINT #1,"Z";:CLOSE\n40 OPEN "E.TXT" FOR APPEND AS 1:PRINT #1,"Z";:CLOSE\n50 OPEN "N.TXT" FOR APPEND AS 1:PRINT #1,"Z";:CLOSE\n' \
    "A.TXT:${Q300:0:10}$EOF1A${Q300:0:289}" "C.TXT:$Q256$Q256" "D.TXT:${Q300}${Q300}$EOF1A${Q300:0:9}" "E.TXT:${Q300:0:250}$EOF1A${Q300:0:9}"
  diskprog "files: a full disk" 1500 \
    '5 CLEAR 1000:ON ERROR GOTO 100\n30 N=30:OPEN "O" FOR OUTPUT AS 1:FOR I=1 TO 40:PRINT #1,STRING$(250,65):NEXT:PRINT "C";LOC(1):CLOSE:PRINT "D"\n40 N=40:SAVE "S"\n45 N=45:BSAVE "T",&HC000,&HCFFF\n50 PRINT "END":END\n100 PRINT N;ERR;I;"|";:RESUME NEXT' BIG=722000
  FILLERS=(); for I in $(seq 110); do FILLERS+=("F$I=0"); done
  diskprog "files: a full directory" 1200 \
    '5 ON ERROR GOTO 100\n10 OPEN "Z1" FOR OUTPUT AS 1:CLOSE:OPEN "Z2" FOR OUTPUT AS 1:PRINT "X"\n20 SAVE "ZZ"\n50 PRINT "END":END\n100 PRINT ERL;ERR;"|";:RESUME NEXT' "${FILLERS[@]}"
  # the test diskerrors (tests/basic: the disk's statements without a drive) with one: the answers of the
  # disk ROMs (without SAVE "B:X": an empty drive B: is not ready here, the original writes nothing and says
  # nothing; no CLS: the first lines are not compared)
  diskbasic "the statements of the test diskerrors, with a drive" 5000 \
    "$(sed 's/56 save "b:x"\\n//; s/10 cls:/10 /' "$HERE/tests/basic/diskerrors.txt")"
  # AUTOEXEC.BAS: run at power on (the disk saved by the original first)
  python3 "$ROOT/tests/mkdsk.py" "$OUT/basic-auto.dsk"
  MSXFREE_SAVEDISK="$OUT/basic-auto.dsk" "$MSXFREE" basic "$OUT/origdisk" '10 PRINT "HELLO";A\n20 A=7\nSAVE "AUTOEXEC.BAS"\n' 600 -disk "$OUT/basic-auto.dsk" > /dev/null
  for W in orig free; do
    "$MSXFREE" basic "$OUT/${W}disk" 'PRINT A\n' 600 -disk "$OUT/basic-auto.dsk" | grep "^[0-9][0-9]|" | grep -v "^0[1-4]|\|^24|" > "$OUT/test-$W.txt"
  done
  if grep -q "HELLO 0" "$OUT/test-orig.txt" && diff "$OUT/test-orig.txt" "$OUT/test-free.txt" > "$OUT/test-diff.txt"; then
    echo "ok    free disk ROM BASIC: AUTOEXEC.BAS"
  else
    echo "FAIL  free disk ROM BASIC: AUTOEXEC.BAS"
    cat "$OUT/test-diff.txt"
    FAILED=1
  fi
  # with the disk operating system's disk (the test set): its FORMAT (4025h), COPY CON with CTRL+Z, the devices,
  # CTRL+C, and CALL SYSTEM from BASIC and back (the screens the same, dates left out: the order of the
  # day and the month is the main ROM's; not the first four lines: the banners)
  if [ -f "$TESTSET/msxdos1.dsk" ]; then
    dosdisk() {
      local NAME="$1" FRAMES="$2" KEYS="$3" CTRL="$4" W
      for W in orig free; do
        rm -f "$OUT/boot-$W.dsk"; cp "$TESTSET/msxdos1.dsk" "$OUT/boot-$W.dsk"; chmod u+w "$OUT/boot-$W.dsk"
        MSXFREE_CTRLC="$CTRL" MSXFREE_KEYS="$KEYS" MSXFREE_SAVEDISK="$OUT/boot-$W.out.dsk" "$MSXFREE" screen "$OUT/${W}disk" \
          "$FRAMES" -disk "$OUT/boot-$W.dsk" | grep "^[0-9][0-9]|" | grep -v "^24|" \
          | sed 's/ *$//;s/ *[0-9]*:[0-9]*[ap]$//;s/ *[ 0-9][0-9]-[0-9][0-9]-[0-9][0-9]$//' | grep -v "^0[1-4]|" > "$OUT/test-$W.txt"
        python3 "$ROOT/tests/dskfiles.py" "$OUT/boot-$W.out.dsk" 2>&1 | grep -v "FAT copies differ" >> "$OUT/test-$W.txt"
      done
      if diff "$OUT/test-orig.txt" "$OUT/test-free.txt" > "$OUT/test-diff.txt"; then
        echo "ok    free disk ROM boot: $NAME"
      else
        echo "FAIL  free disk ROM boot: $NAME"
        cat "$OUT/test-diff.txt"
        FAILED=1
      fi
    }
    dosdisk "FORMAT under the disk operating system" 6200 '1000=FORMAT\n|1300=A|1400=2|1500= |5500=DIR\n' ""
    dosdisk "COPY CON with CTRL+Z, then DIR" 2000 '1000=COPY CON X\n|1100=ABC\n|1300=\n|1500=\n|1700=DIR X\n' 1200:Z,1400:Z
    dosdisk "the devices: CON, NUL" 2300 \
      '1000=COPY CON NUL\n|1100=XY\n|1200=\n|1300=COPY MSXDOS.SYS NUL\n|1450=TYPE NUL\n|1550=DIR NUL\n|1650=COPY NUL Y\n|1800=DIR Y\n' 1150:Z
    dosdisk "CTRL+C at the command line and in TYPE" 1900 '1000=DIR /W|1150=TYPE COMMAND.COM\n|1600=DIR X\n' 1100,1400
    dosdisk "BASIC, CALL SYSTEM, BASIC (a new program)" 3600 '1000=BASIC\n|1600=10 PRINT 5\n|1800=CALL SYSTEM\n|2600=BASIC\n|3200=LIST\n' ""
  fi
  # one drive: drive B: is the same drive, with a prompt; after a key the sector is read (QUANTIKA_DISK.ROM)
  ( cd "$HERE/tests" && sjasmplus.exe --nologo -DDRIVEB dskio.asm > "$OUT/test-asm.log" 2>&1 ) || { cat "$OUT/test-asm.log"; exit 1; }
  RESULT=$(MSXFREE_DRIVEB=0 MSXFREE_KEYS='800= ' "$MSXFREE" exec "$OUT/freedisk" "$HERE/out/dskio.bin" 1000 -type ' ' -disk "$OUT/test.dsk")
  if echo "$RESULT" | grep -q "disk of drive B:" && echo "$RESULT" | grep -q "^D000: 00 00 00 "; then
    echo "ok    free disk ROM test dskio -DDRIVEB with one drive (the prompt, then the sector read)"
  else
    echo "FAIL  free disk ROM test dskio -DDRIVEB with one drive"
    echo "$RESULT" | grep -v "^[0-9][0-9]|$" | head -12
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
