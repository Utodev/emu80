Using the Next with the PI accelerator with Raspibian/NextPI not Bare Metal
===========================================================================

by Mr Tim Gilberts, Mr Darran (D. Xalior) Rimron-Soutter (another Barry boy...
ExPat) major contributions from emook - Mr David Saphier

V0p3 Alpha

The release 3.00.00 core now adds a UART for PI communication and also uses the
i2c bus in a different way to provide the PI with access to the DAC and EAR
audio on the Next to allow clever playing of things like MP3 and TZX files...

See the documentation in /rpi/linux now for details. There are some demo Next
programs in DEMOS/UART and of course new DOT commands: UUENCODE and PISEND

The information below is therefore historical and for interest of the journey
to this point - or if you are using an older 2.0 core for pi2c or TK-PI for 1.0
cores.

History
-------

Since Core .49 the TK-PI bus monitoring has been dropped in favour of some
machine to machine interfaces like SDI and i2c.

If you want to use an older core then in /rpi/archive/tkpi is the source and
demo programs that allow you to use the PI as a HDMI second screen shadowing the
ULA screen.

If you wish to use a full Linux on the PI then these notes and sample programs
should help as that now becomes theoretically possible.

First of all the PI only acts as a MASTER for these two buses and so does the
Next without MASTER/MASTER support, so it is a bit bashing exercise both sides.
Actually the Next has a hardware SPI master but, the PI does not have a way
to use a hardware slave - Sorry talk to the relevant people.

Anyway let's start with the i2c bus.
------------------------------------

This is useful to learn more as it is low speed and runs on stock Raspibian at
the 80-100KHz the Next i2c bus can achieve in Software - and some software is
already installed to use it on Raspibian.

DO NOT ENABLE i2c ON THE PI

Counterintuitive I know but, we will be driving it ourself in userland using the
excellent "pigpio" as in PI GPIO but better as PIG PIO!

This driver is already installed on the latest version of Raspibian but, for
some reason the GUI Remote GPIO feature does not enable it...

I use the full distribution with Graphics and just disable GUI and boot to
command line - This needs an 8Gb card really - the command line one fits on a
4Gb. It is easy to type "startx" if you have the full one...

The C code for pig2i2c from the examples has been updated to allow it to
passively monitor the bus.  Note there was an error in the original reversing
the pins!

Instructions are in the header but, once compiled with:

gcc -o pig2i2c pig2i2c.c

you can type:

sudo pigpiod -s 2		- starts the daemon which allows us to use gpio

pigs no				- asks for a handle to talk to it with.

pigs nb 0 0xC			- Select GPIOs 2 and 3 (0b 00001100)

.pig2i2c 2 3 </dev/pigpio0	- Start watching the i2c bus for data

Now whenever the Next does an i2c event you will see data - the 68 ones are the
Real Time Clock (RTC) if you have one fitted. Or a smaller amount of data where
NextZXOS is asking if one is there if you don't have one.

NB at the moment for some reason (probably the way this bus is working) you
only see 0xFF for the content of the data the RTC sends BACK...

Typing .date and .time will also trigger it.

.i2cscan 

Will show a query to every possible address 1-127!

I have also provided a DOT command with SOURCE that can send an aribitrary 
number of bytes onto the i2c bus and do the same for Read.  

