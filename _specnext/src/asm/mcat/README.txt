The TIMBUCUS submission - MCAT
------------------------------

Version 0.4

Much of this has been based on the code written for PAW back in the 80's and
tried, apart from a modern assembler Z80ASM to use on machine development and
debugging techniques as much as anything to document the process.

Credits
Phil Wade - PAW Microdrive Code
Hisoft and Andy Pennell for the Extended Cat in Devpac3M2 (which I own...)
Gianluca Carri and Ian Logan/Frank O'Hara for the ROM Dissasemblies.
All the live viewers for keeping me focussed and spotting lots of silly
mistakes and possible avenues.  Especially Henk with the actual source code
conversion.  Special Thanks to Rat Mal, Source Code, Ped, Dee, Jonathan Lin,
Tony Dang and em00k, Jason Bullough who were about on the livestream until the
bitter end.

Building:
---------

All the source can be built with:

z80asm -m -v -l -s -b name.asm
assemble mcatmain.asm to create the BIN before doing mcat.asm as it includes it!

Compatability:
--------------

This works fully only under NextZXOS. The -i option allows use under ESXDOS as
it leaves you using the Microdrives as needed - WARNING other functions can erase
your cartridges and SD cards so DONT DO THEM....

I could not test on a Version 2 IF1 but, the patch code is there and prev worked
TREAD CAREFULLY

The files provided are:
MCAT.DOT - the dot file itself
mcatmain.asm - the bit that has to go on page zero with a clear at least as low
as 61439 - the main DOT copies it here.
mcat.asm - the dot file when renamed from mcat.bin to MCAT.DOT or just put as
MCAT in the DOT or BIN directories of the relevant OS.

You need to provide some main memory with CLEAR 61439 or the system could
corrupt the stack or top of basic

Known Issues:
-------------

1) Loops under ESXDOS for the catalogue on the wrong drive number for some reason

2) In NextZXOS returns "C Nonsense in BASIC..." for some reason - investigating

3) Drive errors will halt the machine with a RED border - RESET is needed sorry!
(But that will stop your cart getting formatted like mine did during testing with
a random error) - investigating

Have we followed all the rules?
-------------------------------

Well the unwritten one was not to start before it opened which I did not just
gathering resoutces and setting my dev system up ready.

The rules:

1) The final .dot file can be no larger than 8K (so no bootstrapping more code into memory).

Well the bit that has to be in main memory is copied there when needed so yes

2) It is not required for the .dot file to return to the operating system.

Good because that may not actualy work yet but, but, we want it to to make it useful.

3) Any amount of memory can be used at run time, but no loading data not contained in the original 8K dot file.

OK good because we do use memory elsewhere.

4) You are not required to release source code, but it is encouraged to teach other people.

We have and also extra stuff for people to develop similar programs for other
old systems like OPUS and DiSCIPLE maybe.

5) A submission can come from a team of a people, not just a single programmer.

As above the livestream viewers have helped a lot.

6) Copyright and ownership is retained by the authors.

Yes

7) You can only load external files that the dot file produces itself.  The only exception to this rule is if the dot file is a tool that does data conversion where the input file is clearly used to produce an output file.

N/A yet although the COPY file option will fall into that category when written
