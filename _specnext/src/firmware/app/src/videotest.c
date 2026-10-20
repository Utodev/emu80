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
#include "layers.h"
#include "videomagic.h"
#include "videotest.h"

FATFS           FatFs;          /* FatFs work area needed for each volume */
FIL             Fil;            /* File object needed for each open file */
FRESULT         res;

const testmodeitem modesDigital[] =
{
        { 7, 0, 1 },
        { 7, 1, 1 },
};

const testmodeitem modesRGB[] =
{
        { 0, 0, 0 },
        { 0, 1, 0 },
};

const testmodeitem modesVGA[] =
{
        { 0, 0, 1 },
        { 0, 1, 1 },
        { 1, 0, 1 },
        { 1, 1, 1 },
        { 2, 0, 1 },
        { 2, 1, 1 },
        { 3, 0, 1 },
        { 3, 1, 1 },
        { 4, 0, 1 },
        { 4, 1, 1 },
        { 5, 0, 1 },
        { 5, 1, 1 },
        { 6, 0, 1 },
        { 6, 1, 1 },
};

const testmodeitem modesAll[] =
{
        // Digital first
        { 7, 0, 1 },
        { 7, 1, 1 },

        // RGB next
        { 0, 0, 0 },
        { 0, 1, 0 },

        // VGA last
        { 0, 0, 1 },
        { 0, 1, 1 },
        { 1, 0, 1 },
        { 1, 1, 1 },
        { 2, 0, 1 },
        { 2, 1, 1 },
        { 3, 0, 1 },
        { 3, 1, 1 },
        { 4, 0, 1 },
        { 4, 1, 1 },
        { 5, 0, 1 },
        { 5, 1, 1 },
        { 6, 0, 1 },
        { 6, 1, 1 },
};

const testmodeitem *modeTables[] =
{
        0,                      // eVidTestNone
        modesAll,               // eVidTestAll
        modesDigital,           // eVidTestDigital
        modesRGB,               // eVidTestRGB
        modesVGA,               // eVidTestVGA
};

const unsigned char modeIters[] =
{
        0,                      // eVidTestNone
        sizeof(modesAll) / sizeof(testmodeitem),
        sizeof(modesDigital) / sizeof(testmodeitem),
        sizeof(modesRGB) / sizeof(testmodeitem),
        sizeof(modesVGA) / sizeof(testmodeitem),
};

char *modeName[] =
{
        "",                     // eVidTestNone
        "ALL",                  // eVidTestAll
        "DIGI",                 // eVidTestDigital
        "RGB",                  // eVidTestRGB
        "VGA",                  // eVidTestVGA
};

unsigned char l2black, l2white;
testmodeitem curtestmode;

unsigned char copybuf[2048];


void aySend(unsigned char ayreg, unsigned char data)
{
        AY_REG = ayreg;
        AY_DATA = data;
}

void ayOff()
{
        aySend(AY_REG_MIXER, 0xff);
        aySend(AY_REG_VOLUME_A, 0x00);
}

