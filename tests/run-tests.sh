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

# Currah uSpeech: its ROM starts, and LET s$ speaks through the SP0256
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/currahtest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/currahtest" "$ROOT/roms"

# Adventure Debugger: the DAAD Ready test game on the 48K and 128K interpreters
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/daadtest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/daadtest" "$ROOT/roms" "$ROOT/tests/daad"

# ULAplus, Timex screen modes and Radastan
fpc -O2 -Fu"$ROOT/src" -FU"$BUILD" -FE"$BUILD" "$ROOT/tests/videotest.lpr" > "$BUILD/fpc.log" || {
  cat "$BUILD/fpc.log"; exit 1; }
"$BUILD/videotest" "$ROOT/roms"

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
