/*
ZX Spectrum Next Firmware
Copyright 2020 Garry Lancaster, Fabio Belavenuto & Victor Trucco

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef _MISC_H
#define _MISC_H

#define COREBOOT_MAGIC_SIZE     8
#define COREBOOT_NAMES_SIZE     16
#define COREBOOT_STRUCT_SIZE    128
#define COREBOOT_MAGIC          "COREBOOT"
#define COREBOOT_CHECKSUM       0xCB

typedef struct {
        char            magic[COREBOOT_MAGIC_SIZE];     // must contain COREBOOT
        char            dirname[COREBOOT_NAMES_SIZE];   // core directory
        char            filename[COREBOOT_NAMES_SIZE];  // file to load (null if none)
        unsigned char   padding[COREBOOT_STRUCT_SIZE-(COREBOOT_MAGIC_SIZE+(COREBOOT_NAMES_SIZE*2)+1)];
        unsigned char   checkSum;
} coreboot;

extern const char TITLE[];
extern char line[256];

void display_error(const unsigned char *msg);
void disable_bootrom();
unsigned long get_core_ver();
unsigned long get_fattime();
unsigned char getCoreBoot();

#endif // _MISC_H
