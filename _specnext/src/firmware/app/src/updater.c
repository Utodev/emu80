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
#include <stdio.h>
#include <string.h>
#include "hardware.h"
#include "vdp.h"
#include "ff.h"
#include "spi.h"
#include "misc.h"
#include "config.h"
#include "flash.h"


FATFS           FatFs;          /* FatFs work area needed for each volume */
FIL             Fil;            /* File object needed for each open file */
FRESULT         res;

unsigned char   tbuHeader[512];
unsigned char   mach_version,mach_version_sub;
unsigned char   file_mach_id = 0, file_mach_version = 0, file_mach_sub = 0;
unsigned char   file_board_id = 0xff, file_core_id = 1;
unsigned char   wasUpdated = 0;
unsigned int    bl, i;
unsigned int    imageCS = 0;
unsigned long   fsize, imageStart, imageSize, imageCSType = 0;

extern unsigned char sectBuffer[512];

static unsigned char wait_resp() {
        unsigned char r = 0;
        unsigned char bts = 0;

        REG_NUM = REG_ANTIBRICK;


        while (1) {
                // key Y
                if ((HROW5 & (1 << 4)) == 0) {
                        r = 2;
                        break;
                }
                // key N
                if ((HROW7 & (1 << 3)) == 0) {
                        r = 3;
                        break;
                }

                bts = REG_VAL;


                if (bts & 1) //MF button, same as N
                {
                        r = 3;
                        break;
                }

                if (bts & 2) //Drive button, same as Y
                {
                        r = 2;
                        break;
                }


        }
        return r;
}


static unsigned char wait_ab()
{
        unsigned char bts = 0;

        while (1)
        {
                // key A+B
                if (((HROW1 & 1) == 0) && ((HROW7 & 16) == 0))
                {
                        return 1;
                }
                else
                {
                        // any other key
                        unsigned char row1 = HROW1;
                        unsigned char row7 = HROW7;
                        unsigned char allrows = HROW0 & row1 & row7;
                        allrows &= HROW2;
                        allrows &= HROW3;
                        allrows &= HROW4;
                        allrows &= HROW5;
                        allrows &= HROW6;

                        if ((allrows & 0x1f) != 0x1f)
                        {
                                // ignoring A or B
                                if (((row1 & 1) != 0) && ((row7 & 16) != 0))
                                {
                                        return 0;
                                }
                        }
                }

                // any button
                REG_NUM = REG_ANTIBRICK;
                bts = REG_VAL;

                if (bts & 0x3)
                {
                        return 0;
                }
        }
}


void showUpdater()
{
        vdp_cls();
        vdp_setcolor(COLOR_BLACK, COLOR_BLUE, COLOR_WHITE);
        vdp_prints(TITLE);

        if (machineAB)
        {
                vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_RED);
                vdp_gotoxy(11, 2);
                vdp_prints("Anti-Brick\n\n");

                REG_NUM = REG_ANTIBRICK;
                while (REG_VAL & 3);
        }
        else
        {
                vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_LGREEN);
                vdp_gotoxy(12, 2);
                vdp_prints("Updater\n\n");

                REG_NUM = REG_ANTIBRICK;
                while (REG_VAL & 3);
        }

        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_WHITE);
}


void updateCore()
{
        showUpdater();

        // Images begin after the TBU header.
        imageStart++;

        if (boardId != file_board_id)
        {
                sprintf(line, "Wrong board id: 0x%02x vs 0x%02x", file_board_id, boardId);
                display_error(line);
        }

        vdp_setfg(COLOR_WHITE);
        vdp_gotox(12);
        vdp_prints("Board Id\n");

        vdp_setfg(COLOR_LCYAN);
        vdp_gotox(16 - (strlen(boards[boardId].boardName) / 2));
        vdp_prints(boards[boardId].boardName);
        vdp_prints("\n\n");

        vdp_setfg(COLOR_WHITE);
        vdp_gotox(14);
        vdp_prints("Slot\n");

        vdp_setfg(COLOR_LCYAN);
        sprintf(line, "%02d\n\n", file_core_id);
        vdp_gotox(15);
        vdp_prints(line);

        vdp_setfg(COLOR_WHITE);
        vdp_gotox(12);
        vdp_prints("Version\n");

        vdp_setfg(COLOR_LCYAN);
        sprintf(line, "%d.%02d.%02d\n\n", file_mach_version >> 4, file_mach_version & 0x0f, file_mach_sub);
        vdp_gotox(12);
        vdp_prints(line);

        vdp_setfg(COLOR_WHITE);

        vdp_gotox(16);

        for(i = 0; i < 1500; i++) // Wait a little
        {
                flashProgress();
        };

        vdp_gotox(0);

        if (file_core_id == 0)
        {
                vdp_setbg(COLOR_RED);
                vdp_prints("            WARNING!            ");
                vdp_prints("This updates the ANTIBRICK core ");
                vdp_prints("and will BRICK your Next if it  ");
                vdp_prints("goes wrong or power is removed. ");
                vdp_prints("   Press A+B to update anyway,  ");
                vdp_prints("   or any other key to abort.   ");
                vdp_setbg(COLOR_BLACK);
                vdp_prints("\n");

                if (wait_ab() != 1)
                {
                        return;
                }
        }
        else
        {
                vdp_prints(" Do you want to upgrade? (y/n)");

                if (wait_resp() != 2 ) {
                        vdp_prints("n\n\n");
                        return;
                }

                vdp_prints("y\n\n");
        }

        verifyChecksum(&Fil, imageStart, imageSize, imageCSType, imageCS);
        writeCore(file_core_id, &Fil, imageStart, imageSize);

        wasUpdated = 1;
}


