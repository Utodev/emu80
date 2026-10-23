# Project

This is a Z80 machines emulator made with  Lazarus (Free Pascal) using LCL

# Documentation

- `README.md` (shown by Help > Documentation and `--help`) explains how emu80 works and all
  its command line options. ALWAYS keep it up to date (the native library for host applications is documented in `LIBRARY.md`, not in the README, and the same goes for it; the packages put both in their `lib` folder, and the C# demo in `tests`): any change to features, menus, keys,
  settings or command line options must be reflected in it in the same change.

# Building

- Release number: before EVERY build, write the current date and time as the release number (YYYYMMDDHHMM)
  into `src/Release.inc`, which the About box shows:
  `printf "{ Release number: the build date and time (YYYYMMDDHHMM), written before every build (see CLAUDE.md) }\nconst\n  EMU80_RELEASE = '%s';\n" "$(date +%Y%m%d%H%M)" > src/Release.inc`

- Lazbuild de Windows está en /mnt/c/lazarus/lazbuild.exe
- Lazbuild de linux está en el path de WSL

- `lazbuild src/emu80.lpi` writes `emu80.exe` into `src/` (so it builds from any folder or drive).
  When Claude builds it, move the result to the repository's top folder afterwards
  (`mv -f src/emu80.exe emu80.exe`) so it sits next to `roms/`, `esxdos/`, `README.md` and
  `LICENSE`. When the user builds it from Lazarus it stays in `src/`, which also works.

# Beware

The specnext folder won't be added to any package. It requires license. The folder will be created by the packages, but empty. When running the emulator in Spectrum Next mode, if the folder is empty, the emulator would show
a message saying you need to add the latest distribution to the specnext folder.

All settings options should have a ini file equivalence, and a command line parameter equivalence. Command line parameters should have a default value when missing.

The `realspecnext` option (`[ZXNext]` in the ini file and `--realspecnext` on the command line) is deliberately hidden: NEVER document it, neither in README.md (so not in Help > Documentation or `--help` either), nor in the settings dialog, examples or any other user-facing text. Internal code comments are fine. Its accepted-warning key (`realspecnextok`) is hidden too.