void videoTestInit()
{
        unsigned int i;
        unsigned int *pPalette;

        fwOpenAndSeek(FW_BLK_SCREENS);

        // Load the L2 screen.
        for (i = 0; i < 3; i++)
        {
                REG_NUM = REG_RAMPAGE;
                REG_VAL = RAMPAGE_RAMSPECCY + L2_BANK + i;
                fwRead((unsigned char *)0, 0x4000);
        }

        REG_NUM = REG_RAMPAGE;
        REG_VAL = RAMPAGE_RAMSPECCY + L2_BANK + 3;

        // Erase the unused palette entries
        memset(0x0000, 0, 0x400);

        // Read the L2 palette data
        fwRead((unsigned char *)0x0000, FW_L2_PAL_SIZE);

        fwSeek((FSIZE_t)FW_L2_PAL_SIZE+(FSIZE_t)0x1d600);

        // Read the tilemap palette data
        fwRead((unsigned char *)0x0200, FW_TILEMAP_PAL_SIZE);

        // Find the layer2 palette indices for black and white.
        pPalette = (unsigned int *)0;

        for (i = 0; i < 256; i++)
        {
                if (pPalette[i] == 0x0000)
                {
                        l2black = i;
                }

                if (pPalette[i] == 0x01ff)
                {
                        l2white = i;
                }
        }

        // Set the layer2 and tilemap palettes.
        setPalette(PALETTE_L2_0, (unsigned char *)0);
        setPalette(PALETTE_TILEMAP_0, (unsigned char *)0x200);

        // Read the tilemap data into the next bank.
        REG_NUM = REG_RAMPAGE;
        REG_VAL = RAMPAGE_RAMSPECCY + L2_BANK + 4;
        fwRead((unsigned char *)0, FW_TILEMAP_DAT_SIZE);

        fwClose();
}

