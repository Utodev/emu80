SnapToZX81.bas, version 6 readme

SnapToZX81.bas is a short NextBASIC program by Simon N Goodwin that
extracts a standard '.p' (sometimes stored with a .81 extension) file 
containing the ZX81 BASIC program and variables from a 128K snapshot 
file. The result loads back into the emulator on Next from the file 
browser, and is compatible with other ZX81 emulators and ZXpand.

The key reason for this utility, besides saving 100-odd K per time, is to
make it easy for ZX81 software developed or extended on Next to be shared 
back to the Sinclair/Timex community in the well-established format they 
(and their emulators, ZXpand etc) can read and write. 

Ideally .p file output would be added to future updates of Paul Farrow’s
emulator (made for the Spectrum 128, hence the quirks on Next) but in the 
meantime, or until we have a true ZX81 core for Next, here’s a way to stay 
compatible and be able to share ZX81 experiments from Next with the wider
community. 

SnapToZX81.bas is released under the CC-BY-NC-SA version 4 License
(https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode)

SnapToZX81 uses the NextZXOS file browser to show and allow selection
of .Z80 snapshots. It checks the system variables to ensure the file
contains valid ZX81 BASIC, so programs which are all or mainly machine
code will be rejected if the interpreter variables have been clobbered.

A ZX81 cassette SAVE (or these equivalent bytes in a .P or .81 file)
holds the contents of memory from address 16393, early in the system 
variables, up to the marker at the end of the VARS area. Output files
of up to 16K in length - Sinclair’s limit - are supported.

These .p files include the BASIC program, display file and variables. 
Simon and members of the Facebook Spectrum Next Dev group have tested 
this with various ZX BASIC programs and the CAVE81 game in the distro’s
GAMES/ZX81 subdirectory.

After double-conversion that example does not auto-run, but RUN fixes 
that. The machine-code 3D games by Malcolm Evans do not convert because 
they override the usual ZX81 memory map, but standard ZX BASIC programs
- including those which contain embedded machine code - are convertable.

I hope some of you find this useful. If you have improvements or comments
the author can be contacted via the web page http://simon.mooli.org.uk

Simon N Goodwin, Warwick UK, April 2023


P.S. One tip for those using the Next menus for ZX80/81 emulation - the 
NMI screenshot standard and print options do not work, but the ULA shadow 
screenshot item does capture the ZX80 or ZX81 screen, as a standard 6.75K 
Spectrum SCREEN$ which you can print later with LOAD .. SCREEN$ : COPY