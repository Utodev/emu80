# Project

This is a ZX Spectrum Emulator made with  Lazarus (Free Pascal) using LCL

# Documentation

- `README.md` (shown by Help > Documentation and `--help`) explains how pzx works and all
  its command line options. ALWAYS keep it up to date: any change to features, menus, keys,
  settings or command line options must be reflected in it in the same change.

# Building

- Release number: before EVERY build, write the current date and time as the release number (YYYYMMDDHHMM)
  into `src/Release.inc`, which the About box shows:
  `printf "{ Release number: the build date and time (YYYYMMDDHHMM), written before every build (see CLAUDE.md) }\nconst\n  PZX_RELEASE = '%s';\n" "$(date +%Y%m%d%H%M)" > src/Release.inc`

- `lazbuild src/pzx.lpi` writes `pzx.exe` into `src/` (so it builds from any folder or drive).
  When Claude builds it, move the result to the repository's top folder afterwards
  (`mv -f src/pzx.exe pzx.exe`) so it sits next to `roms/`, `esxdos/`, `README.md` and
  `LICENSE`. When the user builds it from Lazarus it stays in `src/`, which also works.

# Beware

The specnext folder won't be added to any package. It requires license. The folder will be created by the packages, but empty. When running the emulator in Spectrum Next mode, if the folder is empty, the emulator would show
a message saying you need to add the latest distribution to the specnext folder.

All settings options should have a ini file equivalence, and a command line parameter equivalence. Command line parameters should have a default value when missing.