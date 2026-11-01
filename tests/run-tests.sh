#!/bin/sh
# Builds and runs the Z80 core tests with Free Pascal (Linux/WSL or any
# platform with fpc on the PATH). Exits non-zero on unexpected failures.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/tests/build"
mkdir -p "$BUILD"
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/z80test.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/z80test" "$ROOT/tests/fuse/tests.in" > "$BUILD/z80test.out"

# Names of tests whose output differs from tests.expected
awk '
  FNR == 1 { file++ }
  /^[0-9a-f_]+$/ { name = $0 }
  { line = tolower($0) }
  file == 1 { got[FNR] = line; at[FNR] = name; n1 = FNR }
  file == 2 && got[FNR] != line { bad[at[FNR] != "" ? at[FNR] : name] = 1 }
  END { for (t in bad) print t }
' "$BUILD/z80test.out" "$ROOT/tests/fuse/tests.expected" | sort > "$BUILD/failed.txt"
grep -v '^#' "$ROOT/tests/fuse/known-differences.txt" | sort > "$BUILD/known.txt"

TOTAL=$(grep -c '^[0-9a-f_]*$' "$ROOT/tests/fuse/tests.expected" || true)
UNEXPECTED=$(comm -23 "$BUILD/failed.txt" "$BUILD/known.txt")
if [ -n "$UNEXPECTED" ]; then
  echo "FUSE Z80 tests: unexpected failures:"
  echo "$UNEXPECTED"
  exit 1
fi
echo "FUSE Z80 tests: all passed ($(wc -l < "$BUILD/known.txt") known differences)"

# Breakpoint condition expressions
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/condtest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/condtest"

# Debugger memory export/import format
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/memtexttest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/memtexttest"

# +3DOS file system of the disk browser
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/plus3fstest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/plus3fstest" "$ROOT/roms"

# DivMMC: ESXDOS on a new SD card
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/divmmctest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/divmmctest" "$ROOT/roms" "$ROOT/esxdos" "$BUILD/divmmctest.img"
rm -f "$BUILD/divmmctest.img"

# Z80N: the ZX Spectrum Next's extra instructions
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/z80ntest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/z80ntest"

# ZX Spectrum Next: display layers and DMA
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/nextvideotest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/nextvideotest" "$ROOT/roms"

# ZX Spectrum Next: three AY chips, extended keys, Multiface, .nex and snapshots
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/nexthwtest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/nexthwtest" "$ROOT/roms" "$BUILD"

# ZX Spectrum Next: NextZXOS from a card made from specnext/ (skipped without it)
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/nexttest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/nexttest" "$ROOT/roms" "$ROOT/specnext" "$BUILD/nexttest.img"
rm -f "$BUILD/nexttest.img"

# Currah uSpeech: its ROM starts, and LET s$ speaks through the SP0256
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/currahtest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/currahtest" "$ROOT/roms"

# Adventure Debugger: the DAAD Ready test game on the 48K and 128K interpreters
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/daadtest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/daadtest" "$ROOT/roms" "$ROOT/tests/daad" "${DAAD_CPC_DSK:-}"

# ULAplus, Timex screen modes and Radastan
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/videotest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/videotest" "$ROOT/roms"

# Tape: fast loading when the tape is started with Play
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/tapetest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/tapetest" "$ROOT/roms" "$ROOT/tests/daad"

# TZX tapes (1.20): every block, the pulses of each signal, flow control,
# and the DAAD Ready test game as TZX with fast and real-time loading
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/tzxtest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/tzxtest" "$ROOT/roms" "$ROOT/tests/daad"

# ZX-Uno: its real BIOS and ROMs (zxuno folder), then loading a tape
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/zxunotest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/zxunotest" "$ROOT/roms" "$ROOT/tests/daad"

# What the debugger and POKE may write: ROM, RAM paged at 0000
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/poketest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/poketest" "$ROOT/roms" "$ROOT/esxdos"

# Breakpoints and watches saved as JSON and loaded back
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/debugfilestest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/debugfilestest" "$ROOT/roms" "$BUILD"

# The Quill: a database built in memory; with a folder of Quill games
# (QUILL_GAMES, or to_be_ignored/quillgames), those games too
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/quilltest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/quilltest" "$ROOT/roms" "${QUILL_GAMES:-$ROOT/to_be_ignored/quillgames}"

