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

#include <string.h>
#include "hardware.h"
#include "vdp.h"
#include "misc.h"
#include "modules.h"
#include "ff.h"
#include "fwfile.h"
#include "videomagic.h"
#include "config.h"

unsigned char vidtestmode;
unsigned char vidtestiter;

unsigned char * strVidMagic = "VideoTest";
unsigned char *pVidMagic = (unsigned char *)VIDMAGIC_OFFSET;
unsigned char *pVidTestMode = (unsigned char *)VIDMODE_OFFSET;
unsigned char *pVidTestIter = (unsigned char *)VIDITER_OFFSET;

unsigned char videoTestReselect()
{
        unsigned char mode = eVidTestNone;

        if ((HROW0 & 0x10) == 0)        // "V"
        {
                mode = eVidTestVGA;
        }
        else if ((HROW1 & 0x01) == 0)   // "A"
        {
                mode = eVidTestAll;
        }
        else if ((HROW2 & 0x08) == 0)   // "R"
        {
                mode = eVidTestRGB;
        }
        else if ((HROW1 & 0x04) == 0)   // "D"
        {
                mode = eVidTestDigital;
        }

        if ((mode != eVidTestNone)
            && (mode != vidtestmode))
        {
                vidtestmode = mode;
                vidtestiter = 0;
                return 1;
        }
        else
        {
                return 0;
        }
}

unsigned char videoTestActive()
{
        REG_NUM = REG_RAMPAGE;
        REG_VAL = RAMPAGE_ROMSPECCY + 2;

        if (strncmp(pVidMagic, strVidMagic, VIDMAGIC_LEN) == 0)
        {
                // Video mode testing is already in progress.
                vidtestmode = *pVidTestMode;
                vidtestiter = *pVidTestIter;
        }
        else
        {
                vidtestmode = eVidTestNone;
                vidtestiter = 0;
        }

        if (!videoTestReselect())
        {
                if ((vidtestmode == eVidTestNone)
                        && (settings[eSettingTiming] == 8))
                {
                        // Force testing if timing=8 in config.ini.
                        vidtestmode = eVidTestAll;
                }
        }

        return (vidtestmode != eVidTestNone);
}

void videoTestSet()
{
        REG_NUM = REG_RAMPAGE;
        REG_VAL = RAMPAGE_ROMSPECCY + 2;
        strncpy(pVidMagic, strVidMagic, VIDMAGIC_LEN);

        *pVidTestMode = vidtestmode;
        *pVidTestIter = vidtestiter;
}

void videoTestDisable()
{
        REG_NUM = REG_RAMPAGE;
        REG_VAL = RAMPAGE_ROMSPECCY + 2;

        *pVidMagic = 0;
}
