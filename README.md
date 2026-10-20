# pzx

A free pascal / lazarus ZX Spectrum emulator

Emulates the ZX Spectrum 16K, 48K, 128K, +2, +2B and +3 with T-state accurate
Z80 timing, memory and I/O contention, floating bus, ULA snow and per-T-state
video.

The full user manual, including every command line option, follows below (it is
also shown by Help > Documentation, F1).

## Contents

- [Features](#features)
- [1. Getting started](#1-getting-started)
- [2. Keyboard](#2-keyboard)
- [3. Menus and toolbar](#3-menus-and-toolbar)
- [4. Settings](#4-settings)
  - [Interface](#interface)
  - [ZX-Uno](#zx-uno)
  - [Video modes](#video-modes)
  - [ZX Spectrum Next](#zx-spectrum-next)
  - [pzx snapshots (.pzs)](#pzx-snapshots-pzs)
- [5. Tape browser](#5-tape-browser)
  - [TZX tapes](#tzx-tapes)
- [6. Disk browser](#6-disk-browser)
- [7. DivMMC and SD cards](#7-divmmc-and-sd-cards)
  - [SD card browser](#sd-card-browser)
- [8. POKEs](#8-pokes)
- [9. Sound](#9-sound)
  - [Currah µSpeech](#currah-µspeech)
- [10. Debugger](#10-debugger)
  - [Disassembly](#disassembly)
  - [Registers](#registers)
  - [Memory](#memory)
  - [Breakpoints](#breakpoints)
  - [Watches](#watches)
  - [Breakpoint and watch files](#breakpoint-and-watch-files)
  - [Go to and View data](#go-to-and-view-data)
  - [Breakpoint conditions](#breakpoint-conditions)
  - [Keys](#keys)
  - [Labels](#labels)
  - [ROM](#rom)
- [11. Adventure Debugger](#11-adventure-debugger)
  - [Process](#process)
  - [Breakpoints](#breakpoints-1)
  - [Breakpoint conditions](#breakpoint-conditions-1)
  - [Flags](#flags)
  - [Objects location](#objects-location)
  - [Keys and toolbar](#keys-and-toolbar)
- [12. Command line](#12-command-line)
- [13. Files](#13-files)
- [Building](#building)
- [Tests](#tests)
- [ROMs](#roms)

## Features

- Z80 core verified with the FUSE test suite (every bus access and its
  T-state) and with all of Patrik Rak's z80test suites (z80full, z80doc,
  z80flags, z80docflags, z80ccf, z80memptr) running on the emulated machine.
- Contention and floating bus per model; floating bus timing verified with
  Ramsoft's *floatspy* on 48K and 128K timings.
- Beeper and AY-3-8912 sound (ABC stereo), paced by the sound card; optional
  TurboSound; an AY chip can be added to the 16K/48K; mute button.
- Currah µSpeech speech synthesizer (SP0256-AL2): key voices and `LET s$="..."` from BASIC.
- ZX Spectrum Next: Z80N, Next registers, 2 MB with its MMU, Layer 2, sprites, tilemap,
  copper, zxnDMA, three AY chips, its Multiface and `.nex` files, running NextZXOS from its
  official distribution (not included: see [ZX Spectrum Next](#zx-spectrum-next)).
- Joysticks on the cursor keys + Ctrl: Kempston, Sinclair Interface 2 (1 or
  2), Cursor/Protek or Fuller; Kempston mouse.
- TAP and TZX (1.20) tapes with fast loading or real-time loading, auto-load on open.
- SNA and Z80 (v1/v2/v3) snapshots, load and save; pzx's own .pzs snapshots of every model (the
  only kind for the ZX Spectrum Next and the ZX-Uno).
- +3 disk drive (uPD765) with standard and extended DSK images, writable.
- Disk browser: list the +3DOS files on a disk (type, start or autostart line,
  length), rename, delete, and import from / export to the PC.
- DivMMC with esxDOS 0.8.9 (bundled in `esxdos/`, from esxdos.org): SD card
  images, new cards (empty or with esxDOS), and an SD card browser for the FAT
  files (folders, +3DOS details, import/export, rename, delete, new folder).
- Tape browser: play from any block, move and delete blocks, save the tape.
- Menu, settings dialog and a quick toolbar to change model, reset and NMI.
- Pause (F4), turbo (Shift+F11) and CPU speed x2 to x32 (Settings > General):
  the Z80 runs faster but interrupts stay at 50 per second.
- SAVE writes to the inserted tape (or a new blank one, Tape > New blank tape).
- REC button: records the cassette output in real time, decoding standard-speed
  blocks onto the tape (for programs with their own save routines).
- New blank disks for drive A: or B:, already formatted (+3 format, 40
  tracks, 9 sectors). Optional drive B: (Options > Settings). Disk access runs
  at real drive speed unless Floppy > Fast floppy disk access is on.
- Keyboard issue 2 or issue 3 (Settings > Miscellaneous), affecting EAR bit 6.
- POKEs (Machine > POKE..., F9): `35899,0 : 36000,201`, with the last 20
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

---

# pzx - ZX Spectrum emulator

pzx emulates the ZX Spectrum 16K, 48K, 128K, +2, +2B and +3, the ZX-Uno (with its own BIOS
and ROMs) and the ZX Spectrum Next (with its official distribution), with T-state accurate Z80 timing, contended memory and I/O, floating bus, ULA snow and
per-T-state video, so games and demos run at their real speed. The screen and the border are
drawn as the beam reaches them, each 8-pixel cell taking its bytes and border colour at the end
of its 4 T-states (as Fuse does), so multicolour and border effects that race the beam show as
on the real machine.

## 1. Getting started

Open a file with File > Open (F2), by dropping it on the window, or from the command line.
Supported files:

| File | What it is |
|---|---|
| `.tap`, `.tzx` | tape images (TZX: see [TZX tapes](#tzx-tapes)). Opening one resets the machine and loads it (`LOAD ""` on the 16K/48K, the Loader menu option on the others; on the ZX-Uno, `LOAD ""` from its menu's 48 BASIC; on the ZX Spectrum Next it is only inserted). |
| `.sna` | snapshots (48K and 128K; on the ZX-Uno they switch to the 48K or 128K, as its ROM is the one its BIOS chose). |
| `.z80` | snapshots, versions 1, 2 and 3. |
| `.dsk` | +3 disk images (standard and extended). Opening one switches to the +3 if needed and boots it. |
| `.nex` | ZX Spectrum Next programs. Opening one switches to the Next if needed and starts it (see [ZX Spectrum Next](#zx-spectrum-next)). |
| `.pzs` | pzx's own snapshots, of any model (see [pzx snapshots](#pzx-snapshots-pzs)). Opening one switches to its machine. |

The machine model is chosen with the chip button on the toolbar (click it and pick one) or in
Options > Settings.

## 2. Keyboard

| PC key | Spectrum |
|---|---|
| Shift | CAPS SHIFT (see Shift keys below) |
| Ctrl | SYMBOL SHIFT |
| Backspace, Delete | DELETE (CAPS + 0) |
| Cursor keys | CAPS + 5/6/7/8, or a joystick (see below) |
| Esc | BREAK (CAPS + SPACE) |
| Tab | EXTEND MODE (CAPS + SYMBOL) |
| Insert | EDIT (CAPS + 1) |
| Caps Lock | CAPS LOCK (CAPS + 2) |
| Home | TRUE VIDEO (CAPS + 3) |
| End | INV. VIDEO (CAPS + 4) |
| Page Down | GRAPHICS (CAPS + 9) |
| `,` `.` `-` `=` `;` `'` `/` | the matching SYMBOL SHIFT characters |

The keys that are two Spectrum keys at once (all of the above but Shift and Ctrl, and `,` `.`
`;` `'`) are the extra keys of the ZX Spectrum Next's keyboard: on the Next they also show alone
in its registers `B0` and `B1`, and a program can keep them out of the Spectrum keys (NR `68`
bit 4), as on the real keyboard.

**Shift keys**: Settings > Miscellaneous (`--shiftkeys`) chooses between "standard" (the
default: either Shift is CAPS SHIFT, either Ctrl SYMBOL SHIFT) and "sides" (the left Shift and
left Ctrl are CAPS SHIFT, the right Shift and right Ctrl SYMBOL SHIFT).

**Joystick**: Settings > Miscellaneous chooses what the cursor keys plus either Ctrl key (fire)
emulate: nothing (they work as on the keyboard), a Kempston joystick (port `1F`), a Sinclair
Interface 2 joystick 1 (keys 6-0) or joystick 2 (keys 1-5), a Cursor/Protek/AGF joystick (keys
5-8 and 0) or a Fuller joystick (port `7F`). Only the chosen interface is connected.

**Mouse**: with the Kempston mouse on (Settings > Hardware), moving the PC mouse over the picture
moves the Spectrum's Kempston mouse (ports `FBDF` for X, `FFDF` for Y and `FADF` for the
buttons, as in K-Mouse), one Spectrum pixel per zoomed pixel. The PC pointer is hidden over the
picture; the program draws its own. Left, right and middle buttons are passed on. The mouse
stops when the pointer leaves the picture.

**Function keys**:

| Key | Action |
|---|---|
| F1 | documentation (this text) |
| F2 | open |
| F3 | save snapshot |
| F4 | pause |
| F5 | NMI (on the ZX Spectrum Next its M1 button; Shift+F5 its DRIVE button) |
| F6 | hard reset (Shift+F6 reset) |
| F7 | tape browser |
| F8 | play tape (Shift+F8 stop) |
| F9 | POKE |
| F11 | Adventure Debugger |
| Shift+F11 | turbo (as fast as possible) |
| F12 | debugger |

## 3. Menus and toolbar

In the menu bar, the storage menus (Tape, Floppy and SD) are between two separators (|).

**File**: Open, Open recent, Save snapshot (.z80, the default, .sna or .pzs; only .pzs on the ZX
Spectrum Next and the ZX-Uno), Screenshot (.SCR, or PNG at 1x or 2x
with or without the border), Exit.

**Machine**: NMI (F5), Hard reset (F6: off and on, clears the memory), Reset
(Shift+F6), Pause and POKE. On the ZX Spectrum Next, NMI is its M1 button (the Multiface) and
the menu has its DRIVE button too (Shift+F5: the DivMMC's NMI).

**Tape**: Tape browser, Play, Stop, Rewind, Eject, Save tape as, New blank tape, Fast loading
(the ROM loader is skipped and blocks load instantly, also when the tape has been started with
Play: Play at the end of the tape starts it again, and the ROM's LOAD takes its blocks at once), Auto play/stop (real-time loading starts
and stops the tape by itself) "SAVE writes to the tape" (SAVE adds its blocks to the inserted
tape, or to a new blank one, instantly) and Record (REC).

The tape plays at the CPU's pace: with the CPU faster than 1x (Settings > General, or a machine's
own turbo: the ZX Spectrum Next's 7-28 MHz, the ZX-Uno's) real-time loading still works, and
takes that many times less. A machine's own turbo ends with a reset or a change of model: the
other models run at the speed setting.

Record (REC, the red button on the toolbar and in the tape browser) records what the Spectrum
sends to the cassette, as a real recorder would: the MIC output is decoded and every block saved
at standard speed is added at the end of the tape. It works for any program that saves with the
ROM's timing, not only the ROM's SAVE. A block ends when the signal stops; press REC again to
stop recording. With "SAVE writes to the tape" on, the ROM's SAVE still goes to the tape
instantly instead of in real time. Turbo or custom-speed savers can't be decoded.

**Floppy**: Disk browser, insert, create (already formatted, 40 tracks, 9 sectors of 512 bytes)
and eject +3 disks in drives A: and B:, Insert recent disk (A:) and (B:) (the last 8 disk images;
both drives share the list), Save disk (into the file it was loaded from), Save disk as, Fast
floppy disk access (off: the drive works at real speed, with seek and rotation times) and "Drive
B: connected". Drive B: is not connected by default, and while it isn't, the menu entries for it
are hidden. It is connected from this menu, from Options > Settings > Storage, with `--driveb` or
by giving it a disk (`--diskb`).

Menu entries with a description show it in the status bar while the pointer is over them (the
debugger's menus show it in its own status bar).

**SD**: The DivMMC's SD card: SD card browser, insert an image, Insert recent SD card (the last 8
card images), new card (empty or with esxDOS) and eject (see
[DivMMC and SD cards](#7-divmmc-and-sd-cards)).

**Debug**: Debugger (F12), Clear all breakpoints, Load symbols, Load recent symbols (the last 8
symbol files), Clear symbols and, at the bottom, Adventure Debugger (F11, see
[Adventure Debugger](#11-adventure-debugger)).

**Options**: Black and white display, Window size, Mute sound, Turbo speed (Shift+F11: as fast as
possible), Modern interface (dark; see [Interface](#interface)) and Settings (everything else is
in Settings).

**Help**: Documentation (F1, this text from README.md), License (the GNU GPL v3, from the
`LICENSE` file) and About (pzx stands for Pascal ZX; it shows the release number, the build date
and time as YYYYMMDDHHMM, and the credits: the Spectrum ROMs (Amstrad), the authors of the ROM
labels in the .sym files, the ZX-Uno (ZX-Uno Team), the Next's boot ROM (Victor Trucco and
Fabio Belavenuto), esxDOS (Miguel Guerreiro) and the Currah
µSpeech's ROMs and SP0256 emulation (Currah, Microchip, MAME's Joseph Zbiciak and Tim Lindner)).

**Toolbar**: open, save snapshot, machine model (chip), hard reset (switch off and on, F6), NMI
(F5), pause, turbo, tape browser, play, stop, record (REC), disk browser (greyed out when there is
no disk to browse), SD card browser (greyed out without a DivMMC card), debugger and settings.
Hover over a button to see what it does.

The picture is always drawn at a whole-number zoom (1x to 4x), the largest that fits the window,
centred on black.

**Status bar**: the model, the frame rate (and CPU speed), the tape, and the media inserted: A
and B for the floppy drives (B only when it is connected) and SD for the DivMMC's card, each with
a small LED, dark red when idle and light red while the drive or card is read or written, like a
drive's light.

## 4. Settings

Options > Settings has five pages (sections of a page are boxes with a title):

| Page | Contents |
|---|---|
| General | machine model, window size, interface (classic or modern, see [Interface](#interface)), black and white display, mute sound (the same as Options > Mute sound), volume and CPU speed (1x to 32x: the Z80 runs faster but interrupts stay at 50 per second, and contention is not applied above 1x), and whether the settings are saved when pzx closes (on by default; when off, changes last only until pzx is closed). |
| Hardware | what is connected to the machine: TurboSound, an AY chip on the 16K/48K, the Kempston mouse, the DivMMC interface and the Currah µSpeech (changing the DivMMC or the µSpeech switches the machine off and on). Hovering over one explains it. |
| Storage | Tape: fast loading, auto play and SAVE to tape. Floppy: fast floppy disk access, drive B: and floppy drive noise (on by default: the drive's motor, head steps and reading are heard when it works at real speed, not with fast floppy disk access). |
| ROMs | ROMs: the folder with the standard ROMs and, for each model, the ROM file to use for each of its ROMs (empty = the standard one); labels for a ROM are read from a .sym file with the same name next to it. DivMMC: its firmware (empty = the bundled `esxdos/ESXMMC.BIN`). ZX-Uno: its BIOS and ROMs (empty = the ones in the zxuno folder) and its custom ROM (see [ZX-Uno](#zx-uno)). ZX Spectrum Next: its distribution folder, its SD card and whether it starts through its firmware (see [ZX Spectrum Next](#zx-spectrum-next)). |
| Miscellaneous | Graphics: ULAplus, scanlines, Timex screen modes and Radastan mode (all off by default; see [Video modes](#video-modes) below). Controls: keyboard issue 2 or 3 (16K/48K: affects bit 6 of port `FE`) and the shift keys (standard or sides, see [Keyboard](#2-keyboard)), as radio buttons, and the cursor keys joystick. Core features: contended memory and I/O (on by default: real timing; off makes every access take its nominal time), ULA snow (on by default; only the 16K, 48K, 128K and +2 show it) and allow writing to ROM (from the debugger and with POKE; off by default). |

Settings are kept in `pzx.ini` in the same folder as the program (next to pzx.app on macOS); on
Linux, if that folder can't be written (pzx installed from a .deb or .rpm package), in
`~/.config/pzx/pzx.ini`. See `--config` and `--config-add` below to use other files. `pzx.ini` is
an ini file whose keys are named exactly as the command line options (see
[Command line](#12-command-line)), with 1/0 for on/off options and the option's value for the
others:

| Section | Keys |
|---|---|
| `[General]` | `model`, `scale`, `ui` (`classic` or `modern`), `bw`, `mute`, `volume`, `speed`, `saveonexit` |
| `[Machine]` | `contention`, `snow`, `romedit`, `ulaplus`, `timex`, `radastan`, `scanlines`, `joystick`, `issue`, `shiftkeys` |
| `[Hardware]` | `turbosound`, `ay48`, `kmouse`, `divmmc`, `currah` |
| `[TapeDisk]` | `fastload`, `autoplay`, `savetotape`, `fastdisk`, `driveb`, `floppynoise` |
| `[ROMs]` | `romdir`, `rom` (the `--rom "MODEL,N,FILE"` entries separated by `\|`), `divmmcrom`, `zxunofirmware`, `zxunoroms`, `zxunocustomrom` |
| `[ZXNext]` | `nextdir`, `nextcard`, `nextfirmware` (and `distroid`, the distribution the card was made from) |
| `[Media]` | `sdcard` |
| `[Screenshot]` | `pngborder` |

The recent files, pokes and last folder are kept in sections of their own. A pzx.ini from an
older version is read and rewritten with these keys.

### Interface

pzx has two interfaces with the same commands: **classic** (the menu bar, the toolbar and the
status bar described above) and **modern** (dark, with palettes of big buttons). pzx starts in the
modern one; the first time (no settings file yet) a warning says so for 5 seconds, with the button
that changes to the classic one. The one in use is kept in pzx.ini (`[General] ui`) and can be
changed at once, without restarting: with the half dark
circle button (at the right end of the classic toolbar, left of the model in the modern header),
Options > Modern interface, or Settings > General > Interface; or for a session with
`--ui classic` or `--ui modern`.

The modern interface (on Windows 10 and 11 its title bar is dark too):

- **Header**: the menus as buttons (File, Machine, Tape, Floppy, SD, Debug, Options, Help: each
  opens the same menu, dark, with its checks and shortcuts) and, on the right, the button back to
  the classic interface and the model (click to change it: the models open under it). The keyboard shortcuts (F2, F9, F12...) work as in the classic one.
- **Machine palette** (left): Open, Save (snapshot), Off/on (hard reset), Reset, NMI, Pause, Turbo,
  POKE, Debug (the debugger) and Settings, with big buttons; Pause and Turbo are lit while on.
- **Tape palette** (right): a cassette with the tape's name on its label and its progress (all the
  tape starts on the left reel and passes to the right one as it plays; the hubs turn while it
  plays; click it for the tape browser), the tape's name and block, Eject (puts in a tape: as File > Open,
  for .tap and .tzx files only), Rewind, Play, Stop and Record, the tape browser and Fast loading (lit while
  on).
- **Media palette**: drives A: and B: and the SD card, with their LEDs and the files in them, and
  buttons for the disk and SD card browsers.
- **Bottom bar**: the zoom (1x to 4x, the one in use lit; a zoom too big for the screen isn't
  shown, and can't be chosen in Options > Window size) and what the classic status bar says.

The debuggers, the browsers and the other windows are the same in both interfaces, separate and
not modal; with the modern one they are dark too (their lists, fields, drop-down lists (white on
black), views, toolbars, tabs, check boxes, sliders and frames; their status bars and push
buttons are the system's own and stay light). The colours of the debugger's views are turned
round, keeping their hues; its mnemonics are bold white (light red for the undocumented ones,
also bold white on the execution point's green line), the values being edited black on white,
the Adventure Debugger's condacts bright white, the hints white on dark grey, and the
documentation's links and headings light blue.

### ZX-Uno

The ZX-Uno is an FPGA board with many cores; pzx emulates its Spectrum core the way the real one
starts: the boot loader copies its BIOS from the SPI flash and runs it, and the BIOS shows its
boot screen, reads the ROMs from the flash, copies the chosen one into its 512K of SRAM (pages
8-11), sets the machine up through its registers (ports `FC3B` and `FD3B`) and starts it. The
flash is built from `FIRMWARE.ZX1` (the BIOS) and `ROMS.ZX1` (its ROMs, as the BIOS upgrades them
from an SD card: directory and 64 ROM slots), from the zxuno folder or as chosen in Settings >
ROMs (`--zxunofirmware`, `--zxunoroms`; changing them switches the ZX-Uno off and on), with
`esxdos/ESXMMC.BIN` for its DivMMC.

While the boot screen shows, Edit (Shift+1) enters the BIOS setup and Break (Esc) its boot menu,
to start any of its ROMs. Its keys are the Spectrum's: cursors (CAPS + 5/6/7/8), ENTER, Break.
The settings the BIOS saves (active ROM, boot timer, quiet boot, keyboard issue, timing,
contention, DivMMC...) are kept in pzx.ini (`[ZXUno] BiosSettings`) and used from then on;
changes to the ROM list are not kept. Until something is saved, the BIOS shows its boot screen
and starts the first ROM, the 48K. The boot screen lasts about a second and the ROM starts after
about two, as on the real board: the SCANCODE register returns the PS/2 keyboard's power-on
self-test byte (`AA`), without which the BIOS waits five times longer.

**Custom ROM** (Settings > ROMs, `--zxunocustomrom`): a 16K ROM file. If it exists, the BIOS
still runs, but the ROM it chooses is replaced by this one when it starts it, and the machine is
set as a 48K (48K timing, no `7FFD` or `1FFD` paging). Empty or a missing file: the BIOS's
choice. Changing it switches the ZX-Uno off and on.

It always has a DivMMC (with ESXDOS, which the BIOS switches on; as in the core, its firmware is
in SRAM page 12 and its 128K of RAM in pages 16-23, so MASTERMAPPER and the DivMMC see the same
memory), the Timex screen modes, Radastan and ULAplus: in Settings they show on and greyed out
(the values set are kept for the other models), and `--no-divmmc`, `--no-timex`, `--no-radastan`
and `--no-ulaplus` are ignored with `--model zxuno`. Its own registers can switch them off
(DEVCONTROL, DEVCTRL2).

Emulated: MASTERCONF (boot mode, DivMMC, keyboard issue, 48K, 128K or Pentagon timing,
contention, lock: once locked, boot mode can't be entered again), MASTERMAPPER (the SRAM page at
`C000`; as in the core, only in boot mode), the SPI flash (read, status, id, write enable, page
program, sector erase), SCANDBLCTRL (CPU speed 3.5, 7, 14 or 28 MHz), RASTERLINE and RASTERCTRL
(the raster interrupt at the end of the line before the chosen one, which can replace the ULA's
frame interrupt, as Maluva uses it), DEVCONTROL (AY, `7FFD` and `1FFD` paging, ROM selection),
DEVCTRL2 (Timex, ULAplus, Radastan), RADASCTRL and COREID; +2A paging (`7FFD`, `1FFD`; with
`1FFD` paging off, `7FFD` is decoded with fewer address lines, as the core does). Not emulated:
the PS/2 keyboard registers, apart from the self-test byte above (the BIOS reads the Spectrum
keyboard), the Timex MMU, DMA, Prism mode and the UART.

Opening a tape waits for the BIOS and ESXDOS and types `LOAD ""`: at once in 48K mode; with a
128K menu, from its 48 BASIC (the fourth entry). Note that on 128K ROMs ESXDOS pages the 48K BASIC
in after booting (as on a 128K with a DivMMC).

Which ROM is started matters: for a 48K ROM the BIOS switches 128K paging (port `7FFD`) off
through DEVCONTROL, as on the real board, so programs that page memory or switch screens (such
as the Radastan video player `.playrmov`) need a 128K ROM: choose one in the boot menu (Break) or
make it the default in the BIOS setup (Edit).

Hard reset (F6) switches the ZX-Uno off and on (BIOS again); Reset (Shift+F6) restarts the ROM
the BIOS chose. File > Save snapshot saves a .pzs (see [pzx snapshots](#pzx-snapshots-pzs)): .sna
and .z80 can't hold its SRAM and registers.

### Video modes

Settings > Miscellaneous can add these to any model (they are off by default):

| Mode | Description |
|---|---|
| ULAplus | a palette of 64 colours (GGGRRRBB) at ports `BF3B` (register) and `FF3B` (data): registers 0-63 are the palette, register 64 (bit 0) switches it on. Then FLASH and BRIGHT choose one of four 16-colour palettes (8 inks and 8 papers each), there is no flashing, and the border takes the paper colour of the first. |
| Timex | the screen modes of the Timex computers, at port `FF` (reading port `FF` then gives this register instead of the floating bus): bits 0-2 = 1 the second screen (at `6000`), 2 hi-colour (an attribute for every 8x1 cell, at `6000` laid out like the bitmap), 6 hi-res (512x192, columns taken in turn from `4000` and `6000`; bits 3-5 the ink, the paper is its complement, and the border is the paper); bit 6 stops the interrupts. |
| Radastan | the ZX-Uno's 128x96 mode with 16 colours: 4 bits per pixel, 64 bytes per line from `4000` (`6000` with the Timex second screen), colours from ULAplus entries 0-15 (the border too, by its number). Switched on by writing 3 to ULAplus register 64 (`OUT 48955,64: OUT 65339,3`), or to the ZX-Uno register 40h (ports `FC3B` and `FD3B`). |
| Scanlines | with the window at 2x or more, the lower rows of every Spectrum line are drawn darker, as on a TV. |

The picture is kept at twice the width, so the 512-pixel hi-res is shown in full from 2x (at 1x
every other column) and in PNG screenshots at 2x.

### ZX Spectrum Next

The ZX Spectrum Next (`--model zxnext`) is emulated as hardware: the Z80N CPU (its extra
instructions, at 3.5, 7, 14 or 28 MHz), the Next registers (ports `243B` and `253B`), 2 MB of
memory through its MMU (eight 8K slots, NR `50`-`57`, and the 128K/+3 paging ports), its DivMMC
with the SD card, its video (ULA, ULANext, Timex modes, LoRes, Layer 2 at 256x192, 320x256 and
640x256, 128 sprites, the tilemap, palettes, clip windows, layer priorities and the copper), the
zxnDMA (port `6B`), the line interrupt, three AY chips and the DACs (Specdrum and Covox), the
Multiface and the keyboard's extra keys. Its software, the
firmware and NextZXOS with its ROMs, BASIC and programs, comes from its official distribution,
which is not included (it has its own licence): download the latest one from
[https://www.specnext.com/latestdistro/](https://www.specnext.com/latestdistro/) and unpack it
into the `specnext` folder next to the program (it must have `machines/next` in it), or choose
another folder in Settings > ROMs (`--nextdir`). When pzx is installed from a .deb or .rpm, the
folder is `~/.config/pzx/specnext` (the one next to the program can't be written).

Choosing the Next without the distribution (or SD > New SD card with the Next distribution)
starts a few steps, in one window that takes the interface's look: first whether to install it; then the
download page (a link that opens in the browser: in "Full distribution downloads" the lightweight
one is enough); then, with Next, the .zip file downloaded is chosen and unpacked into the folder
(a distribution inside one folder of the zip is moved up) and checked. If it isn't a
distribution, what was unpacked is deleted and it ends there; if it is, the Next starts at once
(its SD card made with the usual size, without asking). Closing the window or Escape stops it at
any step: the machine stays as it was, or with `--model zxnext` pzx closes.

**SD card.** The first time the Next is used, pzx makes its SD card, `zxnext.img` next to pzx.ini
(Settings > ROMs, `--nextcard`), asking its size first (FAT16: the sizes the distribution fits in
with room to spare, up to 2 GB; 512 MB proposed; Cancel leaves the machine as it was), with the
whole distribution (long file names included) and a `config.ini` for it (a few seconds). The card is the Next's own: the other models
keep theirs, and what NextZXOS saves on it is kept (pzx saves it when leaving the Next and when it
closes, without asking). When a newer distribution is unpacked, pzx asks whether to make a new
card from it; the old one is kept, renamed as `zxnext-YYYYMMDD-HHMM.img`. SD > New SD card with
the Next distribution makes another one.

Cards used with older versions of pzx may have files that NextZXOS or the firmware rewrote left
empty (pzx didn't answer the card's status request, CMD13, so every write after the first block
failed): an empty `machines/next/config.ini` makes the firmware show its video test card at every
start. When the Next's card is put in, pzx mends them: each empty file that isn't empty in the
distribution is copied from it again, and an empty `config.ini` gets the default one; a message
lists what was mended.

**Extra cores.** The firmware's extra cores menu (C while it starts) works with an emulated 16 MB
flash (in memory only, empty at every start of pzx): cores can be installed into slots 8-31, but
pzx emulates only the Next's own core, so starting another machine's (the Sinclair QL...) says so
and starts the Next again.

**Starting.** By default (Settings > ROMs > "Start through its firmware", `--nextfirmware`) the
Next starts as the real one: its boot ROM (`roms/tbblue_loader.rom`) loads the firmware
(`TBBLUE.FW`) from the card, which shows its boot screen with the TBBlue logo (pzx says it is an
emulator, machine ID `08`) and starts NextZXOS. Unchecked (`--no-nextfirmware`), NextZXOS starts
directly from the distribution's ROMs, as if the firmware had chosen it. Hard reset (F6) starts
it all again; Reset (Shift+F6) is the Next's soft reset.

**.nex files** (File > Open, or the command line) switch to the Next if needed and are loaded
into its memory and started, as NextZXOS's `.nexload` does (versions 1.0 to 1.3: loading screens
of every kind, palette, the copper code, which starts at once, and the registers as the header
asks). A program that asks for its own file (to read more data from it) gets a handle that the
esxDOS calls F_READ, F_SEEK, F_FGETPOS, F_FSTAT and F_CLOSE read from the .nex; for
DISK_FILEMAP, which programs use to stream data straight from the card, the file is also copied
onto the Next's SD card as `/TMP/PZXNEX.NEX` (replaced each time). Tapes are only inserted (load
them from NextZXOS's browser or with `LOAD ""`), and .sna, .z80 and .dsk files switch to their
own model. File > Save snapshot saves a .pzs (see [pzx snapshots](#pzx-snapshots-pzs)).

**Sound.** Three AY chips (TurboSound Next: port `FFFD` chooses one with `FF`, `FE` or `FD`, its
bits 6 and 5 switching that chip's left and right outputs), each ABC or ACB stereo (NR `08` bit
5) or mono (NR `09` bits 5-7), with the four 8-bit DACs.

**Keys.** The keys that are two Spectrum keys at once (cursors, DELETE, EDIT, BREAK, EXTEND MODE,
CAPS LOCK, TRUE and INV. VIDEO, GRAPHICS and `;` `"` `,` `.`, see [Keyboard](#2-keyboard)) are
the Next's extra keys, read in NR `B0` and `B1`.

**NMI buttons and the Multiface.** NMI (F5) is the Next's M1 button: NextZXOS's Multiface menu
(Snapshot, Screenshot, TAP files, POKEs, Debug tools, Settings, Keymap...), from
`enNextMf.rom` in the distribution. Machine > DRIVE button (Shift+F5) is the DivMMC's NMI. Each
works when NextZXOS lets it (NR `06` bits 3 and 4; NextZXOS turns the DRIVE button off by
default), as on the real machine; NR `02` makes them by software. The Multiface (its four types,
NR `0A`, the +3 one by default) pages its 8K ROM and 8K RAM in over everything else at `0066`
until RETN or its ports page it out; the NMI may be stackless (NR `C0` bit 3, as NextZXOS uses
it: RETN then returns to the address in NR `C2`-`C3`; RETI, which interrupt handlers use, still
returns to the one on the stack).

**Copper.** It runs on its own clock (four steps a T-state, two for a MOVE), and WAIT holds it
until its line and horizontal position (in 8-pixel steps) come, counted from the first line of
the picture moved by NR `64`. A register written while the beam is in a line, by the copper or
the CPU, changes the rest of that line only: what has been drawn stays.

**Debugger.** The disassembly, the instruction help and the assembler export know the Z80N
instructions (the export adds `OPT --zxnext` for sjasmplus), and Next Regs (the chip button)
shows and edits its registers.

### pzx snapshots (.pzs)

.z80 and .sna snapshots can't hold the ZX Spectrum Next or the ZX-Uno, so pzx has its own
format: File > Save snapshot (F3) saves a `.pzs` on those two machines, and on the others it is
a choice in the dialog's file types (.z80 stays the default, then .sna and .pzs; the name's
extension, or else the type chosen, decides). Opening one (File > Open, the command line or
dropping it on the window) switches to its machine and carries on where it was saved. It holds
the whole machine: the CPU, all the memory (the 128K models' eight banks; the ZX-Uno's 512K of
SRAM; the Next's 2 MB with its ROMs, Multiface and DivMMC memory), the registers and ports, the
display (ULAplus, Timex modes; the Next's palettes, sprites, copper, Layer 2), the Next's DMA,
the AY chips, the DivMMC's paging and RAM and the Currah µSpeech's ROM paging. It doesn't hold
the SD card (the Next keeps its own card; on the others the card in use stays), +3 disks, tapes
or the ZX-Uno's flash (made again from its BIOS and ROMs files). The file is `PZXSNAP`, a
version byte (1), the machine's `--model` name (a length byte and the name: `48k`, `zxnext`...),
then the machine compressed with zlib in the order of `SnapIO` in `src/PzxSnap.inc`.

## 5. Tape browser

Tape > Tape browser (F7) lists the blocks of the tape, of any TZX kind (turbo data, tones,
pulses, recordings, pauses, groups, loops, texts, archive info...), with the size and checksum of
those with data (its window title shows the full path of the .tap or .tzx file, and "(modified)" if it has changes to save; a path too long for the title bar is
cut at its start, "...\games\jsw.tap", so the file name always shows, as in the disk and SD card
browsers): the current one is marked with `*` (`>`
while playing) and highlighted (green while playing, yellow when stopped), and the status bar
says where the tape is ("Playing block 3 of 10", "At the end of the tape"). Play at the end of
the tape starts it again from the first block. The toolbar buttons (hover for a hint) play, stop,
rewind, play from the selected block (or double-click it), move the selected block up or down,
delete it (or press Del) and save the tape as a new .tap. At the bottom, choose fast loading or
real-time loading: the same setting as Tape > Fast loading.

Right-click a block with data and choose "Export block as binary..." to save the block's data (without the
flag byte and the checksum) to a file, by default named `blockN.bin`, where N is the block's
position in the tape (`block1.bin`, `block18.bin`).

### TZX tapes

.tzx files (TZX up to version 1.20) open like .tap ones and play exactly as their blocks say:
standard and turbo data (their own pilot, sync and bit lengths), pure tones, pulse sequences,
pure data, direct recordings, CSW recordings (RLE and Z-RLE) and generalized data; pauses and
"stop the tape" (Play goes on after it); groups, jumps, loops, call sequences, "stop the tape on
a 48K" (on the 16K and 48K only) and the signal level; texts, messages, archive info, hardware
type and custom info are shown in the tape browser. Old blocks of earlier versions, and unknown
ones, are skipped; a file cut short keeps the blocks it has.

Fast loading takes at once the blocks the ROM's loader can read (standard data, and turbo or
pure data with the ROM's bit lengths). Anything else (turbo loaders, recordings...) plays in real
time, as on a real cassette: after a block loaded at once, if what comes next is a signal the
ROM can't read, the tape goes on playing by itself for the game's own loader.

Tapes are saved as .tap (Save tape as, and in the tape browser), which keeps only the data
blocks: with blocks from a .tzx that a .tap can't keep, pzx asks first.

## 6. Disk browser

Floppy > Disk browser, or the 3" disk button on the toolbar, lists the files on a disk (its
window title shows the drive and the full path of the disk image). Both are
only available when there is a disk to browse: in drive A:, or in drive B: if it is connected.
The browser opens on A: if it has a disk and on B: otherwise; the drive list at the top left
offers the drives that have a disk (and switches by itself if a disk is ejected). It shows them
as +3DOS sees them: name, type (Program, Bytes, Number array, Character array, or "(no header)"
for files without a +3DOS header), start address of Bytes or autostart line of a Program,
length, size on the disk and attributes (read-only, system, user area). The status bar shows how
much space is free.

The toolbar buttons (hover for a hint):

| Button | Action |
|---|---|
| Refresh | read the directory again (it also refreshes by itself when the emulated +3 writes to the disk or the disk changes). |
| Import | copies files from the PC onto the disk (several can be chosen at once). A file that already has a +3DOS header is copied as it is; for any other file you choose its name and either a Bytes (CODE) header with its load address (16384 is suggested for screens, 32768 otherwise) or no header at all (the header is ticked by default here). With several files, "The same for the other files" applies those choices to the rest, with their own names. If a file with that name is already on the disk, pzx asks whether to overwrite it (Yes to all with several files). |
| Import a folder | (a folder with a blue arrow) copies a folder of the PC with its contents onto the disk. A +3 disk has no folders, so all the files inside the folder and its subfolders are imported side by side. The usual questions (name, +3DOS header, overwrite) are asked, with "for all" to apply the choice to the rest; a progress bar shows meanwhile. |
| Export | saves the selected files to the PC (also with a double-click): one with a save dialog, several into a folder you choose, asking before overwriting a file there. If they have a +3DOS header you can keep it or save only the data (a .bin, a screen...). |
| Rename | (F2) gives the selected file a new name (8 characters and an optional extension of 3). |
| Delete | (Del) removes the selected files and frees their space. |

Files and folders can also be dragged from the PC's file manager and dropped on the disk browser
window: they are imported as with Import and Import a folder (the files inside dropped folders
side by side).

Select several files with Ctrl or Shift + click. The import and export dialogs open in the
folder the disk browser used last (the SD card browser remembers its own); it is kept in
pzx.ini.

Changes are made on the disk image in memory and mark it as modified; save it with Floppy > Save
disk (into its file) or Save disk as, or answer yes when pzx asks on exit or before the disk is
ejected or replaced. The disk browser understands the standard +3 format and the formats
described by a disk specification (and the CPC system and data formats). A program running on
the +3 that is using the disk at that moment may not notice changes until it reads the directory
again.

## 7. DivMMC and SD cards

pzx emulates the DivMMC interface: 8K of EEPROM with its firmware, 128K of RAM and an SD card,
with automatic paging (at `0000`, `0008`, `0038`, `0066`, `04C6`, `0562` and `3Dxx`, and back at
`1FF8`-`1FFF`) and ports `E3` (control), `E7` (card select) and `EB` (SPI data). It works on
every model. The firmware is esxDOS 0.8.9 (`esxdos/ESXMMC.BIN`, from
[http://www.esxdos.org](http://www.esxdos.org)); another one can be chosen in Settings > ROMs.
The interface is connected in Settings > Hardware.

The SD menu:

| Entry | What it does |
|---|---|
| SD card browser | see below (also the SD card toolbar button); only available with a card inserted. |
| Insert recent SD card | one of the last 8 card images used. |
| Use a PC folder as SD card | the card in the DivMMC is ejected (asking to save it if it was changed) and a temporary card is made with esxDOS (SYS, BIN, TMP) and the folder's files and subfolders in its root, their names turned into 8.3 names (two that would clash become `NAME~1`, `NAME~2`...). The machine then boots with it. The card lives in the temporary folder and is deleted when it is replaced, ejected or pzx closes; if it was changed, pzx offers to save it as an image file. The PC folder itself is never changed. |
| Insert SD card image | any raw card image (.img, .mmc, .hdf...). Inserting the one already in is refused. |
| New SD card | an empty card of 16 MB to 2 GB, with one FAT16 partition. |
| New SD card with ESXDOS | the same, with the esxDOS SYS, BIN and TMP folders already copied: ready to boot. |
| New SD card with the Next distribution | a card of the size chosen (as for the Next's own card) with the whole ZX Spectrum Next distribution and a `config.ini` (see [ZX Spectrum Next](#zx-spectrum-next)). |
| Save SD card | saves the changes into the image file it was loaded from. |
| Save SD card as | saves the card, with its changes, as another image file (the dialog starts in the folder it was loaded from); that file is then the card. |
| Eject SD card | |

What the Spectrum writes on the card, and what the SD card browser changes, is kept in memory
(only the 512-byte blocks that changed) until the card is saved: the image file stays as it was.
pzx asks whether to save a modified card when it closes, and before the card is ejected or
replaced. Inserting or creating a card connects the DivMMC if it isn't. The card in use is
remembered for the next session. With the DivMMC on, the machine boots through esxDOS (about 5
seconds), and tapes and disks opened with File > Open wait for it. On the 128K models esxDOS
starts in 48K BASIC; its `.128` command goes back to the 128K menu. The NMI button (F5) opens the
esxDOS browser. Use `.ls`, `.cd`, `LOAD *"name"`, `SAVE *"name"` and the other esxDOS commands as
on the real interface.

### SD card browser

Shows the files and folders of the card (FAT12, FAT16 or FAT32, with or without a partition
table; the window title shows the full path of the card image): name (the long name if it has one; folders have a folder icon), size, for files with a +3DOS header (as esxDOS saves
BASIC) their type, start address or autostart line and length, date, attributes and 8.3 name.
Double-click a folder to enter it (".." or the Up button to go back) and a file to export it. The
toolbar: Up, Refresh, New folder, Import (from the PC, several files at once, with an optional
Bytes header as in the disk browser, unticked by default here), Import a folder (a folder with a
blue arrow: a folder of the PC with its contents), Export (several files at once, with or without
the +3DOS header), Rename (F2) and Delete (Del; files, and folders with all the files and
folders in them, after asking). Importing or exporting a file that already exists asks whether
to overwrite it. The import and export dialogs open in the folder this browser used last. New
names are 8.3, as esxDOS uses them, except on the ZX Spectrum Next's card, where imported files
and folders keep their PC names (NextZXOS reads long names); renaming a file drops its long
name. esxDOS keeps some things in memory, so after changing the card from the browser
it may not notice the changes until it reads that folder again (or after a reset).

Files and folders can also be dragged from the PC's file manager and dropped on the SD card
browser window. Imported folders are recreated inside the folder the browser shows (with 8.3
names made from the PC names, or the PC names themselves on the Next's card), merging with
folders already on the card, and the files in them are copied as they are, without asking (no
+3DOS header). Files imported on their own ask the usual questions (name, +3DOS header), with
"for all" to apply the choice to the rest; overwriting a file is always asked. While several
files are imported a progress bar shows, and pzx can't be used until it is over.

## 8. POKEs

Machine > POKE (F9) takes "address,value" pairs separated by ":", in decimal or in hex with
$, e.g. `35899,0 : 36000,201`. The last 20 POKEs are listed with the name of the file they were
used with (click one to use it, double-click to apply it). POKEs to ROM have no effect unless the
settings allow changing the ROM.

## 9. Sound

The beeper and the AY-3-8912 (128K and later) are mixed in ABC stereo. Settings > Hardware turns
TurboSound on, and can add an AY chip to the 16K/48K, at the same ports as on the 128K (`FFFD`
and `BFFD`), as the AY interfaces for the 48K did. Mute sound (Options menu) silences everything
without changing the speed.

### Currah µSpeech

The Currah µSpeech (MicroSpeech) is a speech synthesizer for the 48K, with a General Instrument
SP0256-AL2 chip that speaks *allophones*, the sounds words are made of. It is connected in
Settings > Hardware (or `--currah`, ini key `currah` in `[Hardware]`), which switches the machine
off and on; its ROM then shows "Speech System (c) CURRAH 1983" at the top of the screen. It needs
`currah.rom` (its 2K ROM) and `sp0256-al2.rom` (the chip's 2K mask ROM) in the ROM folder; both
come with pzx.

From BASIC (as its manual explains):

- **Key voices:** after the first ENTER (after switching on, NEW or an error report), every key
  is spoken as it is typed (`LET` says "let"). `LET keys=0` switches them off and `LET keys=1` on
  again.
- **Speech:** `LET s$="he(ll)(oo)"` says "hello". Single letters are phonetic sounds and two or
  three letters in brackets are other allophones: `(aa)` or `(ay)`, `(ee)`, `(ii)`, `(oo)`, the
  strong `(bb)`, `(dd)`, `(gg)`, `(ggg)`, `(hh)`, `(ll)`, `(nn)`, `(rr)`, `(tt)`, `(yy)`, and
  `(ar)`, `(aer)`, `(ch)`, `(ck)`, `(ear)`, `(eh)`, `(er)`, `(err)`, `(ng)`, `(or)`, `(ou)`,
  `(ouu)`, `(ow)`, `(oy)`, `(sh)`, `(th)`, `(dth)`, `(uh)`, `(wh)`, `(zh)`. An apostrophe, a
  space, a comma and a full stop are pauses, each longer than the last. An allophone with a
  capital letter is said with a higher intonation (in brackets the last letter decides: `(ouU)`
  is intoned up, `(oUu)` isn't). In a program, put `PAUSE 1` after each `LET s$=`. Afterwards
  `PRINT s$` shows it with `*` as its first character if it was spoken, or `?` there and at the
  mistake if it wasn't.

How it works: any access to address `0038` (also the interrupt's) pages its ROM in at
`0000`-`0FFF` or out again; writing `1000` sends an allophone to the chip, and reading it while the
ROM is in gives bit 0 set while the chip is busy; writing `3000` or `3001` sets the intonation
(the chip's clock, 3.05 MHz or about 7% more). The voice is mixed with the rest of the sound. It
is meant for the 16K/48K (on the 128K models, in 48 BASIC). In the debugger, slot 0 shows `SPCH`
while its ROM is paged in.

## 10. Debugger

Debug > Debugger (F12) opens a window and stops the emulation at the current instruction. The
window takes the focus, on the execution line, so F7 and F10 step at once (the Adventure Debugger
does the same). Closing it carries on running. Hovering over a hex value shows it in decimal. The
window has five zones, each with a title: disassembly and registers on top, memory, breakpoints
and watches in the bottom third. The window is made to fit the screen: on a small one the
disassembly and the bottom zones show fewer lines, while the registers zone keeps all of its
lines. The toolbar has run, break, step into, step over, run to cursor, step back, go to address
and add watch; run is greyed out while running and break while stopped.

After a separator, the Z80 button opens a window with the Z80's instruction set as tables, one
per tab: Main (no prefix), CB, ED, DD and FD. Each is 16x16, the opcode's high digit on the left
and the low one on top, with the instruction in each cell (operands as n, nn, d for a
displacement and e for a relative jump); the opcodes a prefix doesn't have are empty, and the
prefixes themselves are greyed. The instructions are in bold, the undocumented ones in dark red. Resting the
mouse on a cell for a second shows what the instruction does, as in the disassembly, and what is
undocumented about it. The window is square, with the letters as big as fit (the operands go on
two lines when that makes them bigger). The box on top (Find instruction) marks, as you type,
every instruction with that text (`LD A`, `IXH`, `(IX+d)`...) in light blue, and the titles of
the tabs that have some; if the table shown has none but another one has, the first such table is
shown. Empty, nothing is marked. Escape closes it.

On the ZX-Uno it also has ZXUno Regs (the chip button): a window, which can stay open, with the
ZX-Uno's registers (number, name, hex value and the names of the bits set), updated while the
machine runs. Select a value, type a new one and press Enter to write it (as an OUT to `FD3B`
with the register selected at `FC3B`). Escape closes it. On the ZX Spectrum Next the same button
is Next Regs, with the Next's registers (written as with `NEXTREG`), the copper, extra keys and
NMI ones among them.

### Disassembly

Resting the mouse on a mnemonic for a second shows what the instruction does: a description with
its operands, what it changes (registers or memory), how it affects the flags and its T-states
without contention ("T-States: 7 or 12" when it takes longer if a condition holds or a block
instruction repeats).

Undocumented instructions (as "The Undocumented Z80 Documented" by Sean Young describes them:
SLL, IXH/IXL/IYH/IYL, the ED duplicates of NEG, RETN and IM, `IN F,(C)` and `OUT (C),0`, ED
opcodes that do nothing, DD/FD prefixes with no effect, DDCB/FDCB that also store the result in a
register...) have their mnemonic in bold dark red, and the hint says what is undocumented about
them.

Search (right-click, or Ctrl+F) asks for a text and finds it in the disassembly (addresses,
bytes, labels and instructions, as shown) from the line after the selected one, round the whole
memory; F3, while the disassembly has the focus, finds the next one.

Labels on the left (20 characters; longer labels are cut, and hovering over a cut one shows it
all), mnemonics in blue, registers in bold. Jumps and memory references show the label, with the
value in grey brackets. The arrow marks the execution point; on a conditional jump, call or
return there, a green tick or red cross says whether it will be taken.

Double-click a line (or press Space) to set or remove an execution breakpoint. Click an
instruction byte to change it. Right-click for: go to address, search, export as assembler, add
(or edit) label, toggle breakpoint, breakpoint type (execution, read, write, read/write), port
breakpoint, breakpoint with condition (opens the same window as adding or editing one in the
breakpoints zone, for that line), enabled, remove.

Keys: cursor keys, Page Up/Down, Home (go to `0000`), End (the end of memory: `FFFF` on the last
line), Backspace (back to where the view was before the last jump: Go to, Home, End...; up to 50
places), Ctrl+G (go to). The disassembly doesn't go round past `FFFF`: an instruction at `FFFE`
or `FFFF` takes its operands from `0000`-`0001`, and nothing follows it.

Add label names the line's address: the name is a user symbol, shown in the disassembly like
those of a .sym file and kept when the code is exported as assembler; an empty name removes it
(Debug > Clear symbols removes them all).

Export as assembler asks for an address and a length and saves that range as a .asm source for
sjasmplus that assembles back to the same bytes: ORG, an instruction per line (its address in a
comment), labels for jump, call and memory targets (the symbol at that address, or `Lxxxx` inside
the range; outside it, defined with EQU) and the symbols at the instructions' addresses.
Encodings an assembler would not produce (unused prefixes, undocumented ED duplicates, DDCB that
also copy to a register) are written as DB, with the instruction in a comment.

Breakpoint lines are red; a switched-off breakpoint is pale pink. The letter on the left is the
type: E execution, R read, W write, A any access. Read and write breakpoints stop before the
instruction that accesses the address, with the execution point (green) on it; instruction
fetches are not reads.

### Registers

AF, HL, DE, BC, IX and IY with the 16-bit word they point to, the alternate set, I, R, SP, PC,
the flags (X = set; resting the mouse on a flag's name for a second explains it), IM, IFF1, IFF2,
DI/EI and HALT. Values changed by the last instruction are dark red (in AF, HL, DE, BC, IX, IY
and the alternate set, only the half that changed: `LD D,0` marks D, not E). Click a value to
edit it; click a flag, IFF1 or IFF2 to toggle it and IM to cycle 0-1-2.

Below: the top 8 stack entries (`>` marks the top), the last 8 port accesses (instruction
address, port, R for a read or W for a write, value; `>` marks the latest; the value is dark red
if the last instruction made the access) and what each 16K slot holds (ROMn, RAMn, or `----` for
no memory on the 16K; DIV for the DivMMC and SPCH for the Currah µSpeech's ROM when they are
paged in). The mouse wheel over the stack or the ports scrolls them (up to 50
entries: the last 50 port accesses are kept); after a step they show the top again. On the 128K
models, click slot 3 (or its arrow) to page another RAM bank in. A slot, or any of the DivMMC and
ZX-Uno values below, that the last instruction changed is dark red (128K/+3 paging, the DivMMC's
MMU and automap, MASTERMAPPER).

With the DivMMC connected, two more lines (the stack and port lists show 6 entries instead of 8)
show its paging: what is at `0000` (EEPROM, or RAM3 with MAPRAM) and the RAM bank at
`2000`-`3FFF`, and whether it is paged in or out; then CONMEM, MAPRAM and automatic paging
(automap). Click the bank (or its arrow) to choose another one, CONMEM to switch it, and automap
to page the DivMMC in or out. MAPRAM can't be switched off, as on the real interface.

On the ZX-Uno the DivMMC lines are always shown, and one more line below them (one stack/port
entry fewer): BOOTM (boot mode, click to switch it), MAPPER (MASTERMAPPER: the SRAM page at
`C000` in boot mode; a drop-down to choose another page; grey when not in boot mode, where it
does nothing) and LOCK. The debugger can change them even when MASTERCONF is locked. Slot 0 shows
BOOT for the boot ROM; RAM numbers are SRAM pages (ROMs are pages 8-11, the DivMMC firmware page
12 and its RAM pages 16-23).

### Memory

Hex and text; bytes outside 32-126 show as a grey ".". The XOR value (the box at the right end of
the zone's title) is applied to every byte shown; what you type is what you see (memory gets it
XORed with the key). Click a hex value to edit it, or a character to type text from there.
Right-click: go to address, add a watch at that byte, read breakpoint, write breakpoint, sprite
mode, Copy, Copy values, Paste, Search, Export text, Import text, Export binary, Import binary.

Search (or Ctrl+F) opens a window to find text (match case or not) or bytes in hex, written with
spaces between them or all together (`3E 01` or `3E01`), as the zone shows them (with the XOR).
It looks from the byte after the selection, round the whole memory, and selects what it finds;
F3, while the memory zone has the focus, finds the next one.

Read breakpoint and Write breakpoint (on the hex values or the text) switch that type on or off
for the byte; if the byte is in the selection, for the whole selection (one breakpoint with a
range); if a breakpoint already covers the byte, for that breakpoint. Bytes with a read or write
breakpoint have a pink background.

In the text column, click and drag (or Shift+click) to select bytes. Copy puts the selection on
the clipboard as text, as the text column shows it (with the XOR, "." for what isn't printable).
Copy values (Ctrl+C) puts the selection on the clipboard as hex values with a $ in front,
separated by commas: `$3E,$01,$CD`. Paste (Ctrl+V) writes the clipboard from the byte
right-clicked (Ctrl+V: from the typing position, or the selection): values separated by commas
(decimal, or $ for hex) are written as they are; any other text as if typed (with the XOR key).
It stops at `FFFF`, and skips ROM as Import does. Escape clears the selection.

Sprite mode (Space, or the context menu) shows the bytes as 8x8 sprites: each box is 8 bytes, one
byte per row of pixels, with the address of each row on the left; hovering over a box shows its
addresses. Space again goes back to hex.

Export text asks for an address and a length (hex; by default what is on screen) and writes a
text file of hex values with $, separated by commas, 16 per line: `$3E,$01,$CD,...` The bytes are
exported as they are in memory, without the XOR.

Import text asks for an address and a length and reads a comma separated text file into memory:
decimal values (0 to 255), or $ and one or two hex digits. It fails if the file has fewer values
than the length, or if any value is not valid; spaces and line breaks don't matter. Bytes that
fall on ROM are not written unless the settings allow changing the ROM.

Export binary asks for an address and a length (by default what is on screen) and saves those
bytes as they are to a binary file (.bin).

Import binary asks for an address (by default the first one shown) and a file, and loads the file
there as it is. It doesn't wrap round: what would go past `FFFF` is not loaded, and a message says
how much. Bytes on ROM are only written if Options > Settings > Miscellaneous allows changing the
ROM; RAM paged at `0000`-`3FFF` (the +2A/+3 all-RAM modes, the DivMMC's RAM at `2000`-`3FFF` when
it is paged in) is written like any RAM, while the DivMMC's EEPROM counts as ROM. Editing bytes,
Import text and POKE follow the same rules.

### Breakpoints

Every breakpoint with its on/off box, type, address, label and condition. Types: Exec
(execution), Read, Write and R/W (memory: any access), and Port R (IN), Port W (OUT) and Port RW
(any). A port up to `FF` matches any high byte (shown as `xxFE`: every ULA port); a longer one,
such as `7FFD`, must match exactly. Port breakpoints stop before the IN or OUT (or INI, OUTI...)
instruction, with the execution point on it.

A line that doesn't fit shows whole as a hint over its box and type (and in the watches, over the
free part of the line). The bevel between the breakpoints and the watches can be dragged to share
the width.

Insert adds one, Delete removes the selected one, Space or a click on the box switches it on or
off, Enter or a double-click edits it (address or port, end address or port, type, condition,
enabled). The editing window includes a short manual of the conditions.

End address makes the breakpoint cover a range of addresses or ports (shown as `8000-80FF`). It
follows the start address while it hasn't been changed by hand; when both are equal it is a
normal breakpoint. A range is a single breakpoint: in the disassembly every line inside it is
red, and toggling, switching off or editing any of them acts on the whole range.

Right-click for the same actions, to show it in the disassembly or to remove them all, and to
save them all to a JSON file or load them from one (loading replaces them); `--breakpoints FILE`
loads one at start.

When any breakpoint stops the emulation, the debugger opens (if it isn't open) with the green
execution point on the instruction where it happened: memory and port breakpoints look at what
the next instruction will access and stop before it runs. A port breakpoint also shows a message
saying which port is read or written and from which instruction. (Accesses made while accepting
an interrupt or by the tape traps are only seen as they happen, so those stop just after.)

### Watches

Addresses whose two bytes are shown (and can be edited). Insert, the add watch toolbar button or
right-click adds one (the address is asked in its own window, written as in Ctrl+G: hex, a
register name or a label; it keeps its own list of the last addresses watched), Delete
removes the selected one. Right-click also saves them to a JSON file or loads them from one
(replacing them); `--watches FILE` loads one at start.

### Breakpoint and watch files

JSON files, with addresses and ports in hex:

```
{"pzx": "breakpoints", "version": 1,
 "memory": [{"address": "8000", "type": "exec", "enabled": true,
             "condition": "A = 3"}],
 "ports":  [{"port": "00FE", "type": "out", "enabled": true,
             "condition": ""}]}
```

(a range adds `"end": "80FF"` after the address or port)
(memory types `exec`, `read`, `write`, `access`; port types `in`, `out`, `any`)

```
{"pzx": "watches", "version": 1, "watches": ["5C3A", "8000"]}
```

```
{"pzx": "daad-breakpoints", "version": 1,
 "breakpoints": [{"address": "8A69", "enabled": true,
                  "condition": "f0 = 3", "condact": "P1 E5  NOUN2 251"}]}
```

(the Adventure Debugger's; `"condact"` only says which one it was)

### Go to and View data

Right-clicking a hex number or a label anywhere in the debugger (an operand, a register, the
stack, a port access, a breakpoint, a watch...) adds two entries to the menu, naming that number
or label: "Go to X" shows that address in the disassembly and "View data at X" in the memory zone.

### Breakpoint conditions

A breakpoint with a condition only stops when it holds. Examples:

| Condition | Meaning |
|---|---|
| `A=3` | A is 3 |
| `BC=289A AND #Z=1` | BC is 289A and the Z flag is set |
| `#Z=0 OR HL>=C000` | Z clear, or HL at C000 or above |
| `NOT (#C=1)` | the carry flag is clear |
| `A = B * 2`, `BC = DE + 1`, `BC = DE + HL` | |
| `A = C & 7` | & is bitwise: A equals the low 3 bits of C |
| `A=@8400` | A equals the byte in memory at 8400 |
| `@(IX+2) = .30` | the byte at IX+2 is 30 (decimal) |
| `HL = SCREEN_START` | a symbol; `#BC` is the symbol called BC |
| `A=0A OR A=0F` | the numbers 10 and 15 |
| `T=5` | the fifth time the breakpoint is reached |
| `T>=2 AND A=0` | from the second time on, when A is 0 |

Numbers are hex: `10` is sixteen, and `FF`, `$FF` and `FFh` are 255. With a dot in front they are
decimal: `.30` is thirty, `.49152` is `C000`.

Registers are case-insensitive: A B C D E H L I R F, IXH IXL IYH IYL, AF BC DE HL IX IY SP PC, the
alternate set as A' F' AF' BC' DE' HL', IFF1, IFF2 (0 or 1) and IM. Flags take a #: `#S #Z #5 #H
#3 #P (#V) #N #C`, and are 0 or 1.

Names: a name is first a register, then a symbol (your symbols, then the labels of the ROM paged
in and the system variables), then a hex number.

- A, B, C, D, E and F on their own are always the registers, never hex digits. To compare with
  those numbers, add a leading 0: `0A 0B 0C 0D 0E 0F`. So `A=0A` means register A holds 10, while
  `A=A` is always true and `D=E` compares two registers. A leading 0 always makes a number: `0BC`,
  `0ADD`, `0CAFE`. Numbers with other digits, like `1A` or `FF`, need nothing.
- A symbol whose name is also a register is reached with #: `BC` is the register, `#BC` the
  symbol called BC. `#name` always means the symbol, and is also how to write names with dots
  (`#main.loop`). The flag names after # (`#Z`, `#C`...) are always the flags.
- Symbols are looked up when the condition is set; loading other symbols later doesn't change it.

`@x` is the byte in memory at address x, as the CPU sees it now: `@8400`, `@HL`, `@(IX+2)`,
`@#COUNTER`, `@(@5C53 + 1)`.

`T` is how many times the breakpoint has been reached, this time included: `T=3` stops only the
third time, `T>=3` every time from the third on, `T=2 AND A=0` the second time only if A is 0.
The count starts again when the condition is changed, and the breakpoints list shows it as
(T=n).

Operators, from lowest to highest priority:

| Operator | Meaning |
|---|---|
| `OR` `XOR` | logical: either is true / only one is true |
| `AND` | logical: both are true |
| `NOT` | logical: is not true |
| `=` `<>` `<` `>` `<=` `>=` | comparisons |
| `+` `-` | add, subtract |
| `\|` | bitwise or (`A \| 80` sets bit 7) |
| `*` `/` `MOD` | multiply, divide, remainder |
| `&` | bitwise and (`C & 7` keeps bits 0 to 2) |
| `-` `@` | negative, byte in memory (in front of a value) |
| `(` `)` | group |

AND, OR, XOR and NOT combine true and false; & and | work on the bits of a value. `A = C & 7`
compares A with the low three bits of C, while `A = C AND 7` would mean "A equals C, and 7 is
true". Comparisons bind tighter than AND/OR, so `A=3 AND E=3` means what it says.

Arithmetic wraps like the Z80's: at 8 bits when both sides are 8-bit values (8-bit registers,
flags, @x, numbers up to FF) and at 16 bits otherwise. With A=0, `A-1` is FF; with DE=FFFF, `DE+1`
is 0; `B*2` stays within 8 bits, while `A+100` (100 is a 16-bit number) does not wrap at FF.

Memory and port breakpoint conditions are checked just before the instruction runs, with the
registers as they are then.

### Keys

F5 run, F7 step into, Shift+F7 step back, F10 step over (CALL, RST, DJNZ, HALT and repeating
block instructions; with the DivMMC connected, RST 8 is followed by an esxDOS function byte, so it
returns to the instruction after that byte), F9 run to the selected line.

Step back (Shift+F7, or its toolbar button) puts the machine back where it was before the last
step into, step over, run to cursor or run: the CPU, all the memory, the paging and the DivMMC
(not the sound, the tape or the disks). It goes back up to 10 times.

Ctrl+PgDn / Ctrl+PgUp move the disassembly and the memory zone 1024 bytes on or back, Shift+PgDn
/ Shift+PgUp 512. Escape closes the debugger (after ending an edit, or the typing or selection in
the memory zone), and the keys go to the main window again, as when it is closed in any other
way. Ctrl+G (or the context menu) goes to an address: hex, a register name such as PC or HL, or
a label; the last 10 addresses are listed. Its "Go to PC" button goes to the execution point
without adding it to the list.

### Labels

The ROM routines and system variables are labelled from the .sym files in the roms folder (48K:
*The Complete Spectrum ROM Disassembly*; 128K, +2 and +3, including the +3DOS entry points: the
ZXSpectrumVault disassemblies; `tools/make-rom-symbols.py` rebuilds them). ROM labels only apply
while that ROM is paged in. Your own symbols, as exported by SjASM / SjASMPlus
(`LABEL: EQU 0x8000`), are loaded with Debug > Load symbols or `--sym` and take precedence:

```
pzx --sym game.sym game.tap
```

### ROM

The ROM can't be changed from the debugger unless Settings > Miscellaneous allows it. Changes
last until the model or its ROMs are loaded again.

## 11. Adventure Debugger

The Adventure Debugger follows a text adventure condact by condact, in a window of its own. It
supports three engines: DAAD, the engine of many text adventures; PAW (the Professional Adventure
Writing System), its predecessor; and The Quill, PAW's predecessor. Open it with Debug >
Adventure Debugger (F11). The engine of the game in memory (DAAD, PAW or Quill) is shown at the
right end of the process zone's title. The game must be in memory: its database (DDB version 2
or 3, as written by DC 2.0 or later and DRC; La Diosa de Cozumel and later), usually at `8400` but
looked for anywhere, with any of the 48K and 128K interpreters, English or Spanish. The status
bar says where it is. (On the 128K, the interpreter's interrupt table overwrites the version byte
at `8400`: the version is then told from the condacts used.)

PAW games (48K, and the 128K ones on a 128K model) are found by the database the interpreter
points at from the top of memory. PAW works like DAAD, with these differences: process 0 is the
response table (shown as "0 (responses)"), there is no indirection (@), and its condacts are
PAW's: some have DAAD names but other numbers or parameters (DESC and PARSE take none, 18 is
INVEN...). "Stop after player input" stops at the first condact run once PAW starts the response
table with the player's order. Texts using characters the game redefines (accented letters, for
instance) show the character the game replaced.

Quill games (Spectrum, versions A and C of its database) are found by the database at its fixed
address. The Quill works much like PAW (its condacts are shown with PAW's names), with these
differences: there are two tables, the event table (the responses, shown as "0 (events)") and the
status table (run every turn, "1 (status)"); each entry has its conditions and then its actions;
there are 33 flags, then the words of the order (33 and 34) and the player's location (35), and
the object locations follow them; words have 4 letters and no type. The Quill wraps words at 32
columns, and its texts often lack the space where a line broke: the debugger puts one there.
Opening it stops the game at the next condact run (if the game is waiting for a command, when it
gets one); closing it carries on running, like Run.

It learns the interpreter as the game runs: the database says where every entry and condact of
every process is, and the first entries run tell which instructions of the interpreter take an
entry and fetch a condact. Other code reading the database (the 128K interpreter moves data
around) is not taken for the game running.

### Process

The entries of a process (their number in the process, the first being 1, verb and noun, then
their condacts with the parameters in decimal; @ marks a flag holding the value). The green arrow marks the condact about
to run, and the process shown follows it; the box in the title shows another process. The texts
of MES, MESSAGE, SYSMESS and DESC are shown in grey. Condacts shared by several entries (DRC does
that) are shown in the entry being run.

Click a condact to select it; double-click it (or press Space) to set or remove a breakpoint on
it. Right-click for: search, toggle breakpoint, breakpoint with condition, enabled, remove.

Search (or Ctrl+F) asks for a text and finds it in the process shown: the entries' words, the
condacts and the texts they print (MES, MESSAGE, SYSMESS, DESC), from the line after the selected
one, round the process; F3, while the process has the focus, finds the next one. Breakpoint lines
are red, pale pink when switched off; a "?" on the left means it has a condition.

On the current condact, a condition shows on the right whether it holds with the flags and
objects as they are: a green tick or a red cross (as in the Z80 debugger). Conditions that depend
on something else (CHANCE, PICTURE, ISDONE, ISNDONE, INKEY, QUIT, PARSE) show an orange "?".

Resting the mouse on a condact's name for a second shows what it does (in a PAW game, what it
does in PAW).

### Breakpoints

Under the process: every breakpoint with its on/off box, the condact's address, process, entry
and text, and its condition. The game stops when the interpreter is about to run that condact
(and its condition holds). Insert adds one on the condact selected in the process, Delete removes
the selected one, Space or a click on the box switches it on or off, Enter or a double-click
edits its condition. Right-click for the same, to show it in the process or to remove them all,
and to save them all to a JSON file or load them from one (loading replaces them; see
[Breakpoint and watch files](#breakpoint-and-watch-files) in [Debugger](#10-debugger));
`--daadbreakpoints FILE` loads one at start. Breakpoints act while the Adventure Debugger is open.

### Breakpoint conditions

Conditions are on flags only:

| Condition | Meaning |
|---|---|
| `f0 = 3 AND f10>11` | flag 0 is 3 and flag 10 is over 11 |
| `f33 = 20 OR @f51 > 3` | the verb is 20, or the flag whose number is in flag 51 is over 3 |
| `NOT f38 = 1` | not at location 1 |

`fN` is flag N (0-255) and `@fN` the flag whose number is in flag N. Numbers are decimal.
Comparisons: `=` (or `==`), `<>` (or `!=`), `<`, `>`, `<=`, `>=`; they are joined with AND and OR
(AND first) and negated with NOT; parentheses group. Upper or lower case, spaces as you like. An
empty condition means always.

### Flags

(the zone's title)

The 256 flags (37 in The Quill): number, value and, after @, the value of the flag it points at
("001 007 @ 090": flag 1 is 7 and flag 7 is 90), with the names of the system flags (DAAD's, also
for PAW games, but for fDarkF: PAW's flag 28 is free for the game; The Quill's own). Click a value
to change it (0-255, decimal; Enter changes it, Escape or clicking elsewhere leaves it); the one
after @ changes the flag pointed at.

Flags holding a word of the vocabulary (fVerb 33, fNoun 34, fAdject1 35, fAdverb 36, fPrep 43,
fNoun2 44, fAdject2 45, fCPronounNoun 46, fCPronounAdject 47) show the word and its synonyms when
the mouse is over their value, and changing them offers the words of that kind to choose from
(verbs include the nouns up to 39), besides typing the number; 255 is no word. The flags (and the
objects) are found from the first stop, and are updated while the game runs. They are shown in as
many columns as fit (down each column, then the next): the flags and objects take 60% of the
window's width until the splitter is moved. After a step (F7), the values the condact changed are
red (flags and object locations).

### Objects location

(the zone's title)

Every object's location, with "carried" (254), "worn" (253) or "not created" (252), and its
description. Click a location to change it.

### Keys and toolbar

F5 run, Break (stop at the next condact), F7 step (run one condact), F10 step over: on a PROCESS,
run until it returns (the next condact of this process); on any other condact, the same as a
step. When it stops (a breakpoint, a step...) the process zone gets the focus, so F7 and F10 act
at once. Escape closes the window, and the keys go to the main window again. The Z80 debugger can
be open at the same time and shows where the interpreter is.

"Stop after player input" (on the toolbar): while on, the game stops at the condact after each
PARSE that reads an order, typed by the player or left in the input buffer (as in "GET LAMP AND
GO NORTH"), so each order can be followed from where the game starts dealing with it. It goes on
working with the window closed: the window opens again when it stops (breakpoints only act while
it is open).

Export process (the floppy button) saves the process shown, and Export game (the disk button) the
whole game, as source code: DSF (DAAD Ready's DRC) or SCE (the original DAAD compiler), as the
file's extension says (.sce, else DSF; with no extension, the type chosen in the dialog). The game
is named after the last game file loaded: the tape, disk or snapshot opened, or the
.TAP/.TZX/.Z80/.SNA/.DSK that esxDOS opened from the SD card (`COZUMEL.TAP`: `COZUMEL.dsf`). The
source has the vocabulary, the system and user messages, the object and location texts, the
connections, the objects and every process, as unDRC and unDAAD write them; compiled again it
gives the same database, with these exceptions: XMES texts are in the XMB file, not in memory,
and are left as markers; PAUSE and BEEP durations are the database's (DRC scales them for each
target); a v3 database needs DRF's `-v3` option (the DSF says so). The DSF file is ISO-8859-1 and
the SCE code page 437.

A PAW game is exported as it is to an SCE (PAW condacts, no object attributes). To a DSF, pzx asks
whether to export it as a PAW game (the same) or to convert it to DAAD, as PAWS2DAAD does: DESC
becomes RESTART, INVEN the SYSMESS/LISTAT entry, SAVE, LOAD and PARSE get their 0, PROMPT becomes
LET fPrompt, TIMEOUT HASAT TIMEOUT, and condacts DAAD lacks (TURNS, SCORE, CHARSET, MODE, GRAPHIC,
LINE, PROTECT), those after a terminator and the words of the entries of PAW processes 1 and 2
are left as "PAWS2DAAD note" comments. The processes are arranged as in DAAD Ready's empty
database, whose definitions and processes 0, 1, 2 and 6 are added: the response table becomes
process 5, PAW processes 1 and 2 become 3 and 4, processes 3 to 6 go after the last one and the
rest keep their numbers (PROCESS calls are renumbered too). The system messages DAAD has and PAW
lacks come from the empty database, and process 1 gets the entry for PAW's auto-decrement flags
as a comment (remove its semicolons if the game needs them). After converting, pzx reminds you
that the source needs checking by hand: PAW's flags and fonts are not DAAD's.

A Quill game can only be exported as a DSF, converted to DAAD in the same way (there is no SCE
export): the event table becomes process 5 and the status table process 4 (which DAAD's process 1
runs every turn before the order, as The Quill does). Its words get a type: those up to 39 are
nouns (DAAD lets them act as verbs, as directions do), the others verbs or nouns as the game uses
them, and those used both ways become nouns renumbered up to 39 while there are free numbers (if
not, the entries that can't use them are left as comments); a comment reminds that The Quill's
words have 4 letters and DAAD's 5, so they may need lengthening. Objects weigh 1, and those whose
word is 200 or more (The Quill's wearable ones) are wearable; the source says how many objects
can be carried.

## 12. Command line

```
pzx [options] [file]
```

A file (.tap, .tzx, .sna, .z80, .dsk, .nex or .pzs) is opened as with File > Open, so a tape or disk is loaded
automatically. Options start with `-` or `--` and take their value as the next argument or after
"=" (`--model=128k`). Options are applied in this order whatever their position: machine, files,
symbols, breakpoints, typed keys.

| Option | Description |
|---|---|
| `--model M` | machine: `16k`, `48k`, `128k`, `plus2`, `plus2b`, `plus3`, `zxuno`, `zxnext` (also `+2`, `+2b`, `+3`) |
| `--speed N` | CPU speed 1, 2, 4, 8, 16 or 32 (as in Settings > General) |
| `--scale N` | window zoom 1 to 4 |
| `--tape FILE` | insert a .tap or .tzx without starting it (combine with `--keyin`) |
| `--disk FILE` | insert a .dsk in drive A: (switches to the +3 unless `--model` says otherwise); `--diska` is the same |
| `--diskb FILE` | insert a .dsk in drive B: (connects drive B:) |
| `--sym FILE` | load a symbol file (also `-s`); the breakpoints given on the command line can then use its symbols, both as addresses (`--bp MAIN`) and in conditions |
| `--bp ADDR` | execution breakpoint at ADDR: hex or a symbol (`#NAME` forces the symbol) |
| `--bpr ADDR` | memory read breakpoint |
| `--bpw ADDR` | memory write breakpoint |
| `--bprw ADDR` | memory read or write breakpoint (any); also `--bpa` |
| `--bpin PORT` | port read (IN) breakpoint; PORT is hex, up to FF matches any high byte |
| `--bpout PORT` | port write (OUT) breakpoint |
| `--bpio PORT` | port read or write breakpoint (any) |
| `--keyin TEXT` | type TEXT on the Spectrum keyboard once the machine has started. Letters and digits are their keys (so in 48K BASIC keyword mode "J" is LOAD), symbols are typed with SYMBOL SHIFT (" is SYMBOL+P). `~` waits half a second. Escapes: `\n` ENTER, `\w` wait one second. Example: `--keyin 'J""\n'` |
| `--sdcard FILE` | insert an SD card image (connects the DivMMC) |
| `--sdfolder FOLDER` | use a PC folder as the SD card (as SD > Use a PC folder as SD card; connects the DivMMC) |
| `--sdadd "FILE,FOLDER"` | copy a PC file onto that card, into FOLDER (such as `/GAMES` or `/GAMES/ARCADE`; missing folders are created; without ",FOLDER" it goes to the root). The name on the card is the 8.3 form of the file name, and a file with that name is replaced. Repeat it for more files. The machine is then switched off and on so esxDOS sees them. Example: `--sdcard my.img --sdadd "C:\games\jsw.tap,/GAMES"` |

Every breakpoint option takes an optional condition, after "if" or a comma:

```
--bp "8000 if A=3"   --bpw "5C78,A=0"
--bpout "FE if A & 7 = 2"
```

**Settings and the Options menu.** Every setting has an option; what they set is kept in the
settings file like a change made in Settings. On/off options turn the setting on as `--name` and
off as `--no-name` (`--no-fastload`, `--bw`...). In pzx.ini each one is a key with the same name
(see [Settings](#4-settings)):

| Option | Setting | Where |
|---|---|---|
| `--ui classic\|modern` | the interface (see [Interface](#interface)); modern if not given | General |
| `--bw` | black and white display | General |
| `--mute` | mute the sound | General |
| `--volume N` | volume 0 to 100 | General |
| `--scale N`, `--speed N`, `--model M` | (see above) | General |
| `--turbo` | run as fast as possible (this session) | Options menu |
| `--contention` | contended memory and I/O | Miscellaneous |
| `--snow` | ULA snow | Miscellaneous |
| `--romedit` | allow changing the ROM | Miscellaneous |
| `--ulaplus` | ULAplus 64-colour palette | Miscellaneous |
| `--timex` | Timex screen modes | Miscellaneous |
| `--radastan` | Radastan mode (ZX-Uno) | Miscellaneous |
| `--scanlines` | scanlines, from window size 2x | Miscellaneous |
| `--joystick J` | what the cursor keys + Ctrl emulate: `none`, `kempston`, `sinclair1`, `sinclair2`, `cursor` or `fuller` | Miscellaneous |
| `--issue N` | keyboard issue 2 or 3 | Miscellaneous |
| `--shiftkeys S` | `standard` (Shift = CAPS, Ctrl = SYMBOL) or `sides` (left = CAPS, right = SYMBOL) | Miscellaneous |
| `--turbosound` | TurboSound | Hardware |
| `--ay48` | AY chip on the 16K/48K | Hardware |
| `--kmouse` | Kempston mouse | Hardware |
| `--divmmc` | DivMMC interface | Hardware |
| `--currah` | Currah µSpeech | Hardware |
| `--fastload` | fast tape loading | Storage |
| `--autoplay` | start the tape automatically | Storage |
| `--savetotape` | SAVE writes to the tape | Storage |
| `--fastdisk` | fast floppy disk access | Storage |
| `--driveb` | drive B: connected (default: no) | Storage |
| `--floppynoise` | emulate floppy drive noise | Storage |
| `--saveonexit` | save the settings when pzx closes | General |
| `--pngborder` | include the border in PNG screenshots | File menu |
| `--romdir DIR` | the standard ROM folder | ROMs |
| `--rom "MODEL,N,FILE"` | ROM N of a model (0 to 3, as many as the model has), e.g. `--rom "48k,0,C:\roms\mine.rom"`; an empty FILE goes back to the standard ROM | ROMs |
| `--divmmcrom FILE` | the DivMMC firmware; empty = the bundled esxDOS | ROMs |
| `--zxunofirmware FILE` | the ZX-Uno's BIOS; empty = `zxuno/FIRMWARE.ZX1` | ROMs |
| `--zxunoroms FILE` | the ZX-Uno's ROMs; empty = `zxuno/ROMS.ZX1` | ROMs |
| `--breakpoints FILE` | breakpoints saved by the debugger (JSON), instead of any there were | |
| `--watches FILE` | watches saved by the debugger (JSON) | |
| `--daadbreakpoints FILE` | breakpoints saved by the Adventure Debugger (JSON); they act once that debugger is open (F11) | |
| `--zxunocustomrom FILE` | a 16K ROM the ZX-Uno runs (as a 48K) instead of the one its BIOS chooses; empty = none | ROMs |
| `--nextdir DIR` | the ZX Spectrum Next's distribution folder; empty = `specnext` next to the program (or next to pzx.ini, see [ZX Spectrum Next](#zx-spectrum-next)) | ROMs |
| `--nextcard FILE` | the ZX Spectrum Next's SD card image, made from the distribution if it doesn't exist; empty = `zxnext.img` next to pzx.ini | ROMs |
| `--nextfirmware` | the ZX Spectrum Next starts through its firmware (boot screen; on by default); `--no-nextfirmware` starts NextZXOS directly | ROMs |

| Option | Description |
|---|---|
| `--config FILE` | use FILE as the settings file instead of pzx.ini; FILE must exist (pzx stops with an error if it doesn't) and changed settings are saved into it |
| `--config-add FILE` | apply the settings in FILE on top of pzx.ini for this session; they are not written into pzx.ini. If FILE doesn't exist it is ignored, without an error |
| `--help` | show this documentation |

The breakpoint, keyin and file options can be repeated.

Examples:

```
pzx game.tap
pzx --model 128k --tape game.tap --keyin "\n"
pzx --model 48k --tape game.tap --keyin 'J""\n'
pzx --sym game.sym --bp START --bpw "5C78 if A=0" game.z80
pzx --bpout "FE if A=2" --bpin 7FFE game.tap
pzx --config-add bw.ini --scale 3 demo.sna
```

A settings file for `--config-add` only needs the values to change, e.g.:

```
[General]
bw=1
```

## 13. Files

| File | What it is |
|---|---|
| `pzx` / `pzx.exe` | the program (its icon is drawn by `tools/make-icon.py`) |
| `pzx.ini` | settings, next to the program (created when pzx closes; `~/.config/pzx/` when installed from a package) |
| `roms/` | Spectrum ROMs and their .sym label files, the Currah µSpeech's ROMs (`currah.rom`, `sp0256-al2.rom`) and the ZX Spectrum Next's boot ROM (`tbblue_loader.rom`) |
| `specnext/` | empty: unpack the ZX Spectrum Next distribution here (it isn't included, as it has its own licence) |
| `zxnext.img` | the ZX Spectrum Next's SD card, next to pzx.ini, made from the distribution the first time the Next is used |
| `zxuno/` | the ZX-Uno's BIOS (`FIRMWARE.ZX1`) and ROMs (`ROMS.ZX1`) |
| `esxdos/` | esxDOS 0.8.9: `ESXMMC.BIN` (the DivMMC firmware) and the SYS and BIN folders for new SD cards |
| `README.md` | this file |
| `LICENSE` | the license, GNU GPL v3 (Help > License) |

`roms`, `README.md` and `LICENSE` are looked for next to the program and, if not there, in the
folder above it (as when pzx is built inside the src folder of the sources).

Linux packages: after `build.sh`, `package.sh` makes a .deb (with dpkg-deb) and a .rpm (with
rpmbuild: on Debian or Ubuntu, `sudo apt install rpm`) in `build/packages`. Both install the
program and its folders in `/usr/lib/pzx`, a `pzx` command, a desktop entry and the icon; they
need GTK 2 and recommend SDL2 (for sound). The version is the release number. `package.sh` also
makes `pzx-VERSION-windows.zip` with `pzx.exe` (built with lazbuild) and its folders, to unpack
anywhere.

The Spectrum ROMs are copyright Amstrad, who allow their distribution.

The ZX Spectrum Next's boot ROM (`roms/tbblue_loader.rom`, from the ZEsarUX distribution) is
(c) Victor Trucco and Fabio Belavenuto (TBBlue), GPL v3. The Next's distribution (firmware,
NextZXOS, its ROMs and programs) is not included: it has its own licence and is downloaded from
specnext.com.

The Currah µSpeech ROM is (c) Currah 1983. Microchip Technology holds the copyright to the
SP0256-AL2 ROM image and the intellectual property rights to the algorithms and data it contains.
The SP0256 emulation (`src/Currah.pas`) is ported from MAME's sp0256.cpp, copyright Joseph Zbiciak
and Tim Lindner, under the BSD-3-Clause licence: redistribution and use in source and binary
forms, with or without modification, are permitted provided that (1) redistributions of source
code retain the copyright notice, this list of conditions and the following disclaimer, (2)
redistributions in binary form reproduce them in the documentation, and (3) neither the name of
the copyright holder nor the names of its contributors are used to endorse or promote products
derived from it without specific prior written permission. That software is provided by the
copyright holders and contributors "as is" and any express or implied warranties, including the
implied warranties of merchantability and fitness for a particular purpose, are disclaimed; in
no event shall the copyright holder or contributors be liable for any damages arising in any way
out of its use, even if advised of the possibility of such damage.

---

## Building

**Windows:** open `src/pzx.lpi` in Lazarus and build, or run `lazbuild src/pzx.lpi`.
The executable is written next to the project, in `src`, so it builds from any
drive or folder; it finds `roms`, `README.md` and `LICENSE` in its own folder
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
Farrow, Garry Lancaster and others). `roms/tbblue_loader.rom` is the ZX Spectrum
Next's boot ROM (Victor Trucco and Fabio Belavenuto, GPL v3).
