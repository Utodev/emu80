IRQ Driven UART driver
----------------------

V0p2

(c) Tim Gilberts, Infinite Imaginations, 2018

This is the second release of an Interrupt driven UART driver using the
loadable device drivers of NextOS.  It creates a 16K buffer in the given
memory BANK or in main memory at $C000/49152 if none is specified.

The only change is to fix a memory paging issue with registry settings and
add support for 2Mb instead of 19200 Baud.  From TBU 52 onwards a new Digital
filter will be on the input which should allow the higher speeds to be more
reliable so this is ready for that.

Note that if you wish to use the ESP WiFi on the UART then you are more likely
to want to use the ESPAT driver as that includes full support for that chip and
is now the only supported route.  TERMINAL.BAS/BIN that supports this driver
will no longer be developed but is included for convenience.  There is also
IUDEMO.BAS which is a simple terminal written in BASIC (both best run at 14Mhz)

It is loaded as with other IM1 drivers using:

.install /nextos/uart.drv

It can also be removed with

.uninstall /nextos/uart.drv

Note that it starts in a limited fashion only gathering the status of the
UART data ready and buffer full flags.  This is so that data does not
overwrite any memory until you have formally assigned a bank or decided
to use the top 16K of main memory explicitly with a CLEAR 49151 command.

It supports an API that can be used from BASIC using a mix of DRIVER and
Streams support.  The driver can also be used from Assembler with
the NextOS driver API commands (see summary of M_DRVAPI at end of this
or in main NetxOS API documentation) where the Streams functions are just API
calls greater than 127...

It's ID is 'U' which is 85 decimal.  So all BASIC DRIVER commands are

DRIVER 85,n,{param1{,param2{ TO var1{,var2{,var3}}}}}

where n is the API call id / function number required.