# Hints: every instruction and condact has a description
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/helptest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/helptest"

# Step back (the machine put back) and labels kept in the exported source
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/stepbacktest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/stepbacktest" "$ROOT/roms"

# Disassembly exported as sjasmplus source
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/asmexporttest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/asmexporttest" "$ROOT/roms" "$BUILD/rom48.asm"
# With sjasmplus, the source must assemble back to the ROM
SJ=${SJASMPLUS:-$(command -v sjasmplus || command -v sjasmplus.exe || true)}
if [ -n "$SJ" ]; then
  (cd "$BUILD" && "$SJ" --nologo --msg=war --raw=rom48.bin rom48.asm) > "$BUILD/sjasm.log" 2>&1
  if cmp -s "$BUILD/rom48.bin" "$ROOT/roms/48.rom" && ! grep -q -i 'warning\|error' "$BUILD/sjasm.log"; then
    echo "Assembler export: sjasmplus rebuilds the 48K ROM"
  else
    echo "Assembler export: sjasmplus does not rebuild the 48K ROM"; cat "$BUILD/sjasm.log"; exit 1
  fi
fi

# Installing the Next distribution from a zip
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/distrotest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/distrotest"

# Settings file entries and the Next's machine ID
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/configtest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/configtest" "$ROOT/roms"

# Tape auto play/stop
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/autoplaytest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/autoplaytest" "$ROOT/roms"

# The native library's API (the C# host demo is in tests/csharp)
fpc -O2 -Fu"$ROOT/src" -Fu"$ROOT/src/lib" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/libtest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/libtest" "$ROOT/roms"

# Amstrad CPC 464, 664 and 6128: firmware boot, banking, keyboard, sound, CDT
# recording and loading, snapshots
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/cpctest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/cpctest" "$ROOT/roms"

# SAM Coupe: ASIC, screen modes, WD1772, SAA1099, disk formats and which machine takes which,
# snapshots. The ROM and SAMDOS tests need the real ROM (it isn't distributed): put
# samcoupe.rom and SAMDOSVersion2.0.dsk in a folder and set SAM_TEST_DIR to it
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/samtest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/samtest" "$ROOT/roms" "$BUILD" "${SAM_TEST_DIR:-}"

# MSX: slots, secondary slot register, memory mapper and I/O space (needs no ROM)
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/msxtest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/msxtest"

# MSX2 on the real BIOS (roms/msx/MSX2.rom, not distributed): BASIC must start; skipped without it
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/msxrun.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/msxrun" "$ROOT/roms"

# The MSX2's default ROMs: QUANTIKA (roms/msx/QUANTIKA.ROM, QUANTIKA_SUB.ROM and QUANTIKA_DISK.ROM, made by their own project,
# ../quantika, which package.sh builds). They must boot to FBASIC in a text mode, with no logo and no pause,
# and have no machine name in them; with the original ROMs and ../quantika here, the test programs of that
# project must give the same results on both (tests/fbasic-difftests.sh; it needs sjasmplus.exe).
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/msxfree.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
if [ ! -f "$ROOT/roms/msx/QUANTIKA.ROM" ] || [ ! -f "$ROOT/roms/msx/QUANTIKA_SUB.ROM" ] || [ ! -f "$ROOT/roms/msx/QUANTIKA_DISK.ROM" ]; then
  echo "FAIL  roms/msx/QUANTIKA.ROM, QUANTIKA_SUB.ROM or QUANTIKA_DISK.ROM is missing (the emulator's MSX2 ROMs)"; exit 1
