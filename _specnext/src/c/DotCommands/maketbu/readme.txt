=======
PURPOSE
=======

Catalog, add and extract fpga bitstreams contained in TBBLUE.TBU for all board issues.

".maketbu" executed on its own prints help.  Must be run from a directory containing a file named TBBLUE.TBU.


====================
BUILDING FROM SOURCE
====================

The dot commmand is greater than 8K and that is largely due to file buffers and text taking up more than 2K of memory.

The are two builds here:

(1)

The no-brainer is making a dotn command which is a dot command > 8K.  Z88DK automatically makes these by splitting the output binary into the normal 8K part and other parts placed into allocated memory.  It provides all the required code to allocate extra memory, load code into it, and return properly and cleanly to basic.

The build is controlled by options in "zpragma-dotn.inc".  The default is to locate the second part of the dot command at 0x8000 and the options in this file specify that the stack should be moved to an address at the top of the 8k page at 0x8000 and that the startup code should only allocate one 8K page for the spillover.  We can do this because the second part of the dot command easily fits into one 8K page.

Execute the windows "BUILD-DOTN.BAT" batch file to compile to a dotn dot command.  The size will be 16K containing two 8K pages.

(2) USED FOR DISTRO

The harder route is constructing a normal dot command but with some things moved into an allocated ram page to shrink it below the 8K limit.  This is easily done as there is about 2K of workspace and strings that can be easily separated from the main code.

The build is controlled by options in "zpragma-dot.inc".

Z88DK has a linking assembler which organizes the output binary according to a memory map.  The default behaviour for ZX builds is to build a single binary blob composed, broadly, of CODE/DATA/BSS segments.  CODE is ROM-able stuff like, well, code.  DATA is initialized data like "int a = 5;" and BSS is data that is initialized to zero.  The 2K of workspace in the output is contained in the DATA/BSS sections.  The CRT_ORG_DATA pragma separates both the DATA+BSS sections from the CODE (destined for divmmc memory at 0x2000) and places them at 0x8000.  The CRT_ORG_BSS pragma is an illegal address that indicates that the BSS section should still follow DATA but it should be output separately from DATA.

The output from the linker is going to be three binaries:  CODE, DATA, BSS.  The build script in "BUILD-DOT.BAT" gets Z88DK to produces these dot-command binaries.  Then the DATA section alone is compressed with ZX0.  This is then appended to the dot command.  The total size must be less than 8K as this whole lot is loaded into dot memory when the dot command is launched.

The code in "dot-data-bss.asm" contains intiialization code inserted into the dot command startup.

"SECTION code_crt_init" is a location where user code can be inserted before main() is called.  The code inserted does several things:  it allocates a single 8K page of memory from the operating system, it places the page at address 0x8000 (mmu4) and then it decompresses the compressed DATA section that was appended to the CODE section to that page.  After that it zeroes the BSS section.  The labels "__CODE_END", "__BSS_head", etc are labels from the memory map that demarcate address boundaries between the sections.

Code is also added to "SECTION code_crt_exit" which is run after main() returns.  Here the allocated memory page must be deallocated to the operating system before return to basic.

Some extra data is added to "SECTION code_user" which is part of the CODE section and therefore part of the portion of the dot command located in divmmc memory.  Memory is set aside to hold a custom error string -- this error string must be located in divmmc memory so that basic can retrieve it.  The "error_noreturn(...)" function used for exit in "maketbu.c" prints custom errors into this buffer.

One very important gotcha is taken care of by the declaration of "_errno".  The C library (such as all the esxdos file operations and the call to the o/s for the memory page) is a thin encapsulation of the raw o/s api but it does return errors to C the normal way by recording error codes in the global variable "errno".  By explicitly placing it in divmmc memory, the C library will put error codes there instead of in the BSS section where the library would place it had "errno" not been defined.  This is important because before the page for the BSS section is allocated, there is a call to the o/s to allocate a page.  A generated error at that point would be written into main memory in the 0x8000-0xA000 range (where BSS is located) and would possibly contaminate an existing basic program.

Execute the windows "BUILD-DOT.BAT" batch file to compile to this dot command.  The size will be < 8K.  This is the version used for the distro.
 