# MSX1 / MSX2 work log

Working notes for the MSX integration (plan: phases 1-10). Updated at the end of every phase.

## Decisions
- Integration follows the CPC/SAM pattern: chip units (`Msx.pas`, `MsxVdp.pas`, `MsxDisk.pas`) plus `SpectrumMSX.inc` and `FIsMSX` branches in `TSpectrum`. No machine base class refactor.
- System ROMs and DOS disks live in `roms/msx/`, which is git-ignored (`roms/msx/*`, except `README.md`). They are never added to the repository, the executables or the packages.
- openMSX (GPL-2) is a behaviour reference only; no code is copied without checking licence compatibility and adding attribution.
- MSX `.dsk` files are raw FAT12 sector dumps (720K: 80 tracks x 2 heads x 9 sectors x 512 bytes). They must never go through the CPC/SAM/Spectrum DSK parsers; the selected machine picks the format.

## Local development material (not distributed)
Copied from `to_be_ignored/MSX` into `roms/msx/` for local testing:

| File | Use |
|---|---|
| (`MSX.rom`, the MSX1 BIOS, is no longer used) | |
| `MSX2.rom` (32K) | MSX2 BIOS + BASIC 2, slot 0 |
| `MSX2EXT.rom` (16K) | MSX2 sub-ROM, slot 3-1 |
| `PHILIPSDISK.rom` (16K) | disk interface ROM, slot 3-1 (MSX1) / 3-3 (MSX2); page 1 only |
| `MSXDOS23.ROM` (64K) | MSX-DOS 2 kernel |
| `msxdos1.dsk`, `msxdos2.dsk` | MSX-DOS boot disks (720K) |

