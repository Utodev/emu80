# .ESPBAUD dot command

To use, copy "ESPBAUD" to the sd card's DOT directory.

## Compiling

~~~
zcc +zxn -v -startup=30 -clib=sdcc_iy -SO3 --max-allocs-per-node200000 @zproject.lst -o espbaud -pragma-include:zpragma.inc -subtype=dot -Cz"--clean" -create-app
~~~

## Usage

`.espbaud` entered on its own at the basic prompt will print help.

This utility ensures communication is established with the on-board esp-wifi module.  It can:

* Reset the esp module
* Detect the esp's current baud rate quickly by testing popular rates first and then if necessary perform a binary search on baud rate segments in popularity order.
* Set a new baud rate in the esp and the Next's uart.
* Test that communication is established.

Besides being called from the command line, it can also be called by a running program to establish a baud rate.  The esp module can reliably support 9600 bps through 2Mbps.  Whether rates can be lower depends on the esp module's firmware; this software will check as low as 300 bps.

The help text is reproduced here:

~~~
ESPBAUD V1.1 (zx next)

-R  = ESP Hard Reset

-d  = Detect ESP bps
bps = Set bps and finetune
-v  = ESP version test

-p  = ESP bps change permanent
-f  = Set bps exactly
-q  = quiet mode

Z88DK.ORG
~~~

In understanding the options above, it is necessary to understand that the esp module has a permanent baud rate and a temporary one.  When the module is reset or powered up, the baud rate is set to the permanent rate.  The temporary rate changes that only until the next power cycle.

ESPBAUD will try to set the temporary rate unless the `-p` option is present.  Some esp modules do not support a temporary rate and if that is the case, ESPBAUD will always set the permanent rate.


## Examples

1. Reset the esp module (takes ~9 seconds), detect the esp baud rate (sets the Next's uart to match), and perform a test:

`.espbaud -Rdv`

2. Detect the esp's baud rate and then set it (and the Next's uart) to 36000 bps:

`.espbaud -d 36000`

3. Detect the esp's baud rate and then set it (and the Next's uart) to 1Mbps in quiet mode as would be suitable if called from a program:

`.espbaud -dq 1000000`

The BREAK key can be pressed at any time to exit the dot command.
