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

#include <string.h>
#include "hardware.h"
#include "vdp.h"
#include "misc.h"
#include "ff.h"
#include "spi.h"

//                    12345678901234567890123456789012
const char TITLE[] = " ZX Spectrum Next Configuration ";
static unsigned char mach_version_major, mach_version_minor, mach_version_sub;
char line[256];

void display_error(const unsigned char *msg)
{
        unsigned char l = 16 - strlen(msg)/2;

        vdp_setcolor(COLOR_RED, COLOR_BLACK, COLOR_WHITE);
        vdp_cls();
        vdp_setcolor(COLOR_RED, COLOR_BLUE, COLOR_WHITE);
        vdp_setflash(0);
        vdp_prints(TITLE);
        vdp_setcolor(COLOR_RED, COLOR_BLACK, COLOR_WHITE);
        vdp_setflash(1);
        vdp_gotoxy(l, 12);
        vdp_prints(msg);
        ULAPORT = COLOR_RED;
        for(;;);
}

void disable_bootrom()
{
        REG_NUM = REG_MACHTYPE;
        REG_VAL = 0;
}

unsigned long get_core_ver()
{
        REG_NUM = REG_VERSION;
        mach_version_major = REG_VAL;

        mach_version_minor = mach_version_major & 0x0F;
        mach_version_major = (mach_version_major >> 4) & 0x0F;

        REG_NUM = REG_VERSION_SUB;
        mach_version_sub = REG_VAL;

        return  (mach_version_major*65536) + (mach_version_minor*256) + mach_version_sub;
}

unsigned long get_fattime()
{
        return 0x44210000UL;
}

unsigned char getCoreBoot()
{
        unsigned int j;
        unsigned char sum = 0;
        coreboot *pCoreBoot = (coreboot *)0x0000;

        REG_NUM = REG_RAMPAGE;
        REG_VAL = RAMPAGE_ALTROM0;

        if (strncmp(pCoreBoot->magic, COREBOOT_MAGIC, COREBOOT_MAGIC_SIZE) == 0)
        {
                for (j = 0; j < COREBOOT_STRUCT_SIZE; j++)
                {
                        sum += *(((unsigned char *)(pCoreBoot)) + j);
                }
        }

        return (sum == COREBOOT_CHECKSUM);
}
