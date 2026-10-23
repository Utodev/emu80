The user manual of the emu80 program is in [README.md](README.md). This file is about the native library only.

# Native library for a host application

The emulation engine (the same one the program runs: the Z80, the memory, the video, the peripherals) can be
built as a native library, `e80lib.dll` (Windows) or `libe80.so` (Linux), that a host application loads **into
its own process**: a C# GUI through P/Invoke, for instance. The program, `emu80.exe`, is unchanged and keeps
working on its own; both use the same engine and the same code for the picture (`src/FramePresenter.pas`:
scaling, black and white, scanlines and [deinterlacing](README.md#deinterlacing)).

**The screen.** The host gives a window to draw in: on Windows, the window handle of one of its controls (a
WinForms `Panel`, a WPF `HwndHost`...) goes to `emu80_attach_window`, and the library draws the frames there as the
machine produces them, fitted to the control's size (in proportion, with black bands, a whole-number scale when
the size allows it) and following it when it is resized. It opens no window and shows no menu of its own. The
host controls the picture's life: `emu80_detach_window` before its control is destroyed, `emu80_attach_window` to
another one later, with the machine going on meanwhile. A control that is drawn on by the library should leave its
painting alone (in WinForms: a `Panel` with the styles `Opaque`, `AllPaintingInWmPaint` and `UserPaint`, and empty
`OnPaint` and `OnPaintBackground`). A toolkit that wants to draw the picture itself (WPF's `WriteableBitmap`, for
instance) takes the frames with `emu80_get_frame` (32-bit BGRA, any whole scale), told by `emu80_set_frame_callback` (from
the emulation thread) that one is ready. Drawing into a host window is Windows only; `emu80_get_frame` works everywhere.

**Input** is the host's: it tells the keys (`emu80_key`, key = row * 5 + bit of the Spectrum's keyboard, 0 = CAPS
SHIFT, 35 = SPACE, 36 = SYMBOL SHIFT) and the Kempston joystick (`emu80_set_kempston`). On an Amstrad CPC model
(8 = CPC 464, 9 = CPC 664, 10 = CPC 6128) the key is line * 8 + bit of the CPC's keyboard matrix (0 to 79, as the
`CPCK_*` constants of `src/Amstrad.pas`: 0 = cursor up, 21 = SHIFT, 18 = RETURN, 47 = SPACE, 72-77 = joystick 1
up, down, left, right, fire 1, fire 2, 79 = DEL); `emu80_load_file` takes `.cdt` tapes, and `emu80_ram_bank_count` is 4
(CPC 464 and 664) or 8 (CPC 6128).

**The API** is plain C (cdecl) with opaque handles, `int32` and pointers (see `src/lib/Emu80Api.pas`; the C# wrapper is
`tests/csharp/Emu80HostDemo/Emu80.cs`). Calls return 0 (or a count) on success and a negative number on failure, with
`emu80_last_error` saying why. It has:

| Group | Calls |
|---|---|
| Instance | `emu80_create(model, romFolder)` (model as in the machine list: 0 = 16K, 1 = 48K, 2 = 128K, 3 = +2, 4 = +2B, 5 = +3, 6 = ZX-Uno, 7 = Next, 8 = CPC 464, 9 = CPC 664, 10 = CPC 6128), `emu80_destroy`, `emu80_set_model`, `emu80_get_model`, `emu80_set_next_dir`, `emu80_version`, `emu80_last_error` |
| Running | `emu80_start`, `emu80_stop` (the thread; `emu80_start` runs it again), `emu80_pause`, `emu80_resume`, `emu80_reset`, `emu80_set_sound`, `emu80_set_turbo` |
| Screen | `emu80_attach_window`, `emu80_detach_window`, `emu80_set_display` (deinterlace 0-2, black and white, scanlines), `emu80_get_frame`, `emu80_set_frame_callback` |
| CPU | `emu80_get_reg`, `emu80_set_reg` (AF, BC, DE, HL, their alternates, IX, IY, SP, PC, I, R, IM, IFF1, IFF2) |
| Memory | `emu80_read_mem`, `emu80_write_mem` (as the CPU sees it), `emu80_set_rom_writable`, `emu80_ram_bank_count`, `emu80_read_ram_bank`, `emu80_write_ram_bank` (the physical 16K RAM banks) |
| Paging | `emu80_get_paging` (7FFD, 1FFD, what is in each 16K slot, the DivMMC...), `emu80_write_port` (7FFD, 1FFD), `emu80_set_slot3_bank`, `emu80_next_reg_get`, `emu80_next_reg_set` (the Next's MMU is in its registers 50-57) |
| Debugging | `emu80_set_breakpoint`, `emu80_get_breakpoint` (flags: 1 execution, 2 read, 4 write, 128 disabled), `emu80_clear_breakpoints`, `emu80_step_into`, `emu80_step_over`, `emu80_run_to` (they pause the machine first), `emu80_get_state` (running, paused, why it stopped, PC, frames, fps...), `emu80_get_break_reason` |
| Loading | `emu80_load_ram` (bytes into memory, then `emu80_set_reg` PC), `emu80_load_file` (.sna, .z80, .e80, .nex; a .tap or .tzx is inserted and loaded) |
| Input | `emu80_key`, `emu80_set_kempston` |

Every call that touches the machine takes the engine's lock, so a host can call from its UI thread while the
machine runs.

**Building.** `src/lib/build-lib.sh` (from WSL or Linux) makes `build/lib/e80lib.dll` with the Windows compiler
of Lazarus, or `libe80.so` with `fpc` (`src/lib/build-lib.sh linux`). The Windows compiler of Lazarus is 32 bits, so
the DLL is 32 bits and the host program must be as well (`/platform:x86`); a 64-bit DLL needs a Win64 Free Pascal.
Neither the library nor the host demo needs Lazarus's LCL.

**In the packages.** The Windows .zip and the Linux .deb and .rpm have a `lib` folder (in the Linux ones, `/usr/lib/emu80/lib`) with the library and this file, and a `tests` folder with the C# demo (`tests/Emu80HostDemo`: sources and `build.bat`; the .zip has the program built as well).

**The C# demo.** `tests/csharp/Emu80HostDemo` is a WinForms program with the Spectrum's screen in a panel and buttons for
pause, registers, memory, paging, breakpoints, stepping and for destroying and creating the panel again without
losing the machine; `tests/csharp/Emu80HostDemo/build.bat` builds it with the .NET Framework's compiler to
`build/csharp` (no .NET SDK needed). `Emu80HostDemo.exe --selftest` runs a script of checks on the panel's real
pixels (the picture is in the panel and nowhere else, it follows resizes, the machine is paused and its registers
and memory changed, a different RAM bank paged in changes what the program does, the panel is destroyed and a new
one shows the same machine), writes `selftest.log` and screenshots, and exits with 0 if all pass.

## Tests

`tests/libtest.lpr` calls the API from Pascal (it is part of `tests/run-tests.sh`), and the C# demo above tests it
with a real screen.
