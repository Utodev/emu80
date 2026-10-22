The user manual of the pzx program is in [README.md](README.md). This file is about the native library only.

# Native library for a host application

The emulation engine (the same one the program runs: the Z80, the memory, the video, the peripherals) can be
built as a native library, `pzxlib.dll` (Windows) or `libpzxlib.so` (Linux), that a host application loads **into
its own process**: a C# GUI through P/Invoke, for instance. The program, `pzx.exe`, is unchanged and keeps
working on its own; both use the same engine and the same code for the picture (`src/FramePresenter.pas`:
scaling, black and white, scanlines and [deinterlacing](README.md#deinterlacing)).

**The screen.** The host gives a window to draw in: on Windows, the window handle of one of its controls (a
WinForms `Panel`, a WPF `HwndHost`...) goes to `pzx_attach_window`, and the library draws the frames there as the
machine produces them, fitted to the control's size (in proportion, with black bands, a whole-number scale when
the size allows it) and following it when it is resized. It opens no window and shows no menu of its own. The
host controls the picture's life: `pzx_detach_window` before its control is destroyed, `pzx_attach_window` to
another one later, with the machine going on meanwhile. A control that is drawn on by the library should leave its
painting alone (in WinForms: a `Panel` with the styles `Opaque`, `AllPaintingInWmPaint` and `UserPaint`, and empty
`OnPaint` and `OnPaintBackground`). A toolkit that wants to draw the picture itself (WPF's `WriteableBitmap`, for
instance) takes the frames with `pzx_get_frame` (32-bit BGRA, any whole scale), told by `pzx_set_frame_callback` (from
the emulation thread) that one is ready. Drawing into a host window is Windows only; `pzx_get_frame` works everywhere.

**Input** is the host's: it tells the keys (`pzx_key`, key = row * 5 + bit of the Spectrum's keyboard, 0 = CAPS
SHIFT, 35 = SPACE, 36 = SYMBOL SHIFT) and the Kempston joystick (`pzx_set_kempston`).

**The API** is plain C (cdecl) with opaque handles, `int32` and pointers (see `src/lib/PzxApi.pas`; the C# wrapper is
`tests/csharp/PzxHostDemo/Pzx.cs`). Calls return 0 (or a count) on success and a negative number on failure, with
`pzx_last_error` saying why. It has:

| Group | Calls |
|---|---|
| Instance | `pzx_create(model, romFolder)` (model as in the machine list: 0 = 16K, 1 = 48K, 2 = 128K, 3 = +2, 4 = +2B, 5 = +3, 6 = ZX-Uno, 7 = Next), `pzx_destroy`, `pzx_set_model`, `pzx_get_model`, `pzx_set_next_dir`, `pzx_version`, `pzx_last_error` |
| Running | `pzx_start`, `pzx_stop` (the thread; `pzx_start` runs it again), `pzx_pause`, `pzx_resume`, `pzx_reset`, `pzx_set_sound`, `pzx_set_turbo` |
| Screen | `pzx_attach_window`, `pzx_detach_window`, `pzx_set_display` (deinterlace 0-2, black and white, scanlines), `pzx_get_frame`, `pzx_set_frame_callback` |
| CPU | `pzx_get_reg`, `pzx_set_reg` (AF, BC, DE, HL, their alternates, IX, IY, SP, PC, I, R, IM, IFF1, IFF2) |
| Memory | `pzx_read_mem`, `pzx_write_mem` (as the CPU sees it), `pzx_set_rom_writable`, `pzx_ram_bank_count`, `pzx_read_ram_bank`, `pzx_write_ram_bank` (the physical 16K RAM banks) |
| Paging | `pzx_get_paging` (7FFD, 1FFD, what is in each 16K slot, the DivMMC...), `pzx_write_port` (7FFD, 1FFD), `pzx_set_slot3_bank`, `pzx_next_reg_get`, `pzx_next_reg_set` (the Next's MMU is in its registers 50-57) |
| Debugging | `pzx_set_breakpoint`, `pzx_get_breakpoint` (flags: 1 execution, 2 read, 4 write, 128 disabled), `pzx_clear_breakpoints`, `pzx_step_into`, `pzx_step_over`, `pzx_run_to` (they pause the machine first), `pzx_get_state` (running, paused, why it stopped, PC, frames, fps...), `pzx_get_break_reason` |
| Loading | `pzx_load_ram` (bytes into memory, then `pzx_set_reg` PC), `pzx_load_file` (.sna, .z80, .pzs, .nex; a .tap or .tzx is inserted and loaded) |
| Input | `pzx_key`, `pzx_set_kempston` |

Every call that touches the machine takes the engine's lock, so a host can call from its UI thread while the
machine runs.

**Building.** `src/lib/build-lib.sh` (from WSL or Linux) makes `build/lib/pzxlib.dll` with the Windows compiler
of Lazarus, or `libpzxlib.so` with `fpc` (`src/lib/build-lib.sh linux`). The Windows compiler of Lazarus is 32 bits, so
the DLL is 32 bits and the host program must be as well (`/platform:x86`); a 64-bit DLL needs a Win64 Free Pascal.
Neither the library nor the host demo needs Lazarus's LCL.

**In the packages.** The Windows .zip and the Linux .deb and .rpm have a `lib` folder (in the Linux ones, `/usr/lib/pzx/lib`) with the library and this file, and a `tests` folder with the C# demo (`tests/PzxHostDemo`: sources and `build.bat`; the .zip has the program built as well).

**The C# demo.** `tests/csharp/PzxHostDemo` is a WinForms program with the Spectrum's screen in a panel and buttons for
pause, registers, memory, paging, breakpoints, stepping and for destroying and creating the panel again without
losing the machine; `tests/csharp/PzxHostDemo/build.bat` builds it with the .NET Framework's compiler to
`build/csharp` (no .NET SDK needed). `PzxHostDemo.exe --selftest` runs a script of checks on the panel's real
pixels (the picture is in the panel and nowhere else, it follows resizes, the machine is paused and its registers
and memory changed, a different RAM bank paged in changes what the program does, the panel is destroyed and a new
one shows the same machine), writes `selftest.log` and screenshots, and exits with 0 if all pass.

## Tests

`tests/libtest.lpr` calls the API from Pascal (it is part of `tests/run-tests.sh`), and the C# demo above tests it
with a real screen.