blueMSX slot layouts (`Machines/MSX*/config.ini`):
- MSX1: slot 0 = `MSX.rom` at pages 0-1; slot 3 (expanded) = 64K RAM in 3-0 and `PHILIPSDISK.rom` in 3-1 (the disk shares the RAM's primary slot: the DAAD engines keep their own copy of the slot register and break if the disk ROM needs a different one); 16K VRAM.
- MSX2: slot 0 = `MSX2.rom`; slot 3 expanded: 3-1 `MSX2EXT.rom`, 3-2 mapper RAM, 3-3 disk ROM (blueMSX's own machine has the music ROM, XBASIC and the disk in the same slot too); 128K VRAM; CMOS clock. The project's MSX2 is fixed at 128K RAM (mapper) and 128K VRAM.

## DAAD test disks (inspected, not yet run)
Both are 720K FAT12 (media F9), boot MSX-DOS 1 and run `AUTOEXEC.BAT`.
- `DAADMSX1.DSK`: `MSXDAAD.COM` (298 bytes, loader that LDIRs itself to A500h), `DAAD.Z80`, `DAAD.MDG`, `DAAD.DDB` (2068 bytes), `001.MS2`.
- `DAADMSX2.DSK`: `MSX2DAAD.COM` (17694 bytes), `DAAD.DDB`, `FONT.IM8`, `001.IM8`; `AUTOEXEC.BAT` runs `mode 80`.
- The DDB is a separate file loaded into RAM by the engine, with no ASCII signature; at `0100h` of the `.COM` there is loader code, not a DDB. Detection has to use the existing marker/machine-nibble validation on the running memory image (phase 9), and the result will be recorded here.

## Phase log
- Phase 1 (audit): done for ochenta architecture and test material; openMSX / grauw / C-BIOS review pending (needs web access).
- Setup: `.gitignore` entry and `roms/msx/` created; ROM and disk copies verified ignored (`git check-ignore`).
- Phase 2 (slots and memory): `src/Msx.pas` written (primary/secondary slots, inverted FFFFh register, ROM/RAM/mapper-RAM devices, memory mapper with ports FC-FF, 256-port I/O space, `Describe` for the debugger). `tests/msxtest.lpr` passes (33 checks) and is in `tests/run-tests.sh`. Not yet wired into `TSpectrum`; that happens in phase 3 together with the VDP, PPI and PSG.
- Phase 3 (MSX1 functional): `smMSX1` added to `Models.pas` (`msx1`, ROM `roms/msx/MSX.rom`, 3.579545 MHz, PAL 313x228 T-states). New units `MsxVdp.pas` (TMS9918A: Graphics I/II, Text, Multicolor, sprites, collision, 5th sprite, frame interrupt), `MsxMachine.pas` (slots + VDP + PPI + PSG ports + joystick state + frame buffer in the 704x288 layout of TSpectrum, 192 lines at row 48) and `SpectrumMSX.inc` (CPU bus, ports with one extra wait state, interrupt, PSG events into the existing `TAY8912` path, PPI click as speaker). `FIsMSX` branches added in `Spectrum.pas` (SetModel with rollback, Reset, memory, ports, IntActive, RenderUpTo, CopyFrameBuffer, ExecuteOne, FinishFrame, Peek). Results: `tests/msxrun.lpr` boots the real BIOS to "MSX BASIC version 1.0 ... 28815 Bytes free / Ok"; G.Beret and Q*bert (32K ROMs in slot 1) start in Graphics II. Full `tests/run-tests.sh` passes; `lazbuild src/ochenta.lpi` builds.
  - Open items: no M1 wait state yet (MSX adds one per opcode fetch); keyboard matrix constants, typing and joystick keys (UI) and the machine menu entry are phase 4; the 48K `DONKEY.ROM` (AB header, INIT 4010h) does not start yet: it stays in BASIC, to be looked at with the cartridge mappers/heuristics in phase 4; no snapshot (.e80) or debugger slot view for MSX yet.
- Phase 4 (menu, cartridges; first testable executable): "MSX > MSX 1" in the machine menu (also `--model msx1`, bare `msx1`); a Cartridge menu (insert/eject/mapper) and, in the modern interface, the SD row of the Media palette turns into a CART row with a cartridge drawing; `.rom` files open into slot 1 from Open, drag and drop or the command line, restarting the machine. Mappers in `Msx.pas`: plain, Konami, Konami SCC (no sound), ASCII8, ASCII16, with a code-scanning guess (`GuessMapper`) and a manual override (`msx_cartmapper`). MSX keyboard (`MapKeyMSX`, 11x8 matrix) and joystick 1 (`msx_joystick`). Settings: `[MSX] msx_joystick`, `msx_cartmapper`. Missing BIOS message names the file, the folder and how to get it. README, `roms/README.md` and `roms/msx/README.md` updated. Model switching MSX <-> Spectrum/CPC/SAM tested; full `tests/run-tests.sh` passes; Windows build with `lazbuild.exe` OK (`ochenta.exe` at the repository root).
  - Mapper results with the games set: 32K konami/ ROMs (G.Beret, Q*bert, Knight, Goonies, HSPORT3) run plain; Xevious -> ascii16 shows a picture; Firebird -> konami; OutRun -> ascii8 (screen still blank after 1500 frames, to check); DONKEY.ROM (48K) only runs as Konami (the guess treats sizes that are not a power of two as Konami).
  - `.cas` tapes (`games/tapes`, found later) are not supported yet: needs a CAS reader producing the 1200/2400 baud FSK signal for PSG register 14 bit 7 and the PPI motor bit.
  - Not tested by a person on screen yet: the GUI paths (menu, modern media row, keyboard) were compiled and the model switching run headless, but nobody has looked at them.
- Phase 4b/6 (CAS tapes, MSX1 disks, settings tab; second testable executable): `.cas` tapes (`Tape.LoadCASFromStream`: pilot tone + 1200 baud FSK pulses per block; auto load types `RUN"CAS:"` or `BLOAD"CAS:",R`; the tape plays as a signal read through PSG R14 bit 7 and the PPI motor bit 4, at turbo speed with fast loading; a BIOS-trap fast loader was tried and dropped because games with their own loaders read the signal directly). Disks: `MsxDisk.pas` (Philips WD2793 interface on `TWD1772`, with new `DataRequest`/`InterruptRequest`/`ReadyAlways`; registers 7FF8-7FFF, 7FFF bits are active low, drive select bit 0 = 0 for A), raw 720K/360K/180K images kept raw on save (`TDiskImage.RawImage`, `SaveRawDisk`), new 720K FAT12 disks, `TDiskImageStream` so the disk browser and `TFatVolume` work on the sectors. MSX-DOS 1.03 boots from `MSXDOS 1.DSK`, DIR lists it, DAADMSX1.DSK boots to `msxdaad`. The Philips ROM asks for the date at power on unless it boots a DOS disk: auto load answers it.
  - Firebird and Xevious use V9938 registers (R8+, R14-R17, R23, R46): MSX2 games, they cannot run on the MSX1. Donkey Kong (48K Ocean) needs the Konami mapper, which auto-detect now picks (sizes that are not a power of two); verified headless to run and take keys.
  - Settings dialog: MSX tab (mapper selector, joystick). Modern UI: CR row in Media, no Cartridge menu in the header.
- Phase 5 (MSX2; third executable): `smMSX2` (`msx2`, ROMs `roms/msx/MSX2.rom`, `MSX2EXT.rom`, optional `PHILIPSDISK.rom`). `MsxVdp.pas` rewritten: V9938 with 128K VRAM (17-bit address via R#14, interleave in Graphics 6/7), 64 registers and S#0-9, palette port 9Ah, indirect port 9Bh, Graphics 3-7, Text 2, sprite mode 2, 192/212 lines, vertical scroll R#23, line interrupt R#19, and the commands (HMMC, YMMM, HMMM, HMMV, LMMC, LMCM, LMMM, LMMV, LINE, SRCH, PSET, POINT with the 8 logical ops and T versions), executed instantly; `MsxMachine.pas` gets the mapper RAM at 3-2 with ports FC-FF, sub-ROM at 3-1, RP-5C01 clock at B4/B5, 212-line framing, HR/VR for S#2. Verified: BASIC 2.1 boots; CHGMOD sets screens 1, 2, 5, 7, 8; BASIC programs draw boxes, circles, paint and lines in SCREEN 8; Xevious (ASCII16) and Firebird (Konami) run their intros (the first needed the HMMC/LMMC NX decrement per byte fixed).
  - Known issue: in direct mode SCREEN 2-8 goes back to text at the prompt (the BIOS calls CHGMDP with FCB0=0 at the prompt); inside programs it works. Cause not found (SRCH EQ polarity also unverified).
  - Also: Insert recent tape / cartridge menus (+ File > Open recent); the modern CR slot is twice as wide with gold contacts when empty and the cartridge with the name on the spine when full.

- DAADMSX1.DSK hang (fixed): the DAAD engine for MSX replaces RST 38 and hooks FFD4h (a hook the Philips DOS ROM calls from DSKIO) with a wrapper that saves and restores its own mirror of port A8h (D023h). With the disk ROM in slot 2 and RAM in slot 3, A8h was FBh while DSKIO ran, the mirror said FFh, and the wrapper switched page 1 back to RAM under the running disk ROM. With the disk in the RAM's primary slot A8h never changes. Also: the disk ROM is mapped in page 1 only (mapped also in page 2 the BIOS found it twice and DOS reserved memory for two interfaces, leaving the TPA too low for the engine), and a restore of an absent drive B stays busy (as the real controller does when nothing answers), which is how the ROM decides there is a single drive.
- DAADMSX2.DSK font (open): `MSX2DAAD.COM` loads `FONT.IM8` with its image-chunk interpreter (25C7h: reads [cmd][w1][w2] chunks; known cmds 00, 01, 11, 13, 14, 15, 81; any other is skipped by w1 bytes). The font file's only chunk has cmd 04, so it is skipped and the glyph area (rows 212-243 of page 0, copied from with HMMM) is never written. Not an emulation error as far as traced (the BDOS calls and the data returned match the disk); cmd 15 sub-type 3 (3FD1h, ZX0-like unpacker to VRAM 1D400h) is the only font path in the program and the file does not use it.

## MSX1 removed, cartridge browser, ports window (2026-10-26)
- MSX 1 is gone: `smMSX1`, the TMS9918A-only VDP (the V9938 keeps its modes), the 64K RAM branch, the `MSX.rom` ROM and its tests. The machine menu has MSX 2 at the first level.
- VDP: R#14 only takes the carry of the 16K address wrap in the V9938's modes (openMSX does the same); in Graphics 1/2, Text 1 and Multicolor it wraps. Super Cobra (`SUCOBRA.ROM`) cleared the whole VRAM, R#14 became 1 and its tables went to the wrong place: black screen.
- Tapes: `AutoLoad` of a `.cas` holds SHIFT while the disk ROM starts (it looks at the key a few seconds in: 100 frames is too early, 300 works) so there is no Disk BASIC and `BLOAD"MINER"` (Manic Miner) goes to the tape instead of "Disk I/O error".
- RAM: mapper RAM is visible in 3-0 and 3-2 (shared bytes). Abracadabra's loader looks for RAM by the primary slot alone (needs the RAM where the subslot register sits after the BIOS: 3-0) and then writes AA to FFFFh (all pages to subslot 2). Either layout alone broke it.
- Firebird: not reproduced as a bug. R5 alternates between two sprite attribute tables every two frames and R23 scrolls; the hero is drawn at Y=32-48 in the first seconds of play (it walks down later).
- New: `CartBrowser.pas` (Info and Hex tabs, edit, import/export block, save, save as), `ikCartridge` icon, MSX ports in `ZXUnoRegsForm.pas` (`TMsxMachine.PortValue`/`SetPortValue`), Esc closes the tape, disk, SD and cartridge browsers.
- Templos Sagrados.tsx (a DAAD engine for MSX on tape): loads completely and the engine starts and draws its text, but all the engine's table pointers at AFF0h-AFFFh (AFF1 messages, AFF3, AFF7 the font, AFF9...) stay 0: no code of the engine writes them and no tape block covers them (the blocks end at A497h and start again at B000h), so the glyphs come from address 0. The file is tagged `[! bugged]`. Opcode fetches now take one wait state on the MSX (as on the real machine); it did not change this.

## Default ROMs: QUANTIKA (from 2026-10-30)
The MSX2's default ROMs are ochenta's own: `roms/msx/QUANTIKA.ROM` (BIOS and FBASIC, compatible with MSX-BASIC 2.1) and
`roms/msx/QUANTIKA_SUB.ROM` (the sub-ROM), in the repository and in the packages; the original ones (MSX2.rom, MSX2EXT.rom,
and PHILIPSDISK.rom for the disk) are chosen in Settings > Common > ROMs and never packaged. Their own development log is
in their project.
- With QUANTIKA there is no disk drive: the original disk ROM calls into the original BASIC and hung at boot on it (HALT at
  F379h with interrupts off). `SetupMSX` leaves the disk interface out when the main ROM has "with FBASIC" in it
  (`IsFreeBios`; `TMsxMachine.RemoveDisk` empties slot 3-3). There is no message when the ROMs are missing: they always are
  there.
- Tests: `tests/run-tests.sh` boots the QUANTIKA ROMs of `roms/msx` (no logo: text mode from power on; the banner within 20
  frames; no machine name in them). `tests/fbasic-difftests.sh` (when the original ROMs and `../quantika` are there) runs
  that project's test programs on the original ROMs and on QUANTIKA with `tests/msxfree.lpr` (exec, basic, pic, picdiff,
  tapeout: the cassette output decoded into bytes; MSXFREE_BREAK, MSXFREE_DUMP, MSXFREE_PIC, MSXFREE_VRAM, MSXFREE_PSGLOG: every write to the PSG) and compares the
  results; `tests/mkcas.py` makes the tape of the file tests. The test tools load the original ROMs by name
  (`UseOriginalMsxRoms` in Models.pas), as the default names are QUANTIKA's.
- Tapes of the test set (`to_be_ignored/MSX/games/tapes`) on QUANTIKA against the original, pictures after 25000 frames:
  Cobra's Arc, Emilio Butragueno, Fernando Martin, Galaxian, Abracadabra, La Aventura Original, Don Quijote, Starquake the
  same; International Karate, Manic Miner, La Abadia del Crimen, Altered Beast (side B: neither loads) within 2%; Abu Simbel
  and A-Team load the same (QUANTIKA boots sooner and is ahead; border stripes). Head over Heels (a Syntax error) and Jet
  Set Willy (hangs at its LOADING screen) do not load yet.

- MSX1 slot layout (`msx_compat`, Options > MSX1 compatibility, 2026-10-31): `TMsxMachine.SetCompat` rebuilds slots 2 and 3 with no slot expanded (RAM alone in slot 3, FFFFh plain RAM; the sub-ROM in slot 2; no disk interface, which has no slot left). `TSpectrum.MsxCompat` is applied at the next reset (`MSXReset` runs `SetupMSX` again when the layout differs); `ApplySettings` resets the machine when it changes. Experiment on the original ROM: International Karate, which restarts the machine at the end of its load with the MSX2 layout, plays with the MSX1 one; Abu Simbel does not change (its BLOAD,R goes through an inter-slot call to slot 1, a different cause); Altered Beast and After Burner do not load either way. Test tool: `MSXFREE_COMPAT=1` in `tests/msxfree.lpr`.
