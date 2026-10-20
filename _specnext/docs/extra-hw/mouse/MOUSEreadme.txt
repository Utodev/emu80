Interrupt driven mouse driver for ZX Next
-----------------------------------------

V0p5 31 July 2018

This is designed to be a demonstration of a use for the
Driver API that is included in NextZXOS (1.95 on) which allows
upto 512 bytes of interrupt code to be added to the standard
Spectrum interrupt system - the one that reads the keyboard
every 1/50th of a second.

All you need is the file MOUSE.DRV in the NEXTZXOS folder and
a version of NextZXOS 195 or greater.

The driver can then be controlled from BASIC with the new
DRIVER command.

There is a demo program called NXMOUSE.BAS that uses
the above Sprite and Text features for you to play with.
The NXMOUSET.BAS uses some of the features of the sprite
cursor and lets you play with acceleration settings in
Timex HiRes.

They both use sprites from the BREAKOUT test but, you can
change line 300 to load any set you wish.  Note that if you
hold the 's' button and move it around at times the
sprite cursor will seem to disappear that is because you
have reached the maximum 12 sprites per display line.

You could modify the code to remove the tail of previously
used sprites if you want but, it is quite fun to play with.

The DRIVER API
--------------

This mouse driver is driver number 126. There
will be a supported list of driver codes and
any that use streams (this does not) will need
to be allocated one from 65-90 A-Z or the lower
case range (or both) so this avoids that area.

To use you need to install the driver. Which
expects the install and uninstall DOT commands
in the BIN directory.

.install /nextos/mouse.drv

It supports the following parameters for driver

DRIVER 126,1 TO %b,x,y

Will get the current location of the mouse on a
192 x 640 grid with 0,0 in the top left of the
outer border where sprites can go.  It uses the
higher X number to allow use in Timex mode where
there are twice as many horizontal pixels

%b@111 will be the three buttons bit activated in
combination so 1,2,4 or 3,5,6,7 for combinations.
%b>>4 will be the current value of the wheel mouse 0-15

DRIVER 126,2{,sprite{,pattern}}

Where the optional sprite number 0-63 and pattern
number 0-63 will default to 0 and will cause that
sprite to always be displayed (anywhere that clipping
is not in effect) at the current X,Y coordinate
- over a timex screen it will sit between two pixels
of course.

DRIVER 126,3

Will disable the sprite cursor.

DRIVER 126,4{,attribute}

will display an Attribute based character cursor using
the ULA attributes - this will cope with some screen
changes but, not scrolling so remember to disable it
when changing the screen wholesale.

So using the new features of NextOS to include a 
binary number (@) in an integer statement (%)

DRIVER 126,4,%@11100111

Will set a Bright, Flashing, Green and White cursor.
the first two 1's are Bright and Flash the next two
groups of three are the paper and ink.

FTGRBGRB - where T-Bright.

DRIVER 126,5

will remove the Attribute based cursor.

DRIVER 126,6,x_threshold

Where x_threshold is forced to be in the range 0-255
by using LSB only.
0 Means always accelerate the X direction
255 Means never accelerate the X direction
by default it is set at 32 which will tigger more rapid
movement if you move the mouse quickly.
You can adjust to suit your own preference.

The Y does not have the option as 0-192 pixels probably
would not benefit but, it is not ruled out and
you have the source o hacker...

Notes
-----

The scrappy source code is provided in case you want to play
with it and is assembled exactly like the Border demo. This
may be developed as time goes on.

In fact 0p2b fixed a bug in the Sprite and Image handling
and 0p4 added the X Acceleration option while 0p5 added basic
support for the wheel mouse so it is being developed.

Note that 0p5 had to take out detection so probably best not
to load the driver if there is no mouse.

PS2 Port and modes of operation
-------------------------------

WARNING: Do not plug in or remove PS2 devices with the power on

You can use ps2mode to see which mode TBU 49 and greater is in
the best place to set the value is in the tbblue .ini file where

PS2=0 is KEYBOARD mode where a PS2 keyboard is plugged into the Next
or with a splitter you can use both a mouse and a keyboard.

PS2=1 is MOUSE mode where the mouse should be plugged in directly
do not use a splitter in this mode as it can have funny effects it
is designed 

If you start in the wrong mode then on the Membrane keyboard you
can type ps2mode -m to select MOUSE or ps2mode -k to select KEYBOARD


Tim Gilberts
July 2018

/source/mouse

mouse.asm
mouse_drv.asm

/demos

NXMOUSE.BAS
NXMOUSET.BAS

/nextzxos

MOUSE.DRV

/bin

PS2MODE

