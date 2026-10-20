SnapToZX80.bas, version 3 readme

SnapToZX80.bas is a short NextBASIC program by Simon N Goodwin that
extracts a standard '.o' file containing the ZX80 BASIC program and
variables from a 128K snapshot file. The result loads back into the 
emulator on Next from the file browser, and is compatible with other
ZX80 emulators and ZXpand.

SnapToZX80.bas is released under the CC-BY-NC-SA version 4 License
(https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode)

SnapToZX80 uses the NextZXOS file browser to show and allow selection
of .Z80 snapshots. It checks the system variables to ensure the file
contains valid ZX80 BASIC, so programs which are all or mainly machine
code will be rejected if the interpreter variables have been clobbered.
 
Since release 2.07 NextZXOS allows snapshots to be saved from the ZX80
emulator. This makes it more useful for ZX80 development (and the Next
keyboard helps) but the resultant files are over 128K long, regardless of
the program content, and cannot be loaded back into a ZX80 with ZXpand 
or any of the emulators like ZX-SP which use the concise .o file format, 
identical to the bytes SAVEd to cassette tape by the real thing.

SnapToZX80.bas uses .EXTRACT to pull 16K from offset 82025 in the 
uncompressed snapshot file - this corresponds to the 16K RAM available
for BASIC on the original expanded machine - and DPEEKs the offsets 
just past the end of the variables to determine how much of that is 
valid BASIC code and variable values. The offset %b allows original 
ZX80 system variable addresses, from the manual, to be cited although 
the data is loaded to the top 16K of the Z80n address space.

I hope some of you find this useful. 

Ideally .o file output would be added to future updates of Paul Farrow’s
emulator (made for the Spectrum 128, hence the quirks on Next) but in the 
meantime, or until we have a true ZX80 core for Next, here’s a way to stay 
compatible and be able to share ZX80 experiments from Next with the wider
community. 

Simon N Goodwin, Warwick UK, April 2023