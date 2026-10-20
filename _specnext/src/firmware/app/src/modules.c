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
#include "modules.h"
#include "ff.h"
#include "fwfile.h"
#include "switch.h"
#include "config.h"

void switchModule(unsigned char m)
{
        unsigned int bl, i, l;

        memset((unsigned char *)0x4000, 0, 6912);

        fwOpenAndSeek(m);
        i = fwBlockLength(m);
        bl = 0;

        while (i)
        {
                REG_NUM = REG_RAMPAGE;
                REG_VAL = RAMPAGE_RAMDIVMMC + bl;

                l = (i > 32) ? 32 : i;
                fwRead((unsigned char *)0x0, l * 512);
                i = i - l;
                bl++;
        }

        fwClose();

        switch_routine();
}
