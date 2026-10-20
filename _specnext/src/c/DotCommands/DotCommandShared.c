///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
#include "DotCommandShared.h"


/*
----
You can generate actual basic errors by returning a non-zero value.

The canned esxdos messages are here if one fits:

https://github.com/z88dk/z88dk/blob/master/include/_DEVELOPMENT/sdcc/arch/zxn/esxdos.h#L512

Or you can return a string with last char having bit 7 set.  Sometimes I try to match sinclair basic errors in form:

http://www.worldofspectrum.org/ZXBasicManual/zxmanappb.html


----
basename, dirname and pathnice are in <libgen.h>

https://github.com/z88dk/z88dk/tree/master/libsrc/_DEVELOPMENT/libgen/z80

they will not understand drive specifier but dirname/basename might help with -p.
They should work as in the posix standard:

http://pubs.opengroup.org/onlinepubs/009696799/functions/dirname.html

http://pubs.opengroup.org/onlinepubs/009604499/functions/basename.html

----
the user could do soemthing silly like 

.rmdir "  c:   /foo/thing"

pathnice removes leading whitespace by moving the ptr forward and removes trailing ws by writing a 0 to terminate the string early.
So the first pathnice will get you to c:.  You walk past that to the space.
Another pathnice (or a strstrip) will move to the / and then this is what dirname operates on.
dirname will write a 0 into the path to chop off the last part of the path.

so after first dirname you will have 

"c:   /foo"

and then 

"c:   /"

forever.  So termination condition is "." or "/" string.  Maybe.
*/

///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
uint8_t save_periph2;
uint8_t save_turboSpeed;

void ExitCleanup(void)
{
	IO_NEXTREG_REG = REG_PERIPHERAL_2;
	IO_NEXTREG_DAT = save_periph2;
	IO_NEXTREG_REG = REG_TURBO_MODE;
	IO_NEXTREG_DAT = save_turboSpeed;
}

void CommonInit(void)
{
	atexit(ExitCleanup);

	IO_NEXTREG_REG = REG_PERIPHERAL_2;
	save_periph2 = IO_NEXTREG_DAT;
	IO_NEXTREG_DAT = IO_NEXTREG_DAT | RP2_ENABLE_TURBO;

	IO_NEXTREG_REG = REG_TURBO_MODE;
	save_turboSpeed = IO_NEXTREG_DAT;
	IO_NEXTREG_DAT = RTM_28MHZ;

	errno = 0;
}

///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
unsigned char pathname[512];  // read buffer

#define ebuf pathname

int PrintFormatted(char *fmt, ...)
{
   va_list v;
   va_start(v, fmt);

#ifdef __SCCZ80
   vsnprintf(ebuf, sizeof(ebuf), va_ptr(v,char *), v);
#else
   vsnprintf(ebuf, sizeof(ebuf), fmt, v);
#endif

	printf(ebuf);
	return (int)ebuf;
}

///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
void PrintErrorMessage(unsigned int error)
{

	//ebuf[strlen(ebuf)-1] += 0x80;

	exit(error);
}

///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
char* MakeNicePath(char* path)
{
	char* newPath = pathnice(path);

//	PrintFormatted("%s\n", path);//TEST
//	PrintFormatted("%s\n", newPath);//TEST

	return newPath;
}
