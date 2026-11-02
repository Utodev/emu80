The user manual of the ochenta program is in [README.md](README.md). This file is about the native library only.

# Native library for a host application

The emulation engine (the same one the program runs: the Z80, the memory, the video, the peripherals) can be
built as a native library, `ochentalib.dll` (Windows) or `libochenta.so` (Linux), that a host application loads **into
its own process**: a C# GUI through P/Invoke, for instance. The program, `ochenta.exe`, is unchanged and keeps
working on its own; both use the same engine and the same code for the picture (`src/FramePresenter.pas`:
scaling, black and white, scanlines and [deinterlacing](README.md#deinterlacing)).

**The screen.** The host gives a window to draw in: on Windows, the window handle of one of its controls (a
WinForms `Panel`, a WPF `HwndHost`...) goes to `ochenta_attach_window`, and the library draws the frames there as the
machine produces them, fitted to the control's size (in proportion, with black bands, a whole-number scale when
the size allows it) and following it when it is resized. It opens no window and shows no menu of its own. The
host controls the picture's life: `ochenta_detach_window` before its control is destroyed, `ochenta_attach_window` to
another one later, with the machine going on meanwhile. A control that is drawn on by the library should leave its
painting alone (in WinForms: a `Panel` with the styles `Opaque`, `AllPaintingInWmPaint` and `UserPaint`, and empty
`OnPaint` and `OnPaintBackground`). A toolkit that wants to draw the picture itself (WPF's `WriteableBitmap`, for
instance) takes the frames with `ochenta_get_frame` (32-bit BGRA, any whole scale), told by `ochenta_set_frame_callback` (from
the emulation thread) that one is ready. Drawing into a host window is Windows only; `ochenta_get_frame` works everywhere.

**Input** is the host's: it tells the keys (`ochenta_key`, key = row * 5 + bit of the Spectrum's keyboard, 0 = CAPS
SHIFT, 35 = SPACE, 36 = SYMBOL SHIFT) and the Kempston joystick (`ochenta_set_kempston`). On an Amstrad CPC model
(8 = CPC 464, 9 = CPC 664, 10 = CPC 6128) the key is line * 8 + bit of the CPC's keyboard matrix (0 to 79, as the
`CPCK_*` constants of `src/Amstrad.pas`: 0 = cursor up, 21 = SHIFT, 18 = RETURN, 47 = SPACE, 72-77 = joystick 1
up, down, left, right, fire 1, fire 2, 79 = DEL); `ochenta_load_file` takes `.cdt` tapes, and `ochenta_ram_bank_count` is 4
(CPC 464 and 664) or 8 (CPC 6128). On a SAM Coupé (11) the key is row * 8 + bit of its matrix (0 to 71, as the `SAMK_*` constants of
`src/Sam.pas`: 0 = SHIFT, 48 = RETURN, 56 = SPACE, 57 = SYMBOL, 64 = CTRL, 65-68 = cursor up, down, left, right),
`ochenta_set_kempston` is its joystick (port 31), and `ochenta_ram_bank_count` is 32 (16K pages of its 512K). Its 32K ROM is
the `roms` folder's `samcoupe.rom`: `ochenta_create(11, folder)` needs it in the folder (it fails, with `ochenta_last_error`, if it is not there).
On a Commodore 64 (13) the key is column * 8 + row of its keyboard matrix (0 to 63, as the `C64K_*` constants of `src/C64.pas`: 1 = RETURN, 60 = SPACE, 63 = RUN/STOP), 64 to 68 are the joystick in control port 2 (up, down, left, right, fire) and 69 is RESTORE; `ochenta_load_file` takes a `.d64` (put in drive 8 and loaded), a `.prg`, `.p00` or `.t64` (loaded and run) and a `.tap` (played); the ROMs are `Kernal.rom`, `Basic.rom`, `Char.rom` and `VC1541.rom` in the `roms/c64` folder of the folder given to `ochenta_create`.

**The API** is plain C (cdecl) with opaque handles, `int32` and pointers (see `src/lib/OchentaApi.pas`; the C# wrapper is
`tests/csharp/OchentaHostDemo/Ochenta.cs`). Calls return 0 (or a count) on success and a negative number on failure, with
`ochenta_last_error` saying why. It has:

