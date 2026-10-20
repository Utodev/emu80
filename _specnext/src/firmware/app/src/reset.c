/*
ZX Spectrum Next Firmware
Copyright 2020 Garry Lancaster

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

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "hardware.h"
#include "vdp.h"
#include "ff.h"
#include "misc.h"
#include "config.h"
#include "fwfile.h"

FATFS           FatFs;          /* FatFs work area needed for each volume */
FIL             Fil;            /* File object needed for each open file */
FRESULT         res;

void main()
{
        vdp_init();

        // Read config.ini (sets up drive etc)
        load_config();

        reset_settings();
        save_config();
        vdp_cls();
        vdp_gotoxy(3, 3);
        vdp_prints("Settings reset to defaults!\n\n");
        vdp_gotoxy(7, 7);
        vdp_prints("Turn the power off");
        for (;;);
}
