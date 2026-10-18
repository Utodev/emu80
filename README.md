# pzx
A free pascal / lazarus ZX Spectrum emulator

Emulates the ZX Spectrum 16K, 48K, 128K, +2, +2B and +3 with T-state accurate
Z80 timing, memory and I/O contention, floating bus, ULA snow and per-T-state
video.

The full user guide, including every command line option, is
[README.TXT](README.TXT) (also in Help > Documentation, F1).

## Features

- Z80 core verified with the FUSE test suite (every bus access and its
  T-state) and with all of Patrik Rak's z80test suites (z80full, z80doc,
  z80flags, z80docflags, z80ccf, z80memptr) running on the emulated machine.
- Contention and floating bus per model; floating bus timing verified with
  Ramsoft's *floatspy* on 48K and 128K timings.
- Beeper and AY-3-8912 sound (ABC stereo), paced by the sound card; optional
  TurboSound; an AY chip can be added to the 16K/48K; mute button.
- Joysticks on the cursor keys + Ctrl: Kempston, Sinclair Interface 2 (1 or
  2), Cursor/Protek or Fuller; Kempston mouse.
- TAP tapes with fast loading or real-time loading, auto-load on open.
- SNA and Z80 (v1/v2/v3) snapshots, load and save.
- +3 disk drive (uPD765) with standard and extended DSK images, writable.
- Disk browser: list the +3DOS files on a disk (type, start or autostart line,
  length), rename, delete, and import from / export to the PC.
- DivMMC with esxDOS 0.8.9 (bundled in `esxdos/`, from esxdos.org): SD card
  images, new cards (empty or with esxDOS), and an SD card browser for the FAT
  files (folders, +3DOS details, import/export, rename, delete, new folder).
- Tape browser: play from any block, move and delete blocks, save the tape.
- Menu, settings dialog and a quick toolbar to change model, reset and NMI.
- Pause (F9), turbo (F11) and CPU speed x2 to x32 (Settings > General):
  the Z80 runs faster but interrupts stay at 50 per second.
- SAVE writes to the inserted tape (or a new blank one, File > New blank tape).
- REC button: records the cassette output in real time, decoding standard-speed
  blocks onto the tape (for programs with their own save routines).
- New blank disks for drive A: or B:, already formatted (+3 format, 40
  tracks, 9 sectors). Optional drive B: (Options > Settings). Disk access runs
  at real drive speed unless Floppy > Fast floppy disk access is on.
- Keyboard issue 2 or issue 3 (Settings > Machine), affecting EAR bit 6.
- POKEs (Machine > POKE..., F4): `35899,0 : 36000,201`, with the last 20
  POKEs and the file they were used with.
- Screenshots as .SCR, or PNG at 1x or 2x, with or without the border.
- Black and white display; contention and ULA snow can be switched off.
- A ROM file of your choice for each ROM of each model; the ROM can only be
  changed from the debugger or with POKE if the settings allow it.
- Settings in `pzx.ini` next to the program; `--config FILE` uses another
  file, which must exist, and `--config-add FILE` applies extra settings for
  one session (a missing extra file is ignored).
- Command line: model, speed, zoom, tapes, disks, symbols, breakpoints and
  typed keys, e.g. `pzx --model 48k --tape game.tap --keyin 'J""\n'`.

## Building

**Windows:** open `src/pzx.lpi` in Lazarus and build, or run `lazbuild src/pzx.lpi`.
The executable is written next to the project, in `src`, so it builds from any
drive or folder; it finds `roms`, `README.TXT` and `LICENSE` in its own folder
or in the one above. To distribute it, put them next to the executable.
The executable expects the `roms` folder next to it (the ROM folder can be
changed in Options > Settings).

**Linux and macOS:** run `./build.sh`. It uses `lazbuild` if Lazarus is
installed (GTK2 on Linux, Cocoa on macOS); otherwise point it at a Lazarus
source tree with `LAZARUS_DIR=/path/to/lazarus ./build.sh` and it compiles
with `fpc` alone. The result, with its `roms` folder, goes to `build/linux/`
or `build/macos/pzx.app`. Linux needs the GTK2 development package to build
(`libgtk2.0-dev`). Sound uses SDL2 at run time (`libsdl2-2.0-0` on Linux,
`brew install sdl2` on macOS); without it pzx runs silently at the right speed.

## Keys

| PC key | Spectrum |
|---|---|
| Shift | CAPS SHIFT |
| Ctrl | SYMBOL SHIFT |
| Backspace | DELETE (CAPS+0) |
| Cursor keys | CAPS+5/6/7/8, or a joystick (see below) |
| Esc | BREAK (CAPS+SPACE) |
| Tab | Extended mode (CAPS+SYMBOL) |
| , . - = ; ' / | the matching SYMBOL SHIFT characters |

Options > Settings > Machine chooses what the cursor keys plus either Ctrl
(fire) emulate: nothing, Kempston, Sinclair Interface 2 joystick 1 or 2, Cursor/Protek or
Fuller.

F2 open, F3 save snapshot, F4 POKE, F5 NMI, F6 hard reset (Shift+F6 reset),
F7 tape browser, F8 play tape (Shift+F8 stop), F9 pause, F11 turbo.
Files can also be dropped on the window or passed on the command line.

