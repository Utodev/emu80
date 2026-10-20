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

#include <stdlib.h>
#include <string.h>
#include "hardware.h"
#include "vdp.h"
#include "ff.h"
#include "misc.h"
#include "config.h"

void save_config()
{
        unsigned int i;

        res = f_open(&Fil, CONFIG_FILE, FA_CREATE_ALWAYS | FA_OPEN_EXISTING | FA_WRITE);

        for (i = 0; i < eSettingMAX; i++)
        {
                ERR_CHECK_PF(f_printf(&Fil, "%s=%d\n", settingName[i], settings[i]));
        }

        // Delete any further part of the file that we haven't overwritten
        ERR_CHECK(f_sync(&Fil));
        ERR_CHECK(f_truncate(&Fil));
        ERR_CHECK(f_close(&Fil));

        if (res != FR_OK)
        {
                //             12345678901234567890123456789012
                display_error("Error saving configuration!");
        }
}
