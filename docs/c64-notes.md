# Commodore 64: implementation notes

How the C64 is built in emu80 (for whoever maintains it; the user's documentation is README.md > Commodore 64).

## Files

| File | What |
|---|---|
| `src/Cpu6510.pas` | The 6510/6502 core (also the 1541's CPU). Every cycle is a `Read` or a `Write` on a `T6502Bus`, in the real order (dummy reads, the double write of read-modify-write instructions, page-cross cycles). Undocumented opcodes, from the table `OpName`/`OpMode` (also the disassembler's). |
| `src/C64Vic.pas` | The 6569, after Christian Bauer's VIC-II article. `Tick` is one cycle: bad lines, VC/VCBASE/RC/VMLI, c- and g-accesses, the sprite pointer/DMA cycles (MC, MCBASE, Y expansion flip-flop), the border flip-flops compared per pixel, 8 pixels rendered per cycle into a 352x288 frame (raster 7.., x 8..). `BaLow` and `BaRun` tell the CPU when it is held. |
| `src/C64Cia.pas` | 6526: timers A/B (clock and underflow modes), the ICR, the TOD (50 Hz input), the FLAG pin, the ports (the machine gives the pins' external levels through `OnPortA/B`). |
| `src/C64Sid.pas` | 6581. Writes are kept with their cycle and replayed when the frame's audio is made (`Generate`); oscillators, ADSR (rate counter + exponential counter) and noise are clocked every cycle, the SVF filter once per sample. Combined waveforms are the AND of the parts, damped. |
| `src/C64Via.pas`, `src/C64Drive.pas`, `src/C64Disk.pas` | The 1541: 6502 + two 6522 + 2K RAM + `VC1541.rom`; the head, the motor, the byte timer (26-32 cycles per GCR byte by speed zone), the write head; `TIecBus` (open collector lines); `.d64` <-> GCR (`BuildTrack`, `TrackWritten`). Sync is a run of two or more `$FF` bytes (a lone one can be data). |
| `src/C64.pas` | The machine: PLA banking from the 6510's port, I/O, keyboard matrix and joysticks, the cassette (`TC64Tape`: pulses from a `.tap`), the drives, audio, breakpoints, PRG injection, typing through the KERNAL's keyboard buffer, the auto load state machine. `Clock` runs every chip one cycle on each CPU access. |
| `src/C64Expr.pas`, `src/C64Disasm.pas`, `src/C64Help.pas`, `src/C64Debugger.pas` | The debugger, laid out like the Z80 one, and its mnemonic hints (not translated, like the Z80 one). |
| `src/SpectrumC64.inc`, `src/MainC64.inc` | The glue: `TSpectrum` holds a `TC64` as it holds the CPC's or MSX's hardware (frame loop, picture, sound, memory for the debuggers, tape); the main window's keyboard, files, drives and tapes. |

## Timing

The VIC-II's cycle is the machine's: 63 cycles a line, 312 lines, 19656 cycles a frame (`C64_CLOCK` 985248 Hz, 50.12 fps). `Read` waits while `BaLow` (the first read cycle after BA falls halts the CPU; writes go on for three cycles), so a bad line costs the CPU 40-43 cycles and a sprite 2. A register write is seen by the VIC-II from the next cycle's tick.
The 1541 runs on credit: every computer cycle adds 1.015 drive cycles, and the drive's CPU steps while it has credit, so the two are never more than one instruction apart.
Interrupts are looked at between instructions (the 6502 samples them in the last cycle; the I flag's delay after CLI/SEI/PLP is not reproduced).

## Serial bus (IEC)

Inputs of the computer (CIA 2 port A bits 6-7) read the line levels (1 = high); its outputs (bits 3-5) hold a line low when set. The drive's VIA 1 reads the lines inverted (1 = low) and its ATN input also goes to CA1; its outputs PB1 (DATA) and PB3 (CLK) hold a line low when set, and the "ATN acknowledge" gate holds DATA low when ATN is low XOR PB4 (ATNA) is set. Verified by running the real DOS and KERNAL.

## DAAD (Adventure Debugger)

`Daad.pas` has `MACHINE_C64 = 2` (the database header's second byte, high nibble) and `DDB_BASE_C64 = $3880`; the interpreter's flags are at `C64_DAAD_FLAGS = $3880 - 514 = $367E` (`USER = VERSNO-514` in the interpreter's source; its `FLAG` at `$02A7` is the interpreter's own workspace, not the game's flags). `TSpectrum.DaadRead` is called by `TC64.Read` for the addresses the map flags (`OnDaadRead`) and learns the interpreter's fetch instruction as on the Z80 machines.

## Not done

Cartridges, user port, REU, `.t64`/`.g64`, SAVE to tape, snapshots (and the debugger's step back), a `.d64` directory browser, the 8580, the datasette's sound, the exact timing of the VIC-II's unstable effects (sprite crunching, the DMA delay on certain instructions), the 6502's interrupt polling details.