The picture is always drawn at a whole-number zoom (1x to 4x, Options >
Window size), the largest that fits the window, centred on black.

## Debugger

Debug > Debugger (F12) opens a non-modal window and stops at the current
address; closing it carries on running (like F5). Hovering over any hex value
shows it in decimal.

- **Disassembly:** labels on the left (the column fits the labels on screen,
  up to 20 characters; hover over a cut one to see it all), mnemonics in
  blue, registers in bold. Jumps and memory references show the label
  instead of the number, with the value in grey brackets. The execution point
  is marked with an arrow. Double-click a line (or press Space) to set or
  remove an execution breakpoint; breakpoint lines are red. Right-click a
  breakpoint to make it an execution, read or write breakpoint (read/write
  ones stop after the instruction that touches that address; opcode fetches
  don't count as reads). On a conditional jump, call or return at the
  execution point, a green check or red cross shows whether the condition
  holds. Click an instruction byte to change it.
- **Registers:** AF, HL, DE, BC, IX and IY with the 16-bit word they point to,
  the alternate set, I, R, SP, PC, flags (X = set), IM, IFF1 and IFF2 and the
  top 10 stack entries (> marks the top). Values changed by the last
  instruction are dark red. Click a register, a pointed-to word or a stack
  value to edit it; click a flag, IFF1 or IFF2 to toggle it and IM to cycle
  0, 1, 2. DI/EI shows whether interrupts are enabled. Next to the stack, the
  last 10 port accesses: the address of the instruction, the port, `W` for a
  write or `R` for a read, and the value. Below, what each 16K slot holds
  (ROMn, RAMn, or ---- for no memory on the 16K); on the 128K models click
  slot 3 to page another RAM bank in.
- **Memory:** hex and ASCII. Bytes outside 32-126 show as an inverse "?".
  "Apply XOR" (hex) is applied to every byte before display. Click a hex
  value to edit it, or a character to type text from there. With a XOR key
  set, what you type is what you see: memory gets it XORed with the key.
- **Breakpoints:** every breakpoint with an on/off box, type, address, label
  and condition: add, edit, remove, switch on and off. Types: execution,
  memory read / write / any, and port read (IN) / write (OUT) / any. Switched-off ones are
  pale pink in the disassembly.
- **Memory** can be shown as 8x8 sprites (Space) and exported to or
  imported from a text file of `$XX` values.
- **Watches:** add addresses (toolbar glasses button or Insert, same input as
  Ctrl+G) to see the two bytes at each one; select one and press Delete to
  remove it.

**Breakpoint conditions.** A breakpoint can have a condition; it then stops
only when the condition holds, e.g. `BC=289A`, `A=3 AND #Z=1`, `A = C & 7`,
`A=@8400`, `HL = SCREEN_START`, `T=3`. Numbers are hex (`.30` is decimal);
registers are case-insensitive and win over symbols, which win over hex
numbers (`#NAME` forces a symbol, a leading 0 a number: `A=0A`). Flags take a
`#`: `#S #Z #5 #H #3 #P #N #C`. `@x` is the byte at address x, `T` the times
the breakpoint has been reached. Operators: logical `AND OR XOR NOT`,
comparisons, `+ - * / MOD` and bitwise `& |`; arithmetic wraps at 8 or 16
bits like the Z80. README.TXT has the full syntax.

Right-click the disassembly or the memory view for "Go to address" and more.

Keys: F5 run, F7 step into, F10 step over (CALL, RST, DJNZ, HALT and
repeating block instructions), F9 run to the selected line. Ctrl+G in the
disassembly or memory view goes to an address (hex, a register name such as
PC or HL, or a label) and lists the last 10 addresses used.

**Labels.** ROM routines and system variables are labelled from the `.sym`
files in `roms/`: the 48K ROM with the names from *The Complete Spectrum ROM
Disassembly*, and the 128K, +2 and +3 ROMs (including the +3DOS entry points)
from the ZXSpectrumVault disassemblies (`tools/make-rom-symbols.py` rebuilds
them). ROM labels only apply while that ROM is paged in. Your own symbols, in
the format SjASM / SjASMPlus export (`LABEL: EQU 0x8000`), can be loaded with
Debug > Load symbols or from the command line, and take precedence:

    pzx --sym game.sym game.tap

## Tests

`tests/run-tests.sh` builds and runs the FUSE Z80 core tests with `fpc`
(Linux, WSL or any platform with Free Pascal on the PATH).

`tests/machinetest.lpr` runs any model headless, optionally loading a file
and typing keys, and writes the screen as a PPM image plus the recognised
screen text. See the comment at the top of the file for its arguments.

## ROMs

The Spectrum ROMs in `roms/` are copyright Amstrad, who allow their
distribution but retain the copyright; see `roms/README.md`. The ROM labels in
`roms/48.sym` come from Richard Dymond's SkoolKit edition of *The Complete
Spectrum ROM Disassembly* by Ian Logan and Frank O'Hara
(github.com/skoolkid/rom, GPL v3). The 128K, +2 and +3 labels come from the
disassemblies collected in github.com/ZXSpectrumVault/rom-disassemblies (Paul
Farrow, Garry Lancaster and others).