void main()
{
        vdp_init();
        detectBoard();

        if (machineId != HWID_ZXNEXT)
        {
                sprintf(line, "Unsupported machine: 0x%02x", machineId);
                display_error(line);
        }

        GET_NEXTREG(REG_VERSION, mach_version);
        GET_NEXTREG(REG_VERSION_SUB, mach_version_sub);

        if (machineAB == 0)
        {
                SET_NEXTREG(REG_TURBO, 3);

                // Read config.ini and honour the video settings.
                // Can't be done for AB cores on KS1 machines, since they do
                // not include video mode setting registers.
                load_config();
                update_video_settings();
        }
        else
        {
                // TODO Might be able to set to 3 if high enough AB version
                SET_NEXTREG(REG_TURBO, 0);
                reset_settings();
        }

        showUpdater();

        f_mount(&FatFs, "", 0);                         /* Give a work area to the default drive */

        res = f_open(&Fil, NEXT_UPDATE_FILE2, FA_READ);
        if (res != FR_OK) {
                display_error("Error opening " NEXT_UPDATE_FILE2 " file");
        }
        fsize = f_size(&Fil);
        res = f_read(&Fil, tbuHeader, 512, &bl);
        if (res != FR_OK || bl != 512) {
                display_error("Error reading " NEXT_UPDATE_FILE2 " file!");
        }

        if (0 == strncmp(tbuHeader, "TBUFILE", 7)) {
                byteoffset = 0;
                cso = 0;
        } else if (0 == strncmp(tbuHeader, "ZXNFILE", 7)) {
                byteoffset = 1;
                cso = 0xa1;
        } else {
                display_error("Wrong Magic!");
        }

        if (0 == strncmp(tbuHeader+8, "ZX SPECTRUM NEXT", 16))
        {
                unsigned char *pRec = tbuHeader + 25;

                while (pRec[0] != 0xff)
                {
                        if ((pRec[2] == boardId) && (pRec[0] >= 15))
                        {
                                file_core_id = pRec[1];
                                file_board_id = pRec[2];
                                file_mach_version = pRec[3];
                                file_mach_sub = pRec[4];
                                imageStart = *((unsigned long *)(pRec+5));
                                imageSize = *((unsigned long *)(pRec+9));
                                imageCSType = 1;
                                imageCS = *((unsigned int *)(pRec+13));

                                if (file_core_id < boards[boardId].numCores)
                                {
                                        updateCore();
                                }
                        }

                        pRec += pRec[0];
                }

        }
        else
        {
                // Old single-core TBU for issue 2.
                memcpy(&imageSize, tbuHeader+7, 4);
                if ((fsize != imageSize + 512) || (imageSize & 0x1ff)) {
                        sprintf(line, "Wrong image size, %ld", imageSize);
                        display_error(line);
                }

                imageStart = 0;
                imageSize >>= 9;

                imageCSType = 0;
                imageCS = tbuHeader[13];

                file_mach_id = tbuHeader[11];
                file_mach_version = tbuHeader[12];
                file_mach_sub = tbuHeader[500];
                file_board_id = 0;
                file_core_id = 1;

                if (machineId != file_mach_id)
                {
                        sprintf(line, "Wrong machine id: 0x%02x vs 0x%02x", file_mach_id, machineId);
                        display_error(line);
                }

                updateCore();
        }

        if (!wasUpdated)
        {
                SET_NEXTREG(REG_RESET, RESET_HARD);
        }

        vdp_cls();
        vdp_gotoxy(12, 5);
        vdp_prints("Updated!\n\n");
                //  12345678901234567890123456789012
        if (boardId == 0)
        {
                //          12345678901234567890123456789012
                vdp_prints(" Turn the power off and remove\n");
                vdp_prints(" the HDMI cable. Then turn the\n");
                vdp_prints(" power back on again.");
        }
        else
        {
                vdp_prints("Turn the power off and on again.");
        }

        f_close(&Fil);

        for(;;);
}
