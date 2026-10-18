# Project

This is a ZX Spectrum Emulator made with  Lazarus (Free Pascal) using LCL

# Target

- Properly emulate Spectrum 48K, Spectrum 128K, Spectrum +2, Spectrum +2B and Spectrum +3
- Perfect Z80 timing, condented memory, etc. so games run at real speed
- Possible to load TAP, SNA, Z80 and DSK files.
- Tape browser that allows deleting or moving blocks
- A proper menu, settings and a quick button bar to change model, reset and NMI

# Documentation

- `README.TXT` (shown by Help > Documentation and `--help`) explains how pzx works and all
  its command line options. ALWAYS keep it up to date: any change to features, menus, keys,
  settings or command line options must be reflected in it in the same change.

# Building

- Release number: before EVERY build, write the current date and time as the release number (YYYYMMDDHHMM)
  into `src/Release.inc`, which the About box shows:
  `printf "{ Release number: the build date and time (YYYYMMDDHHMM), written before every build (see CLAUDE.md) }\nconst\n  PZX_RELEASE = '%s';\n" "$(date +%Y%m%d%H%M)" > src/Release.inc`

- `lazbuild src/pzx.lpi` writes `pzx.exe` into `src/` (so it builds from any folder or drive).
  When Claude builds it, move the result to the repository's top folder afterwards
  (`mv -f src/pzx.exe pzx.exe`) so it sits next to `roms/`, `esxdos/`, `README.TXT` and
  `LICENSE`. When the user builds it from Lazarus it stays in `src/`, which also works.

