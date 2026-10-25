# Amstrad CPC: tests with real programs

`tests/cpctest.lpr` (run by `run-tests.sh`) checks what can be checked without a game: the three
models' boot, banking, switching models, keyboard, sound, SAVE and LOAD on tape (CDT) and disc,
snapshots, TZX/CDT files. The checks below use real programs, which are not in the repository (they
are other people's work and some have no clear licence): download them to a folder of your own and
run them with `tests/cpcrun.lpr`:

```
fpc -O2 -Fusrc -FUbuild -FEbuild tests/cpcrun.lpr
build/cpcrun roms cpc6128 game.dsk 1500 out.png 500:early.png
```

(`cpcrun roms <model> <file.dsk|file.cdt|file.tzx> <frames> <out.png> [typed text] [frames:out.png...]`;
the disc or tape is loaded the way File > Open does it; `CPCRUN_NOAUTO=1` only inserts it.) It saves the
picture of the CPC after the given number of emulated frames (50 a second). Every result below was
observed by running it and looking at the picture; "ok" means the program behaved as it should on a real
CPC.

| Program (source) | Model | What it checks | Result |
|---|---|---|---|
| Amstrad Diagnostics 1.3A, `AmstradDiag.dsk` and `.cdt` (github.com/llopis/amstrad-diagnostics, release v1.3) | 464 (CDT), 6128 (DSK) | its system info (model, vendor, 50 Hz, RAM size, CRTC type, disc controller), lower RAM test, upper RAM test (the 6128's banked 64K), lower and upper ROM tests | ok: shows CPC 464 / 64KB / FDC none, CPC 6128 / 128KB / FDC detected; lower RAM, upper RAM, lower ROM and upper ROM tests PASSED. With each of the five CRTC chips chosen (CPCRUN_CRTC=0..4) its detection routine reports the chip chosen (00, 01, 02, 03, 04). The keyboard and soak tests are interactive and were not run. |
| Transversion 2024 `tv2024.dsk` (github.com/davemoore22/cpctv2024, GPL 2) | 6128 | disc loading of a BASIC loader, a binary and a screen file, mode 1, raster colour bars in the title | ok: menu and colour bars drawn |
| Reginald and the She Vampires `reg1.dsk` (github.com/davemoore22/cpcreg) | 6128 | DISC.BAS autoload, several files, mode 1 text | ok |
| 8BP v43 `8bp_v43_001.dsk` (github.com/jjaranda13/8BP) | 6128 | a BASIC and binary library loading, a text window and graphics mode | ok: shows its menu |
| DAAD `TEST.DSK` for the CPC (an Adventure Debugger test game made with DAAD; in the DAAD distribution) | 6128 | `DAAD.BIN` interpreter and a database loaded from disc, mode 2 text | ok: the game's text screen is shown after loading from disc |
| DAAD games `RUR1.dsk` and `RUR2.dsk` (Las aventuras de Rudolphine Rur, Dwalin 2020; not in the repository) | 6128 | the Adventure Debugger on the CPC: `DAAD_CPC_DSK=RUR1.dsk tests/run-tests.sh` (or `daadtest`'s third parameter) finds the database at 2880, learns the interpreter's fetch (09B4) and stops on condacts | ok on both discs; the tape versions (`.CDT`) were not run through the test |
| `azimut.cdt` (github.com/JuanLPerea/Azimuth-CPC-464) | 464 | a real CDT with a BASIC header, a turbo block with the loader and a screen: `RUN"`, motor control, real-time loading | ok: loads and runs |
| `nwo.cdt` (github.com/mycodeself/nwo) | 464 | a 28 KB CDT in real time (it took 14000 frames, the tape's own length); "Loading NWO.BIN block N" messages | loads block by block; not run to the end here |

## The collection `Z:\EMULACION\Amstrad CPC\Juegos\JuegosCPC`

The NAS was off at first; later its drive was seen by Windows but not mounted in WSL, so the 516 files (509 `.DSK`
and 7 `.SNA`) were copied (read only, the originals untouched) to a folder outside the repository and run with
`tests/cpcbatch.lpr`:

```
cpcbatch roms cpc6128 GAME.DSK 2500 out.png -keys
```

Each disk is loaded as File > Open does it, run for 2500 frames (50 seconds of CPC time), looked at, answered with
N, RETURN, SPACE and RETURN to whatever waits for a key, run 1800 frames more and looked at again. A picture of
the BASIC prompt (blue paper and at most three colours) both times counts as "still at the prompt". Result with the
final code:

- **460 of the 516 show something else** (a game, a menu, a loader screen, a demo); 56 stay at the prompt.
- Looking at the pictures of samples, they are what the programs draw (HATE, Klax, Xevious, Commando...), in modes 0,
  1 and 2, with raster effects and many colours; it does not mean they are playable or free of glitches: only a person
  playing each could say, and that wasn't done.
- The 56 that stay at the prompt, as far as they were looked into, are of these kinds: the second side or a utility
  disk of a game (`TIME1`, `UTIL1`, `SAMURAI2`, `XYPHOES2`...), which only make sense after the first; damaged
  images (`CYBERII`, `ROADRUN`: tracks of garbage that no emulator would read). Disks with a boot sector and no
  directory AMSDOS can read (`GAUNTLET`) are started with `|CPM` and run; copy-protected disks with many sectors flagged with errors (`DEVILS`,
  `ISLE`, `STUNTMAN`); and disks where the program chosen from the directory wasn't the one to run (the choice is a
  guess, see the README). They were **not** investigated one by one.
- The 7 `.SNA` snapshots load (a 6128's `.sna` with 64K of memory is a 6128): `HATE`, `ALIENH`, `DEFLEKT`,
  `HIGHWAY`, `REV`, `ANDROID1` and `TLL` show a picture after a few seconds.

What has *not* been verified against real hardware: the instruction times (in microseconds, taken from
Caprice32's tables), the position of mid-line raster effects, CRTC edge cases
(register changes in the middle of a character row, R9 or R4 changes, interlace), the Gate Array's
sub-character pixel timing, and cassette formats that need exact pulse widths at the CPC's 2000 baud.

## Problems reported (to_be_ignored/Amstrad CPC/problems)

- **Jet Set Willy (UK) (1985).dsk**: the menu showed, but the game's screen was black. The game sets its own CRTC values
  (R1 = 32 characters, R4 = 37, R5 = 6, R6 = 23 rows: a frame of 310 lines) and the emulator only completed a picture
  when a frame reached the 312 lines the usual values give, so none was ever shown. A picture is now completed when the
  VSYNC starts if the frame was shorter (black below what was drawn). Checked: the room "The Bathroom" shows.
- **babaspalace.dsk** and **mojon-twins--cheman.dsk**: wrong sound. Their player (the same engine) writes a PSG register like
  this: `OUT C,latch` (BDIR and BC1 both set), then `OUT A,register number`, then `OUT C,inactive`, then the data and write.
  The emulator took the register number when the latch cycle started, so it read the previous value of port A and every
  register was written to the wrong place (R1 became "R11", and so on). The address is now latched when the latch cycle ends,
  from what is on the bus then (players that put the number on the bus before the cycle work as before). Checked: the PSG
  registers of both games now hold a coherent set (periods, mixer `38`, volumes). Not checked by ear: no audio device here.
  `tests/cpctest.lpr` has both cases.

- **mojon-twins-amstrad-cpc-hobbit_v1_1_ES.cdt** (turbo CDT, 5 blocks): the last block (20260 bytes of ZX7-packed game) never
  loaded. The first stage reads a block with the firmware (259 bytes: sync, 256 and the CRC), stops the motor and goes on with
  its own loader, which expects the tape to continue where it was; the emulator started the block again from its beginning
  when the motor went on, so the loader read the old data. The tape now goes on from where it was when the motor is stopped in the
  data of a block (`TTape.Hold` and `Resume`). Checked: all blocks load and the title screen of the game shows
  ("the HOBBIT", keyboard or joystick), on a CPC 464. `tests/cpctest.lpr` has a test of the tape's position.
- **pd_A.dsk** (Pinball Dreams, the 21st Century Entertainment eagle): the game moves the HSYNC position (R2 between `2D` and `2F`)
  on every line, and the emulator moved each line sideways with it (two characters: 16 pixels, so the picture was made of
  shifted lines, and showed colour fringes). A real monitor's oscillator doesn't follow each HSYNC: the picture is drawn from its
  averaged phase now. Checked: the eagle and the text show straight. The rest of the game was not examined; its raster effects
  (R4/R6/R7/R9 changes inside the frame, palette changes by line) were not compared with a reference.

## CDT tapes (the files of `to_be_ignored/Amstrad CPC/problems` and `Dinamic`, CPC 464)

Run headless (`tests/cpcrun.lpr` and tools like it): the tape inserted, `RUN"` as File > Open does it, up to 60000 frames
(20 minutes of emulated time), Auto play on. "Plays to its end" means the signal reached its last block and the program went on;
it says nothing about the game being right after that (only a few were looked at). The fixes of this round: the "Press PLAY then any
key:" prompt is answered by a key pressed a few frames after it appears (a loader that hides its screen waited for ever,
as in Camelot Warriors); the tape goes on from where it was when the motor stops in the data of a block (The Hobbit, see above).

| Tape | Result |
|---|---|
| 01 - Babaliba 1984 | the tape plays to its end (frame 8788); picture 8% lit, PC=443D |
| 02 - Rocky 1985 | **still loading or waiting at 60000 frames** (block 20 of 20), PC=9BCA, picture 5% lit |
| 03 - Abu Simbel Profanation 1985 | the tape plays to its end (frame 7887); picture 3% lit, PC=1D1A |
| 04 -West Bank 1985 | the tape plays to its end (frame 12606); picture 8% lit, PC=77F2 |
| 05 - Olé, toro 1985 | **still loading or waiting at 60000 frames** (block 9 of 9), PC=B9AE, picture 1% lit |
| 06 - Sgrizam 1985 | the tape plays to its end (frame 11457); picture 11% lit, PC=012B |
| 07 - Cobra's Arc 1986 | the tape plays to its end (frame 11444); picture 12% lit, PC=A330 |
| 09 - Nonamed 1986 | the tape plays to its end (frame 11347); picture 8% lit, PC=B9DE |
| 10 - Phantomas 2 A 1986 | the tape plays to its end (frame 11752); picture 100% lit, PC=1B9E |
| 10 - Phantomas 2 B 1986 | the tape plays to its end (frame 11752); picture 100% lit, PC=1B9E |
| 11 - Camelot Warriors 1986 | the tape plays to its end (frame 11275); picture 7% lit, PC=765B |
| 12 - Army Moves 1986 | **still loading or waiting at 60000 frames** (block 206 of 412), PC=82DC, picture 21% lit |
| 13 - Dustin 1986 | the tape plays to its end (frame 12935); picture 11% lit, PC=76A8 |
| 14 - Game Over A 1987 | the tape plays to its end (frame 11960); picture 3% lit, PC=76B2 |
| 14 - Game Over B 1987 | the tape plays to its end (frame 12056); picture 3% lit, PC=76A8 |
| 15 - Don Quijote A 1987 | the tape plays to its end (frame 12544); picture 27% lit, PC=1A74 |
| 15 - Don Quijote B 1987 | the tape plays to its end (frame 12430); picture 100% lit, PC=07BE |
| 16 - Fernando Martin 1987 | the tape plays to its end (frame 12664); picture 5% lit, PC=7857 |
| 17 - Freddy Hardest A 1987 | **still loading or waiting at 60000 frames** (block 7 of 7), PC=769E, picture 2% lit |
| 17 - Freddy Hardest B 1987 | **still loading or waiting at 60000 frames** (block 7 of 7), PC=769F, picture 2% lit |
| 18 - Megacorp A 1987 | **still loading or waiting at 60000 frames** (block 7 of 7), PC=1B61, picture 9% lit |
| 18 - Megacorp B 1987 | the tape plays to its end (frame 12771); picture 100% lit, PC=1B9D |
| 19 - Phantis A 1987 | the tape plays to its end (frame 13749); picture 52% lit, PC=7857 |
| 19 - Phantis B 1987 | the tape plays to its end (frame 14068); picture 52% lit, PC=7857 |
| 20 - Aspar G.P. Máster A 1988 | the tape plays to its end (frame 12731); picture 11% lit, PC=33CC |
| 20 - Aspar G.P. Máster B 1988 | the tape plays to its end (frame 12717); picture 11% lit, PC=33CE |
| 21 - Capitan Sevilla A 1988 | the tape plays to its end (frame 14072); picture 58% lit, PC=354D |
| 21 - Capitan Sevilla B 1988 | the tape plays to its end (frame 13951); picture 52% lit, PC=216F |
| 22 - Comando Tracer 1988 | the tape plays to its end (frame 11660); picture 3% lit, PC=7669 |
| 23 - Hundra 1988 | the tape plays to its end (frame 13586); picture 75% lit, PC=7224 |
| 24 - La guerra de las vajillas A 1988 | the tape plays to its end (frame 12235); picture 33% lit, PC=1D2B |
| 24 - La guerra de las vajillas B 1988 | the tape plays to its end (frame 12034); picture 9% lit, PC=1B9E |
| 25 - Meganova A 1988 | the tape plays to its end (frame 12366); picture 9% lit, PC=76A6 |
| 25 - Meganova B 1988 | the tape plays to its end (frame 8044); picture 100% lit, PC=2925 |
| 26 - Navy Moves 1 1988 | the tape plays to its end (frame 15747); picture 5% lit, PC=6AB2 |
| 26 - Navy Moves 2 1988 | **still loading or waiting at 60000 frames** (block 10 of 10), PC=6E45, picture 1% lit |
| 27 - Target Plus 1988 | the tape plays to its end (frame 11169); picture 6% lit, PC=19E2 |
| 28 - Turbo Girl 1988 | the tape plays to its end (frame 13465); picture 5% lit, PC=80F1 |
| 29 - AMC Astro Marine Corps A 1989 | the tape plays to its end (frame 19411); picture 13% lit, PC=A338 |
| 29 - AMC Astro Marine Corps B 1989 | **still loading or waiting at 60000 frames** (block 5 of 1953), PC=1D2A, picture 0% lit |
| 30 - After the War A 1989 | the tape plays to its end (frame 18240); picture 2% lit, PC=7699 |
| 30 - After the War B 1989 | the tape plays to its end (frame 18254); picture 0% lit, PC=5EB5 |
| 31 - Bestial Warrior 1989 | the tape plays to its end (frame 15469); picture 70% lit, PC=1B9F |
| 32 - Cosmic Sheriff 1989 | the tape plays to its end (frame 13720); picture 9% lit, PC=E179 |
| 33 - El Capitan Trueno A 1989 | the tape plays to its end (frame 17372); picture 5% lit, PC=AF39 |
| 33 - El Capitan Trueno B 1989 | the tape plays to its end (frame 18756); picture 15% lit, PC=72A6 |
| 34 - Freddy Hardest en Manhattan Sur | the tape plays to its end (frame 18320); picture 39% lit, PC=9F15 |
| 35 - Míchel Fútbol Máster + Superskills A 1989 | the tape plays to its end (frame 14340); picture 33% lit, PC=F902 |
| 35 - Míchel Fútbol Máster + Superskills B 1989 | **still loading or waiting at 60000 frames** (block 413 of 461), PC=1B61, picture 100% lit |
| 36 - Rescate atlantida A 1989 | **still loading or waiting at 60000 frames** (block 1191 of 3055), PC=ADD4, picture 0% lit |
| 36 - Rescate atlantida B 1989 | the tape plays to its end (frame 13348); picture 100% lit, PC=29DF |
| 37 - Satán A 1989 | the tape plays to its end (frame 15722); picture 1% lit, PC=7043 |
| 37 - Satán B 1989 | the tape plays to its end (frame 17101); picture 0% lit, PC=6DB9 |
| 38 - Buggy Ranger 1990 | the tape plays to its end (frame 14929); picture 18% lit, PC=8014 |
| 39 - Narco Police A 1990 | **still loading or waiting at 60000 frames** (block 6 of 8), PC=0FF4, picture 39% lit |
| 39 - Narco Police B 1990 | the tape plays to its end (frame 8966); picture 100% lit, PC=29E5 |
| 40 - Simulador Profesional de Tenis 1990 | the tape plays to its end (frame 13717); picture 5% lit, PC=BB3F |
| 41 - Hammer Boy A 1991 | the tape plays to its end (frame 18436); picture 3% lit, PC=BAF5 |
| 41 - Hammer Boy B 1991 | the tape plays to its end (frame 18441); picture 3% lit, PC=B752 |
| 42 - Megaphoenix 1991 | the tape plays to its end (frame 9992); picture 7% lit, PC=0347 |
| NoMeToquesLosHuevos | the tape plays to its end (frame 8107); picture 12% lit, PC=08E9 |
| mojon-twins-amstrad-cpc-hobbit_v1_1_ES | the tape plays to its end (frame 7968); picture 4% lit, PC=13A0 |

The CPU's timing (this round): every instruction now takes the microseconds of the CPC's NOP tables (as Caprice32 has them) and its
I/O reaches the chips in the right microsecond; before, each instruction's T-states were rounded up to a whole microsecond, which made
`OUT (C),r`, `PUSH`, `OUTI`, the interrupt and others a microsecond short. With it most tapes that had failed now load to their
menu or title (before, many ended at the BASIC prompt or over a screen of garbage: Abu Simbel, Nonamed, Dustin, Fernando Martin,
Aspar, Cosmic Sheriff, Buggy Ranger, Megaphoenix...). Whether `Babaliba`'s dependence on the phase between the key and the
tape is gone was not checked.

Not resolved: the ones marked "still loading or waiting" are mostly very long tapes (hundreds or thousands of blocks, tens of
minutes of tape) that the 60000 frames didn't finish, or games that load their last block only when a game starts: `Freddy Hardest`,
`Olé, toro` and `Rocky` wait in their menus, `Megacorp A` waits at its first location, `Navy Moves 2` and `Narco Police A` ask for
their access code. Second parts (`Meganova B`, `Míchel ... B`, `Narco Police B`, `Rescate atlantida B`) are loaded from the
first part, not with `RUN"`, and `Phantomas 2` still ends at the BASIC prompt. `NoMeToquesLosHuevos` loads and its loading screen
shows. The audio: the CPC's tape is heard at the real speed (see the README).

- **pd_A.dsk / pd_B.dsk, the pinball tables** (after the eagle: "Please insert disk side B", pd_B.dsk, a key, the menu, F1-F4): the
  table flickered (whole frames black or half drawn) and the game later hung. The game splits the frame into virtual frames with
  R4, R9, R6, R7 and the screen address, at the Gate Array's interrupts, and scrolls by a line with R0: a line of 44 characters and
  five of 4, whose HSYNCs still come every 64 microseconds. Its writes must land at given characters, and with the old timing
  (`OUT (C),r` in 3 microseconds instead of 4) they landed before R4 was met, the row counter ran past it and the frames came out of
  step. With the CPC's instruction times the four tables (Ignition, Steel Wheel, Beat Box, Nightmare) load and draw whole, on CRTC
  types 0 and 1 alike; the R9 rule added before for type 1 is not needed and was removed. The monitor now follows the HSYNC in
  absolute time and makes its own lines, so the short lines no longer bend the top of the table. Run headless: the attract mode
  for 9000 frames and a game (F1, flippers) for 12000 frames, without hanging; not played by hand.
  For quick tests, `pd_insert_disk_B.e80` (in the same folder) is the machine at the "Please insert disk side B" prompt: open it,
  insert `pd_B.dsk` in drive A: and press a key (the intro takes about two minutes otherwise).
