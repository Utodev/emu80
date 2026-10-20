Professional Adventure Writer - ZX Spectrum Next Release 2018
=============================================================

This document is a text version of the getting started section of the supplied
PDF of the Tutorial Manual.  Also on the SD card is a copy of the Quick
Reference Guide as a PDF.  The Technical Guide is only available as part of the
purchased system.

This version is the last issued of the original versions produced for the
Spectrum +3.  This is fully operational on NextZXOS and you merely need to
browse and click on the DSK file.

Paw_A17_+3.dsk 		- located in the /apps/dev directory.

However, before you do that it is a good idea to set-up a 'B' drive on your
computer where you can save your work.  Although NextZXOS supports upto 16Mb for
a drive image, due to the delays that can cause and the fact that games will not
be more than 128K in size, a 1Mb file will be more than large enough.  If you
intend to use other +3 utilities then perhaps make it 4Mb!

Thus (for a 1Mb file) using the Command Line and the mkdata DOT command:

.MKDATA /NEXTZXOS/DRV-B.DSK 1
MOVE "B:" IN "/NEXTZXOS/DRV-B.DSK"

If it fails to map in then the file may be fragmented on the disk in which case:

.DEFRAG DRV-B.DSK

will (after a short delay) rewrite the file as a contiguous block so you can
retry the MOVE.  Note that the Browser will detect a fragmented file and
undertake the defrag for you when you mount.

We named the file DRV-B.DSK and put it in the NextZXOS directory so that this
disk is always available to you as it will be found on boot.  You just need to
use the browser to temporarily mount and boot the PAW disk when you want to use
it, or any other +3 utilities as needed.  If you only use PAW then you could
make a copy of that file in NextZXOS called DRV-A.DSK and it would also be
available on boot.

If you want to load PAWS from the command line you will need:

MOVE "A:" IN "Paw_A17_+3.dsk"
LOAD"A:":LOAD"*"

If it fails to map A: then again you may need to defrag the file.

PAW will display a start up screen when loaded which shows its current version
number, a letter followed by a two digit number e.g. A17 and the system it
supports = +3. Also shown are two address' in decimal which will be required if
you wish to write your own BASIC or machine code additions to PAW - details in
the technical guide.

Pressing any key will cause the main menu to be displayed...

Note that this software and the remainder of the manual date from 1986 and as
few changes have been made as possible.  There will hopefully be an updated
version of PAW produced for both ESXDOS and ZX Spectrum Next which will allow
you to make full use of its extra facilities.  We will ensure that a database
produced with this version can be loaded into them so don't be afraid to start
writing your game...

The original addendum provided with +3 copies of PAW is in Appendix A and there
are some useful tips in there even today.

Any communication regarding PAW should be directed to:-

Infinite Imaginations

2 Park Crescent,
Barry,
South Glamorgan,
CF62 6HD.

Support is limited to bugs and issues, for paid registered owners of the
software - we cannot give individual support or advice on use.  However, there
is a large community of users on social media that can and do help in using this
and similar products.

This is a copy of the original full version and is not function limited in any
way - the only item missing is The Technical Guide - please enquire if you want
a copy.  We have provided a Quick Reference Guide though...

For news and information you can follow me:

Twitter: @Timbucus

Tim Gilberts
August 2018