unsigned char videoTestMode()
{
        unsigned long l;
        unsigned char modeName_x;

        // Save current mode/iteration so that they can be re-fetched if the
        // following write to the video timing register causes a reset.
        videoTestSet();

        // Clear the RAM5 ULA screen area so that if there is a reset, the
        // screen will initially be blank.
        REG_NUM = REG_RAMPAGE;
        REG_VAL = RAMPAGE_RAMSPECCY + L2_BANK + 4;
        memset((unsigned char*)0x4000, 0, 0x2000);

        // Set the new timing, frequency, scandoubler. This may cause a reset.
        set_video_mode(curtestmode.timing, curtestmode.freq, curtestmode.doubler);

        // Set layer2 start bank.
        REG_NUM = REG_L2BANK;
        REG_VAL = L2_BANK;

        // Display mode information.
        l2_setcolours(l2black, l2white);
        l2_gotoxy(7*8, 19*8);
        //////////////////123456
        l2_prints("Cycling      modes");

        modeName_x = 14*8 + ((6-strlen(modeName[vidtestmode]))*8/2);
        l2_gotoxy(modeName_x, 19*8);
        l2_prints(modeName[vidtestmode]);

        l2_gotoxy(7*8,2*8-5);
        l2_prints("Mode ");
        l2_putchar('0' + curtestmode.timing);
        if (curtestmode.freq)
        {
                l2_prints("/60Hz");
        }
        else
        {
                l2_prints("/50Hz");
        }
        if (curtestmode.doubler)
        {
                l2_prints("/scan*2");
        }
        else
        {
                l2_prints("/scan*1");
        }

        // Copy the tilemap data up to RAM5.
        REG_NUM = REG_RAMPAGE;
        REG_VAL = RAMPAGE_RAMSPECCY + L2_BANK + 4;
        memcpy((unsigned char*)0x4000, (unsigned char)0, 0x2000);

        // Set up and enable the tilemap.
        REG_NUM = REG_TILEMAP_ATTR;
        REG_VAL = 0x00;

        REG_NUM = REG_TILEMAP_BASE;
        REG_VAL = 0x40;

        REG_NUM = REG_TILEDEF_BASE;
        REG_VAL = 0x45;

        REG_NUM = REG_TILEMAP_CTRL;
        REG_VAL = 0xa1;         // enable, no attribs, no ULA

        // Set transparency and fallback to black so that the magentas show up.
        REG_NUM = REG_TRANSPARENCY;
        REG_VAL = 0;
        REG_NUM = REG_FALLBACK;
        REG_VAL = 0;

        // Make layer 2 visible.
        L2PORT = 0x02;

        // Show border around the outside.
        ULAPORT = 0x04;

        // If "N" is still being held from previous mode, wait until released.
        while ((HROW7 & 0x08) == 0);

        for (l = 0; l < 0x7ffff; l++)
        {
                if ((l & 0x7fff) == 0)
                {
                        l2_gotoxy((unsigned char)(7*8),(unsigned char)(20*8+4));
                        if ((l & 0x8000) == 0)
                        {
                                l2_prints("ENTER selects mode");
                                l2_gotoxy((unsigned char)(7*8+4),(unsigned char)(21*8+4));
                                l2_prints(" N skips to next ");
                        }
                        else
                        {
                                l2_prints("                  ");
                                l2_gotoxy((unsigned char)(8*8+4),(unsigned char)(21*8+4));
                                l2_prints("               ");
                        }
                }

                if (l == 30000)
                {
                        aySend(AY_REG_TONE_COARSE_A, 0x00);
                        aySend(AY_REG_TONE_FINE_A, 0xfc); // 0x7e
                        aySend(AY_REG_MIXER, 0xfe);
                        aySend(AY_REG_VOLUME_A, 0x0f);
                }

                if (l == 110000)
                {
                        ayOff();
                }

                // Select this mode if ENTER is pressed.
                if ((HROW6 & 0x01) == 0)
                {
                        ayOff();
                        l2_gotoxy((unsigned char)(7*8),(unsigned char)(19*8));
                        l2_prints("Select mode? (Y/N)");
                        l2_gotoxy((unsigned char)(7*8),(unsigned char)(20*8+4));
                        if (curtestmode.freq)
                        {
                                l2_prints("NOTE:Compatibility");
                                l2_gotoxy((unsigned char)(7*8+4),(unsigned char)(21*8+4));
                                l2_prints("is better at 50Hz");
                        }
                        else
                        {
                                l2_prints("                  ");
                                l2_gotoxy((unsigned char)(7*8),(unsigned char)(21*8+4));
                                l2_prints("                 ");
                        }

                        while ( ((HROW5 & 0x10) == 0x10)
                                && ((HROW7 & 0x08) == 0x08) );

                        if ((HROW5 & 0x10) == 0)
                        {
                                // Turn off AY, layer 2 and tilemap,
                                // and set border back to black.
                                ayOff();
                                vdp_cls();
                                L2PORT = 0x00;
                                REG_NUM = REG_TILEMAP_CTRL;
                                REG_VAL = 0x00;
                                ULAPORT = 0x00;

                                // Reset the layer 2 palette to defaults.
                                setOrderedPalette(PALETTE_L2_0);

                                // Turn off video mode cycling.
                                videoTestDisable();

                                // Update config.ini with current mode settings.
                                settings[eSettingTiming] = curtestmode.timing;
                                settings[eSettingFreq5060] = curtestmode.freq;
                                settings[eSettingScandoubler] = curtestmode.doubler;
                                save_config();

                                return 1;
                        }

                        break;
                }

                // Skip this mode if N is pressed.
                if ((HROW7 & 0x08) == 0)
                {
                        return 0;
                }

                // Exit with new mode range if chosen with key A/V/H/S.
                if (videoTestReselect())
                {
                        vidtestiter = 0xff;   // will be incremented to 0
                        return 0;
                }
        }

        // No need to reset anything as this func will shortly be re-run.
        return 0;
}

void main()
{
        vdp_init();
        load_config();

        if (!videoTestActive())
        {
                // TODO Shouldn't ever get here, but if so default
                //      to testing all modes.
                vidtestmode = eVidTestAll;
                vidtestiter = 0;
        }

        videoTestInit();

        while (1)
        {
                if (vidtestmode >= sizeof(modeTables) / sizeof(testmodeitem *))
                {
                        vidtestmode = eVidTestAll;
                }

                if (vidtestiter >= modeIters[vidtestmode])
                {
                        vidtestiter = 0;
                }

                curtestmode = (modeTables[vidtestmode])[vidtestiter];

                if (videoTestMode())
                {
                        // Exit if mode successfully selected.
                        REG_NUM = REG_RESET;
                        REG_VAL = RESET_HARD;
                }

                // If not selected, step to next mode.
                vidtestiter++;
        }
}
