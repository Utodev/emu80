Nextramon is Copyright 1982 - 2023 by Simon N Goodwin.
The latest is always at: simon.mooli.org.uk/nextech/

Nextramon is released under the CC-BY-NC-SA version 4 License
(https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode)



Nextramon - semi-intelligent disassembler and memory monitor
============================================================

Nextramon.bas This development and investigation tool reads 
ROM or RAM and decodes the Z80 assembly-language (mnemonic 
machine code), ZX 40-bit floating point language - used 
for much of the BASIC runtime code, and by native ZX compilers 
- ASCII text or numbers wherever you point it, to your screen 
or printer. It's a NextBASIC disassembler and memory monitor, 
capable of disassembling all the Z80N instructions including 
Nextras, Floating point calculator (FPC) language codes, System
Variables directly addressed or by indexing the IY register,
Sinclair reports and Interface 1, GDOS and Unidos hook codes. 
Memory areas can also be displayed as text, hex or decimal.

This is a major update and bugfix for Spectramon, a Z80 
disassembler written in ZX BASIC first published in ZX Computing
 magazine. Simon wrote the original on his new Spectrum in 1982, 
in a three-day marathon attempt to get to grips with keyword 
entry and adapt from TRS-80 BASIC.

The original program was documented and listed in the April/May
and June/July 1983 issues of ZX Computing, and later sold on 
cassette by Argus Press Software. Just for good measure, Argus 
also ran it, over nine pages, in the Spring 1984 issue of 
Personal Software magazine. An extended version for Sam Coupe 
appeared in issue 33 of the Sam Supplement disc magazine.

The current update knows about 182 of the System Variables 
stored in memory between 23552 TO 23733, and can use their 
symbolic names instead of numbers in the disassembly, making 
it easier to see what compiled code and ROM routines are doing.
 
Since you may be disassembling code that overwrites the system
data or pages other memory to those addresses, there is a new 
option in the main menu - type S to toggle whether or not 
System variable names are shown in disassembly when 
corresponding addresses or offsets are encountered.

The NextZXOS 2.08 versions are faster, though still not
as fast as a disassembler written well in machine code. 
They select 28 MHz with RUN AT 3 from the start, to take full 
advantage of the Next. They still give nonsensical results, 
like any dissembler, if you disassemble memory that does 
not contain valid Z80 code. You can avoid this by checking 
with the A or N options. if you're looking for ROM patches, 
these are a quicker way to find them than by paging through 
the disassembly. Addresses may be entered in decimal or hex 
- add a H suffix or $ prefix if the hex address contains no
letters, to avoid ambiguity.

System Variables are identified by Nextramon in two contexts. 
The Spectrum ROM expects the IY register to point into the 
system variables specifically at address 23610 (5C3AH) 
which holds ERRNR, the error report code. The interrupt 
routine which polls the keyboard at the start of each 
display field relies on this, which is why the Next 
manual says machine code called from BASIC must preserve 
that value. The same assumption is made in many places 
in the Spectrum ROM and system-friendly programs, so 
Nextramon checks the offsets associated with code 
references to the IY register and substitutes symbolic 
names if the offsets fall within the range of System 
Variables documented in all the Spectrum Manuals. 
Extras added in the ZX printer buffer (before the 
original system variables) are not detected as they 
fall out of the 8-bit signed range accessible via IY.

Often the ROM uses IY to access system variables, but 
sometimes it uses the 16-bit addresses directly, e.g. 
when transferring values between memory and the HL 
register. To cater for this, Nextramon checks 16-bit 
addresses used in load and store instructions and if 
they fall into the relevant range it substitutes 
names for numbers then as well, as long as the 'S' 
option is enabled in the menu. Since the symbolic 
values are offsets relative to address 23610, for 
compatibility with indexing IY, an extra symbolic 
constant SV is added to the absolute value; to 
reassemble code that uses either indexed or direct 
addressing, equate SV to 23610 in your assembler.

The mnemonic names are essentially those used in 
Spectrum manuals and Ian Logan's ROM disassembly, 
except that underscores are omitted as not all 
assemblers support them, and the names are unambiguous 
without them; when names differ between ZXOS versions 
the Next label is generally used. Next's STIMEOUT 
is an outlier (Sinclair labels were 6 bytes max) 
but it just fits the array. Many of the system 
variables occupy multiple bytes, so in the case 
of word pointers the label is used for the first 
(low order) byte and the same label with +1 appended 
appears if the second byte is accessed. KSTATE is 
similar so what Logan calls KSTATE4 is KSTATE+4 in 
the disassembly.

The large tables of stream pointers and calculator
workspace are specially handled to show the internal 
structure; for instance the 30 byte workspace is 
shown as six five-byte memory areas, labelled MEM0 
to MEM5 matching references to those in the Floating 
point calculator language. Those labels point to the 
exponent of each value. Suffixes +1 to +4 refer to 
the mantissa bytes, e.g. MEM5+4 is the label of the 
last byte of workspace. Streams use 38 bytes, with 
a pair for each channel number from #-3 to #15. For 
the negative streams it has to use M instead of the 
minus sign as '-' is treated as an operator by most 
assemblers. Streams accessible to BASIC use 
corresponding positive numbers in the internal 
labels, e.g. STRM15+1 for the last byte of the 
last stream pointer.

Nextramon automatically switches between Z80N and FPC machine 
language byte encodings after a RST 40 instruction which 
switches the Spectrum to expect FPC code, but sometimes FPC 
code is entered directly via a branch from other FPC code. 
The F option allows you to start disassembly in FPC mode, 
whereas D defaults to Z80N instructions. FPC code is extensively
used in the original Spectrum ROM and generated code from ZX 
compilers that support Sinclair's five-byte floating point 
format. The rendering of embedded floating-point constants in 
FPC code has been tidied again in the latest release.

Nextramon uses Timex 2068 HiRes (LAYER 1,2) for a 64-column
display. It supports the Alphacom and ZX printers, and other 
printers which are fully compatible with NextBASIC.

For more details browse the NextGuide by typing this command:

.GUIDE Nextramon


Simon N Goodwin, Warwick UK, October 2023 