On entry in assembler, use B=call id with HL,DE other parameters.
(NOTE: HL will contain the value that was either provided in HL (when called
from dot commands) or IX (when called from a standard program).

When called from the DRIVER command, DE is the first input and HL is the 
second.

When returning values, the DRIVER command will place the contents of BC into
the first return variable, then DE and then HL.  Just use them directly in
assembler.

;-----
B=1:
;-----
Set Baud rate / prescaler DE {HL}, returns used prescaler value in BC, 
If DE is <15 then set prescaler to that from supported list.

It supports a very limited number of built in prescale values as of course
You can supply your own via DRIVER/HL command and it was mainly intended
to support the ESP8266 Network interface which only needs a few speeds.

	DEFW 2917,2976,3069,3125,3229,3333,3438,2813 	; 9600 (0)
;WAS	DEFW 1458,1488,1535,1563,1615,1667,1719,1406 	; 19200 (1)
	DEFW 14,14,15,15,16,16,17,14			; 2000000 (1)
	DEFW 243,248,256,260,269,278,286,234 		; 115200 (2)
	
If DE=255 then use second value in HL directly as the prescaler.
Note that your own prescaler MUST correct for the video timing
as in the above table which represents VGA0-6 and HDMI7

;-----
; B=2: 
;-----
Get current address values and flags; C=Flag status
(BIT 2 = UART was filled. BIT 1 = BUFFER was filled)
DE and HL are input and output positions on the UART read buffer.
These are actual memory address values in your assigned BANK
assuming it is paged at 49152.
Flags are cleared by this call - so that each time it is used
you can see if there may have been data loss.
Both this and the next call will start the data receive so DO NOT
call either until you have set the memory BANK to use or made
a suitable CLEAR 49151 in BASIC.

;-----
; B=3:
;-----
Set values of input and output buffer directly (also resets the flags)

;-----	
; B=4:
;-----
Set RX/TX timeout - allows you to wait for variable periods for send
and receive before the system decides there is no more data or the
outbound UART is not emptying.

;-----
; B=5:
;-----
Set available memory BANK to use - ignores upper values of MSB
converts a 16K BASIC BANK to 8K pages available to the driver
to page in at $C000 - if you do not give it a bank then when
it starts running it will begin to write to main memory so make
sure you have done a clear 49151 before starting it up by
calling the get or set values/flags calls.


The driver supports the streams interface as follows:

;-------
; B=$f9: open channel
;-------
; In this case for the UART:

; OPEN #n,"D>U"
;
; This call returns a unique channel handle in A from assembler - only
; one is available for use as there is currently only a single UART.

;-------
; B=$fa: close channel
;-------

; This call is entered with D=handle, and should close the channel
; If it cannot be closed for some reason, exits with an error (this will be
; reported as "In use").
;
; CLOSE #n

;-------
; B=$fb: output character
;-------

; This call is entered with D=handle and E=character.
; Returns with carry set and A<$fe, so the error
; "Invalid I/O device" will be reported on a timeout for send.
;
; **TODO we should add a small output buffer to prevent any blocking then
; use the End of file error return if it is filled before transmission.
; This will have to be added to the IRQ routine for transmission but space
; is limited at the moment unless we switch to a TSR and memory block solution
;
; PRINT #n
; plus others like LIST etc.

;-------
; B=$fc: input character
;-------
; This call is entered with D=handle.
; Returns the character in A (with carry reset).
; If no character is currently available, returns with A=$ff and carry set.
; This will cause INPUT # or NEXT # to continue calling until a character
; is available.

;-------
; B=$fd: get current stream pointer
;-------
; This call is entered with D=handle.
; This will always return 0/Carry set as we are always at the start
;
; This is used with RETURN #n TO var

;-------
; B=$fe: set current stream pointer
;-------
; This call is entered with D=handle and IXHL=pointer.
; Exit with A=$fe and carry set if the pointer is invalid (will result in
; an "end of file" error). This means you are trying to skip more
; bytes than there are in the buffer.
; NOTE: Normally you should not use IX as an input parameter, as it cannot
;       be set differently to HL if calling via the esxDOS-compatible API.
;       This call is a special case that is only made by NextOS.
; This can be used to ADD x bytes to the stream to bulk skip over incoming
; data - it cannot be used to rewind the stream, error if x is > extent
;
; This is used with "GOTO #n,m" 

;-------
; B=$ff: get stream size/extent
;-------
; This call is entered with D=handle
; Returns the size/extent in DEHL (with carry reset).
; This is the number of bytes in the input buffer at the moment.
;
; This is used with "DIM #n TO var"


As a reminder here is the NextOS API documentation for M_DRVAPI - please check
that for most up to date version as it could have changed since this
was written.

	
; *************************************************************************
; * M_DRVAPI                                                                *
; *************************************************************************
; Entry:
;       C=driver id (0=driver API)
;       B=call id (or as described by driver documentation)
;       HL,DE=other parameters
; Exit (success):
;       Fc=0
;       other values depend on API call
; Exit (failure):
;       Fc=1
;       A=0, driver not found
;       else A=driver-specific error code (esxDOS error code for driver API)

; If C=0, the driver API is selected and calls are as follows:
;
; B=0, query the RTC
; (returns the same results as M_GETDATE)
;
; B=1, install a driver
;       D=number of relocations (0-255)
;       E=driver id, with bit 7=1 if should be called on an IM1 interrupt
;       HL=address of 512-byte driver code followed by D x 2-byte reloc offsets
; Possible error values are:
;       esx_eexist (18)         driver with same id already installed
;       esx_einuse (23)         no free driver slots available
;       esx_eloadingko (26)     bad relocation table
;
; B=2, uninstall a driver
;       E=driver id (bit 7 ignored)
;
; B=3, get paging value for driver banks
;       C=port (always $e3 on ZXNext)
;       A=paging value for DivMMC bank containing drivers (usually $82)
;
;IX when called from outside a dot command, HL is for internal use (and dot commands)