.pi2c {-h} | {-d} {-rHH | -wHH{HH{HH...} 

You will need to use -d at the moment as the bit bashed driver on the PI does
not do an ACK...

I have reused an address $42 as I like the number and Douglas Adams, this means
you will not be able to add a:
Group 8 (1000) 0 1 0 TDA8415 TV/VCR stereo/dual sound processor
to your Next - sorry :)

Internally the FPGA uses GPIO pins 2(SDA) and 3(SCL) connecting to the PI
itself on the standard 3 and 5 of the i2c on the Header.  NB see later but,
the wiringPI library calls these 8 and 9 (for good but, complicated reasons).

Note that between 15-20% of the processor time will be used watching for events
on the bus...

What Next
---------

Next Step is to allow pig2i2c it to send an ACK and return bytes to the Next...

then

... turn it into a daemon that can run and wait for instructions from the Next.

The plan is to use the Length byte top two bits to encode a command to go
with the length.

00 - send or receive 0-63 bytes (based on the i2c Read/Write bit)
01 - RESERVED
10 - RESERVED
11 - extend code next bits are more complex less frequent instructions...
11100001 - Single/Dual byte as keyboard code for PI e.g. UP key / DOWN key
           I want to use the Next as the PI KB instead of a USB one... 
11100010 - Same for MOUSE?
11100011 - RTC time packet...
11100100 - Pipe to ESPAT....??? Probably better on SDI with this as Control chan
....
11100110 - Switch mode to baremetal (rename kernal) - wait until that OS has
           functionality to switch back before implementing.
11100111 - Shutdown PI.  (Not FF as occurs on BUS a lot...)

If needed add a checksum function to both .pi2c and derivative code to correct
errors - not seen any as yet so maybe just at a higher level.

This functionality could be added to the Bare Metal OS as well... we could then
have both on the card and switch between them as in above example.

i2c Links
---------

PIgpio:

http://abyz.me.uk/rpi/pigpio/

Primer on i2c:

http://maxembedded.com/2014/02/inter-integrated-circuits-i2c-basics/

How NOT to use them for us:
https://learn.sparkfun.com/tutorials/raspberry-pi-spi-and-i2c-tutorial
but, interesting...

Issues on pins...

https://github.com/joan2937/pigpio/issues/78



Other connected GPIO's
----------------------

That would be telling... and would assume I actually knew without looking at the
VHDL... or understood that... or any were.  They AREN't by the way, they are
all floating so with some soldered wires you COULD use them for other things.
It also means you could hook up a bigger (or second) PI using i2c only on the
J15 connector...  It could even be an Arduino but, those things were always
possible.



SPI - The fast one (hopefully YMMV)
-----------------------------------

The Documentation says: SPI port 0 (pins 19,21,23,24,26) on the PI...

To confuse you of course these are the PINS on the header... common libraries
like PIgpio and wiringPI use a mix of the Broadcom and their own internal
schemes - and of course it is different between revisions etc - this is the PI0
in the Next (if you added your own CHECK... if wiringpi is installed do
"gpio readall" for a nice table):

HEADER	NAME		BCM	WiringPI
19 	SPI0_MOSI	GPIO10	12
21 	SPI0_MISO	GPIO9	13
23 	SPI0_SCLK	GPIO11	14	
24 	SPI0_CE0_N	GPIO8	10
26 	SPI0_CE1_N	GPIO7	11

On the Next:

Port 0xE7 now selects the Raspberry PI on bits 2 (/CE0) and 3 (/CE1).
Victor comments: "For some reason the PI SPI port have 2 CS lines... With a
quick search I believe both can be used, but to keep the things simple, I'm
using CE 0 on bit 2 port E7."

Remember: the SD Cards are on bits 0 and 1 so make sure they stay 
high...  The CE lines are normally high and LOWERED for a select (hence _N)

0xE7 SD_CONTROL; 
0xE7 SD_STATUS;
0xEB SD_DATA;
(The 0xE3 divIDE control port is not relevant in this context
https://velesoft.speccy.cz/zx/divide/divide_plus/diwide.html)

This does of course mean you will never be able to talk to the Microdrive or
interface 1 without the PI getting stuff on those pins... so be careful. It
is a real shame the designers of the DivIDE didn't use 0xE7 for data instead
of 0xEB...

SPI is clocked at 28Mhz so 1 bit per cycle...

Not my area of knowledge but, of course that is bi-directional so once the
exchange happens you need to be piping back the bit as well when the CLK rises
according to Victor.

You can obviously throttle the data rate sent but, the bits have to dance to
the 28Mhz clock signal the FPGA hardware module generates. 

Victor also suggests that either IRQ for /CS and FIRQ to CLK or FIRQ to /CS and
rising detect on CLK would both cope with the data rate.  For Linux it is the
former trust us:

Dealing with the speed of SPI was an issue... Darran takes over the story...

[Insert stuff on getting bit bashed SDI on a realtime kernel etc...]


SPI Links
---------

WiringPI:

wiringpi.com

Support for SPI bit bank in kernel:

https://github.com/raspberrypi/linux/pull/2318

SPI slave model (not in the FPGA... yet):

https://www.digikey.com/eewiki/pages/viewpage.action?pageId=7569477


Other issues using the PI
-------------------------

Victor seems good with the idea of a stripped Linux as the main accelerator OS
if we can get it to 10secs as even ESXDOS takes that long (Actually closer to
19 as does NExtZXOS) and then you need another 5 or so to NMI and select a game!

Standard Raspibian is very bloated and takes some time to start so to get a 10s
startup takes some effort - watch for updates from Mr D.

If not games will need to check if it is there anyway so could just wait for it
to come online and bomb after 10 seconds with "Who ate all the PI?"

As it has a real OS you need to ensure it is shut down gracefully to avoid
filesystem issues.  Darren has cleverly worked around this with a read only
root filesystem and an rw /tmp.

Still best to do .PI(I2C/SPI) -shutdown though...

See notes above on Real time Kernel tricks etc.

