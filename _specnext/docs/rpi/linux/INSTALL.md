How to Install NextPi
---------------------
 
 * Your SD image be noticeably _smaller_ than your SD card.
 
   NextPi's default images use "Extreme Overprovisioning" to try and reduce the
   catastrophic effects of block wear and tear.  By this we mean the image for a
   16GB SD card will be approximately 95% of the card size (just as prior NextPi
   images were approximately 920Mb for 1GB cards.)
   
   This has two "primary" goals; the first that - as mentioned - it helps make
   sure there's plenty of spare blocks^ for use if you ever "burn a hole" in the
   SD card rewriting* to the same file; and - secondly - it fits on cheap
   16Gigabyte SD cards which are actually 16Gigibytes and smaller.
   
   You can find the "premade" SD card images at http://zx.xalior.com/NextPi/ -
   legacy (aka older) versions and PlusPacks (aka extensions to the base image)
   can be found in subdirectories here, but for first installs, and all support
   and trouble-shooting purposes a basic install of the latest version is the
   advised configuration.
   
 * You can write a raw SD card image
 
   Etcher, Win32DiskImager, or dd all will suffice for this.  There is nothing
   special or specific required above and beyond the normal Raspberry Pi based
   Linux distributions.  The file to burn is called "NextPi.img" - for details
   on how to burn an SD image, it works like all other Pi operating systems.
   See https://dietpi.com/docs/install/#2-flash-the-dietpi-image for a set of
   details instructions. You need ONLY follow "step 2" from this guide *AFTER*
   you have extracted the .tar.gz file to reveal the NextPi2 dated *.img* file.

Notes about NextPi first run
----------------------------

  Unlike most Raspberry Pi Linux distros NextPi _DOES_NOT_ automatically resize
  to fill your SD card upon first execution (see Extreme Overprovisioing, below)
  and also because this is very difficult to recover from if it goes wrong on a
  sealed box unit.  

  The current releases of NextPi (Pre-release and all public images) are
  shipped in a single configuration - designed for 16GB SD card.  The plan is to
  create, and support, other SD card sizes as NextPi2 some point long after now

Extreme Overprovioning
----------------------

   ^ The strategy of Extreme Over-provisioning is a bit of a "magic art" on SD
   media, with different vendors and firmwares re-allocating blocks as and when
   they see fit (for some that is "never and never", sadly) - so there is no 
   way to "prove" how this works on any specific cards, but the side effects
   (outwith of "wasted space") are not negative, and can be very positive.
   
   It is hoped that any "good" SD card would take an awful lot of repeated same
   place writes to actually "burn" the underlying flash media due to integrated
   flash level translations and the flash quality but this extra precaution is
   added for scenarios, such as the cased spectrum next, where swapping SD cards
   is neither convenient, or desirable.
