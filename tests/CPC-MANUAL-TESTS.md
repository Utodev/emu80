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

What has *not* been verified against real hardware or a reference emulator: the cycle accuracy of
instruction timing beyond the 4 T-state rounding, the position of mid-line raster effects, CRTC edge cases
(register changes in the middle of a character row, R9 or R4 changes, interlace), the Gate Array's
sub-character pixel timing, and cassette formats that need exact pulse widths at the CPC's 2000 baud.
