Installing and Running esxDOS on the ZX Spectrum Next
-----------------------------------------------------

Author:  Phoebus R. Dokos
Date:	 2018-09-24
License: CC BY-NC-SA
Version: 1.2

Changelog
---------
2022-04-27: 1.2 Updated by TJG to reflect NextZXOS changes to personality menu
	    for latest distro
2020-04-24: 1.1 Updated to reflect changes in the folder structure
2019-09-24: 1.0 Initial Version

Users wishing to use esxDOS with their boards / cased ZX Spectrum Next computers
need to first download the 0.8.6b4 (minimum) (0.8.7 recommended) esxDOS 
distribution from  www.esxdos.org and then do the following under NextZXOS

1. Create two folders on the root folder named c:/bin/ and c:/sys/ by giving:
   mkdir "c:/bin"
   mkdir "c:/sys"

2. Using a PC or Mac, unzip the contents of the bin and sys folders into their 
   respective places.
3. Copy the esxmmc.bin into c:/machines/next
4. Edit the menu.ini/menu.def to add the esxmmc.bin switch into any Spectrum 
   personality in the distribution EXCEPT the Next personalities and the ZX80
   and ZX81 emulator personalities. Read the config.ini document elsewhere in 
   this distribution for the proper details of a menu line.

IMPORTANT NOTE regarding "dot" command compatibility
----------------------------------------------------
Note that NextZXOS has several dot commands that are newer than the ones
included with esxDOS so you may want to use these. Many of these work on
both systems. For esxDOS compliant versions, use the ones located under
c:/dot/extra.