| Group | Calls |
|---|---|
| Instance | `ochenta_create(model, romFolder)` (model as in the machine list: 0 = 16K, 1 = 48K, 2 = 128K, 3 = +2, 4 = +2B, 5 = +3, 6 = ZX-Uno, 7 = Next, 8 = CPC 464, 9 = CPC 664, 10 = CPC 6128, 11 = SAM Coupé, 12 = MSX2, 13 = Commodore 64), `ochenta_destroy`, `ochenta_set_model`, `ochenta_get_model`, `ochenta_set_next_dir`, `ochenta_version`, `ochenta_last_error` |
| Running | `ochenta_start`, `ochenta_stop` (the thread; `ochenta_start` runs it again), `ochenta_pause`, `ochenta_resume`, `ochenta_reset`, `ochenta_set_sound`, `ochenta_set_turbo` |
| Screen | `ochenta_attach_window`, `ochenta_detach_window`, `ochenta_set_display` (deinterlace 0-2, black and white, scanlines), `ochenta_get_frame`, `ochenta_set_frame_callback` |
| CPU | `ochenta_get_reg`, `ochenta_set_reg` (AF, BC, DE, HL, their alternates, IX, IY, SP, PC, I, R, IM, IFF1, IFF2) |
| Memory | `ochenta_read_mem`, `ochenta_write_mem` (as the CPU sees it), `ochenta_set_rom_writable`, `ochenta_ram_bank_count`, `ochenta_read_ram_bank`, `ochenta_write_ram_bank` (the physical 16K RAM banks) |
| Paging | `ochenta_get_paging` (7FFD, 1FFD, what is in each 16K slot, the DivMMC...; on the SAM Coupé: `Port7FFD` is LMPR, `Port1FFD` is HMPR, `UnoConf` is VMPR, and the slots hold a RAM page, -1 for ROM0 or -2 for ROM1), `ochenta_write_port` (7FFD, 1FFD; on the SAM Coupé `FA` LMPR, `FB` HMPR, `FC` VMPR, `FE` border, `F9` line interrupt, and `F8` with the CLUT entry in the high byte), `ochenta_set_slot3_bank`, `ochenta_next_reg_get`, `ochenta_next_reg_set` (the Next's MMU is in its registers 50-57) |
| Debugging | `ochenta_set_breakpoint`, `ochenta_get_breakpoint` (flags: 1 execution, 2 read, 4 write, 128 disabled), `ochenta_clear_breakpoints`, `ochenta_step_into`, `ochenta_step_over`, `ochenta_run_to` (they pause the machine first), `ochenta_get_state` (running, paused, why it stopped, PC, frames, fps...), `ochenta_get_break_reason` |
| Loading | `ochenta_load_ram` (bytes into memory, then `ochenta_set_reg` PC), `ochenta_load_file` (.sna, .z80, .e80, .nex; a .tap or .tzx is inserted and loaded) |
| Input | `ochenta_key`, `ochenta_set_kempston` |

Every call that touches the machine takes the engine's lock, so a host can call from its UI thread while the
machine runs.

**Building.** `src/lib/build-lib.sh` (from WSL or Linux) makes `build/lib/ochentalib.dll` with the Windows compiler
of Lazarus, or `libochenta.so` with `fpc` (`src/lib/build-lib.sh linux`). The Windows compiler of Lazarus is 32 bits, so
the DLL is 32 bits and the host program must be as well (`/platform:x86`); a 64-bit DLL needs a Win64 Free Pascal.
Neither the library nor the host demo needs Lazarus's LCL.

**In the packages.** The Windows .zip and the Linux .deb and .rpm have a `lib` folder (in the Linux ones, `/usr/lib/ochenta/lib`) with the library and this file, and a `tests` folder with the C# demo (`tests/OchentaHostDemo`: sources and `build.bat`; the .zip has the program built as well).

**The C# demo.** `tests/csharp/OchentaHostDemo` is a WinForms program with the Spectrum's screen in a panel and buttons for
pause, registers, memory, paging, breakpoints, stepping and for destroying and creating the panel again without
losing the machine; `tests/csharp/OchentaHostDemo/build.bat` builds it with the .NET Framework's compiler to
`build/csharp` (no .NET SDK needed). `OchentaHostDemo.exe --selftest` runs a script of checks on the panel's real
pixels (the picture is in the panel and nowhere else, it follows resizes, the machine is paused and its registers
and memory changed, a different RAM bank paged in changes what the program does, the panel is destroyed and a new
one shows the same machine), writes `selftest.log` and screenshots, and exits with 0 if all pass.

## Tests

`tests/libtest.lpr` calls the API from Pascal (it is part of `tests/run-tests.sh`), and the C# demo above tests it
with a real screen.
