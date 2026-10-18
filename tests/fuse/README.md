# FUSE Z80 core tests

`tests.in` and `tests.expected` come from the [FUSE emulator](https://fuse-emulator.sourceforge.net/)
source tree (`z80/tests/`), copyright Philip Kendall and contributors, GPL v2 or later.

Each test sets up registers and memory, runs until a T-state count is reached and lists
every memory/port access with its T-state, so they check per-cycle timing as well as results.

`known-differences.txt` lists tests where pzx intentionally differs from FUSE.
Run everything with `tests/run-tests.sh`.
