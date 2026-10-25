# SAM Coupé: manual test results

Headless runs (`tests/sambatch.lpr`, `tests/samrun.lpr`): ROM v3.0, the image inserted and booted the way the GUI does it, no further input unless
noted. `lit` is the percentage of non-black pixels in the final picture. The ROM, SAMDOS and the games are the user's collection in
`to_be_ignored/Sam Coupe/games` (not distributed). The real GUI was not run (no display here): the menus, the Settings tab, the mouse over the picture and
the real keyboard (layouts, AltGr, Alt+F keys) were compiled but not tried by hand.

## Disks (28 files, 1800 frames after F9, contention and the SAMDOS trap on)

26 of 28 load and boot; 2 are ZIP files with a `.dsk` name and are rejected with "unzip it first". Chicago waits at its language menu and Coloris at
"Fire to start": a key is needed (both show their screens). Blancmange Burps and Carrier Command say `53 No DOS`, as a real SAM does with a disk without DOS.
Blast Turbo!, Blitz 4A (error 104 at the end of the run), Blokker, Booty and Bowin (SAD, error 17) run, but whether they reach their real screens is not confirmed.

| Image | Result |
|---|---|
| Aquaintance (EU).mgt | PC=1A5D LMPR=1F VMPR=7E ERRNR=0 lit=99% |
| Arcadia Disk Magazine 1 (Crossword Edition 1 - EU).dsk | PC=8120 LMPR=1F VMPR=7E ERRNR=0 lit=17% |
| Arcadia Disk Magazine 2 (Crossword Edition 2 - EU).dsk | PC=8120 LMPR=1F VMPR=7E ERRNR=0 lit=18% |
| Arcadia Disk Magazine 3 (Solitaire, Snake - Large Playfield, and Crossword Edition 3 - EU).dsk | PC=F011 LMPR=5F VMPR=7E ERRNR=0 lit=17% |
| Arcadia Disk Magazine 5 (Bombardment and Os and Xs - EU).dsk | PC=F011 LMPR=5F VMPR=7A ERRNR=0 lit=84% |
| Arcadia Disk Magazine 6 (Lemming Attack - EU).dsk | PC=F011 LMPR=5F VMPR=7A ERRNR=0 lit=98% |
| Banzai Games Collection (Fruit Machine, Laser Dodge, Yahtzee, Drac Attack, Worms World, Dead Ducks, Dan's Diamonds, Solitaire, Simon, Annoyance, and Spec Tiles - EU).dsk | PC=0E6F LMPR=1F VMPR=7E ERRNR=0 lit=8% |
| Billy Bounce (EU).dsk | PC=1636 LMPR=1F VMPR=7E ERRNR=0 lit=22% |
| Blancmange Burps (EU).dsk | PC=01BF LMPR=1F VMPR=7E ERRNR=53 lit=0% |
| Blast Turbo! (EU).dsk | PC=0E69 LMPR=1F VMPR=5E ERRNR=0 lit=2% |
| Blitz Magazine Issue 4A (Impossamole - EU).dsk | PC=6178 LMPR=21 VMPR=7E ERRNR=104 lit=52% |
| Blokker (EU).dsk | PC=031A LMPR=26 VMPR=7E ERRNR=0 lit=2% |
| Boggle Bubble (EU).mgt | PC=0E6F LMPR=1F VMPR=7E ERRNR=0 lit=26% |
| Booty (EU).dsk | PC=E9DC LMPR=A3 VMPR=84 ERRNR=255 lit=9% |
| Bowin and the Count Dracula (EU).sad | PC=2E33 LMPR=24 VMPR=E8 ERRNR=17 lit=1% |
| CMS - The Games Collection (Evasive+, Satellite, Bombs Away, and Farewell... - EU).dsk | PC=04E7 LMPR=1F VMPR=7A ERRNR=0 lit=6% |
| Capricorn Softwear Disk 1 (Knock-Out, SAM Coupé Derby, and Guess the Number - EU).dsk | PC=EE5A LMPR=5F VMPR=74 ERRNR=0 lit=24% |
| Capricorn Softwear Disk 2 (Stocks, Maze Muncher, and Bits and Bobs - EU).dsk | PC=4E28 LMPR=1F VMPR=7E ERRNR=0 lit=15% |
| Carrier Command (EU).dsk | PC=01BF LMPR=1F VMPR=7E ERRNR=53 lit=0% |
| Chicago (EU).mgt | PC=04ED LMPR=1F VMPR=7E ERRNR=0 lit=0% |
| Coloris (With Bugfixes - EU).mgt | PC=1567 LMPR=1F VMPR=7E ERRNR=0 lit=11% |
| Contact - Best of PD '90 (Tetris, Shanghai, and Soccer Boss - EU).dsk | PC=F011 LMPR=5F VMPR=7E ERRNR=0 lit=7% |
| Curse of the Serpent's Eye (EU).dsk | PC=F011 LMPR=5F VMPR=7E ERRNR=0 lit=33% |
| Dave Infuriators (EU).dsk | PC=0D7F LMPR=22 VMPR=6A ERRNR=0 lit=41% |
| Dave Invaders (EU).dsk | PC=1C2D LMPR=22 VMPR=E6 ERRNR=0 lit=29% |
| Days of Sorcery (EU).dsk | rejected: Days of Sorcery (EU).dsk is a zip file, not a disk image: unzip it first. |
| Deep Scan (EU).dsk | PC=04FA LMPR=1F VMPR=1E ERRNR=0 lit=6% |
| Defender (2002 Version - EU).dsk | rejected: Defender (2002 Version - EU).dsk is a zip file, not a disk image: unzip it first. |

## Tapes (`to_be_ignored/Sam Coupe/games/tapes`, loaded with `LOAD ""` and Play, as File > Open does)

These are "turbo" TZX files (block 0x11 with pilot of about 580 T-states instead of 2168): they load only with the contention emulated (without it the ROM's
loading loop is too fast for them and waits forever for the last block).

| Tape | Result |
|---|---|
| ManicMiner_TURBO.tzx | loads (6 blocks, ~3 min of emulated time), title screen, the game runs and Willy moves with the keys (before the beam ports `F8`/`01F8` were emulated the game froze in its raster-wait loop, which is what was reported) |
| manic_miner_completo_samcoupe.tzx | standard-speed tape of 14 blocks: loads completely |
| Tetris_TURBO.tzx | loads, title and game screen, sound |
| Astroball_TURBO.TZX | loads and the game runs |
| Kreuzen_TURBO.tzx | loads, "Backup to tape?" prompt of the program |
| FLASH!_TURBO.tzx | loads, "Backup to Tape?" prompt of the program |
| Prince_of_persia_demo_TURBO.tzx | loads (26 blocks), the first screen of the demo |
| SAMCoupe_DEMO_TURBO.tzx | loads (18 blocks), the demo runs |
| SCR_Astro_TURBO.scr.tzx, SCR_King_TURBO.scr.tzx | SCREEN$ files: `LOAD ""` skips them (it prints `Screen: astro` and looks for a BASIC program, as the ROM does); `LOAD "" SCREEN$` is what they need (not tried: the autoload types `LOAD ""` only) |

## What the other tests cover

`tests/samtest.lpr` (see README) with the real ROM, SAMDOS and DAAD.MGT: boot, BASIC, every character typed, SAVE and LOAD through a tape, SAMDOS boot,
the SAMDOS load trap compared with the DOS's own load (the same picture and the same memory), the SAMDOS file system on the real SAMDOS disk, and the DAAD database.

## Known limitations

See "Not emulated" in the README's SAM Coupé section: MIDI, light pen, the `FF` attribute port, external memory, the Dallas clock, the parallel and serial
interfaces; the contention grid and the mouse and clock protocols were written from descriptions of the hardware, not checked against a real SAM.
SBT, SDF and DS2 disk images and zipped images are rejected with a message.
