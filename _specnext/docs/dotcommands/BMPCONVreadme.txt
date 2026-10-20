BMPCONVert "dot" command (c) 2018 Jim Bagley
============================================
Converts BMP files to ZX Spectrum Next tiles
and tilemaps as defined by NextBASIC.

USAGE
--------------------------------------------
.BMPCONV <-switches> filename.bmp

Switches are :

-i = save image, default tilemap
-b = map is saved in bytes
-8 = block size 8x8, norm 16x16
-t = include tileset base
-2 = save 2MB layout
-r = don't remove repeat tiles