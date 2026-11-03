# ochenta

An emulator of machines from the 80s, written in Free Pascal with Lazarus (LCL).

Emulates the ZX Spectrum 16K, 48K, 128K, +2, +2B and +3 with T-state accurate
Z80 timing, memory and I/O contention, floating bus, ULA snow and per-T-state
video, the Amstrad CPC 464, 664 and 6128 and the SAM Coupé.

Also, emulates Commodore 64, Spectrum Next and ZX-Uno

The full user manual, including every command line option, follows below (it is
also shown by Help > Documentation, F1).

## Contents

- [Features](#features)
- [1. Getting started](#1-getting-started)
- [2. Keyboard](#2-keyboard)
- [3. Menus and toolbar](#3-menus-and-toolbar)
- [4. Settings](#4-settings)
  - [Language](#language)
  - [Interface](#interface)
  - [ZX-Uno](#zx-uno)
  - [Video modes](#video-modes)
  - [Deinterlacing](#deinterlacing)
  - [ZX Spectrum Next](#zx-spectrum-next)
  - [Amstrad CPC](#amstrad-cpc)
  - [SAM Coupé](#sam-coupé)
  - [MSX](#msx)
  - [Commodore 64](#commodore-64)
  - [ochenta snapshots (.e80)](#ochenta-snapshots-e80)
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
- Amstrad CPC 464, 664 and 6128 (see [Amstrad CPC](#amstrad-cpc)): Z80 at 4 MHz held to the Gate Array's
  1 MHz grid, Gate Array (palette, modes 0-3, ROM and RAM banking, the interrupt counter), 6845 CRTC drawn
  as the beam goes, 8255 PPI, AY-3-8912, the keyboard matrix, CDT and TZX tapes in real time (and
  recording to CDT), the 664's and 6128's disc drive on DSK images, the 6128's 128K and .e80 snapshots.
- MSX 2 (see [MSX](#msx)): Z80 at 3.58 MHz, 128K of RAM in a memory mapper, a clock chip and the V9938 (128K of VRAM, a
  512-colour palette, screens 0 to 8, 80-column text, sprites of mode 2, the line interrupt and the VDP commands), the PSG,
  the keyboard matrix and joystick, cartridges (`.rom`) with the Konami, Konami SCC, ASCII8 and ASCII16 mappers,
  tapes (`.cas`) and a disk drive (`.dsk`). The BIOS is not distributed.
- Commodore 64 (PAL; see [Commodore 64](#commodore-64)): the 6510 cycle by cycle (undocumented opcodes included), the VIC-II
  drawn as the beam goes (every mode, bad lines, sprites and their DMA, collisions, the raster interrupt, the 38-column and
  24-row tricks and opened borders), two CIAs, the SID (three voices, envelopes, ring modulation, sync and the filter), the
  keyboard and joysticks, `.tap` tapes in real time, `.prg` programs `.t64` tape containers and `.d64` disks on a real 1541 (its own 6502 running its DOS,
  the serial bus, GCR on the disk, writing included) with a second drive, a 6510 debugger and the Adventure Debugger for the
  DAAD interpreter. The ROMs are not distributed.
- SAM Coupé (see [SAM Coupé](#sam-coupé)): Z80B at 6 MHz, 256K or 512K of RAM paged in 16K pages (LMPR and HMPR), the ASIC's
  four screen modes with its 128-colour palette, line and frame interrupts, the 72-key matrix, the WD1772 disk
  controller on MGT, SAD and DSK images, the SAA1099 sound chip in stereo, tapes in real time (and recording)
  and its Kempston joystick; its ROM is not included.
- Joysticks on the cursor keys + Ctrl: Kempston, Sinclair Interface 2 (1 or
  2), Cursor/Protek or Fuller; Kempston mouse.
- TAP and TZX (1.20) tapes with fast loading or real-time loading, auto-load on open.
- SNA and Z80 (v1/v2/v3) snapshots, load and save; ochenta's own .e80 snapshots of every model (the
  only kind for the ZX Spectrum Next and the ZX-Uno).
- +3 disk drive (uPD765) with standard and extended DSK images, writable.
- Disk browser: list the +3DOS files on a disk (or the SAMDOS ones on a SAM Coupé disk: type, start or autostart line,
  length), rename, delete, and import from / export to the PC.
- DivMMC with esxDOS 0.8.9 (bundled in `esxdos/`, from esxdos.org): SD card
  images, new cards (empty or with esxDOS), and an SD card browser for the FAT
  files (folders, +3DOS details, import/export, rename, delete, new folder).
- Tape browser: play from any block, move and delete blocks, save the tape.
- Menu, settings dialog and a quick toolbar to change model, reset and NMI.
- Pause (F4), turbo (Shift+F11) and CPU speed x2 to x32 (Settings > Common > General):
  the Z80 runs faster but interrupts stay at 50 per second.
- SAVE writes to the inserted tape (or a new blank one, Tape > New blank tape).
- REC button: records the cassette output in real time, decoding standard-speed
  blocks onto the tape (for programs with their own save routines).
- New blank disks for drive A: or B:, already formatted (+3 format, 40
  tracks, 9 sectors). Optional drive B: (Options > Settings). Disk access runs
  at real drive speed unless Floppy > Fast floppy disk access is on.
- Keyboard issue 2 or issue 3 (Settings > ZX Spectrum > Machine), affecting EAR bit 6.
- POKEs (Machine > POKE..., F9): `35899,0 : 36000,201`, with the last 20
  POKEs and the file they were used with.
- Screenshots as .SCR, or PNG at 1x or 2x, with or without the border.
- Monitor: colour, black and white, or green or orange phosphor; contention and ULA snow can be switched off.
- A ROM file of your choice for each ROM of each model; the ROM can only be
  changed from the debugger or with POKE if the settings allow it.
- Settings in `ochenta.ini` next to the program; `--config FILE` uses another
  file, which must exist, and `--config-add FILE` applies extra settings for
  one session (a missing extra file is ignored).
- Command line: model, speed, zoom, tapes, disks, symbols, breakpoints and
  typed keys, e.g. `ochenta --model 48k --tape game.tap --keyin 'J""\n'`.

---

# ochenta - emulator of Z80 machines

ochenta emulates the ZX Spectrum 16K, 48K, 128K, +2, +2B and +3, the ZX-Uno (with its own BIOS
and ROMs), the ZX Spectrum Next (with its official distribution) the Amstrad CPC 464, 664 and 6128 and the SAM Coupé, with T-state accurate Z80 timing, contended memory and I/O, floating bus, ULA snow and
per-T-state video, so games and demos run at their real speed. The screen and the border are
drawn as the beam reaches them, each 8-pixel cell taking its bytes and border colour at the end
of its 4 T-states (as Fuse does), so multicolour and border effects that race the beam show as
on the real machine.

## 1. Getting started

Open a file with File > Open (F2), by dropping it on the window, or from the command line.
Supported files:

| File | What it is |
|---|---|
| `.cdt` | Amstrad CPC tape images (a CDT is a TZX file: see [TZX tapes](#tzx-tapes) and [Amstrad CPC](#amstrad-cpc)). Opening one switches to the CPC 464 if the machine is not a CPC, resets it and loads it (`RUN"`; `|TAPE` first on the 664 and 6128). |
| `.tap`, `.tzx` | tape images (TZX: see [TZX tapes](#tzx-tapes)); a .tzx also loads on a CPC, but a .tap is a Spectrum tape and is refused there. Opening one resets the machine and loads it (`LOAD ""` on the 16K/48K, the Loader menu option on the others; on the ZX-Uno, `LOAD ""` from its menu's 48 BASIC; on the ZX Spectrum Next it is only inserted). |
| `.sna` | snapshots: the Spectrum's (48K and 128K; on the ZX-Uno they switch to the 48K or 128K, as its ROM is the one its BIOS chose) and the Amstrad CPC's (CPCEmu and Winape's, see [Amstrad CPC](#amstrad-cpc): opening one switches to the CPC model it says). |
| `.z80` | snapshots, versions 1, 2 and 3. |
| `.dsk` | disk images (standard and extended), for the +3, for the CPC 664 and 6128 and for the SAM Coupé; a 720K or 360K raw one also for the MSX (see [MSX](#msx)). What a `.dsk` is, is told by what is in it, not by its name: a SAM Coupe disk (80 cylinders of 10 sectors of 512 bytes) can only be used on the SAM Coupe (any other machine says so), and the SAM Coupe takes the +3 and CPC ones too (see [SAM Coupé](#sam-coupé)). Opening one switches to the +3 if needed (to the CPC 6128 if the machine is a CPC 464) and boots it (on a CPC, `RUN"` of the program it chooses, or `|CPM` for a boot disk; see [Amstrad CPC](#amstrad-cpc); on a SAM Coupe, F9 from BASIC: `BOOT`). |
| `.mgt`, `.sad` | SAM Coupe disk images: MGT (raw sectors, 819200 bytes) and SAD (SAm Disk). They only open on the SAM Coupe. |
| `.rom` | MSX cartridges (see [MSX](#msx)). Opening one switches to the MSX if needed and starts it. |

**No autoload with Alt or AltGr.** Holding Alt or AltGr while a disk, tape, program or cartridge is opened (File > Open, the Insert options, the recent lists, drag and drop) inserts it without starting anything, on every machine, even from an option that would normally autoload (an MSX cartridge goes in without restarting the machine).
| `.cas` | MSX tapes (see [MSX](#msx)): they open on the MSX, which Auto load starts with `RUN"CAS:"`. |
| `.nex` | ZX Spectrum Next programs. Opening one switches to the Next if needed and starts it (see [ZX Spectrum Next](#zx-spectrum-next)). |
| `.e80` | ochenta's own snapshots, of any model (see [ochenta snapshots](#ochenta-snapshots-e80)). Opening one switches to its machine. |

The machine model is chosen with the chip button on the toolbar (click it: ZX Spectrum above and Amstrad CPC
below open the list of their machines, and the MSX 2 and then the SAM Coupé, at the end, are chosen directly) or in Options > Settings.
On an Amstrad CPC or a SAM Coupé the Spectrum's extra hardware
(TurboSound, the AY on the 16K/48K, the Kempston mouse, the DivMMC and the Currah µSpeech) is off, and greyed out in Settings.

## 2. Keyboard

| PC key | Spectrum |
|---|---|
| Left Shift | CAPS SHIFT (the left Ctrl instead, if "Make Left Ctrl be CAPS SHIFT instead of Left Shift" is on; see below) |
| Right Shift | SYMBOL SHIFT |
| Ctrl | nothing (fire, if the joystick option below uses it) |
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

CAPS SHIFT is the left Shift by default. Settings > ZX Spectrum > Machine > Controls has "Make Left Ctrl be CAPS SHIFT
instead of Left Shift" (`--zx_leftctrl`, `zx_leftctrl`; off by default): when on, the left Ctrl is CAPS SHIFT, the left
Shift does nothing and only the right Ctrl is the joystick's fire.

The keys that are two Spectrum keys at once (all of the above but Shift and Ctrl, and `,` `.`
`;` `'`) are the extra keys of the ZX Spectrum Next's keyboard: on the Next they also show alone
in its registers `B0` and `B1`, and a program can keep them out of the Spectrum keys (NR `68`
bit 4), as on the real keyboard.

**Amstrad CPC keyboard.** On a CPC model each PC key is the CPC key in the same place (or with the same
label); the CPC's matrix is read by the firmware as on the real machine, so SHIFT, CTRL, CAPS LOCK and the key
combinations of the firmware (CTRL+SHIFT+ESC resets, CTRL+ESC...) work:

| PC key | CPC |
|---|---|
| letters, digits, space, `,` `.` `/` `-` | the same |
| Enter | RETURN |
| Shift (either) | SHIFT |
| Left Ctrl | CONTROL |
| Right Ctrl | CONTROL (or joystick 1 fire, see below) |
| Esc, Tab, Caps Lock | ESC, TAB, CAPS LOCK |
| Backspace, Delete, Insert | DEL, CLR, COPY |
| Cursor keys | the cursor keys (and joystick 1, see below) |
| `=` `;` `'` `` ` `` `[` `]` `\` | `^` `;` `:` `@` `[` `]` `\` |
| keypad 0-9 and `.` | the CPC's numeric keypad: F0-F9 and F. |
| keypad `+` `*` `/` | SHIFT+`;` (+), SHIFT+`:` (*), `/` |

The PC's function keys keep their ochenta meaning. With "Amstrad CPC: cursor keys and right Ctrl as joystick 1"
(Settings > Amstrad CPC, `--cpc_joystick`, on by default) the cursor keys also move joystick 1 (the CPC's keyboard
matrix line 9) and the right Ctrl is its fire button; off, the right Ctrl is CONTROL too. The Spectrum joystick
choice below does not apply to the CPC.

**SAM Coupé keyboard.** On the SAM Coupé each PC key is the SAM key in the same place (or with the same label):

| PC key | SAM Coupé |
|---|---|
| letters, digits, space | the same |
| Enter | RETURN |
| Left Shift | SHIFT |
| Right Shift | SYMBOL |
| Left Ctrl | CTRL (the right one too, or the joystick's fire, see below) |
| Esc, Tab, Caps Lock | ESC, TAB, CAPS |
| Backspace, Delete | DELETE |
| Insert, End | EDIT, INV |
| Cursor keys | the cursor keys (and a Kempston joystick, see below) |
| keypad 0-9 | the SAM's F0-F9 |
| Alt+F1 ... Alt+F10 | the SAM's F1 ... F9 and F0 (the PC's function keys alone are ochenta's; Alt+F4 is the system's) |
| keypad `+` `-` | `+` `-` |

**Commodore 64 keyboard.** On the C64 the letters and the digits are the keys of the same name, the other characters go by the
character the PC's layout gives (as on the SAM Coupé: `"`, `@`, `+`, `*`, `:` ... are typed with the C64's own keys, SHIFT pressed
when it needs it, whatever the PC layout), and the rest:

| PC key | Commodore 64 |
|---|---|
| Enter | RETURN |
| Left Shift, Right Shift | SHIFT (left and right) |
| Left Ctrl | CTRL |
| Tab | the Commodore key (C=) |
| Esc, Pause | RUN/STOP |
| Page Up | RESTORE (an NMI; with RUN/STOP it goes back to the BASIC prompt) |
| Backspace, Delete | INST/DEL (Insert is SHIFT + INST/DEL) |
| Home | HOME (with Shift, CLR) |
| Cursor keys | the cursor keys (the C64 has two: right and down; left and up are SHIFT + them) |
| keypad `+` `-` `*` `/` `.` | the same keys |
| Shift+F1 ... Shift+F8 | the C64's F1 ... F8 (F2, F4, F6 and F8 are the C64's SHIFT + F1, F3, F5 and F7; the PC's function keys alone are ochenta's) |
| keypad 8, 2, 4, 6, 7, 9, 1, 3 and 0, 5; right Ctrl | the joystick (directions, diagonals and fire; see [Commodore 64](#commodore-64)) |

**Punctuation on any keyboard.** Letters, digits and signs are taken by the character the PC keyboard layout gives (not by the key's
place), and the SAM keys that make that character are pressed for it, with the SAM's own SHIFT or SYMBOL as needed: with a Spanish,
English or any other layout `"` `?` `@` `#` `[` `]` `{` `}` `<` `>` `|` `\` `^` `~` `_` `*` `/` and the rest come out as typed (AltGr works for the
characters that need it). Held Shift or Ctrl of the PC don't add their own SHIFT or CTRL to such a character. Ctrl with a letter or a digit
is still the SAM's CTRL with that key.

The matrix is read by the ROM as on the real machine (9 rows of 8 keys, through ports `FE` and `F9`), so holding SHIFT at
power on (which makes the ROM treat the machine as a 256K one) and CTRL combinations work. With "SAM Coupé: cursor keys and right Ctrl as a
joystick" (Settings > SAM Coupé, `--sam_joystick`, on by default) the cursor keys also move a Kempston joystick
(port `1F`) and the right Ctrl is its fire button; off, the right Ctrl is CTRL too. The Spectrum joystick choice
below does not apply to the SAM Coupé. On the SAM Coupé's first screen (the rainbow) the ROM waits for a key; F9 in BASIC
(keypad 9) types `BOOT`.

**Joystick**: Settings > ZX Spectrum > Machine chooses what the cursor keys plus either Ctrl key (fire; only the right
one when the left Ctrl is CAPS SHIFT, see above) emulate: nothing (they work as on the keyboard), a Kempston joystick (port `1F`), a Sinclair
Interface 2 joystick 1 (keys 6-0) or joystick 2 (keys 1-5), a Cursor/Protek/AGF joystick (keys
5-8 and 0) or a Fuller joystick (port `7F`). Only the chosen interface is connected. By default
it is a Kempston joystick.

**Mouse**: with the Kempston mouse on (Settings > ZX Spectrum > Hardware), moving the PC mouse over the picture
moves the Spectrum's Kempston mouse (ports `FBDF` for X, `FFDF` for Y and `FADF` for the
buttons, as in K-Mouse), one Spectrum pixel per zoomed pixel. The PC pointer is hidden over the
picture while a program is reading the mouse (it draws its own; a program that doesn't read it for two seconds gets the PC pointer back). Left, right and middle buttons are passed on. The mouse
stops when the pointer leaves the picture, and then the PC pointer and the emulated one are no longer
aligned. To avoid that, the first click on the picture while a program is reading the mouse asks whether to **attach the
mouse to the window** (Settings > Common > General, `--attachmouse`, off by default): the PC pointer (hidden) then can't
leave the picture while the window is the active one and a program is reading the mouse (otherwise it moves freely), so only the emulated one is seen and its edges are easy to
reach. Holding Ctrl+Alt frees it (to reach the menus); Alt-Tab and any dialog free it too. The ZX-Uno and the
ZX Spectrum Next have the Kempston mouse on by default (switching to either connects it, as the DivMMC).

**Function keys**:

| Key | Action |
|---|---|
| F1 | documentation (this text) |
| F2 | open (Ctrl+F2: insert a disk in drive A:) |
| F3 | save snapshot |
| F4 | pause |
| F5 | NMI (on the ZX Spectrum Next its M1 button; Ctrl+F5 its DRIVE button) |
| F6 | hard reset (Ctrl+F6 reset) |
| F7 | tape browser |
| F8 | play/pause tape (Ctrl+F8 stop) |
| F9 | POKE |
| F11 | Adventure Debugger |
| Shift+F11 | turbo (as fast as possible) |
| F12 | debugger |

On the MSX, Shift+F1 to Shift+F10 are the MSX's function keys (see MSX > Keyboard).

## 3. Menus and toolbar

In the menu bar, the storage menus (Tape, Floppy and SD) are between two separators (|).

**File**: Open, Open recent, Save snapshot (.z80, the default, .sna or .e80; only .e80 on the ZX
Spectrum Next and the ZX-Uno), Screenshot (.SCR, or PNG at 1x or 2x
with or without the border), Exit.

Loading a recent file (Open recent, or Insert recent tape, disk, SD card or cartridge) makes its folder the one the file dialogs open in next,
as inserting it from a dialog does.

**Open recent** lists the last 10 recent files that make sense for the selected machine (the last 30 are kept, so after a while a machine's own are still a few), and opening one puts it where it goes: a tape (.tap,
.tzx, .cdt) in the tape, a disk image (.dsk, and .mgt and .sad on the SAM Coupé) in drive A:, an SD card image in the card reader, and a snapshot or
program (.sna, .z80, .nex, .e80) as File > Open does. Anything else is not listed: no .mgt on a +3, no .cdt on a Spectrum, no card
image on a SAM Coupé or a machine without a DivMMC, no .tap on a CPC (its tapes are .cdt and .tzx; a Spectrum or SAM Coupé takes .tap and .tzx), a .e80 only on the machine it was saved on. The list changes with the machine. The
recent lists of the Floppy and SD menus are filtered the same way.

**Machine** (classic interface): NMI (F5), Hard reset (F6: off and on, clears the memory), Reset
(Ctrl+F6), Pause and POKE. On the ZX Spectrum Next, NMI is its M1 button (the Multiface) and
the menu has its DRIVE button too (Ctrl+F5: the DivMMC's NMI).

**Tape**: Insert tape & load (a .tap or .tzx, or .cdt or .tzx on a CPC; the tape is put in and the machine starts loading it, as File > Open does; clicking the cassette in the modern interface does the same), Just insert tape (only puts the tape in, with no autoload), Insert recent tape & load and Just insert recent tape (the same two, for the last tapes inserted), Tape browser, Play/pause (F8; the button, in both interfaces, shows a pause while the tape plays, and pressing it then stops the tape where it is, and Play goes on from there; a block stopped in its middle starts again from its beginning), Stop, Rewind, Eject, Save tape as, New blank tape, Fast loading
(the ROM loader is skipped and blocks load instantly, also when the tape has been started with
Play: Play at the end of the tape starts it again, and the ROM's LOAD takes its blocks at once), Auto play/stop (see below),
"SAVE writes to the tape" (SAVE adds its blocks to the inserted tape, or to a new blank one, instantly),
continuous playback (Settings > Common > Storage, `--tapeloop`, on by default: when the tape reaches its end it goes on from
its start while a load asks for it, and a LOAD after the last block takes the first one again; off: **stop at the end of
the tape**, as Spectaculator does: the tape stops at its end and Auto play doesn't start it again, even with the
Spectrum still trying to load, until you rewind it, put another tape in, choose a block or press Play) and Record (REC).

**Auto play/stop** (Tape > Auto play/stop, Settings > Common > Storage, `--autoplay`, on by default) starts the tape when the
Spectrum asks for data and stops it, where it is, when it no longer does, so multiload games work with TAP and TZX
tapes: the next load goes on from the block the tape was left at (a block being played when it stops starts again
from its beginning; if only its pause was left, the tape goes on after it). It knows a load in two ways:
the ROM's LD-BYTES, which starts the tape when it is called and stops it a few frames after it returns (if no other
call follows, as there does between a header and its data); and, for loaders of their own, the Spectrum reading the
EAR bit over and over (hundreds of times a frame, where a keyboard scan reads it a few times): after a fifth of a
second of that the tape starts, and after one and a half seconds without it, it stops. A single read, or the
keyboard being read now and then, doesn't start it, and a short silence in the middle of a load doesn't stop it.
Stop (by hand) while a load is asking for the tape keeps Auto play from starting it again for that same load: the next
load (the ROM's LD-BYTES, or reading again after a silence), Play, Rewind, choosing a block or putting a tape in
lets it work again. A TZX's own "stop the tape" (a pause of 0 ms, or "stop on a 48K") stops the tape the same way: it
waits for the next load, or for Play. A custom loader that reads the EAR bit in an unusual way, or a program that
reads the port that fast for another reason (waiting for a key in a tight loop), can fool it: switch Auto
play/stop off and use Play and Stop yourself. Tape > Fast loading, if it is on, takes what the ROM's loader asks for
at once, and the custom loaders go as above. The state shows next to the block number ("playing", "stopped", "end of
tape", or "stopped (auto play waits for the next load)").

The tape plays at the CPU's pace: with the CPU faster than 1x (Settings > Common > General, or a machine's
own turbo: the ZX Spectrum Next's 7-28 MHz, the ZX-Uno's) real-time loading still works, and
takes that many times less. A machine's own turbo ends with a reset or a change of model: the
other models run at the speed setting.

Record (REC, the red button on the toolbar and in the tape browser) records what the Spectrum
sends to the cassette, as a real recorder would: the MIC output is decoded and every block saved
at standard speed is added at the end of the tape. It works for any program that saves with the
ROM's timing, not only the ROM's SAVE. A block ends when the signal stops; press REC again to
stop recording. With "SAVE writes to the tape" on, the ROM's SAVE still goes to the tape
instantly instead of in real time. Turbo or custom-speed savers can't be decoded.

Inserting an image that is already in a drive (or in the card reader) puts it in again, with no warning; if what is in there has been changed, you are asked about saving it first, as for any other image.

The Floppy menu is shown where the machine has a disk drive, or a DivMMC is on; the SD menu where there is a DivMMC (or
the machine's own, the ZX-Uno's and the Next's).

**Floppy**: Disk browser, insert (drive A: is Ctrl+F2), create (already formatted, 40 tracks, 9 sectors of 512 bytes; on the SAM Coupe 80 tracks,
2 sides, 10 sectors of 512 bytes) and eject disks in drives A: and B: (on the SAM Coupe: drives 1 and 2), Insert recent disk (A:) and (B:) (the last 10 disk images that fit the machine;
both drives share the list), Save disk (into the file it was loaded from, in its format: a `.mgt` or `.sad` is written as one, a `.dsk` as an extended DSK), Save disk as
(`.dsk`, or `.mgt` and `.sad` for a SAM Coupe disk), Fast
floppy disk access (off: the drive works at real speed, with seek and rotation times) and "Drive
B: connected". Drive B: is not connected by default, and while it isn't, the menu entries for it
are hidden. It is connected from this menu, from Options > Settings > Common > Storage, with `--driveb` or
by giving it a disk (`--diskb`). On the Commodore 64 the two drives are drive 8 (A:) and drive 9 (B:, a second 1541).

Menu entries with a description show it in the status bar while the pointer is over them (the
debugger's menus show it in its own status bar).

**SD**: The DivMMC's SD card: SD card browser, insert an image, Insert recent SD card (the last 10 that fit the machine
card images), new card (empty or with esxDOS) and eject (see
[DivMMC and SD cards](#7-divmmc-and-sd-cards)).

**Debug**: Debugger (F12), Clear all breakpoints, Load symbols, Load recent symbols (the last 10
symbol files), Clear symbols and, at the bottom, Adventure Debugger (F11, see
[Adventure Debugger](#11-adventure-debugger)).

**Options**: Monitor (colour, black and white, green phosphor or orange phosphor: the picture of any machine as
shades of grey or of that phosphor; the orange one is also called amber), Scanlines (from zoom 2x; the same as the setting), Zoom, Mute sound, Turbo speed (Shift+F11: as fast as
possible), Deinterlace (Progressive, Bob or Weave; see [Deinterlacing](#deinterlacing); only on the
Spectrum models; the SAM Coupe and the CPC are progressive) or, on the Amstrad CPC, CRTC chip (the model's own, or type 0 to 4), Modern interface (dark; see [Interface](#interface)), MSX 1 compatibility mode (MSX only, checked when on: the slots of an MSX1, see [Memory mapper](#msx); resets the machine), Virtual Keyboard (on every machine: a window, not modal and always on top, with up to 35 symbols in rows of 6: `| : ; . , / @ + * - = # ! " · $ % & ( ) ? ' [ ] { } < > ~ ¬ _ ¿ ¡ ñ Ñ`; a click types that symbol on the machine with the keys that give it there, as `--keyin` types its text (on the Spectrum `[ ] { } | ~ \` through the extended mode; on the MSX `ñ Ñ ¿ ¡ ¬ ·`, which have no key of their own, go into the BIOS's keyboard buffer); only the ones the machine can type are shown (in bold, one after another in that order); Esc closes it; the modern interface has it as the Virt. Kb button instead), ZX Keyboard Guide (on every Spectrum, not the CPC, the SAM Coupe or the MSX: a window with the ZX Spectrum keyboard map and the keywords of every key; Esc or a click closes it; it is not modal and 1064 px wide, smaller only if the screen is; the modern interface has it as the ZX Guide button instead), Install Spectrum Next Distribution
(only while the Next's distribution isn't installed; see [ZX Spectrum Next](#zx-spectrum-next)) and
Settings (everything else is in Settings).

**Help**: Documentation (F1, this text from README.md), License (the GNU GPL v3, from the
`LICENSE` file) and About (ochenta stands for Pascal ZX; it shows the release number, the build date
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

Options > Settings opens a window that is not modal (the emulator goes on and can be used while it is
open; it is as tall as its tallest tab needs, appears in the middle of the screen the first time and then where it was left): **OK** applies the changes and closes it, **Apply** applies them and leaves it open, and **Cancel**
closes it putting back what the settings were when it was opened (what Apply had applied too).
It has four main tabs: **Common** (what is the same on every machine), **ZX Spectrum**
(what belongs to the Spectrum models, the ZX-Uno and the Next), **Amstrad CPC** and **SAM Coupé**. Common and ZX
Spectrum have tabs of their own inside, set apart under a band with the machine's logo (none under Common)
(sections of a page are boxes with a title):

| Tab | Contents |
|---|---|
| Common > General | four boxes. General: CPU speed (1x to 32x: the Z80 runs faster but interrupts stay at 50 per second, and contention and the CPC's wait states are not applied above 1x), allow writing to ROM (from the debugger and with POKE; off by default), whether the settings are saved when ochenta closes (on by default; when off, changes last only until ochenta is closed) and whether the mouse is attached to the window (the PC mouse stays over the picture while the emulated mouse is in use; Ctrl+Alt frees it; off by default, see [Mouse](#2-keyboard)) and the interface's language, a list to the right of "Allow writing to ROM" (see [Language](#language)). Layout: the theme (classic or modern, see [Interface](#interface)) and the zoom. Video: the monitor (colour, black and white, green phosphor or orange phosphor) and scanlines (from zoom 2x). Sound: volume and mute sound (the same as Options > Mute sound). The machine is chosen from the toolbar's menu, not here. |
| Common > Storage | Tape: fast loading, Smart Tape Player (starts and stops the tape by itself when the machine loads: Auto play/stop in the Tape menu) and continuous tape playback (from the start again at the end). Floppy: fast floppy disk access (no real drive timing), drive B: and floppy drive noise (on by default: the drive's motor, head steps and reading are heard when it works at real speed, not with fast floppy disk access; while the disk turns and no step has been heard for 3 seconds, the head moves now and then by itself, a step or a short seek at random). |
| Common > ROMs | the folder with the standard ROMs and, for each model (the CPCs too), the ROM file to use for each of its ROMs (empty = the standard one); labels for a ROM are read from a .sym file with the same name next to it. |
| ZX Spectrum > Hardware | what is connected to the machine: TurboSound, an AY chip on the 16K/48K, the Kempston mouse, the DivMMC interface and the Currah µSpeech (changing the DivMMC or the µSpeech switches the machine off and on), and whether SAVE writes to the tape. Hovering over one explains it. |
| ZX Spectrum > Machine | Graphics: ULAplus, Timex screen modes, Radastan mode and deinterlacing (Weave by default; see [Deinterlacing](#deinterlacing)) (all off by default; see [Video modes](#video-modes) below). Controls: keyboard issue 2 or 3 (16K/48K: affects bit 6 of port `FE`) as radio buttons, and the cursor keys joystick. Core features: contended memory and I/O (on by default: real timing; off makes every access take its nominal time) and ULA snow (on by default; only the 16K, 48K, 128K and +2 show it). |
| ZX Spectrum > Firmware | DivMMC: its firmware (empty = the bundled `esxdos/ESXMMC.BIN`). ZX-Uno: its BIOS and ROMs (empty = the ones in the zxuno folder) and its custom ROM (see [ZX-Uno](#zx-uno)). ZX Spectrum Next: its distribution folder, its SD card and whether it starts through its firmware (see [ZX Spectrum Next](#zx-spectrum-next)). |
| Amstrad CPC | Video: the CRTC chip (see [Amstrad CPC](#amstrad-cpc)). Timing: the Gate Array's wait states. Controls: the cursor keys and right Ctrl as joystick 1. |
| SAM Coupé | Memory: 256K or 512K of RAM (changing it resets the machine). Sound: the SAA1099 heard or not. Controls: the cursor keys and right Ctrl as a Kempston joystick (see [SAM Coupé](#sam-coupé)). Peripherals: the SAM's mouse (the PC's over the picture) and the SAMBUS clock, a check for each. DOS: Boot SAMDOS automatically (`SAMDOS2.dsk` inserted and booted on start and reset). The Common tabs apply to it too: Storage (disk drive noise, fast disk access, drive 2, tape auto play and loop), General, ROMs (the SAM Coupé's ROM file) and the monitor. |

Settings are kept in `ochenta.ini` in the same folder as the program (next to ochenta.app on macOS); on
Linux, if that folder can't be written (ochenta installed from a .deb or .rpm package, or run as an AppImage), in
`~/.config/ochenta/ochenta.ini`. On Windows no other ini is ever read (not even an older one from another
folder or from the user's profile). See `--config` and `--config-add` below to use other files. `ochenta.ini` is
an ini file whose keys are named exactly as the command line options (see
[Command line](#12-command-line)), with 1/0 for on/off options and the option's value for the
others. The options of the ZX Spectrum models start with `zx_` and those of the Amstrad CPC with
`cpc_`; the ones that are the same for every machine have no prefix:

| Section | Keys |
|---|---|
| `[General]` | `model`, `scale`, `ui` (`classic` or `modern`), `monitor` (`color`, `bw`, `green` or `orange`), `mute`, `volume`, `speed`, `lang` (`auto`, `en`, `es`, `fr`, `pt` or `de`), `saveonexit` |
| `[Machine]` | `romedit`, `scanlines`, `attachmouse` |
| `[TapeDisk]` | `fastload`, `autoplay`, `tapeloop`, `fastdisk`, `driveb`, `floppynoise` |
| `[ROMs]` | `romdir`, `rom` (the `--rom "MODEL,N,FILE"` entries separated by `\|`) |
| `[Screenshot]` | `pngborder` |
| `[ZXSpectrum]` | `zx_contention`, `zx_snow`, `zx_ulaplus`, `zx_timex`, `zx_radastan`, `zx_deinterlace`, `zx_joystick`, `zx_issue`, `zx_turbosound`, `zx_ay48`, `zx_kmouse`, `zx_divmmc`, `zx_currah`, `zx_leftctrl`, `zx_savetotape`, `zx_divmmcrom`, `zx_unofirmware`, `zx_unoroms`, `zx_unocustomrom`, `zx_unocard`, `zx_sdcard`, `zx_nextdir`, `zx_nextcard`, `zx_nextfirmware` (and `zx_distroid`, the distribution the Next's card was made from, and `zx_unobios`, the ZX-Uno BIOS's own settings) |
| `[AmstradCPC]` | `cpc_crtc`, `cpc_waitstates`, `cpc_joystick` |

The recent files, pokes and last folder are kept in sections of their own. An ochenta.ini from an
older version is read and rewritten with these keys; the names the options had before they took
`zx_` and `cpc_` (`turbosound`, `joystick`, `issue`, `nextdir`, `sdcard`, `cpcjoystick`...) are still understood, in the file and on the
command line, and the file is written with the new ones.

### Language

The interface (menus, toolbar, settings, dialogs, messages and the browsers) comes in English, Spanish
(`es`), French (`fr`), Portuguese (`pt`, Brazilian) and German (`de`). The Debugger, the Adventure
Debugger, the Z80 instruction help, this documentation and `--help` are always in English, and so are
the names of the machines and of some terms (Debug, NMI, SD, Zoom, Turbosound, DivMMC, Currah, ULAplus,
Timex, Radastan, Joystick, Scanlines, Breakpoints, Watches...). The language is chosen like this, in
this order:

1. If the **left Ctrl** key is held down while ochenta starts, English, whatever the rest says (a way out
   if a language is set that can't be read).
2. `--lang auto|en|es|fr|pt|de` on the command line, for that run.
3. `lang` in ochenta.ini (`[General] lang`), set in Settings > Common > General > Language. **Automatic**
   (the default) uses the language of the system (Windows' display language; on Linux and macOS
   `LC_ALL`, `LC_MESSAGES`, `LANGUAGE` or `LANG`) if it is one of the four, and English otherwise.

The language is used when ochenta starts: after changing it in Settings (OK), ochenta offers to restart
at once, and comes back with the machine that was running (in a snapshot for every machine but the
MSX2, which starts again with its model). If the answer is No, it is used the next time.

### Interface

ochenta has two interfaces with the same commands: **classic** (the menu bar, the toolbar and the
status bar described above) and **modern** (dark, with palettes of big buttons). ochenta starts in the
modern one; the first time (no settings file yet) a warning says so for 5 seconds, with the button
that changes to the classic one. The one in use is kept in ochenta.ini (`[General] ui`) and can be
changed at once, without restarting: with the half dark
circle button (at the right end of the classic toolbar, left of the model in the modern header),
Options > Modern interface, or Settings > Common > General > Layout > Theme; or for a session with
`--ui classic` or `--ui modern`.

The modern interface (on Windows 10 and 11 its title bar is dark too):

- **Header**: the menus as buttons (File, Tape, Debug, Options, Help; the Machine menu is the
  classic interface's, its commands are the Machine palette's buttons, and the Floppy and SD menus are behind the Media palette's
  buttons: each
  opens the same menu, dark, with its checks and shortcuts) and, on the right, the button back to
  the classic interface and the model (click to change it: the models open under it). The keyboard shortcuts (F2, F9, F12...) work as in the classic one.
- **Machine palette** (left): Open, Save (snapshot), Off/on (hard reset), Reset, NMI, Pause, Turbo,
  POKE, Debug (the debugger), Settings and Virt. Kb (the virtual keyboard), with big buttons; Pause and Turbo are lit while on. On every Spectrum (not the CPC, the SAM Coupe or the MSX)
  a ZX Guide button after Virt. Kb opens the ZX keyboard guide (see Options).
- **Tape palette** (right): a cassette with the tape's name on its label and its progress (all the
  tape starts on the left reel and passes to the right one as it plays; the hubs turn while it
  plays; with no tape in it, an empty cassette player is shown
  instead; **click it to insert a tape**, as File > Open for the tapes of the machine: .tap and .tzx, or .cdt and .tzx on a CPC), the tape's name and block on one line (when it is longer than the room it scrolls to its end and back now and then, not all the time), Rewind, Play/pause, Stop and Record (flat, wide buttons),
  a button with the **Tape menu** (like the drives' menu buttons), the tape browser and Fast (fast loading, lit while on). The Tape, Floppy and SD menus are not in the header: they are behind these buttons. They leave out what has a button
  (play, stop, rewind, record, the browsers, fast loading and fast floppy access; their shortcuts, F7, F8 and Ctrl+F8, still work); the classic interface's menus have everything.
- **Media palette**: drives A: and B: and the SD card, each a row with its LED, a drawing of the drive (two floppy drives and an SD card reader: empty, or with a floppy
  or a card in: a card sticks out of its slot only by a little, as in a real reader), the name of what is in it (it scrolls when it is longer than the room, as the tape's does).
  Which of them can be used depends on the machine: the drives only where the machine has one (the +3, the CPC 664 and 6128 and the SAM Coupé; drive B: also
  needs to be connected), the card reader where there is a DivMMC (fitted in Settings, or the ZX-Uno's and the Next's own); the others are drawn dim ("not available"). **Click a drive or the
  card reader** to insert something in it (the same as Floppy > Insert disk in drive A: (Ctrl+F2) and B:, and SD > Insert SD card image), and use the
  **menu button on its right** to open the Floppy menu (the two drives) or the SD menu; and
  below, three buttons: Disks and SD (the disk and SD card browsers) and Fast (fast floppy disk access, lit
  while on: the same as Settings > Common > Storage, as Fast is the fast loading of the tape).
- **Bottom bar**: the zoom (1x to 4x, the one in use lit; a zoom too big for the screen isn't
  shown, and can't be chosen in Options > Zoom) and what the classic status bar says.

The debuggers, the browsers and the other windows are the same in both interfaces, separate and
not modal; with the modern one they are dark too (their lists, fields, drop-down lists (white on
black), views, toolbars, tabs, check boxes, sliders and frames; their status bars and push
buttons are the system's own and stay light). The colours of the debugger's views are turned
round, keeping their hues; its mnemonics are bold white (light red for the undocumented ones,
also bold white on the execution point's green line), the values being edited black on white,
the Adventure Debugger's condacts bright white, the hints white on dark grey, and the
documentation's links and headings light blue.

### ZX-Uno

The ZX-Uno is an FPGA board with many cores; ochenta emulates its Spectrum core the way the real one
starts: the boot loader copies its BIOS from the SPI flash and runs it, and the BIOS shows its
boot screen, reads the ROMs from the flash, copies the chosen one into its 512K of SRAM (pages
8-11), sets the machine up through its registers (ports `FC3B` and `FD3B`) and starts it. The
flash is built from `FIRMWARE.ZX1` (the BIOS) and `ROMS.ZX1` (its ROMs, as the BIOS upgrades them
from an SD card: directory and 64 ROM slots), from the zxuno folder or as chosen in Settings >
ROMs (`--zx_unofirmware`, `--zx_unoroms`; changing them switches the ZX-Uno off and on), with
`esxdos/ESXMMC.BIN` for its DivMMC.

While the boot screen shows, Edit (Shift+1) enters the BIOS setup and Break (Esc) its boot menu,
to start any of its ROMs. Its keys are the Spectrum's: cursors (CAPS + 5/6/7/8), ENTER, Break.
The settings the BIOS saves (active ROM, boot timer, quiet boot, keyboard issue, timing,
contention, DivMMC...) are kept in ochenta.ini (`[ZXUno] BiosSettings`) and used from then on;
changes to the ROM list are not kept. Until something is saved, the BIOS shows its boot screen
and starts the first ROM, the 48K. The boot screen lasts about a second and the ROM starts after
about two, as on the real board: the SCANCODE register returns the PS/2 keyboard's power-on
self-test byte (`AA`), without which the BIOS waits five times longer.

**Custom ROM** (Settings > ZX Spectrum > Firmware, `--zx_unocustomrom`): a 16K ROM file. If it exists, the BIOS
still runs, but the ROM it chooses is replaced by this one when it starts it, and the machine is
set as a 48K (48K timing, no `7FFD` or `1FFD` paging). Empty or a missing file: the BIOS's
choice. Changing it switches the ZX-Uno off and on.

It always has a DivMMC (with ESXDOS, which the BIOS switches on; as in the core, its firmware is
in SRAM page 12 and its 128K of RAM in pages 16-23, so MASTERMAPPER and the DivMMC see the same
memory), the Timex screen modes, Radastan and ULAplus: in Settings they show on and greyed out
(the values set are kept for the other models), and `--no-zx_divmmc`, `--no-zx_timex`, `--no-zx_radastan`
and `--no-zx_ulaplus` are ignored with `--model zxuno`. Its own registers can switch them off
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

Hard reset (F6) switches the ZX-Uno off and on (BIOS again); Reset (Ctrl+F6) restarts the ROM
the BIOS chose. File > Save snapshot saves a .e80 (see [ochenta snapshots](#ochenta-snapshots-e80)): .sna
and .z80 can't hold its SRAM and registers.

### Video modes

Settings > ZX Spectrum > Machine can add these to any model (they are off by default):

| Mode | Description |
|---|---|
| ULAplus | a palette of 64 colours (GGGRRRBB) at ports `BF3B` (register) and `FF3B` (data): registers 0-63 are the palette, register 64 (bit 0) switches it on. Then FLASH and BRIGHT choose one of four 16-colour palettes (8 inks and 8 papers each), there is no flashing, and the border takes the paper colour of the first. |
| Timex | the screen modes of the Timex computers, at port `FF` (reading port `FF` then gives this register instead of the floating bus): bits 0-2 = 1 the second screen (at `6000`), 2 hi-colour (an attribute for every 8x1 cell, at `6000` laid out like the bitmap), 6 hi-res (512x192, columns taken in turn from `4000` and `6000`; bits 3-5 the ink, the paper is its complement, and the border is the paper); bit 6 stops the interrupts. |
| Radastan | the ZX-Uno's 128x96 mode with 16 colours: 4 bits per pixel, 64 bytes per line from `4000` (`6000` with the Timex second screen), colours from ULAplus entries 0-15 (the border too, by its number). Switched on by writing 3 to ULAplus register 64 (`OUT 48955,64: OUT 65339,3`), or to the ZX-Uno register 40h (ports `FC3B` and `FD3B`). |
| Scanlines | with the window at 2x or more, the lower rows of every Spectrum line are drawn darker, as on a TV. |

The picture is kept at twice the width, so the 512-pixel hi-res is shown in full from 2x (at 1x
every other column) and in PNG screenshots at 2x.


### Deinterlacing

The Spectrum sends a progressive picture: every frame (50 a second) is the same field, with no
odd or even one. Some demos (DeMarché's Mescaline and Paralactika, the end of Gasman's
Ultraviolet) draw two different pictures in alternate frames, counting on a TV to mix them, so
they flicker in stripes when each frame is shown on its own. Options > Deinterlace (also Settings
> ZX Spectrum > Machine, `--zx_deinterlace`) takes each two frames in a row as the odd and even fields of an
interlaced picture of 352x576 (704x576 with Timex hi-res):

| Method | What is shown |
|---|---|
| Progressive | each frame on its own, scaled to the whole picture, as the Spectrum sends it. |
| Bob | the two fields blended: each pixel the mean of the red, green and blue of the same pixel in both, every line drawn twice. This is how those demos are meant to be seen. |
| Weave | both fields at once, interlaced: a line of the odd field, then one of the even field, and so on (each Spectrum line's rows, the upper half from the odd field, the lower from the even one). At 1x, with no room for both, it blends them as Bob. The default. |

It only changes what is shown: screenshots (PNG) still save the frame as the Spectrum made it.
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
another folder in Settings > ZX Spectrum > Firmware (`--zx_nextdir`). When ochenta is installed from a .deb or .rpm, or run as an AppImage, the
folder is `~/.config/ochenta/specnext` (the one next to the program can't be written).

Choosing the Next without the distribution (or SD > New SD card with the Next distribution)
says so in a window ("La distribución de Spectrum Next no está instalada...") with the download
page as a link that opens in the browser, and the machine stays as it was (with `--model zxnext`, ochenta closes). Download the .zip and
choose Options > Install Spectrum Next Distribution (this entry is only there while the distribution
isn't installed): pick the .zip file and ochenta unpacks it into the folder (a distribution inside one
folder of the zip goes straight into it, with no extra level) and checks it, and only then moves it
into place, so a broken file leaves nothing half installed. A path in the zip that would write
outside the folder (`..`, an absolute path or another drive) makes ochenta refuse the whole file, and
links are not made. If it is a distribution, ochenta says so and asks whether to start the Next now
(Yes: the machine changes to the Next, its SD card made at the usual size without asking; No: nothing
else). If it isn't ("Distribución no valida", or a file that isn't a zip), pressing OK **deletes
everything in the distribution's folder**, which is what that message means: don't point
`--zx_nextdir` at a folder with other things in it. A file that can't be read or written, or a damaged
zip, is reported as an error and installs nothing.

**SD card.** The first time the Next is used, ochenta makes its SD card, `zxnext.img` next to ochenta.ini
(Settings > ZX Spectrum > Firmware, `--zx_nextcard`), asking its size first (FAT16: the sizes the distribution fits in
with room to spare, up to 2 GB; 512 MB proposed; Cancel leaves the machine as it was), with the
whole distribution (long file names included) and a `config.ini` for it (a few seconds). The card is the Next's own: the other models
keep theirs, and what NextZXOS saves on it is kept (ochenta saves it when leaving the Next and when it
closes, without asking). When a newer distribution is unpacked, ochenta asks whether to make a new
card from it; the old one is kept, renamed as `zxnext-YYYYMMDD-HHMM.img`. SD > New SD card with
the Next distribution makes another one.

Cards used with older versions of ochenta may have files that NextZXOS or the firmware rewrote left
empty (ochenta didn't answer the card's status request, CMD13, so every write after the first block
failed): an empty `machines/next/config.ini` makes the firmware show its video test card at every
start. When the Next's card is put in, ochenta mends them: each empty file that isn't empty in the
distribution is copied from it again, and an empty `config.ini` gets the default one; a message
lists what was mended.

**Extra cores.** The firmware's extra cores menu (C while it starts) works with an emulated 16 MB
flash (in memory only, empty at every start of ochenta): cores can be installed into slots 8-31, but
ochenta emulates only the Next's own core, so starting another machine's (the Sinclair QL...) says so
and starts the Next again.

**Starting.** By default (Settings > ZX Spectrum > Firmware > "Start through its firmware", `--zx_nextfirmware`) the
Next starts as the real one: its boot ROM (`roms/tbblue_loader.rom`) loads the firmware
(`TBBLUE.FW`) from the card, which shows its boot screen with the TBBlue logo (ochenta says it is an
emulator, machine ID `08`) and starts NextZXOS. Unchecked (`--no-zx_nextfirmware`), NextZXOS starts
directly from the distribution's ROMs, as if the firmware had chosen it. Hard reset (F6) starts
it all again; Reset (Ctrl+F6) is the Next's soft reset.

**.nex files** (File > Open, or the command line) switch to the Next if needed and are loaded
into its memory and started, as NextZXOS's `.nexload` does (versions 1.0 to 1.3: loading screens
of every kind, palette, the copper code, which starts at once, and the registers as the header
asks). A program that asks for its own file (to read more data from it: through the handle the
header asks for, or opening it again by name with F_OPEN) gets a handle that the esxDOS calls
F_READ, F_SEEK, F_FGETPOS, F_FSTAT and F_CLOSE read from the .nex; for
DISK_FILEMAP, which programs use to stream data straight from the card, the file is also copied
onto the Next's SD card as `/TMP/OCHENTANEX.NEX` (replaced each time). Tapes are only inserted (load
them from NextZXOS's browser or with `LOAD ""`), and .sna, .z80 and .dsk files switch to their
own model. File > Save snapshot saves a .e80 (see [ochenta snapshots](#ochenta-snapshots-e80)).

**Sound.** Three AY chips (TurboSound Next: port `FFFD` chooses one with `FF`, `FE` or `FD`, its
bits 6 and 5 switching that chip's left and right outputs), each ABC or ACB stereo (NR `08` bit
5) or mono (NR `09` bits 5-7), with the four 8-bit DACs.

**Keys.** The keys that are two Spectrum keys at once (cursors, DELETE, EDIT, BREAK, EXTEND MODE,
CAPS LOCK, TRUE and INV. VIDEO, GRAPHICS and `;` `"` `,` `.`, see [Keyboard](#2-keyboard)) are
the Next's extra keys, read in NR `B0` and `B1`.

**NMI buttons and the Multiface.** NMI (F5) is the Next's M1 button: NextZXOS's Multiface menu
(Snapshot, Screenshot, TAP files, POKEs, Debug tools, Settings, Keymap...), from
`enNextMf.rom` in the distribution. Machine > DRIVE button (Ctrl+F5) is the DivMMC's NMI. Each
works when NextZXOS lets it (NR `06` bits 3 and 4; NextZXOS turns the DRIVE button off by
default), as on the real machine; NR `02` makes them by software. The Multiface (its four types,
NR `0A`, the +3 one by default) pages its 8K ROM and 8K RAM in over everything else at `0066`
until RETN or its ports page it out; the NMI may be stackless (NR `C0` bit 3, as NextZXOS uses
it: RETN then returns to the address in NR `C2`-`C3`; RETI, which interrupt handlers use, still
returns to the one on the stack).

**Configuration mode.** While NR `03`'s machine type is `000`, `0000`-`3FFF` is the 16K of SRAM
that NR `04` chooses, writable. Writing type `111` to NR `03` goes back to it from any machine
type, as on the real Next: games such as Atic Atac use that to write their own DivMMC NMI entry
into the DivMMC's memory, and stream their sound through the DivMMC NMI. NR `09` bit 3 clears
the DivMMC's MAPRAM (port `E3` bit 6), which the original DivMMC can't do.

**Copper.** It runs on its own clock (four steps a T-state, two for a MOVE), and WAIT holds it
until its line and horizontal position (in 8-pixel steps) come, counted from the first line of
the picture moved by NR `64`. A register written while the beam is in a line, by the copper or
the CPU, changes the rest of that line only: what has been drawn stays.

**Debugger.** The disassembly, the instruction help and the assembler export know the Z80N
instructions (the export adds `OPT --zxnext` for sjasmplus), and Next Regs (the chip button)
shows and edits its registers.

### Amstrad CPC

The CPC 464 (tape, 64K), CPC 664 (3" disc drive, 64K) and CPC 6128 (disc drive, 128K in eight 16K banks) are
chosen like any other machine: the chip button, Options > Settings, `--model cpc464`, `--model cpc664`,
`--model cpc6128` (or just `ochenta cpc464`). Their firmware is in `roms/` (`cpc464.rom`, `cpc664.rom`,
`cpc6128.rom`: the 16K operating system followed by the 16K BASIC; `amsdos.rom`, the disc ROM of the 664
and 6128), and each model's file can be replaced in Settings > Common > ROMs as for the Spectrum.

What is emulated, in `src/Amstrad.pas` (the hardware) and `src/SpectrumCPC.inc` (its join to the Z80, the
sound, the tape and the disc controller, which the Spectrum models share):

- **The CPU at 4 MHz held to the Gate Array's 1 MHz grid**: every instruction takes the whole number of
  microseconds the CPC's NOP-count timings give it (as Caprice32 has them: `OUT (C),r` takes 4, not its 12
  T-states rounded to 3; `PUSH` 4, `OUTI` 5, a taken `JR` 3, an interrupt 5), and its I/O reaches the chips in the
  microsecond it does on the real machine (`OUT (C),r` in its third, `IN r,(C)` in its fourth), so programs that
  change the CRTC or the palette at a given character (split screens, rasters, `Pinball Dreams`' tables) see it
  where they expect, and the loaders and protections that count microseconds work. The Gate Array's wait states
  setting (Settings > Amstrad CPC > Timing, `--cpc_waitstates`) switches this off (the Z80's own T-states are used
  then), and it is not applied above 1x speed.
- **Gate Array**: the 16 pens and the border with the 27 colours (hardware colours 0-31), screen modes 0, 1, 2 and
  3 (changed in mid-frame, even mid-line, at the character it happens), lower and upper ROM enable, the upper ROM
  number (port `DFxx`: BASIC, and AMSDOS as ROM 7 on the 664 and 6128), the 6128's RAM banking (the eight
  configurations `C0`-`C7`; the 464 and 664 ignore it), and the interrupt counter: 52 HSYNCs, the reset by the
  CPU's acknowledge, by bit 4 of the ROM register and the synchronisation after the VSYNC (two HSYNCs).
- **The CRTC chips**: the five that CPCs had, chosen in Settings > Amstrad CPC (`--cpc_crtc`, `cpc_crtc` in
  `[AmstradCPC]`; by default the one the model came with: type 0 on the 464, type 1 on the 664 and 6128):
  type 0 (HD6845S / UM6845), type 1 (UM6845R), type 2 (MC6845), type 3 (AMS40489, the CPC+'s ASIC) and type 4
  (AMS40226, the pre-ASIC). What differs, as programs that detect the chip and demos rely on it:
  which registers read back (types 0 and 4 read R12-R17, types 1 and 2 only R14-R17, type 3 shows 8 registers: the
  light pen, two status registers and the screen address; what can't be read gives 0), the status register at
  `BExx` (type 1: bit 5 in VSYNC; types 3 and 4: it shows the register data; types 0 and 2: nothing), the bits each
  register keeps (types 1 and 2 have no VSYNC width in R3's high nibble, so a VSYNC of 16 lines, and no display
  skew in R8), an HSYNC width of 0 (none on types 0 and 1, 16 characters on types 2 and 3), the display skew of
  R8 (0 to 2 characters, on types 0, 3 and 4), the compares for the end of the displayed rows (R6) and the VSYNC
  (R7), which all chips do by equality with the row counter (a value the counter has passed isn't met again
  until it wraps) but the AMS40489 only on the first raster of a row, the UM6845R's start address (R12-R13)
  taking effect in the first row too, and PPI port C (the CPC+'s ASIC doesn't clear it when the PPI's mode is
  set, which is how a program tells type 3 from type 4). Tested with the detection routine of Amstrad
  Diagnostics, which reports all five correctly.
- **6845 CRTC**: registers 0-9 and 12-13 (horizontal and vertical totals, displayed, sync position and widths,
  vertical adjust, raster count, start address) run character by character, so programs that change them in the
  frame (split screens, vertical scroll, overscan, rupture) get what they set; the video address is built as the
  hardware does (`MA13-12`, `RA`, `MA9-0`), and the screen and border are drawn as the beam reaches them.
- **8255 PPI**: the keyboard matrix (10 lines), the PSG bus (latch, write, read), the VSYNC line, the 50 Hz and
  manufacturer jumpers, the cassette input and output and the motor relay.
- **AY-3-8912** at 1 MHz (the sound code is the Spectrum's, with its own clock); the joystick and the keyboard
  are read through its register 14.
- **Tape**: see below. **Disc**: the uPD765 of the Spectrum +3 (`FDC765.pas`), which is the same chip wired the
  same way on the CPC, at ports `FA7E` (motor), `FB7E` (status) and `FB7F` (data), with the same DSK images
  (standard and extended), at real drive speed unless "Fast floppy disk access" is on, and with the drive's
  noise. The CPC 464 has no drive (the Floppy menu is hidden, and the drive is dim in the modern interface's Media palette), and there is no SD card on any CPC.

**The picture** is 44 characters (704 of the 640-pixel mode's pixels) by 288 lines: the 40-character screen with
two characters of border each side, and the lines around the CRTC's VSYNC; the frame buffer has the size of the
Spectrum's (352x288, twice as wide), so zoom, black and white, scanlines and the library work unchanged. At 1x each
pair of columns is averaged (in the 640-pixel mode every column is a pixel); the CPC pixels are not square (in
mode 2 they are twice as tall as wide), and 352x288 is the proportion of the monitor's 4:3 picture, as for the
Spectrum. The picture follows the HSYNC and VSYNC the CRTC gives (it rolls if a program makes a frame of another
length, as a monitor would; a frame shorter than the usual 312 lines, which a program with its own CRTC values makes, shows what
it drew, black below). The picture's lines are the monitor's: its horizontal oscillator runs by itself (64 microseconds a line) and is pulled towards the
HSYNCs in a few lines, by when they come and not by where the CRTC's lines start. So a program that moves the HSYNC from line to
line (R2 alternating, as `Pinball Dreams`' title screen does) doesn't shift the picture line by line, and one that makes short CRTC
lines whose HSYNCs still come every 64 microseconds (`Pinball Dreams`' tables scroll by a line that way: a line of 44 characters
and five of 4) doesn't move it at all; with a steady HSYNC nothing changes. The raster counter ends a character row when it meets
R9 (if R9 is lowered below it, it counts on to 31 and round). **Screenshots**: PNG at 1x (352x288, or 320x200 without the border) or 2x (704x576, or
640x400), with the same menu as the Spectrum's, and `.SCR`: the 16K of screen memory the CRTC shows, behind an
AMSDOS header (a binary for `&C000`, as `LOAD "x.scr",&C000` takes it), without the palette.

**Tapes (.cdt and .tzx).** A CDT is a TZX file, so the same blocks (turbo data `11`, tones, pulses, pure data,
direct recordings, pauses, loops...) are played, in real time, as the signal the CPC's tape input reads: the
pulse lengths of a TZX are in the T-states of a 3.5 MHz machine and are scaled to the CPC's clock. The cassette
motor is the program's (the PPI), so the tape moves only while the motor is on and Play is pressed (Tape > Play,
F8) or **Auto play** is on (the default): when a program switches the motor on, the tape starts, and where the
program stops it, it stops (stopped in the middle of the data of a block, it goes on from there when the motor goes on again, as a
tape deck does: a loader that reads part of a block and starts the next stage while the same block goes on, like `The Hobbit`'s, needs it;
stopped in a tone, a sync or a pause it goes on from the start of that block). `RUN"` shows "Press PLAY then any key": Opening a .cdt does that for you. Multi-block
and multi-stage loads, pauses, and programs with their own loaders (they only read the input) work because it is
the signal that is read. The CPC's tape loads at the real speed and is heard (the loading tones through the speaker, with the music some loaders play); "Fast loading" doesn't run it faster, as it has no ROM trap to skip the loader: Turbo (F11) runs it as fast as the machine can. With Auto play on, "Press PLAY then any key:" is answered by the emulator (a key is pressed a few frames after the prompt), so a program that loads its parts one after another, with its screen black meanwhile, doesn't wait for you. A .tzx made for the Spectrum has blocks `10` (standard speed, the ROM's pilot and sync): they play
as a signal, but the CPC's firmware can't read them; opening a tape that has them says so. A .tap is refused on
a CPC (it is a Spectrum tape). A CDT keeps its pauses in whole milliseconds, so a gap of 1.4 ms is stored as 1 and a loader that has to be back at the tape before the next block's short tone is over (`Michel Futbol Master`'s side B, with a gap of 1 ms and 13 pulses of tone) can miss it: a pause of 1 or 2 ms plays half a millisecond longer on a CPC, which is what the truncation takes on average. Limitations: nothing is skipped by a ROM trap (there is none), so loading takes the
tape's time unless the emulator runs fast; the 3.5 MHz scaling uses the exact 7/8.
**Recording (REC)**: the tape output (PPI C bit 5, while the motor is on) is kept as it is, edge by edge, as
pulse blocks and the pauses between them, so what the CPC `SAVE`s (also with its own save routines) is stored
without being decoded: Tape > Save tape as writes it as a `.cdt` (or `.tzx`), which loads back in ochenta and in other
emulators. Limitations of that: the file is larger than a decoded CDT (two bytes a pulse), a pulse longer than
18 ms or a silence longer than 5 s is cut (as a pause), and the blocks aren't named until the tape is loaded again.
Tape > Save tape as can't write CSW recordings, generalized data blocks or flow control blocks (it says so).

**Disks.** A DSK in drive A: (File > Open, the Floppy menu, `--disk`) works like the +3's; opening one on a CPC
464 switches to a CPC 6128. Floppy > New disk in A: makes an empty disc in AMSDOS's data format (sector numbers C1-C9) on a CPC (the +3's format on the +3, which AMSDOS can't read), ready for `SAVE`. Opening a disk starts it as a user would, typing `RUN"` and a program name chosen from
the directory: the one named as the disk image (GAME.BAS or GAME.BIN for GAME.DSK, or one named almost so: RASTAN.BIN
for RASTAN1.DSK), else DISC, DISK, START, LOADER, GAME or RUN, else the first BASIC program, a file with no extension
or the smallest binary (a loader is a few hundred bytes); empty files and names that can't be typed (the "1-------"
decorations of cracked disks) are skipped. A disk whose directory AMSDOS can't read (a boot disk, as many commercial
ones: the directory isn't where AMSDOS looks) is started with `|CPM`. It is a guess, as there is no standard: when it
isn't the right one, type the command yourself. The Disk browser reads the CPC's CP/M directories (on a CPC the headers are AMSDOS ones: Import offers a binary with an AMSDOS header, loaded and run at the address you give, and Export asks whether to keep a file's header; a file that already has one is copied as it is. A `.SCR` is offered at `&C000`).

**Snapshots**: File > Save snapshot writes a CPC `.sna` (the format of CPCEmu and Winape: the Z80, the Gate Array, CRTC,
PPI and PSG registers and 64K or 128K of RAM, version 1; it records the model, which loading it switches to) or ochenta's own `.e80`
(the same and more: the model, the whole CPU, the 64K or 128K RAM, the Gate Array, CRTC, PPI and PSG state with the CRTC
chip, the PSG chip, the interrupt counter and where the beam is; the version-1 `.e80`, with the model's name, as for the
other models). A `.sna` doesn't say where the beam is or the CRTC's chip: the machine goes on from the start of a frame.
Opening a `.sna` made with its memory in compressed chunks (some version 3 files), or of a CPC+ or a GX4000, says that it
can't. The tape's position and a disc transfer in progress are in neither; the discs stay inserted as they are.

**Debugger**: the same one: the disassembly, memory and registers show the memory as the CPU sees it (ROM
paged in or RAM under it; the slot list shows `ROM0` operating system, `ROM1` BASIC, `ROM2` AMSDOS, `RAM0`-`RAM7`;
click a slot to change what it holds, as the CPC itself would: the lower ROM at `0000` or RAM, the BASIC or AMSDOS ROM at
`C000` or RAM, and the RAM banks the Gate Array's configurations allow in each slot (the 464 and 664 have the first four
only)),
breakpoints, port breakpoints and the port log work on the CPC's ports (`7Fxx` Gate Array, `BCxx`-`BFxx` CRTC,
`DFxx` upper ROM, `F4xx`-`F7xx` PPI, `FA7E`-`FB7F` disc), step back included. The 464, 664 and 6128 have labels
(`roms/cpc464.sym`, `cpc664.sym` and `cpc6128.sym`): the firmware jumpblocks (`KM_WAIT_KEY`, `TXT_OUTPUT`...), the
indirections, the kernel and its system variables, and the routines of the lower ROM, those the jumpblock leads to
as `KM_WAIT_KEY_ROM` and the rest as in the 6128's commented source. Labels in the lower ROM (`0000`-`3FFF`) only
show while it is switched in, and those in `C000`-`FFFF` while the BASIC ROM is; the jumpblocks and the variables
are in RAM and always show (the low kernel at `0000`-`003F` too, as it is in RAM as well). The 664 and 6128 also
have labels for the AMSDOS ROM (`roms/amsdos.sym`: the RSX commands, the BIOS and extended jumpblocks, the disc, FDC,
cassette-over-disc and file routines, and the disc workspace variables), which show only while AMSDOS is the upper ROM in
use (`ROM2` in the slot list).

**Not emulated**: the CPC+ range and the GX4000 (only its CRTC chip types are there, as above); the CRTC's cursor,
light pen and interlace modes (R8 bits 0-1, R10, R11); the Gate Array's sub-microsecond pixel timing (colours and modes change at
whole characters); the 464's DDI-1 and other disc interfaces; expansion RAM beyond the 6128's 128K and expansion
ROMs; the printer port, the Multiface, the light gun, mouse and speech; the instruction times come from Caprice32's
tables and were not measured on a real machine.

### SAM Coupé

The SAM Coupé (MGT, 1989: a Z80B at 6 MHz, 256K or 512K of RAM, the ASIC, a WD1772 disk controller and the SAA1099 sound chip) is
the last machine of the list: the chip button's menu has it after the two families, as an entry of its own (no sub-menu), or
`--model sam` (or just `ochenta sam`, `ochenta sam game.mgt`). Its 32K ROM (version 3.0, `samcoupe.rom`) and the SAMDOS 2 disk
(`SAMDOS2.dsk`) are in `roms/` with the others; another ROM file can be chosen in Settings > Common > ROMs (SAM Coupé, ROM 0).
Without the ROM, choosing the SAM Coupé says so and the machine stays as it was. With "Boot SAMDOS automatically" (Settings >
SAM Coupé > DOS, `--sam_autodos`, on by default) the SAM starts, resets and is chosen with `SAMDOS2.dsk` in drive 1, booted as a user would
(the ROM's first screen, a key, F9): with a disk of your own in drive 1 (opened from the menu, dropped or on the command line) or a command
line that types or loads something it does nothing, so your disk or your tape is what runs. On the command line a disk for the SAM Coupé
(`--disk`, or a `.dsk`/`.mgt`/`.sad` given as a file) goes in after SAMDOS has booted: SAMDOS goes in drive 1, boots, and when its DOS is in memory
the disk asked for takes its place (with `--no-sam_autodos` the disk boots by itself).

What is emulated, written from the SAM Coupé Technical Manual (`src/Sam.pas`, the ASIC; `src/SpectrumSAM.inc`, its join to the Z80,
the sound, the tape and the disk controller, which the other machines share; `src/WD1772.pas`; `src/SAA1099.pas`;
`src/DiskFormat.pas`, the disk image formats):

- **The CPU at 6 MHz**: a frame is 312 lines of 384 T-states (about 50 Hz) and the ports take their 4 T-states. The "CPU speed" setting works as
  on the other machines.
- **Contention** (Settings > ZX Spectrum > Machine, "Memory contention", as on the other machines; off above 1x speed): the ASIC holds every access of the CPU to
  RAM (the ROM is free) and to the ports to a grid of 4 T-states, of 8 while it is reading the picture (the whole screen area: modes 2, 3 and 4 with the
  screen on; in mode 1 the left half of the line as well). It was found from what the ROM's tape routines and the games need: the turbo tapes load and the games
  that wait for the beam (`LPEN`/`HPEN`, below) run, but the exact edges of the grid are an approximation: programs timed to the cycle may differ from the real thing.
- **The beam's place**: port `F8` (`LPEN`) reads the beam's X position and port `01F8` (`HPEN`) its line (0 is the first line of the screen, so 191 the last): the games that
  synchronise with the raster read them. There is no light pen.
- **Memory**: 512K (or 256K, Settings > SAM Coupé) in 32 pages of 16K, and the 32K ROM. LMPR (port `FA`) pages the low block: the page at
  `0000` (ROM0 or RAM, by bit 5; bit 7 write-protects it) and the next page at `4000`; bit 6 puts ROM1 over `C000`. HMPR (`FB`) pages the
  high block: the page at `8000` and the next at `C000`. A page the machine has no RAM for (above 15 on a 256K one) reads `FF`.
- **The ASIC's video**: the four screen modes chosen by VMPR (`FC`: bits 0-4 the page, 5-6 the mode): mode 1 (the Spectrum's layout with 32x24
  attributes, flash), mode 2 (an attribute for each row of 8 pixels), mode 3 (512x192, 4 colours of the CLUT group HMPR bits 5-6 choose) and
  mode 4 (256x192, 16 colours), the 128-colour palette through the CLUT (port `F8`, the entry in the high byte of the address), the border and screen
  off (port `FE`). A line is drawn in cells of 4 T-states (16 pixels of the screen, 6 of the border) as the beam goes by, with the registers it has then,
  so the effects done with the line interrupt (colours or mode changed from line to line: the 128 colours on screen) show, and so do the border and the
  colours changed in the middle of a line (the SAM's "border scrollies" and raster bars) from the next cell on.
  The picture is the same 352x288 as the other machines' (the mode-3 pixels one column each).
- **Interrupts**: FRAME (at the start of the frame, 50 times a second), LINE (port `F9`: while the beam is hidden at the end of the line before the one given, so a handler can change the colours before the line is drawn) and
  STATUS (port `F9`, 0 = requesting, with the keyboard's K6-K8).
- **Keyboard** (see [Keyboard](#2-keyboard)): the 9x8 matrix through ports `FE` and `F9`, and a Kempston joystick on port `1F`.
- **Mouse** (Settings > SAM Coupé, `--sam_mouse`, off by default): moving the PC mouse over the picture moves the SAM's (the pointer is hidden over the picture; the
  left, right and middle buttons are its buttons 1 to 3). It is read as the SAM's mouse interface is, through the keyboard port with its high byte `FF`: two
  header nibbles, the buttons (0 = pressed) and the X and Y counts in 12 bits, nibble by nibble, and a read after a pause of about a millisecond starts the sequence
  again. One count is one pixel of the screen; Y grows upwards. It was made from the interface's description, with no mouse software at hand to try it.
- **Clock** (Settings > SAM Coupé, `--sam_clock`, on by default): the real-time clock of the SAMBUS interface (an OKI MSM6242: the digits of seconds, minutes, hours, day,
  month and year, ones then tens, and the day of the week, in the registers `0`-`C` that the high byte of the port address chooses, at port `EF`) follows the PC's clock;
  the control registers `D`-`F` (24 or 12 hours) can be written. The Dallas clock of some interfaces is not emulated.
- **Sound**: the beeper (port `FE` bit 4) and the SAA1099 (data at port `FF`, the register with address bit 8 set: `01FF`), in stereo: six tone
  generators with their octave and frequency (middle C is octave 3, 33: 261.5 Hz as the manual says), two noise generators, two envelope generators
  and an amplitude for each side of each channel. Settings > SAM Coupé switches it off (it keeps running).
- **Tape**: the same signal as the Spectrum's (the SAM Coupé's ROM saves and loads at the Spectrum's standard speed): EAR in port `FE` bit 6, MIC/EAR out
  recorded by REC. The tape's pulse lengths are in T-states of a 3.5 MHz machine and are scaled by 12/7 to the 6 MHz clock. There is no ROM trap, but with
  "Fast loading" on a tape that is playing makes the emulator run as fast as it can (as for turbo tapes on the Spectrum); Auto play/stop works, from the EAR reads.
  The turbo tapes of the SAM (`Tetris`, `Manic Miner`, `Astroball`, `Kreuzen`...) load, which needs the contention above. `LOAD ""` and `SAVE "name"` ("Start tape and then press a
  key" first) work, and recording to a TZX and loading it back was tested with the ROM's own SAVE and LOAD. File > Open of a tape resets the machine, types
  `LOAD ""` (after the first screen's key) and presses Play; `--tape` only inserts it.
- **Disk**: one WD1772 for the two drives, at ports `E0`-`E3` (drive 1) and `F0`-`F3` (drive 2), the side chosen by address bit 2 (so `E4`-`E7` are the second
  side), with its commands: restore, seek, step, step in/out, read and write sector (single and multiple), read address, read track, write track (format) and
  force interrupt; the index hole passes once a turn (the ROM tells there is a disk by it). At real drive speed unless "Fast floppy disk access" is on
  (Floppy menu or Settings > Common > Storage), with the drive's noise as on the other machines. With it on, **SAMDOS loads are trapped**: when the ROM asks the
  DOS to load a whole file that is on a SAMDOS disk in a drive (the hook the ROM uses for `LOAD`), the file goes into memory at once, with the paging and the head
  position as the DOS leaves them, and the DOS isn't run; the file `AUTO` (what `BOOT` loads) and files loaded in pieces are left to the DOS, because the programs
  that follow read the disk with routines of their own, which expect the DOS's own state. And while a drive is in use the emulator runs as fast as it can. The disks are the same `DSK` images the +3 and CPC use, of any
  geometry, so the SAM Coupé reads what the software on it can read.

**Disk images.** What a file is is told by what it holds, not by its name (a `.dsk` can be a CPC's, a +3's or a SAM Coupé's):

| Format | What it is |
|---|---|
| MGT (`.mgt`, or a `.dsk`) | 819200 bytes: 80 cylinders, 2 sides, 10 sectors of 512 bytes, the two sides alternating track by track; also written back as one (Save disk) |
| SAD (`.sad`) | SAm Disk: the header `Aley's disk backup`, sides, cylinders, sectors and sector size/64, then the sectors, all of side 1 then all of side 2; written back as one |
| DSK, extended DSK | the CPC's container, with any geometry: what SAMdisk writes for a SAM Coupé disk (10 sectors of 512 bytes numbered from 1) is told from a CPC's disk by its tracks, not by its signature |
| raw 720K | 737280 bytes (80 x 2 x 9 x 512, CP/M) |

A SAM Coupé disk is accepted on the SAM Coupé only: on the +3 or the CPC the error says it is a SAM Coupé disk and that the machine is chosen in the
machine menu. The SAM Coupé accepts the +3's and the CPC's disks too (its controller reads them; CP/M and other DOSes know the formats). A file that
isn't a disk is told apart: a zip or gzip ("unzip it first"; compressed images aren't read), an empty file, a SAD or DSK with the data cut short or damaged
("corrupt"), and a size no disk has ("not a disk image ochenta knows"; SBT, SDF and DS2 are not supported). Nothing is written into the file until Save disk.
The disk browser (Floppy menu, [section 6](#6-disk-browser)) reads SAMDOS directories too: the files with their type (BASIC, number or string array, CODE, SCREEN$), the
page and address a CODE file starts at, their length, the space they take and whether they are hidden or protected; it exports a file to the PC (its data, without
SAMDOS's 9 byte header), imports one (a plain file becomes CODE at 32768; one with a +3DOS header, as the +3 browser exports them, keeps its type and start), renames and deletes,
and tells the free space. Opening a disk boots it as a user would: the ROM's first screen
waits for a key, which takes it to BASIC, and F9 (`BOOT`) loads the disk's DOS; a disk without DOS (a data disk, or a game that wants SAMDOS loaded first: boot a
SAMDOS disk, change the disk in drive 1 and `LOAD "AUTO"`) says `No DOS`, as on the real machine.

**Snapshots**: File > Save snapshot writes ochenta's `.e80` (the RAM, the CPU, the ASIC's registers, the CLUT and the SAA1099's registers); disks and tapes stay as they are.

**Debugger**: the same one. The slot list shows `ROM0` at `0000`, `ROM1` at `C000` and `RAM0`-`RAM31`; click a slot to choose what it holds (the ROM0 at `0000`, the
ROM1 at `C000`, or a page of RAM: it writes LMPR or HMPR as a program would; the pages go in pairs, so choosing the page of `4000` also moves `0000`'s). SAM Regs (the chip
button) opens a window, which can stay open, with the main ports (LMPR and HMPR, which are the direct access to the paging, VMPR, border, line interrupt,
status), the 16 CLUT entries and the SAA1099's registers, each with its value (hex, editable: writing it is like an OUT to the port) and the names of the bits
set, and what LMPR and HMPR put in the four sections. Step back, breakpoints and port breakpoints work on the SAM Coupé's ports. There are no labels for its ROM.
The **Adventure Debugger** works on DAAD games for the SAM Coupé (see [Adventure Debugger](#11-adventure-debugger)).

**Not emulated**: MIDI, the light pen, the screen's attribute port (`FF` reads `FF`), external memory (HMPR bit 7), the parallel and serial interfaces, the
Quazar and Blue Alpha interfaces and the Dallas clock; contention is an approximation (above), and a change of the picture's registers shows from the next 4 T-state cell, not to
the pixel. Not supported: tape and disk files in other formats than the above.

**Tests**: `tests/samtest.lpr` (run by `run-tests.sh`) tests the paging, the four screen modes and the CLUT, the interrupts, the keyboard, the WD1772 (restore, seek, read,
write, read address, not ready, write protect), the SAA1099 (the pitch of middle C, noise, silence), the tape's pulse scaling, the disk formats and which machine takes which, changing
machines, contention, the beam's ports, the mouse, the clock, the characters of the keyboard, the SAMDOS file system and snapshots, with a ROM of its own making; if a folder with the real `samcoupe.rom` (and `SAMDOSVersion2.0.dsk`, and `DAAD.MGT`) is given as `SAM_TEST_DIR` it also boots the ROM, answers BASIC, types every character,
saves a program to the tape and loads it back, boots SAMDOS from the disk, loads a screen with the DOS and with the trap and compares them, and reads a DAAD game's database. `tests/samrun.lpr` runs a SAM Coupé for N frames with a disk or tape, typed
keys and screenshots, and `tests/sambatch.lpr` tries every image of a folder (`tests/SAM-MANUAL-TESTS.md` lists what was tried).

**Settings** (Settings > SAM Coupé; in ochenta.ini the section `[SAMCoupe]`):

| Option | Setting |
|---|---|
| `--sam_memory K` | the RAM in K: `256` or `512` (the default); changing it resets the machine; `sam_memory` |
| `--sam_saa` | the SAA1099 is heard (on by default); `--no-sam_saa` mutes it; `sam_saa` |
| `--sam_joystick` | cursor keys and right Ctrl as a Kempston joystick (on by default); `sam_joystick` |
| `--sam_autodos` | insert and boot `SAMDOS2.dsk` on start, reset and choosing the SAM Coupé when drive 1 is empty (on by default); `--no-sam_autodos`; `sam_autodos` |
| `--sam_mouse` | the PC's mouse over the picture is the SAM's mouse (off by default); `--no-sam_mouse`; `sam_mouse` |
| `--sam_clock` | the SAMBUS clock, following the PC's (on by default); `--no-sam_clock`; `sam_clock` |

### MSX

Choose **MSX 2** in the machine menu (or `--model msx2`, or just `ochenta msx2`). It is a PAL machine: a Z80 at 3.579545 MHz, the PSG (an AY-3-8910) and the PPI, in slots built as on the real
machine: four primary slots, secondary slots under the expanded one (register at `FFFFh`) and the slot register at port
`A8h`. The first cartridge slot is slot 1.

- 128K of RAM in a memory mapper (ports `FCh`-`FFh`, 16K segments, in subslot 3-0), the sub-ROM in subslot 3-1,
  the disk interface in subslot 3-3, a clock chip (RP-5C01, ports `B4h`/`B5h`, that follows the PC's clock, with its battery-backed RAM) and the Yamaha V9938:
  128K of VRAM, the 512-colour palette (port `9Ah`), the indirect register port (`9Bh`), the display modes Graphics 3 to 7
  (screens 4 to 8, the VRAM interleaved in Graphics 6 and 7) and Text 2 (80 columns), sprites of mode 2 (8 a line, a colour
  for each line, CC, IC and EC), 192 or 212 lines, vertical scroll, the line interrupt and the commands (HMMC, YMMM, HMMM,
  HMMV, LMMC, LMCM, LMMM, LMMV, LINE, SRCH, PSET and POINT, with the logical operations). The commands are executed at once,
  which is faster than the real chip; a game that depends on their speed may run too fast.

The disk interface shares the primary slot of the RAM, as in the Philips machines, so the slot register keeps the value the
programs that page the memory themselves (the DAAD engines for MSX) expect while the disk ROM runs. With the Drive B
setting off, the disk ROM sees a single drive (it waits a second and a half for drive B at power-on, as on a one-drive
machine), and the programs that size themselves by the memory left by DOS get more of it.

**ROMs.** The MSX2 runs on ochenta's own ROMs, QUANTIKA: `roms/msx/QUANTIKA.ROM` (the 32K BIOS with FBASIC, a BASIC
compatible with MSX-BASIC 2.1; the machine starts with "QUANTIKA ROM with FBASIC 1.0", the date and time of the build and
its RAM and VRAM, white on dark blue, and its bottom row shows the date and time instead of the function keys, which
type nothing until `KEY n,"..."` gives them a string) and
`roms/msx/QUANTIKA_SUB.ROM` (the 16K sub-ROM), with `roms/msx/QUANTIKA_DISK.ROM` for the disk interface (see Disks below). They
come with ochenta and are still being completed. To use the original ROMs
instead, look for `MSX2.rom` (the 32K BIOS and MSX-BASIC 2 of an MSX2) and `MSX2EXT.rom` (its 16K sub-ROM), and for a
disk drive also `PHILIPSDISK.rom` (see Disks below); they are not distributed. Put them in `roms/msx/` and choose them with
`--rom "msx2,0,FILE"`, `--rom "msx2,1,FILE"` and `--rom "msx2,2,FILE"` (the disk interface) or in Settings > Common > ROMs, where
the MSX 2 has three: ROM (the main ROM), SUBROM and FLOPPY DISK (the disk interface's ROM). The first time the
MSX starts, a note says what it emulates, that it uses unofficial ROMs, and where to put the original ones; it is shown once
(`msx_notice` in the `[MSX]` section of the settings file, `--msx_notice` shows it again).

**Recent files.** *Tape > Insert recent tape & load* (or *Just insert recent tape*) and *Cartridge > Insert recent cartridge* list the last tapes and cartridges
inserted (the ones that fit the machine, as the recent disks and SD cards do); File > Open recent includes them too.

**Cartridges.** The *Cartridge* menu (in the modern interface the CART row of the Media palette, which takes the place of
the SD card) inserts a `.rom` file into slot 1 and restarts the machine, and ejects it. Opening a `.rom` (File > Open, drag and
drop, or on the command line) does the same. ROMs of up to 32K need no mapper; bigger ones have one of these, which is
guessed from the writes their code makes to the mapper registers, or chosen in *Cartridge > Mapper* (`--msx_cartmapper`):

| Mapper | Banks | Registers (writes at) |
|---|---|---|
| `plain` | none (16K, 32K or 48K at 4000h) | none |
| `konami` | 8K at 4000h (fixed), 6000h, 8000h, A000h | 6000h-7FFFh, 8000h-9FFFh, A000h-BFFFh |
| `konamiscc` | 8K | 5000h, 7000h, 9000h, B000h (the SCC's sound is not emulated yet) |
| `ascii8` | 8K | 6000h, 6800h, 7000h, 7800h |
| `ascii16` | 16K | 6000h, 7000h |

The guess is a heuristic: if a game does not start, try the other mappers from the menu (choosing one inserts the cartridge
again with it).

**Memory mapper.** The MSX2 has 128K of RAM in 16K segments chosen per page through the ports FCh-FFh (the mapper; MSX-DOS 2
needs it). Programs written for an MSX1, which has no mapper, may use those ports for something of their own: the ZX
Spectrum conversions on tape write to FEh, the Spectrum's border and beeper port, and with the mapper there that moves the
RAM under the program, which then crashes (*Mantis 1* is one). *Settings > MSX > RAM mapper* (`--msx_mapper`) says what to do:
`on` always keeps the mapper, `off` takes it away (the machine then has the 64K of an MSX1: no mapper ports, the segments the BIOS
leaves) and `auto`, the default, keeps it except when Auto load starts a tape, where it is off for that start (a disk, a
cartridge or a reset made afterwards has it again). It takes effect with the next reset.

**MSX 1 compatibility mode (slots).** The MSX2 here has its primary slot 3 expanded into four subslots (RAM, sub-ROM, RAM again and
the disk interface), with the subslot register at FFFFh. Some programs written for an MSX1, which has no expanded slot in
that place, break on it: they use FFFFh as ordinary RAM, or look for the RAM in a primary slot alone and take the wrong
one (*International Karate* restarts the machine when its tape has loaded). *Options > MSX 1 compatibility mode* (or *Settings >
MSX > Memory*, `--msx_compat`) gives the machine the slots of an MSX1: none is expanded, FFFFh is RAM, the RAM is slot 3 alone,
the sub-ROM is in slot 2 and cartridges stay in slot 1. There is no room then for the disk interface, so the machine has
no disk drive while it is on. It resets the machine, and is off by default. It is independent of the RAM mapper above (a
tape that starts the machine also turns the mapper off, with `auto`, but keeps the slots).

**Keyboard.** Each PC key is the MSX key in the same place (the international layout): Shift, Ctrl, Caps Lock, Esc, Tab,
Backspace (BS), Enter, Space, Home, Insert, Delete and the cursor keys are the MSX's; Page Up is CODE, Page Down GRAPH, End
SELECT and Pause STOP; the MSX's function keys are Shift+F1 to Shift+F5 (F1 to F5; the MSX's SHIFT is let go while
they are held) and Shift+F6 to Shift+F10 (F6 to F10, which on the MSX are SHIFT+F1 to F5), and also the numeric keypad's 1
to 5 (F1 to F5; the PC's F keys alone are the emulator's); the keypad's other digits are the digits. With "MSX: cursor keys and right Ctrl as joystick 1" (`--msx_joystick`, on by default) the cursor keys also move
joystick 1 and the right Ctrl is its first button.

| Setting | Command line | Settings file (`[MSX]`) |
|---|---|---|
| Cursor keys and right Ctrl as joystick 1 | `--msx_joystick` / `--no-msx_joystick` | `msx_joystick` (default on) |
| Mapper of the cartridges inserted | `--msx_cartmapper auto\|plain\|konami\|konamiscc\|ascii8\|ascii16` | `msx_cartmapper` (default `auto`) |
| RAM mapper (ports FCh-FFh) | `--msx_mapper auto\|on\|off` | `msx_mapper` (default `auto`) |
| MSX 1 compatibility mode | `--msx_compat` / `--no-msx_compat` | `msx_compat` (default off) |
| Show the note about the ROMs the first time the MSX starts | `--msx_notice` / `--no-msx_notice` | `msx_notice` (default on; off once shown) |

**Tapes (`.tsx`).** A `.tsx` file is a TZX one for the MSX (open it as a `.cas`): it adds the block 4Bh, data in the Kansas City
Standard that the MSX's cassette uses (a pilot tone and, for each byte, its start bits, eight bits and stop bits, each a number of
pulses), which is played as the same signal; the other blocks are the TZX ones. If it has a `TSX.LOAD` custom info block, Auto
load types the command it holds (`RUN"CAS:"`, `BLOAD"CAS:",R`...).

**Tapes (`.cas`).** A `.cas` file is a block-by-block image of an MSX cassette. Opening one (File > Open, drag and drop,
the command line or the tape controls) inserts it in the tape and, with Auto play, starts it as a user would: `RUN"CAS:"`
(or `BLOAD"CAS:",R` if the first file is a binary one) is typed and the tape plays when the program starts the motor. As
many tape programs say `BLOAD"NAME"` without the `CAS:` device (which a machine with a disk drive sends to the drive: "Disk I/O
error"), the machine starts without its disk interface, as a user holding SHIFT at power-on does (there is no Disk BASIC
then; reset the machine, or open a disk, to have it back). The tape
is played as the real signal (1200 baud FSK: a 2400 Hz pilot, then 0 bits as a cycle of 1200 Hz and 1 bits as two of
2400 Hz), so loaders that read it themselves work; with "Fast loading" on, the emulator runs as fast as it can while the
tape plays. The tape browser lists the files of the tape. A `.tap` (a ZX Spectrum tape) is refused on the MSX. Saving to
tape is not emulated.

**Disks.** The machine has a disk drive: the Philips WD2793 interface (its registers at 7FF8h-7FFFh), with drive A:
(and B: if "Drive B connected" is on), driven by the interface's ROM (Settings > Common > ROMs > FLOPPY DISK). By default
it is ochenta's own, `roms/msx/QUANTIKA_DISK.ROM`: it reads and writes disks, boots MSX-DOS 1 disks and game disks (with a
DOS kernel compatible with MSX-DOS 1), and has Disk BASIC (LOAD, SAVE, MERGE, RUN, BLOAD, BSAVE, FILES, LFILES, KILL, NAME,
COPY, DSKF, CALL FORMAT, CALL SYSTEM, AUTOEXEC.BAS, and the files: OPEN for input, output, append and random access,
INPUT #, LINE INPUT #, PRINT #, INPUT$, EOF, LOC, LOF, FIELD, GET, PUT, LSET, RSET, MKI$, MKS$, MKD$, CVI, CVS, CVD, DSKI$,
DSKO$, MAXFILES); BASIC's banner then says "QUANTIKA Disk BASIC extension 1.0" and it asks no date at power-on. The
original one is the disk ROM of a Philips MSX (the `PHILIPSDISK.rom` of its disk interface or the machine's own): copy it to
`roms/msx/PHILIPSDISK.rom` and choose it there. The disk ROM must suit the main ROM: `PHILIPSDISK.rom` calls into the
original BASIC and cannot run on ochenta's own main ROM (`QUANTIKA.ROM`, the default), and `QUANTIKA_DISK.ROM` runs only on
it; a disk ROM that does not suit the main ROM is left out, and so is a missing file: then the machine has no disk drive
(the Floppy menu says so; also with the MSX1 slot layout, above). The disk images are raw sectors (`.dsk`): 720K
(80 cylinders, 2 sides, 9 sectors of 512 bytes), 360K (40 cylinders, 2 sides, or 80 cylinders and 1 side; told apart by the
boot sector's media byte), and 180K, 320K and 160K ones; they are FAT12 volumes, and a .dsk is saved back as raw sectors
(never converted to an Amstrad DSK). **File > Open** of a `.dsk` inserts it in drive A: and restarts the machine, which
boots it (a DOS disk: its MSX-DOS to the `A>` prompt; a data disk or no disk: Disk BASIC starts, and runs AUTOEXEC.BAS
if the disk has it; `PHILIPSDISK.rom` first asks the date, which Auto load answers with ENTER). The Floppy menu and the disk browser work as on the other machines: the
browser shows the root directory of the FAT12 disk (name, type, size, attributes) and imports, exports, renames and
deletes files; new disks (Floppy > New disk) are formatted 720K. Disks made for MSX-DOS 2 need the DOS 2 kernel ROM, which
is not emulated yet (MSX-DOS 1 disks boot).

**Settings.** Options > Settings > MSX has the cartridge mapper (Auto-detect, Plain ROM, Konami, Konami SCC, ASCII8 or
ASCII16) and the joystick. Changing the mapper inserts the cartridge again with it.

Known issue on the MSX2: a SCREEN 2 to 8 typed in direct mode goes back to text when BASIC shows its prompt (the BIOS
calls its screen restore with the text mode it remembers; why a real MSX2 does not is not known yet), while a program keeps
its screen and the games are not affected.

**Cartridge browser.** The Cartridge menu's first option (enabled when a cartridge is in), the CR button (it takes the place of the SD card browser's, in the toolbar, in the modern interface's
Media palette and in the File menu; in the debugger's toolbar there is a cartridge button too) opens a window on the cartridge in
slot 1, with two tabs. *Info* has its name, file, size, mapper, banks (or where a plain ROM is shown), the ROM header (the `AB`
signature and the INIT, STATEMENT, DEVICE and TEXT addresses) and its CRC32. *Hex* is a hex dump of its bytes (offset, 16 bytes
in hex, and as characters) that can be edited, by typing hex digits or, after Tab, characters, and has a selection (mouse, or
Shift with the cursor keys; Ctrl+A selects all, Ctrl+G goes to an offset). A change is made in the running machine's ROM at once.
The buttons save the cartridge to its file (Ctrl+S) or to another one (Save as; that file becomes the cartridge's), import a block
(a file of the PC written into the cartridge from an offset; a cartridge keeps its size) and export a block (the selected
bytes, or an offset and a length asked for) to a file; closing the window with changes unsaved asks whether to save them. Escape
closes it, as in every browser (tape, disk, SD card and cartridge).

Known issue: Firebird (Konami, 1987) was reported to show its hero too high on the screen and blinking; it was not reproduced
here (the sprites are drawn as the V9938 manual describes) and is still to be looked at on a real machine's capture.

Not done yet: MSX-DOS 2, ZIP files with games, snapshots, DAAD on the MSX, the MSX2's timed commands and the debugger's
slot view (the ports window, below, shows what the slot registers hold).

In the debugger the chip button is **MSX Ports**: a window like the ZX-Uno's, which can stay open, with the slot registers (`A8h`
and the subslot register of slot 3, with the slot each page shows), the PPI's port C, the mapper's segments (`FCh`-`FFh`), the PSG's
registers, the VDP's registers R#0-R#23 and R#32-R#46 (with the names of their bits), its status registers S#0-S#9 and the 16
palette colours. Select a value, type a new one (hex; a palette colour is three digits, R, G and B) and press Enter to write it.
The VDP's TMS9918A modes (Graphics I and II, Text and Multicolor) wrap their address at 16K as the MSX1 games expect; the V9938's
carry it into R#14.

The RAM of the machine is visible in subslots 3-0 and 3-2 (the same bytes), because game loaders look for it both ways: through
the primary slot alone and by writing a subslot register value that selects 3-2.

### Commodore 64

Choose **Commodore 64** in the machine menu (or `--model c64`, or just `ochenta c64`, `ochenta c64 game.d64`). It is a PAL machine: the 6510 at
985248 Hz, the VIC-II (the 6569: 312 lines of 63 cycles, 50.12 frames a second), two CIAs (6526), the SID (6581) and, on the serial bus, 1541 disk drives.
Everything runs one cycle at a time: every access of the CPU advances the chips, the VIC-II stops it on the bad lines and for its sprites' DMA as
the real chip does, and the 1541's own 6502 runs in step with it.

**ROMs.** They are the originals, which are not distributed: put `Kernal.rom` (8K), `Basic.rom` (8K), `Char.rom` (4K, the character generator) and, for the disk drives,
`VC1541.rom` (16K, the 1541's DOS) in the `roms/c64` folder. Their names can be changed in Settings > Common > ROMs (choose the Commodore 64 there). Without the
first three the machine does not start (ochenta says which are missing and stays as it was); without `VC1541.rom` it starts with no disk drive.

**The picture** is the 320x200 screen with a border of 16 pixels at each side and 44 lines above and below (352x288; the real border is wider), every pixel
twice as wide as in the VIC-II's own resolution. The VIC-II is drawn as the beam goes, cycle by cycle (eight pixels each), from the registers as they are at that cycle: the
raster bars and splits, the scroll registers, FLD and FLI (bad lines made or avoided by writing `$D011`), the 38-column and 24-row modes and
the tricks that open the side and top borders work. Standard and multicolour text, extended colour text and the standard and multicolour bitmaps are
there (the invalid combinations show black), the eight sprites with their expansion, priority, multicolour and DMA (they steal cycles from the CPU; the border
covers them, except where it is opened), the sprite-sprite and sprite-background collisions (detected under the border too), the raster interrupt, the 16K bank chosen by CIA 2 with the character ROM in banks 0 and 2, and the idle state that shows the
last byte of the bank (opened borders show it). Not emulated: the light pen and the exact timing of the VIC-II's unstable effects.

**Sound.** The SID is clocked cycle by cycle: three voices with triangle, saw, pulse and noise waveforms (combined waveforms are their AND, heard a little
quieter; noise combined with another waveform locks up until the test bit resets it), the ADSR envelopes
(with their exponential decay and rate counters), ring modulation, hard sync, the test bit, and the multimode filter (low, band and high pass, cutoff and
resonance, voices routed to it, voice 3 off). The volume register is heard by itself, so the digitised sound programs play. `$D41B` and `$D41C` read the third voice's
oscillator (its upper 8 bits, whatever the envelope) and envelope as they are at the cycle of the read, so the noise works as a random number generator.
The paddles read as released.

**The CIAs** have their two timers (one-shot or continuous, chained, force load, their output on PB6 and PB7 as a toggle or a one-cycle pulse), the
time of day clock (BCD, 12 hours with the AM/PM flag, stopped by a write to the hours until the tenths are written, latched by a read of the hours until
the tenths are read, the alarm, 50 or 60 Hz), the serial register (its output; the input is not emulated) and the interrupt mask.

**Keyboard and joysticks.** See [Keyboard](#2-keyboard). The keypad is a joystick (8, 2, 4, 6, the diagonals 7, 9, 1, 3 and the fire on 0, 5 or the right Ctrl) in the
control port Settings > Commodore 64 chooses (both ports by default, since some games, like Mikie, read port 1 and most read port 2; port 1 shares its lines with the keyboard, and a joystick there can type by
itself, as on the real machine). With Settings > Commodore 64 > *Cursor keys and Ctrl as a joystick* (on by default) the cursor keys and either Ctrl are the joystick (the fire button is Ctrl) and are not the C64's own cursor keys and CTRL; **Scroll Lock** switches between the two while running (to type with the cursor keys or CTRL, or to play). As on the real machine, a key of the keyboard in the same lines as the joystick (the space bar, CTRL...) also reads as a joystick direction or fire button in a game that reads port 2. The C= key is the PC's Tab.

**Tapes (`.tap`).** File > Open, Tape > Insert tape & load, drag and drop or `--tape`. A `.tap` is the C64's own format (`C64-TAPE-RAW`, versions 0 and 1; a Spectrum `.tap` has
no such header and is not one of these): its pulses are played into the CIA 1's FLAG line while the motor is on (bit 5 of the 6510's port) and PLAY is down, at the real speed, so
the KERNAL's loader and the turbo loaders alike work. *Insert tape & load* resets the machine, presses PLAY and types `LOAD"",1,1` and, when it has finished, `RUN`.
With Tape > Auto play/stop (on by default) PLAY is down whenever there is a tape that has not reached its end, so "PRESS PLAY ON TAPE" does not wait for the button; with it off, the
Play/pause button (F8) is the PLAY key of the datasette (the machine says PRESS PLAY ON TAPE and waits for it). Stop, Rewind and Eject are as on the other machines.
Fast loading (Tape > Fast loading) runs the emulation flat out, muted, while a tape plays and the motor is on. SAVE to tape is not available on the C64. With **Settings > Commodore 64 > Disconnect the drives while a tape is loaded** (`--c64_tapenodrive`, on by default) opening a tape disconnects the disk drives (inserting a disk connects drive 8 again, and drive 9 comes back with its setting): some tape games, like Ghostbusters and Green Beret, refuse to load with a drive on the serial bus.

**Tape browser and Disk browser.** On the C64 they are simpler than the Spectrum's. The *Disk browser* (Floppy menu) lists the directory of the disk in drive 8 or 9 (name, type, blocks, size; a `*` before the type marks a file that was not closed); *Load* (or a double click) types `LOAD"name",8` and *Export...* saves the file as a `.prg`. The *Tape browser* (F7) lists the files the KERNAL saved on the tape (name, type, start and end addresses, size) and *Go to* puts the tape at the start of the one chosen; a tape that has a fast loader of its own has no KERNAL files to list. A `.t64` is not a tape the machine plays: its first program is loaded as a `.prg`.

**Programs (`.prg`, `.p00`, `.t64`).** Opening one (File > Open, drag and drop, the command line) resets the machine, waits for the BASIC prompt, puts the program in memory and
types `RUN` (if it starts at `$0801`, with its BASIC line) or `SYS` and its start address. A `.t64` (a tape container) loads its first program the same way.

**Disks (`.d64`).** Opening a `.d64` (35, 40 or 42 tracks, with or without the error bytes) puts it in drive 8 and, with File > Open, resets the machine and types `LOAD"*",8,1` and `RUN`. The Floppy
menu (drive A: is drive 8, B: is drive 9) and `--disk`, `--diskb` do the same for the drives, so inserting a disk in either drive also resets the machine and types `LOAD"*",8,1` (or `,9,1` for drive 9) and `RUN`, unless Alt or AltGr is held (as for every machine; the hint of the Media drives says so too): *Insert disk*, *New disk* (a formatted empty `.d64`), *Save disk* (as
`.d64`; also the disk the drives have written, see below) and *Eject*. The drive is a real 1541: its 6502 runs `VC1541.rom`, with its two 6522 VIAs, 2K of RAM, the stepper motor moving
the head half a track at a time, the motor and the LED, the disk turning at 300 rpm with the four speed zones (the bytes of every track come under the head one by one, 26 to
32 cycles each, as GCR with its sync marks, headers, data blocks and gaps), the write protect sensor and the byte-ready signal that sets the overflow flag; and the
serial bus (ATN, CLK and DATA, open collector, with the drive answering ATN by itself) joins its VIA to CIA 2. Everything the DOS does is the DOS's own: LOAD, SAVE, `OPEN` and the
command channel (`NEW`, `SCRATCH`, `VALIDATE`...), the fast loaders that run code in the drive, the formats. What a program writes is decoded from the GCR the head wrote back
into the image, so a disk formatted or saved to in the emulator is a real `.d64`. With **Settings > Commodore 64 > What the drives write goes into the .d64 files** (`--c64_savedisk`, on by
default) the file is written once the drive has been quiet for a moment and when the disk is taken out; with it off the changes are kept in memory until the disk is ejected unless Floppy > Save disk
is used. A `.d64` that is read-only on the PC is a write-protected disk. The error bytes of the `.d64` (no sync, header or data not found, checksum and ID errors) are reproduced, for copy protections that read them.
**Fast floppy disk access** (Floppy menu) runs the emulation flat out, muted, while a drive works: without it a disk loads at the real speed (a 1541's: about 400 bytes a second). At that speed the drive is heard, as the other machines' drives are, with Settings > Common > Storage > Emulate floppy drive noise (`floppynoise`, on by default): the motor turning, the head scratching the disk as it turns under it, a knock for each step of the head (a seek is a buzz of them) and the rattle of the head hitting its stop at track 0. While the disk turns and no step has been heard for 3 seconds, the head moves now and then by itself.
The second drive (device 9) is connected with Settings > Commodore 64 > Second disk drive, with the Floppy menu's "Drive 9: connected" (the "Drive B:" entry), with `--c64_drive9`, or by giving it a disk. `G64` images, the 1571 and the 1581 are not emulated.

**Not emulated**: cartridges (`.crt`) and the expansion port, the user port and RS-232, the REU, `.t64` and `.g64` files, tape recording (SAVE to tape), snapshots, the datasette's
sound, the 8580 SID and the filter's exact curve. The sound is mixed in mono.

**Debugger.** Machine > Debug > Debugger (F12) opens the 6510's own debugger (the Z80 one is the other machines'), laid out and used like the Z80 debugger and with the same colours: the
disassembly in the middle, on its right the registers with the stack on their right and under them the ports and the zero page side by side, and at the bottom the memory, the breakpoints and the
watches. Its title is *Debugger*, as the Z80 one's. Closing it carries on running, Escape closes it (after ending an edit, or the typing or selection in the memory zone) and the keys go to the main
window again; the hints of the menus and the toolbar show in the status bar. Every value is changed
where it is shown: a click opens a box over it (a hex number, or an expression; Enter applies, Escape cancels). A right-click on any address, 16-bit value or label offers *Go to* (in the
disassembly) and *View data at* (in the memory), as in the Z80 debugger. Ctrl+G (go to, in the disassembly or the memory) lists the last 10 addresses gone to, and its *Go to PC* button goes
to the execution point without adding it to them. The toolbar runs (F5) and breaks, steps into (F7) and over (F10: a JSR runs as a whole), steps out (F11: to the address
the stack returns to), runs to the selected line (F9), steps back (Shift+F7, see below), goes to an address (Ctrl+G), puts or takes away a breakpoint on the selected line (F8, or a click on the gutter or a double-click on the line),
removes all the breakpoints, adds a watch, loads symbols and opens the *chips* window; after a separator, the 6502 button opens the table of opcodes (see below).
*Step back* (Shift+F7, or its toolbar button), as in the Z80 debugger, puts the machine back where it was before the last step into, step over, step out, run to cursor or run, up to 10 times:
the 6510, all the RAM and the colour RAM, the VIC-II (and the picture drawn so far), the SID, the CIAs, the place on the tape and the 1541 drives (their 6502, RAM, VIAs and head). What a drive wrote
to a disk is not undone.
*6502 opcodes*: the 6502's instruction set (the 6510 runs it) as one 16x16 table, made and used as the Z80's: the opcode's high digit on the left and the low one on top, the instruction in each cell
(operands as n for a byte, nn for an address, e for a relative jump: `LDA (n),Y`, `JMP (nn)`, `BNE e`), all in bold and the undocumented opcodes in dark red. Resting the mouse on a cell for a second
shows what the instruction does, as in the disassembly (with what is undocumented about it, its flags, its addressing mode, its bytes and its cycles). The window is square, with the letters as big as
fit (the operands go on two lines when that makes them bigger). The box on top (Find instruction) marks, as you type, every instruction with that text (`LDA`, `(n),Y`, `#n`...) in light blue. It has
no tabs: there are no prefixes. Escape closes it.
*Disassembly*: the program counter in green and the breakpoints in red (`E`, `R`, `W` or `A` in the gutter, `?` if conditional, pale if switched off), the mnemonics blue (bold dark red
for the undocumented opcodes, as in the Z80 debugger), A, X and Y bold, and a name stands for the address it has with its value in grey brackets; at the program counter a conditional branch shows a tick or a cross: taken or not.
Over a mnemonic, after a second, a hint says what the instruction does, the flags it changes, its addressing mode, its bytes and its cycles; over a hex number its decimal value (and its names) shows;
all 105 undocumented opcodes are disassembled with the names of *No More Secrets* (NMOS 6510 Unintended Opcodes, groepaz, 2015: `SLO RLA SRE RRA SAX LAX DCP ISC ANC ALR ARR SBX LAS NOP JAM SHA
SHX SHY TAS ANE`, `LAX #` for `$AB` and `SBC #` for `$EB`), and their hint adds whether they are stable, the instructions they combine, their other names (`KIL`, `AXS`, `LXA`, `ISB`...) and what to
beware of (the "magic constant" of `ANE` and `LAX #`, the high byte of `SHA`, `SHX`, `SHY` and `TAS`);
over a label, its description. Click an instruction's byte to change it. It follows the program counter while the machine is stopped; scroll with the wheel, the cursor keys or Page Up/Down (Shift: `1000` hex,
4096 bytes; Ctrl: 1024), Home and End go to `0000` and `FFF0`, Backspace goes back to where the view was before the last jump, Ctrl+F searches the lines (an address, bytes, a mnemonic, a label) and F3
searches again. Its right-click menu: go to an address, search, export as assembler (a range as 6502 source for 64tass and the like, its first line saying it is in 64tass format: `* = $C000`, labels for the jumps and branches, `NAME = $ADDRESS`
for the names outside it, `.byte` for the undocumented opcodes), add or edit a label, run to here, set the PC here, and the breakpoint on the line: put or take away, its type (execution, read, write,
read or write), with a condition, enabled, remove.
*Names*: the labels of `roms/c64.sym`, loaded automatically, are the ROMs' own names (the BASIC's from Microsoft's source, the KERNAL's from Commodore's, the system variables' from the memory map,
with the description of each routine as its hint, made from [pagetable.com/c64ref](https://pagetable.com/c64ref/)). The BASIC ROM's labels (`A000`-`BFFF`) apply only while the BASIC ROM is paged
in, the KERNAL ROM's (`E000`-`FFFF`) only while the KERNAL is, and the chips' registers (the VIC-II, SID and CIA names) only while the I/O is: with RAM there, the code there is the program's. The
symbols of a file loaded with the Symbols button (lines `NAME = $ADDRESS`, as the assemblers write them; the DAAD interpreter's `.sym` files for one) and the labels added from the menu come first.
*Registers*: A, X, Y, SP, PC and P, all in hex (click one to change it; dark red if the last instruction changed it), the flags (click to toggle, hint over each name), the interrupt lines (who holds
the IRQ: VIC, CIA1; the NMI: CIA2), the processor port's DDR and PORT bytes (click to change them) and the memory configuration, on two lines: what is paged in at `$A000` and `$D000`, then at
`$E000`. Click it (or the bank number) to choose one of the eight configurations of LORAM, HIRAM and CHAREN from a menu. *Stack* (on the registers' right): from SP upwards as 16-bit words, `>`
marking the top; click one to change it, the wheel scrolls. *Ports*, as the Z80 debugger's: the last 50 accesses of the processor to the chips' registers (the VIC-II, the SID, the CIAs, `DE00`-`DFFF`;
not the colour RAM) and to the 6510's port (`0`, `1`): the instruction's address, the register, `R` or `W` and the value, dark red if the last instruction made the access; `>` marks the latest, the
wheel scrolls, and after a step the latest shows again. *Zero page*: its 256 bytes, 8 a row
(click one to change it; right-click: a watch, read and write breakpoints).
*Memory*: a hex dump with its characters, with the Z80 debugger's tools: an *XOR* box (every byte is shown and typed XORed with that hex value), a *RAM only* switch (show and change the RAM under the
ROMs and the I/O instead of what the processor sees), click a byte to change it or the text column to type text there, drag over the text column to select, Space for the sprite mode (each 8 bytes as
an 8x8 cell), and a right-click menu: go to, add a watch, read and write breakpoints (on the byte or the selection), copy as text, copy values (`$3E,$01,...`, Ctrl+C), paste (Ctrl+V), search text or
hex bytes (Ctrl+F, F3), export and import as text, export and import as binary.
*Breakpoints*: execution, read and write, on an address or a range, each with an optional condition, switched on and off with its box (Insert adds, Delete removes, Enter or a double-click edits,
Space switches); the right-click menu also shows it in the disassembly, removes them all and saves and loads them as JSON (the files of `--breakpoints`). The dialog that adds or changes one has a
type list, the end of a range, an *Enabled* box and the conditions' manual. A breakpoint stops the machine at the instruction that did the access. *Watches*: expressions shown in hex and decimal
(Insert adds, Delete removes; saved and loaded as JSON from the right-click menu).
The *chips* window has a *Registers* tab with the registers of the VIC-II, the SID (the values last written: its registers are write-only) and the two CIAs, each changed in place (the hint names it),
and a *State* tab with the 6510's port and the memory configuration, the VIC-II's registers decoded, the CIAs, the drives with their program counter, track, motor and LED, the serial bus and the tape.
Conditions and watches use the debugger's expressions: hex numbers (`$C000`, or just `C000`), decimal ones after a dot (`.10`), the registers `A X Y SP PC P`, the flags `#N #V #B #D #I #Z #C`, names
(yours, the labels of `c64.sym`, the KERNAL's entry points and the chips' registers: `PC=CHROUT`, `@VIC_RASTER=.100`), `@x` (the byte at an address), `T` (how many times the breakpoint has been reached),
`+ - * / MOD & |`, `= <> < > <= >=`, `AND OR XOR NOT` and parentheses: `A=3 AND X>.10`, `@D020=0`, `#Z=1 OR PC>=E000`. A range has no condition. The command line's `--bp`, `--bpr`,
`--bpw` and `--bprw` (with a condition: `--bp 'C000 if A=3'`) and `--breakpoints` work on the C64's addresses. A change of machine closes it (and its chips window).

**Adventure Debugger.** Debug > Adventure Debugger (F11) works on the DAAD interpreter for the Commodore 64 (the database's header says machine 2): the database is where the interpreter puts it, `$3880`, and the 256 flags
(then the objects' locations) are 514 bytes before it, at `$367E`. The condacts are followed as on the other machines (the interpreter's fetch is learnt as the game runs); see
[Adventure Debugger](#11-adventure-debugger).

**Settings** (Settings > Commodore 64; in `ochenta.ini` the section `[Commodore64]`):

| Setting | Command line | ochenta.ini |
|---|---|---|
| Numeric keypad and right Ctrl as a joystick | `--c64_joystick` / `--no-c64_joystick` | `c64_joystick` (default on) |
| Cursor keys and Ctrl as a joystick | `--c64_cursorjoy` / `--no-c64_cursorjoy` | `c64_cursorjoy` (default on) |
| Control port of that joystick | `--c64_joyport 1\|2\|3` (3: both) | `c64_joyport` (default `3`, both) |
| Second disk drive (device 9) | `--c64_drive9` / `--no-c64_drive9` | `c64_drive9` (default off) |
| What the drives write goes into the .d64 files | `--c64_savedisk` / `--no-c64_savedisk` | `c64_savedisk` (default on) |
| Disconnect the drives while a tape is loaded | `--c64_tapenodrive` / `--no-c64_tapenodrive` | `c64_tapenodrive` (default on) |

**Tests**: `tests/c64cputest.lpr` (needs no ROMs: the 6510's flags, decimal mode, addressing modes and cycle counts (every documented opcode against the
Programmer's Reference Guide's table), interrupts, undocumented opcodes, the CIA's time of day clock and timer outputs, the VIC-II's border over the
sprites, the SID's voice 3 as read by the CPU, the `.d64` GCR coding and the debugger's expressions) and, when the four ROMs are in `roms/c64`,
`c64spec`, `c64sound` (the SID plays a note at its pitch), `c64tape` (a program made by `tests/mkc64tap.py` loads from a `.tap`), `c64save` (SAVE and LOAD on a new `.d64`, and a second drive), `c64back` (the step back: the machine kept while the 1541 works, put back, runs on the same again) and, with `C64_DAAD_D64` set to a `.d64` of a DAAD game,
`c64daad` (the Adventure Debugger follows its condacts), all run by `run-tests.sh`. `tests/c64run.lpr <roms/c64> [frames] [d64 or tap] [commands]` boots the machine and prints its screen as text (`C64PPM=file.ppm` saves the picture).

### ochenta snapshots (.e80)

.z80 and .sna snapshots can't hold the ZX Spectrum Next or the ZX-Uno, so ochenta has its own
format: File > Save snapshot (F3) saves a `.e80` on those two machines, and on the others it is
a choice in the dialog's file types (.z80 stays the default, then .sna and .e80; the name's
extension, or else the type chosen, decides). Opening one (File > Open, the command line or
dropping it on the window) switches to its machine and carries on where it was saved. It holds
the whole machine: the CPU, all the memory (the 128K models' eight banks; the ZX-Uno's 512K of
SRAM; the Next's 2 MB with its ROMs, Multiface and DivMMC memory), the registers and ports, the
display (ULAplus, Timex modes; the Next's palettes, sprites, copper, Layer 2), the Next's DMA,
the AY chips, the DivMMC's paging and RAM and the Currah µSpeech's ROM paging (the SAM Coupé's: its 512K, the ASIC's registers and CLUT and the SAA1099's). It doesn't hold
the SD card (the Next keeps its own card; on the others the card in use stays), +3 disks, tapes
or the ZX-Uno's flash (made again from its BIOS and ROMs files). The file is `EMU80SNAP`, a
version byte (1), the machine's `--model` name (a length byte and the name: `48k`, `zxnext`...),
then the machine compressed with zlib in the order of `SnapIO` in `src/OchentaSnap.inc`.

## 5. Tape browser

Escape closes the window, as its close button does (while a name is being edited it only cancels the edit).

Tape > Tape browser (F7) lists the blocks of the tape, of any TZX kind (turbo data, tones,
pulses, recordings, pauses, groups, loops, texts, archive info...), with the size and checksum of
those with data (its window title shows the full path of the .tap or .tzx file, and "(modified)" if it has changes to save; a path too long for the title bar is
cut at its start, "...\games\jsw.tap", so the file name always shows, as in the disk and SD card
browsers): the current one is marked with `*` (`>`
while playing) and highlighted (green while playing, yellow when stopped), and the status bar
says where the tape is ("Playing block 3 of 10", "At the end of the tape"). Play at the end of
the tape starts it again from the first block. The toolbar buttons (hover for a hint) play, stop,
rewind, play from the selected block (a double-click on a block does it too), move the selected block up or down,
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
pure data with the ROM's bit lengths). Anything else (turbo loaders, recordings, tones, pulse
sequences, generalized data...) can't be skipped, as it is the game's own loader that reads it, so
it plays as on a real cassette: after a block loaded at once, if what comes next is a signal the
ROM can't read, the tape goes on playing by itself for the game's own loader. With fast loading
on, the emulator runs as fast as possible (and mute) while the tape plays like that, so those
blocks load in a fraction of their time without being altered: the tape and the CPU keep their
own T-state clock, pauses, loops and the rest of the flow included. With fast loading off the
tape plays at the CPU's pace as always.

Tapes are saved as .tap (Save tape as, and in the tape browser), which keeps only the data
blocks: with blocks from a .tzx that a .tap can't keep, ochenta asks first. Or as .tzx (on the Amstrad CPC,
.cdt: the same format), which keeps every block ochenta can play except CSW recordings, generalized data and the
flow control blocks (jumps, loops, calls and selections): it says so if the tape has any.

## 6. Disk browser

Escape closes the window, as its close button does (while a name is being edited it only cancels the edit).

Floppy > Disk browser, or the 3" disk button on the toolbar, lists the files on a disk (its
window title shows the drive and the full path of the disk image). Both are
only available when there is a disk to browse: in drive A:, or in drive B: if it is connected.
The browser opens on A: if it has a disk and on B: otherwise; the drive list at the top left
offers the drives that have a disk (and switches by itself if a disk is ejected). It shows them
as +3DOS sees them: name, type (Program, Bytes, Number array, Character array, or "(no header)"
for files without a +3DOS header), start address of Bytes or autostart line of a Program,
length, size on the disk and attributes (read-only, system, user area). The status bar shows how
much space is free.

On a SAM Coupé disk the browser shows SAMDOS's directory instead: name, type (BASIC, Number array, String array, CODE, SCREEN$), the page and address a CODE file
starts at, length, size on the disk and attributes (hidden, protected). Export saves a file's data without SAMDOS's 9 byte header; Import makes a CODE file at
32768 (a file with a +3DOS header, as the +3 browser exports, keeps its type and start address); rename and delete work; the file names are 10 characters.

The toolbar buttons (hover for a hint):

| Button | Action |
|---|---|
| Refresh | read the directory again (it also refreshes by itself when the emulated +3 writes to the disk or the disk changes). |
| Import | copies files from the PC onto the disk (several can be chosen at once). A file that already has a +3DOS header is copied as it is; for any other file you choose its name and either a Bytes (CODE) header with its load address (16384 is suggested for screens, 32768 otherwise) or no header at all (the header is ticked by default here). With several files, "The same for the other files" applies those choices to the rest, with their own names. If a file with that name is already on the disk, ochenta asks whether to overwrite it (Yes to all with several files). |
| Import a folder | (a folder with a blue arrow) copies a folder of the PC with its contents onto the disk. A +3 disk has no folders, so all the files inside the folder and its subfolders are imported side by side. The usual questions (name, +3DOS header, overwrite) are asked, with "for all" to apply the choice to the rest; a progress bar shows meanwhile. |
| Export | saves the selected files to the PC (also with a double-click): one with a save dialog, several into a folder you choose, asking before overwriting a file there. If they have a +3DOS header you can keep it or save only the data (a .bin, a screen...). |
| Rename | (F2) gives the selected file a new name (8 characters and an optional extension of 3). |
| Delete | (Del) removes the selected files and frees their space. |

Files and folders can also be dragged from the PC's file manager and dropped on the disk browser
window: they are imported as with Import and Import a folder (the files inside dropped folders
side by side).

Select several files with Ctrl or Shift + click. The import and export dialogs open in the
folder the disk browser used last (the SD card browser remembers its own); it is kept in
ochenta.ini.

Changes are made on the disk image in memory and mark it as modified; save it with Floppy > Save
disk (into its file) or Save disk as, or answer yes when ochenta asks on exit or before the disk is
ejected or replaced. The disk browser understands the standard +3 format and the formats
described by a disk specification (and the CPC system and data formats). A program running on
the +3 that is using the disk at that moment may not notice changes until it reads the directory
again.

## 7. DivMMC and SD cards

ochenta emulates the DivMMC interface: 8K of EEPROM with its firmware, 128K of RAM and an SD card,
with automatic paging (at `0000`, `0008`, `0038`, `0066`, `04C6`, `0562` and `3Dxx`, and back at
`1FF8`-`1FFF`) and ports `E3` (control), `E7` (card select) and `EB` (SPI data). It works on
every model. The firmware is esxDOS 0.8.9 (`esxdos/ESXMMC.BIN`, from
[http://www.esxdos.org](http://www.esxdos.org)); another one can be chosen in Settings > ZX Spectrum > Firmware.
The interface is connected in Settings > ZX Spectrum > Hardware.

**Changing hardware.** The DivMMC and its card follow the machine, each one remembering the card last used in it
(the card inserted from the SD menu, or saved as another file, while a machine is the current one is the one it
remembers): the standard models share `zx_sdcard`, the ZX-Uno has `zx_unocard` and the Next `zx_nextcard`.
- Switching to the **Next**: the DivMMC and the Kempston mouse are connected and the Next's last card goes in (made from its distribution
  the first time; see [ZX Spectrum Next](#zx-spectrum-next)).
- Switching to the **ZX-Uno**: the DivMMC and the Kempston mouse are connected and the ZX-Uno's last card goes in, if it has one (if not,
  the card that was in stays).
- Switching from the ZX-Uno or the Next to a **standard Spectrum**: the standard models' card comes back (the
  ZX-Uno's or the Next's goes out, its changes first saved or asked about) and ochenta asks whether to switch the DivMMC
  off; if not, it stays connected (the Kempston mouse is switched off).

The SD menu:

| Entry | What it does |
|---|---|
| SD card browser | see below (also the SD card toolbar button); only available with a card inserted. |
| Insert recent SD card | one of the last 10 card images used. |
| Use a PC folder as SD card | the card in the DivMMC is ejected (asking to save it if it was changed) and a temporary card is made with esxDOS (SYS, BIN, TMP) and the folder's files and subfolders in its root, their names turned into 8.3 names (two that would clash become `NAME~1`, `NAME~2`...). The machine then boots with it. The card lives in the temporary folder and is deleted when it is replaced, ejected or ochenta closes; if it was changed, ochenta offers to save it as an image file. The PC folder itself is never changed. |
| Insert SD card image | any raw card image (.img, .mmc, .hdf...). Inserting the one already in is refused. |
| New SD card | an empty card of 16 MB to 2 GB, with one FAT16 partition. |
| New SD card with ESXDOS | the same, with the esxDOS SYS, BIN and TMP folders already copied: ready to boot. |
| New SD card with the Next distribution | a card of the size chosen (as for the Next's own card) with the whole ZX Spectrum Next distribution and a `config.ini` (see [ZX Spectrum Next](#zx-spectrum-next)). |
| Save SD card | saves the changes into the image file it was loaded from. |
| Save SD card as | saves the card, with its changes, as another image file (the dialog starts in the folder it was loaded from); that file is then the card. |
| Eject SD card | |

What the Spectrum writes on the card, and what the SD card browser changes, is kept in memory
(only the 512-byte blocks that changed) until the card is saved: the image file stays as it was.
ochenta asks whether to save a modified card when it closes, and before the card is ejected or
replaced. Inserting or creating a card connects the DivMMC if it isn't. The card in use is
remembered for the next session. With the DivMMC on, the machine boots through esxDOS (about 5
seconds), and tapes and disks opened with File > Open wait for it. On the 128K models esxDOS
starts in 48K BASIC; its `.128` command goes back to the 128K menu. The NMI button (F5) opens the
esxDOS browser. Use `.ls`, `.cd`, `LOAD *"name"`, `SAVE *"name"` and the other esxDOS commands as
on the real interface.

### SD card browser

Escape closes the window, as its close button does (while a name is being edited it only cancels the edit).

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
name. A file is written in one piece when the card has a free stretch big enough for it (as on
a freshly formatted card): programs that read the card directly, such as .nex games that stream
their data with DISK_FILEMAP, need their file that way. esxDOS keeps some things in memory, so after changing the card from the browser
it may not notice the changes until it reads that folder again (or after a reset).

Files and folders can also be dragged from the PC's file manager and dropped on the SD card
browser window. Imported folders are recreated inside the folder the browser shows (with 8.3
names made from the PC names, or the PC names themselves on the Next's card), merging with
folders already on the card, and the files in them are copied as they are, without asking (no
+3DOS header). Files imported on their own ask the usual questions (name, +3DOS header), with
"for all" to apply the choice to the rest; overwriting a file is always asked. While several
files are imported a progress bar shows, and ochenta can't be used until it is over.

## 8. POKEs

Machine > POKE (F9) takes "address,value" pairs separated by ":", in decimal or in hex with
$, e.g. `35899,0 : 36000,201`. The last 20 POKEs are listed with the name of the file they were
used with (click one to use it, double-click to apply it). POKEs to ROM have no effect unless the
settings allow changing the ROM.

## 9. Sound

The beeper and the AY-3-8912 (128K and later) are mixed in ABC stereo. Settings > ZX Spectrum > Hardware turns
TurboSound on, and can add an AY chip to the 16K/48K, at the same ports as on the 128K (`FFFD`
and `BFFD`), as the AY interfaces for the 48K did. Mute sound (Options menu) silences everything
without changing the speed.

### Currah µSpeech

The Currah µSpeech (MicroSpeech) is a speech synthesizer for the 48K, with a General Instrument
SP0256-AL2 chip that speaks *allophones*, the sounds words are made of. It is connected in
Settings > ZX Spectrum > Hardware (or `--zx_currah`, ini key `zx_currah` in `[ZXSpectrum]`), which switches the machine
off and on; its ROM then shows "Speech System (c) CURRAH 1983" at the top of the screen. It needs
`currah.rom` (its 2K ROM) and `sp0256-al2.rom` (the chip's 2K mask ROM) in the ROM folder; both
come with ochenta.

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
does the same). Closing it carries on running. A change of machine (from the menu, by opening a file or a snapshot for
another one, or in the settings) closes it, and the Adventure Debugger, and the machine runs. Hovering over a hex value shows it in decimal, and, for a 16-bit one, after a dash the labels
with that value, if any (`16384 - USER, START`). The
window has five zones, each with a title: disassembly and registers on top, memory, breakpoints
and watches in the bottom third. The window is made to fit the screen: on a small one the
disassembly and the bottom zones show fewer lines, while the registers zone keeps all of its
lines. The toolbar has run, break, step into, step over, step out (F11: runs until the subroutine
returns, to the address on the top of the stack), run to cursor, step back, go to address, put or
take away a breakpoint on the selected line (F8), remove all the breakpoints and add watch; then
load symbols (as Debug > Load symbols) and the chips button (see below); run is greyed out while
running and break while stopped.

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

The chips button opens a window, which can stay open, with the machine's ports and the registers
of its chips (name, hex value and the names of the bits set), updated while the machine runs.
Select a value, type a new one and press Enter to write it: it is written as an OUT to its port
would (what was selected, as an AY or a CRTC register or a pen, is selected again), and is not
listed in the ports zone. On a ZX Spectrum (16K to +3): the ULA's port `FE` (the last value written:
border, MIC, EAR), `7FFD` (the 128K's paging: it keeps its lock) and `1FFD` (the +2A/+3's), the Timex
port `FF` and ULAplus' `BF3B`/`FF3B` when they are on, and the AY's register selected and its 16
registers (and the second AY's, with TurboSound) when there is one. On an Amstrad CPC: the Gate
Array's pen selected, the 16 pens and the border (hardware colours), the mode and ROM register, the
RAM configuration, the upper ROM, the CRTC's register selected and its 18 registers, the PPI's ports
(B, an input, can't be changed) and the PSG's register selected and its 16 registers. On the MSX it
is MSX Ports, and on the SAM Coupé SAM Regs (see their sections).

On the ZX-Uno it is ZXUno Regs: the
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

Double-click a line (or press Space or F8) to set or remove an execution breakpoint. Click an
instruction byte to change it. Right-click for: go to address, search, export as assembler, add
(or edit) label, run to here, set the PC here, toggle breakpoint, breakpoint type (execution, read, write, read/write), port
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
sjasmplus that assembles back to the same bytes (its first line says it is in sjasmplus format): ORG, an instruction per line (its address in a
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
the flags (X = set; resting the mouse on a flag's name for a second explains it), Bus (the data bus
value, FF by default: what an interrupt reads), IM, IFF1, IFF2, DI/EI and HALT. At the right of I
and SP, IM2 ADDR is where an IM 2 interrupt jumps to: I as the high byte and Bus as the low one,
and the word read there in brackets. Editing the address edits I and Bus (the Z80 uses the Bus
value in IM 2 interrupts), and editing the word in brackets edits the memory. Values changed by the last instruction are dark red (in AF, HL, DE, BC, IX, IY
and the alternate set, only the half that changed: `LD D,0` marks D, not E). Click a value to
edit it; click a flag, IFF1 or IFF2 to toggle it and IM to cycle 0-1-2.

Below: the top 8 stack entries (`>` marks the top), the last 8 port accesses (instruction
address, port, R for a read or W for a write, value; `>` marks the latest; the value is dark red
if the last instruction made the access) and what each 16K slot holds (ROMn, RAMn, or `----` for
no memory on the 16K; DIV for the DivMMC and SPCH for the Currah µSpeech's ROM when they are
paged in). The mouse wheel over the stack or the ports scrolls them (up to 50
entries: the last 50 port accesses are kept); after a step they show the top again. On the 128K
models, click slot 3 (underlined) to page another RAM bank in. A slot, or any of the DivMMC and
ZX-Uno values below, that the last instruction changed is dark red (128K/+3 paging, the DivMMC's
MMU and automap, MASTERMAPPER).

With the DivMMC connected, two more lines (the stack and port lists show 6 entries instead of 8)
show its paging: what is at `0000` (EEPROM, or RAM3 with MAPRAM) and the RAM bank at
`2000`-`3FFF`, and whether it is paged in or out; then CONMEM, MAPRAM and automatic paging
(automap). Click the bank (underlined) to choose another one, CONMEM to switch it, and automap
to page the DivMMC in or out. MAPRAM can't be switched off, as on the real interface.

On the ZX-Uno the DivMMC lines are always shown, and one more line below them (one stack/port
entry fewer): BOOTM (boot mode, click to switch it), MAPPER (MASTERMAPPER: the SRAM page at
`C000` in boot mode; underlined, click to choose another page; grey when not in boot mode, where it
does nothing) and LOCK. The debugger can change them even when MASTERCONF is locked. Slot 0 shows
BOOT for the boot ROM; RAM numbers are SRAM pages (ROMs are pages 8-11, the DivMMC firmware page
12 and its RAM pages 16-23).

On the SAM Coupé the slot list shows `ROM0`, `ROM1` and `RAM0`-`RAM31`, and every slot can be clicked to choose what it holds (see [SAM Coupé](#sam-coupé)); SAM Regs
(the chip button) opens its ports, the CLUT and the SAA1099's registers.

On the ZX Spectrum Next one more line (one stack/port entry fewer) shows the MMU: `MMU` and the eight registers
(`$50`-`$57`), the 8K page of each slot from `0000` to `E000` in decimal (`ROM` is 255). Click one to choose another
page from a two-level menu: `ROM` (only for the first two slots), and `1Mb` (pages 0-95) and `2Mb` (96-223), each a
list of pages. It is written as a `NEXTREG` would, so the paging and the register read through the Next's ports follow.

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
how much. Bytes on ROM are only written if Options > Settings > Common allows changing the
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
{"ochenta": "breakpoints", "version": 1,
 "memory": [{"address": "8000", "type": "exec", "enabled": true,
             "condition": "A = 3"}],
 "ports":  [{"port": "00FE", "type": "out", "enabled": true,
             "condition": ""}]}
```

(a range adds `"end": "80FF"` after the address or port)
(memory types `exec`, `read`, `write`, `access`; port types `in`, `out`, `any`)

```
{"ochenta": "watches", "version": 1, "watches": ["5C3A", "8000"]}
```

```
{"ochenta": "daad-breakpoints", "version": 1,
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
returns to the instruction after that byte), F11 step out (run until the subroutine returns: to
the address on the top of the stack), F9 run to the selected line, F8 put or take away a
breakpoint on it.

Step back (Shift+F7, or its toolbar button) puts the machine back where it was before the last
step into, step over, step out, run to cursor or run: the CPU, all the memory, the paging and the DivMMC
(not the sound, the tape or the disks). It goes back up to 10 times; a change of machine forgets them.

Ctrl+PgDn / Ctrl+PgUp move the disassembly and the memory zone 1024 bytes on or back, Shift+PgDn
/ Shift+PgUp `1000` hex (4096 bytes). Escape closes the debugger (after ending an edit, or the typing or selection in
the memory zone), and the keys go to the main window again, as when it is closed in any other
way. Ctrl+G (or the context menu) goes to an address: hex, a register name such as PC or HL, or
a label; the last 10 addresses are listed. Its "Go to PC" button goes to the execution point
without adding it to the list.

### Labels

The ROM routines and system variables are labelled from the .sym files in the roms folder (48K:
*The Complete Spectrum ROM Disassembly*; 128K, +2 and +3, including the +3DOS entry points: the
ZXSpectrumVault disassemblies; `tools/make-rom-symbols.py` rebuilds them; Amstrad CPC 464: the firmware
jumpblock, indirections and system variables from *Amstrad CPC464 Firmware Explained* and Don Thomasson's
memory maps, and the 664 and 6128 from the commented source of the 6128 firmware; `tools/make-cpc-symbols.py`; AMSDOS: named from the comments of its commented disassembly,
`tools/make-amsdos-symbols.py`).
ROM labels only apply
while that ROM is paged in. Your own symbols, as exported by SjASM / SjASMPlus
(`LABEL: EQU 0x8000`), are loaded with Debug > Load symbols or `--sym` and take precedence:

```
ochenta --sym game.sym game.tap
```

### ROM

The ROM can't be changed from the debugger unless Settings > Common > General allows it. Changes
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

It also works on the Amstrad CPC (DAAD games for the 464, 664 and 6128, from disc or tape): the
database is at `2880` in the RAM (the debugger reads the RAM even when the lower ROM is paged
over it) and the machine code in its header is 3. And on the SAM Coupé (DAAD games for it, with its interpreter): the database is at `0100`
in the RAM page the interpreter has in the low block (the debugger sees the memory as the CPU does, so it is there while the interpreter runs) and the machine code in its header is 9;
the game's disk needs SAMDOS in memory first (boot a SAMDOS disk, change the disk and `LOAD "AUTO"`). PAW and Quill are Spectrum engines only.

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
gets one); closing it carries on running, like Run. A change of machine closes it.

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

A PAW game is exported as it is to an SCE (PAW condacts, no object attributes). To a DSF, ochenta asks
whether to export it as a PAW game (the same) or to convert it to DAAD, as PAWS2DAAD does: DESC
becomes RESTART, INVEN the SYSMESS/LISTAT entry, SAVE, LOAD and PARSE get their 0, PROMPT becomes
LET fPrompt, TIMEOUT HASAT TIMEOUT, and condacts DAAD lacks (TURNS, SCORE, CHARSET, MODE, GRAPHIC,
LINE, PROTECT), those after a terminator and the words of the entries of PAW processes 1 and 2
are left as "PAWS2DAAD note" comments. The processes are arranged as in DAAD Ready's empty
database, whose definitions and processes 0, 1, 2 and 6 are added: the response table becomes
process 5, PAW processes 1 and 2 become 3 and 4, processes 3 to 6 go after the last one and the
rest keep their numbers (PROCESS calls are renumbered too). The system messages DAAD has and PAW
lacks come from the empty database, and process 1 gets the entry for PAW's auto-decrement flags
as a comment (remove its semicolons if the game needs them). After converting, ochenta reminds you
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
ochenta [options] [file]
```

A file (.tap, .tzx, .cdt, .sna, .z80, .dsk, .mgt, .sad, .nex, .e80, or the Commodore 64's .d64, .prg, .p00 and .t64) is opened as with File > Open, so a tape or disk is loaded
automatically. Options start with `-` or `--` and take their value as the next argument or after
"=" (`--model=128k`). Options are applied in this order whatever their position: machine, files,
symbols, breakpoints, typed keys.

| Option | Description |
|---|---|
| `--model M` | machine: `16k`, `48k`, `128k`, `plus2`, `plus2b`, `plus3`, `zxuno`, `zxnext`, `cpc464`, `cpc664`, `cpc6128`, `sam`, `msx2`, `c64` (also `+2`, `+2b`, `+3`). A CPC, the SAM Coupé, the MSX2 or the Commodore 64 can also be named alone: `ochenta cpc6128`, `ochenta cpc464 game.cdt`, `ochenta sam game.mgt`, `ochenta c64 game.d64` |
| `--speed N` | CPU speed 1, 2, 4, 8, 16 or 32 (as in Settings > Common > General) |
| `--scale N` | window zoom 1 to 4 |
| `--tape FILE` | insert a .tap, .tzx or .cdt without starting it (combine with `--keyin`; a Commodore 64 tape is a .tap) |
| `--disk FILE` | insert a .dsk, .mgt or .sad (a .d64 on the Commodore 64: drive 8) in drive A: (switches to the +3 unless `--model` says otherwise; a CPC 464 becomes a 6128; a SAM Coupe disk needs `--model sam`, and says so if it isn't); `--diska` is the same |
| `--diskb FILE` | insert a disk image in drive B: (connects drive B:) |
| `--sym FILE` | load a symbol file (also `-s`); the breakpoints given on the command line can then use its symbols, both as addresses (`--bp MAIN`) and in conditions |
| `--bp ADDR` | execution breakpoint at ADDR: hex or a symbol (`#NAME` forces the symbol) |
| `--bpr ADDR` | memory read breakpoint |
| `--bpw ADDR` | memory write breakpoint |
| `--bprw ADDR` | memory read or write breakpoint (any); also `--bpa` |
| `--bpin PORT` | port read (IN) breakpoint; PORT is hex, up to FF matches any high byte |
| `--bpout PORT` | port write (OUT) breakpoint |
| `--bpio PORT` | port read or write breakpoint (any) |
| `--keyin TEXT` | type TEXT on the keyboard once the machine has started (on the SAM Coupé: every character its keyboard can make (SHIFT or SYMBOL are pressed as its ROM wants), `\n` RETURN, `\w` and `~`, `\\` and `\~` for a backslash and a tilde; its first screen waits for a key, so `--keyin '\n~load ""\n'`. On a CPC: letters as they come, lower case, with SHIFT for upper case and the symbols of the CPC's keyboard, no escapes beyond `\n` RETURN, `\w` and `~`: `--model cpc464 --keyin 'run"\n'`; on an MSX: letters as capitals, the symbols of its keyboard, `\n` RETURN, `\w` and `~`, `\\` for a backslash). On the Spectrum: Letters and digits are their keys (so in 48K BASIC keyword mode "J" is LOAD), symbols are typed with SYMBOL SHIFT (" is SYMBOL+P). `~` waits half a second. Escapes: `\n` ENTER, `\w` wait one second. Example: `--keyin 'J""\n'` |
| `--zx_sdcard FILE` | insert an SD card image (connects the DivMMC) |
| `--zx_unocard FILE` | the SD card the ZX-Uno uses (the last one used in it); empty = none |
| `--zx_sdfolder FOLDER` | use a PC folder as the SD card (as SD > Use a PC folder as SD card; connects the DivMMC) |
| `--zx_sdadd "FILE,FOLDER"` | copy a PC file onto that card, into FOLDER (such as `/GAMES` or `/GAMES/ARCADE`; missing folders are created; without ",FOLDER" it goes to the root). The name on the card is the 8.3 form of the file name, and a file with that name is replaced. Repeat it for more files. The machine is then switched off and on so esxDOS sees them. Example: `--zx_sdcard my.img --zx_sdadd "C:\games\jsw.tap,/GAMES"` |

Every breakpoint option takes an optional condition, after "if" or a comma:

```
--bp "8000 if A=3"   --bpw "5C78,A=0"
--bpout "FE if A & 7 = 2"
```

**Settings and the Options menu.** Every setting has an option; what they set is kept in the
settings file like a change made in Settings. On/off options turn the setting on as `--name` and
off as `--no-name` (`--no-fastload`...). In ochenta.ini each one is a key with the same name
(see [Settings](#4-settings)):

| Option | Setting | Where |
|---|---|---|
| `--ui classic\|modern` | the interface (see [Interface](#interface)); modern if not given | Common > General |
| `--lang auto\|en\|es\|fr\|pt\|de` | the interface's language (see [Language](#language)); the settings' (automatic by default) if not given. Left Ctrl held at start overrides it | Common > General |
| `--monitor M` | the monitor, for any machine: `color` (the default), `bw` (black and white), `green` or `orange` (shades of a green or orange phosphor); `--bw` is the same as `--monitor bw` | Common > General |
| `--mute` | mute the sound | Common > General |
| `--volume N` | volume 0 to 100 | Common > General |
| `--scale N`, `--speed N`, `--model M` | (see above) | Common > General |
| `--turbo` | run as fast as possible (this session) | Options menu |
| `--zx_contention` | contended memory and I/O | ZX Spectrum > Machine |
| `--zx_snow` | ULA snow | ZX Spectrum > Machine |
| `--romedit` | allow changing the ROM | Common > General |
| `--zx_ulaplus` | ULAplus 64-colour palette | ZX Spectrum > Machine |
| `--zx_timex` | Timex screen modes | ZX Spectrum > Machine |
| `--zx_radastan` | Radastan mode (ZX-Uno) | ZX Spectrum > Machine |
| `--scanlines` | scanlines, from zoom 2x | Common > General |
| `--attachmouse` | the PC mouse can't leave the picture while the emulated mouse is in use (off by default); `--no-attachmouse` | Common > General |
| `--zx_deinterlace M` | how the picture is deinterlaced: `progressive`, `bob` or `weave` (the default) (see [Deinterlacing](#deinterlacing)) | ZX Spectrum > Machine, Options menu |
| `--zx_joystick J` | what the cursor keys + Ctrl emulate: `none`, `kempston` (the default), `sinclair1`, `sinclair2`, `cursor` or `fuller` | ZX Spectrum > Machine |
| `--zx_issue N` | keyboard issue 2 or 3 | ZX Spectrum > Machine |
| `--zx_turbosound` | TurboSound | ZX Spectrum > Hardware |
| `--zx_ay48` | AY chip on the 16K/48K | Hardware |
| `--zx_leftctrl` | the left Ctrl is CAPS SHIFT instead of the left Shift (off by default) | Machine > Controls |
| `--zx_kmouse` | Kempston mouse | ZX Spectrum > Hardware |
| `--zx_divmmc` | DivMMC interface | ZX Spectrum > Hardware |
| `--zx_currah` | Currah µSpeech | ZX Spectrum > Hardware |
| `--cpc_crtc C` | Amstrad CPC: the CRTC chip, `auto` (the one the model came with: type 0 on the 464, type 1 on the 664 and 6128; the default) or `0` to `4` (see [Amstrad CPC](#amstrad-cpc)) | Amstrad CPC |
| `--cpc_waitstates` | Amstrad CPC: the Gate Array's wait states, every access on the 1 MHz grid (on by default) | Amstrad CPC |
| `--cpc_joystick` | Amstrad CPC: cursor keys and right Ctrl as joystick 1 (on by default) | Amstrad CPC |
| `--sam_memory K` | SAM Coupé: the RAM in K, `256` or `512` (the default); resets the machine (see [SAM Coupé](#sam-coupé)) | SAM Coupé |
| `--sam_saa` | SAM Coupé: the SAA1099 is heard (on by default) | SAM Coupé |
| `--sam_joystick` | SAM Coupé: cursor keys and right Ctrl as a Kempston joystick (on by default) | SAM Coupé |
| `--c64_joystick` | Commodore 64: the keypad and the right Ctrl are a joystick (on by default) | Commodore 64 |
| `--c64_cursorjoy` | Commodore 64: the cursor keys and Ctrl (either) are a joystick, not the C64's own keys; Scroll Lock switches (on by default) | Commodore 64 |
| `--c64_joyport N` | Commodore 64: the control port of that joystick, `1`, `2` or `3` for both (the default) | Commodore 64 |
| `--c64_drive9` | Commodore 64: a second 1541, drive 9 (off by default; `--diskb` connects it too) | Commodore 64 |
| `--c64_tapenodrive` | Commodore 64: opening a tape disconnects the disk drives, as some tape games need (on by default) | Commodore 64 |
| `--c64_savedisk` | Commodore 64: what the drives write goes into the `.d64` files (on by default) | Commodore 64 |
| `--msx_joystick` | MSX: cursor keys and right Ctrl as joystick 1 (on by default) | MSX |
| `--msx_cartmapper M` | MSX: mapper of the cartridges: `auto` (the default), `plain`, `konami`, `konamiscc`, `ascii8` or `ascii16` | MSX |
| `--msx_mapper M` | MSX2: the RAM mapper's ports: `auto` (the default: off when Auto load starts a tape), `on` or `off`; from the next reset | MSX |
| `--msx_compat` | MSX2: the slots of an MSX1 (none expanded, so FFFFh is RAM; no disk drive); resets the machine (off by default) | MSX |
| `--msx_notice` | MSX: the note about the unofficial ROMs is shown the first time the machine starts (on until it has been shown) | MSX |
| `--sam_autodos` | SAM Coupé: Boot SAMDOS automatically (on by default) | SAM Coupé |
| `--sam_mouse` | SAM Coupé: the PC's mouse is the SAM's (off by default) | SAM Coupé |
| `--sam_clock` | SAM Coupé: the SAMBUS clock (on by default) | SAM Coupé |
| `--fastload` | fast tape loading | Common > Storage |
| `--autoplay` | start the tape automatically | Common > Storage |
| `--tapeloop` | continuous tape playback: at the end the tape goes on from its start (on by default) | Common > Storage |
| `--zx_savetotape` | SAVE writes to the tape | ZX Spectrum > Hardware |
| `--fastdisk` | fast floppy disk access | Common > Storage |
| `--driveb` | drive B: connected (default: no) | Common > Storage |
| `--floppynoise` | emulate floppy drive noise | Common > Storage |
| `--saveonexit` | save the settings when ochenta closes | Common > General |
| `--pngborder` | include the border in PNG screenshots | File menu |
| `--romdir DIR` | the standard ROM folder | Common > ROMs |
| `--rom "MODEL,N,FILE"` | ROM N of a model (0 to 3, as many as the model has), e.g. `--rom "48k,0,C:\roms\mine.rom"` or `--rom "sam,0,C:\roms\samco_v3.0.rom"`; an empty FILE goes back to the standard ROM | Common > ROMs |
| `--zx_divmmcrom FILE` | the DivMMC firmware; empty = the bundled esxDOS | ZX Spectrum > Firmware |
| `--zx_unofirmware FILE` | the ZX-Uno's BIOS; empty = `zxuno/FIRMWARE.ZX1` | ZX Spectrum > Firmware |
| `--zx_unoroms FILE` | the ZX-Uno's ROMs; empty = `zxuno/ROMS.ZX1` | ZX Spectrum > Firmware |
| `--breakpoints FILE` | breakpoints saved by the debugger (JSON), instead of any there were | |
| `--watches FILE` | watches saved by the debugger (JSON); on the Commodore 64, its debugger's (expressions), or the Z80 debugger's (the byte at each address) | |
| `--daadbreakpoints FILE` | breakpoints saved by the Adventure Debugger (JSON); they act once that debugger is open (F11) | |
| `--zx_unocustomrom FILE` | a 16K ROM the ZX-Uno runs (as a 48K) instead of the one its BIOS chooses; empty = none | ZX Spectrum > Firmware |
| `--zx_nextdir DIR` | the ZX Spectrum Next's distribution folder; empty = `specnext` next to the program (or next to ochenta.ini, see [ZX Spectrum Next](#zx-spectrum-next)) | ZX Spectrum > Firmware |
| `--zx_nextcard FILE` | the ZX Spectrum Next's SD card image, made from the distribution if it doesn't exist; empty = `zxnext.img` next to ochenta.ini | ZX Spectrum > Firmware |
| `--zx_nextfirmware` | the ZX Spectrum Next starts through its firmware (boot screen; on by default); `--no-zx_nextfirmware` starts NextZXOS directly | ZX Spectrum > Firmware |

| Option | Description |
|---|---|
| `--config FILE` | use FILE as the settings file instead of ochenta.ini; FILE must exist (ochenta stops with an error if it doesn't) and changed settings are saved into it |
| `--config-add FILE` | apply the settings in FILE on top of ochenta.ini for this session; they are not written into ochenta.ini. If FILE doesn't exist it is ignored, without an error |
| `--help` | show this documentation |

The breakpoint, keyin and file options can be repeated.

Examples:

```
ochenta game.tap
ochenta --model 128k --tape game.tap --keyin "\n"
ochenta --model 48k --tape game.tap --keyin 'J""\n'
ochenta --sym game.sym --bp START --bpw "5C78 if A=0" game.z80
ochenta --bpout "FE if A=2" --bpin 7FFE game.tap
ochenta --config-add bw.ini --scale 3 demo.sna
```

A settings file for `--config-add` only needs the values to change, e.g.:

```
[General]
bw=1
```

## 13. Files

| File | What it is |
|---|---|
| `ochenta` / `ochenta.exe` | the program (its icon is drawn by `tools/make-icon.py`) |
| `ochenta.ini` | settings, next to the program (created when ochenta closes; `~/.config/ochenta/` when installed from a package) |
| `roms/` | Spectrum and Amstrad CPC ROMs (`cpc464.rom`, `cpc664.rom`, `cpc6128.rom`, `amsdos.rom`) and the Spectrum ROMs' .sym label files (the SAM Coupé's ROM, `samcoupe.rom`, and its SAMDOS disk, `SAMDOS2.dsk`), the Currah µSpeech's ROMs (`currah.rom`, `sp0256-al2.rom`) and the ZX Spectrum Next's boot ROM (`tbblue_loader.rom`) |
| `specnext/` | empty: unpack the ZX Spectrum Next distribution here (it isn't included, as it has its own licence) |
| `zxnext.img` | the ZX Spectrum Next's SD card, next to ochenta.ini, made from the distribution the first time the Next is used |
| `zxuno/` | the ZX-Uno's BIOS (`FIRMWARE.ZX1`) and ROMs (`ROMS.ZX1`) |
| `esxdos/` | esxDOS 0.8.9: `ESXMMC.BIN` (the DivMMC firmware) and the SYS and BIN folders for new SD cards |
| `README.md` | this file |
| `LICENSE` | the license, GNU GPL v3 (Help > License) |

`roms`, `README.md` and `LICENSE` are looked for next to the program and, if not there, in the
folder above it (as when ochenta is built inside the src folder of the sources).

Linux packages: after `build.sh`, `package.sh` makes a .deb (with dpkg-deb) and a .rpm (with
rpmbuild: on Debian or Ubuntu, `sudo apt install rpm`) in `build/packages`. Both install the
program and its folders in `/usr/lib/ochenta`, a `ochenta` command, a desktop entry and the icon; they
need GTK 2 and recommend SDL2 (for sound). The version is the release number. `package.sh` also
makes `ochenta-VERSION-x86_64.AppImage` (a single file that runs on most Linux distributions without installing:
`chmod +x` it and run it; it needs `appimagetool` in the PATH, or `APPIMAGETOOL=path`, and GTK 2 and SDL2 installed on the machine that
builds it: it carries them, with their libraries, so it needs nothing installed to run, only the C library and the
graphics drivers of the system; like the packages it keeps its settings in `~/.config/ochenta`) and
`ochenta-VERSION-windows.zip` with `ochenta.exe` (built with lazbuild) and its folders, to unpack
anywhere. The three packages have a `lib` folder (`/usr/lib/ochenta/lib` in the Linux ones) with the native
library for host applications (`ochentalib.dll`, or `libochenta.so`) and its documentation, `LIBRARY.md`; `package.sh`
builds the library with `src/lib/build-lib.sh` if it is not built yet. They also have a `tests` folder with the
C# host demo (`OchentaHostDemo`: its sources and `build.bat`; the Windows .zip has it built too, `OchentaHostDemo.exe --selftest`).

The Spectrum and CPC ROMs are copyright Amstrad, who allow their distribution.

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

**Windows:** open `src/ochenta.lpi` in Lazarus and build, or run `lazbuild src/ochenta.lpi`.
The executable is written next to the project, in `src`, so it builds from any
drive or folder; it finds `roms`, `README.md` and `LICENSE` in its own folder
or in the one above. To distribute it, put them next to the executable.
The executable expects the `roms` folder next to it (the ROM folder can be
changed in Options > Settings).

**Linux and macOS:** run `./build.sh`. It uses `lazbuild` if Lazarus is
installed (GTK2 on Linux, Cocoa on macOS); otherwise point it at a Lazarus
source tree with `LAZARUS_DIR=/path/to/lazarus ./build.sh` and it compiles
with `fpc` alone. The result, with its `roms` folder, goes to `build/linux/`
or `build/macos/ochenta.app`. Linux needs the GTK2 development package to build
(`libgtk2.0-dev`). Sound uses SDL2 at run time (`libsdl2-2.0-0` on Linux,
`brew install sdl2` on macOS); without it ochenta runs silently at the right speed.

## Tests

`tests/run-tests.sh` builds and runs the FUSE Z80 core tests with `fpc`
(Linux, WSL or any platform with Free Pascal on the PATH).

`tests/cpctest.lpr` (run by `run-tests.sh`) boots the three CPC models, checks the 6128's banking and the 464's lack
of it, switching between the Spectrum and the CPC (and a missing firmware leaving the machine as it was), typing
BASIC through the keyboard matrix, sound, recording a program with `SAVE` to a CDT and loading it back, and
snapshots (the run after restoring one is the same run as the first time).
`tests/cpcbatch.lpr` runs a disk or `.sna` for N frames and prints one line about the picture (for trying a
collection of games), and `tests/CPC-MANUAL-TESTS.md` lists what was tried by hand and how it went.
`tests/cpcrun.lpr` runs a CPC with a disk or tape for N frames and saves pictures
(`cpcrun roms cpc6128 game.dsk 1500 out.png 500:early.png`), to try programs without the GUI.

`tests/samtest.lpr` (run by `run-tests.sh`; see [SAM Coupé](#sam-coupé)) tests the SAM Coupé's ASIC, WD1772, SAA1099, disk formats and snapshots, and with the real ROM (set `SAM_TEST_DIR` to a folder
with `samcoupe.rom`, `SAMDOSVersion2.0.dsk` and `DAAD.MGT`) boots it, saves to tape and loads back, boots SAMDOS and reads a DAAD game. `tests/samrun.lpr` and `tests/sambatch.lpr` try the machine, a disk or a folder of them without the GUI.

`tests/machinetest.lpr` runs any model headless, optionally loading a file
and typing keys, and writes the screen as a PPM image plus the recognised
screen text. See the comment at the top of the file for its arguments.

## ROMs

The MSX BIOS is not distributed: it goes in `roms/msx/` (see [MSX](#msx)), which git ignores. Nor are the Commodore 64's ROMs (`Kernal.rom`, `Basic.rom`, `Char.rom` and the 1541's `VC1541.rom`): they go in `roms/c64/` (see [Commodore 64](#commodore-64)), which git ignores too.

The SAM Coupé's ROM (`samcoupe.rom`, version 3.0) and the SAMDOS 2 disk (`SAMDOS2.dsk`) are in `roms/`, (c) MGT (the games and disks used to try the machine are not distributed). Another ROM can be named
in Settings > Common > ROMs. The SAM Coupé emulation was written from its Technical Manual and checked against its behaviour; no code of SimCoupe (GPL v2) or of any other emulator is used.

The Spectrum ROMs in `roms/` are copyright Amstrad, who allow their
distribution but retain the copyright; see `roms/README.md`. The ROM labels in
`roms/48.sym` come from Richard Dymond's SkoolKit edition of *The Complete
Spectrum ROM Disassembly* by Ian Logan and Frank O'Hara
(github.com/skoolkid/rom, GPL v3). The 128K, +2 and +3 labels come from the
disassemblies collected in github.com/ZXSpectrumVault/rom-disassemblies (Paul
Farrow, Garry Lancaster and others). The CPC labels (`roms/cpc464.sym`, `cpc664.sym`, `cpc6128.sym`) use the names of the 6128 firmware source by
Bread80 (github.com/Bread80/CPC6128-Firmware-Source, from the commented disassembly of Kevin Thacker) and, for the
jumpblock and some variables of the 464, those of *Amstrad CPC464
Firmware Explained* (Locomotive Software) and *Amstrad: desensamblado de la ROM y mapa de memoria* (Don
Thomasson). `roms/tbblue_loader.rom` is the ZX Spectrum
Next's boot ROM (Victor Trucco and Fabio Belavenuto, GPL v3).