fi
FREEROMS="$BUILD/freeroms"
mkdir -p "$FREEROMS/msx"
rm -f "$FREEROMS/msx/PHILIPSDISK.rom"
cp -f "$ROOT/roms/msx/QUANTIKA.ROM" "$FREEROMS/msx/MSX2.rom"
cp -f "$ROOT/roms/msx/QUANTIKA_SUB.ROM" "$FREEROMS/msx/MSX2EXT.rom"
if "$BUILD/msxfree" screen "$FREEROMS" 100 | grep -q "QUANTIKA ROM with FBASIC 1.0"; then
  # no boot logo: the ROMs stay in a text mode (TMS mode 2) from power on to the banner
  for F in 3 10 25 50 75; do
    "$BUILD/msxfree" screen "$FREEROMS" $F | tail -1 | grep -q "^mode=2 " || {
      echo "FAIL  the QUANTIKA ROMs left the text mode while booting (frame $F): no logo is allowed"; exit 1; }
  done
  # no pause at boot: the banner is up within 20 frames (only the font is copied to VRAM before it)
  "$BUILD/msxfree" screen "$FREEROMS" 20 | grep -q "QUANTIKA ROM with FBASIC 1.0" || {
    echo "FAIL  the QUANTIKA ROMs take too long to show the banner (a pause at boot?)"; exit 1; }
  # the machine's name is not in them
  for R in "$ROOT"/roms/msx/QUANTIKA.ROM "$ROOT"/roms/msx/QUANTIKA_SUB.ROM "$ROOT"/roms/msx/QUANTIKA_DISK.ROM; do
    if LC_ALL=C grep -aqi "msx" "$R"; then echo "FAIL  $(basename "$R") contains the text MSX"; exit 1; fi
  done
  echo "ok    roms/msx/QUANTIKA.ROM and QUANTIKA_SUB.ROM boot to FBASIC (no logo, no pause, no machine name)"
  # the MSX1 slot layout (no expanded slot, the sub-ROM in slot 2): the ROMs boot there too
  MSXFREE_COMPAT=1 "$BUILD/msxfree" screen "$FREEROMS" 100 | grep -q "QUANTIKA ROM with FBASIC 1.0" || {
    echo "FAIL  the QUANTIKA ROMs do not boot with the MSX1 slot layout"; exit 1; }
  echo "ok    the QUANTIKA ROMs boot with the MSX1 slot layout (no expanded slot)"
  # with the QUANTIKA disk ROM (in a folder of its own, under the original's name) the machine boots with its disk
  # interface; the original disk ROM is left out with the QUANTIKA main ROM (it would hang the machine)
  FREEDISK="$BUILD/freedisk"
  mkdir -p "$FREEDISK/msx"
  cp -f "$FREEROMS/msx/MSX2.rom" "$FREEROMS/msx/MSX2EXT.rom" "$FREEDISK/msx/"
  cp -f "$ROOT/roms/msx/QUANTIKA_DISK.ROM" "$FREEDISK/msx/PHILIPSDISK.rom"
  OUTPUT=$("$BUILD/msxfree" screen "$FREEDISK" 300)
  echo "$OUTPUT" | grep -q "QUANTIKA ROM with FBASIC 1.0" && echo "$OUTPUT" | tail -1 | grep -q " disk=1" &&
    echo "$OUTPUT" | grep -q "QUANTIKA Disk BASIC extension 1.0" || {
    echo "FAIL  the QUANTIKA ROMs do not boot with QUANTIKA_DISK.ROM in the disk interface"; exit 1; }
  echo "ok    the QUANTIKA ROMs boot with QUANTIKA_DISK.ROM in the disk interface (Disk BASIC)"
  if [ -f "$ROOT/roms/msx/PHILIPSDISK.rom" ]; then
    cp -f "$ROOT/roms/msx/PHILIPSDISK.rom" "$FREEDISK/msx/PHILIPSDISK.rom"
    OUTPUT=$("$BUILD/msxfree" screen "$FREEDISK" 300)
    echo "$OUTPUT" | grep -q "QUANTIKA ROM with FBASIC 1.0" && echo "$OUTPUT" | tail -1 | grep -q " disk=0" || {
      echo "FAIL  the original disk ROM is not left out with the QUANTIKA main ROM"; exit 1; }
    cp -f "$ROOT/roms/msx/QUANTIKA_DISK.ROM" "$FREEDISK/msx/PHILIPSDISK.rom"
    echo "ok    the original disk ROM is left out with the QUANTIKA main ROM"
  fi
else
  echo "FAIL  roms/msx/QUANTIKA.ROM and QUANTIKA_SUB.ROM do not boot to FBASIC"; exit 1
fi
if [ -f "$ROOT/roms/msx/MSX2.rom" ] && [ -f "$ROOT/roms/msx/MSX2EXT.rom" ]; then
  if command -v sjasmplus.exe > /dev/null; then
    "$ROOT/tests/fbasic-difftests.sh" "$BUILD/msxfree" "$ROOT/roms" || exit 1
  else
    echo "SKIP  sjasmplus.exe is not in the PATH: the QUANTIKA ROMs are not compared with the original ones"
  fi
fi
