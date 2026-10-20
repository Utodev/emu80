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
#include "misc.h"
#include "modules.h"
#include "config.h"
#include "fwfile.h"
#include "videomagic.h"
#include "videotest.h"
#include "switch.h"
#include "flash.h"

FATFS           FatFs;          /* FatFs work area needed for each volume */
FIL             Fil;            /* File object needed for each open file */
FRESULT         res;

unsigned char * FW_version = "1.44";

// minimal required for this FW
unsigned long minimal = 0x03010a; // 03 01 0a = 3.01.10
unsigned long l = 0;
unsigned long current = 0;

const char *filename;
static unsigned char    mach_id = 0;
static unsigned char    opc = 0, mftype = 0;
static unsigned int     bl = 0, cont, i;

unsigned char s[] = { 2, 0, 0, 0, 0, 0, 0, 0, 0, 7, 1, 3, 5, 6, 4, 0, };

void error_loading(unsigned char *s)
{
        vdp_prints(s);

        ULAPORT = COLOR_RED;
        for(;;);
}

void loadFile(unsigned char destpage, unsigned char numpages, unsigned int blocklen)
{
        vdp_prints(filename);
        vdp_prints("...");
        strcpy(line, NEXT_DIRECTORY);
        strcat(line, filename);
        res = f_open(&Fil, line, FA_READ);
        if (res != FR_OK) {
                error_loading("unable to open!");
        }

        REG_NUM = REG_RAMPAGE;

        while (numpages--)
        {
                REG_VAL = destpage++;
                res = f_read(&Fil, (unsigned char *)0, blocklen, &bl);
                if (res != FR_OK || bl != blocklen) {
                        error_loading("error reading!");
                }
        }

        f_close(&Fil);
        vdp_prints("OK!\n");
}

void load_roms()
{
        //turn off the debug led
        LED = 1;

        REG_NUM = REG_RAMPAGE;

        filename = 0;

        if (settings[eSettingDivMMC] == 1)
        {
                filename = ESXMMC_FILE;
        }

        if (pMenu->divmmc_romfile[0])
        {
                filename = pMenu->divmmc_romfile;
        }

        if (filename) {
                vdp_prints("Loading ESXMMC:\n");
                loadFile(RAMPAGE_ROMDIVMMC, 1, 8192);
        }

        filename = 0;

        if (settings[eSettingMF] == 1) {
                switch ( pMenu->mode ) {
                        case 0:
                                mftype = 3;
                                filename = MF1_FILE;
                        break;

                        case 1:
                                // MF128 87.2 ROMs are type 1 (ports BF/3F)
                                mftype = 1;
                                filename = MF128_FILE;
                        break;

                        case 2:
                                mftype = 0;
                                filename = MF3_FILE;
                        break;

                        case 3: // Pentagon
                                mftype = 1;
                                filename = MF128_FILE;
                        break;
                }
        }

        if (pMenu->mf_romfile[0])
        {
                filename = pMenu->mf_romfile;
        }

        if (filename) {
                if ( (strncmp(filename, MF128_V1_FILE, strlen(MF128_V1_FILE)) == 0)
                   ||(strncmp(filename, MF128_V12_FILE, strlen(MF128_V12_FILE)) == 0)
                   )
                {
                        // MF128 87.1 and 87.12 ROMs are type 2 (ports 9F/1F)
                        mftype = 2;
                }

                vdp_prints("Loading Multiface ROM:\n");
                loadFile(RAMPAGE_ROMMF, 1, 8192);
        }

        filename = pMenu->romfile;

        vdp_prints("Loading ROM:\n");

        switch (pMenu->mode)
        {
                case 0:
                        // 48K: 1 x 16K block
                        i = 1;
                        break;
                case 2:
                        // +2A/+3e: 4 x 16K blocks
                        i = 4;
                        break;
                default:
                        // 128K, Pentagon: 2 x 16K blocks
                        i = 2;
                        break;
        }

        loadFile(RAMPAGE_ROMSPECCY, i, 16384);
}

void check_coreversion()
{
        REG_NUM = REG_MACHID;
        mach_id = REG_VAL;

        if (mach_id == HWID_EMULATORS)
        {
                return;
        }

        REG_NUM = REG_RAMPAGE;
        REG_VAL = RAMPAGE_ROMSPECCY + 1;
        l = (FSIZE_t)8896*s[mach_id >> 4];
        readFlash(boards[boardId].coreBlocks - 1, 0x5d, 0x40, 0x0000, 16*4);

        current = get_core_ver();

        if (current < minimal)
        {

                vdp_cls();
                vdp_setcolor(COLOR_BLACK, COLOR_BLUE, COLOR_WHITE);
                vdp_prints(TITLE);

                vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_LGREEN);

                if (current == 0)
                {
                        vdp_gotoxy(11, 3);
                        vdp_prints("Anti-Brick\n\n\n");

                        vdp_setcolor(COLOR_RED, COLOR_BLACK, COLOR_WHITE);
                        vdp_prints("No " NEXT_UPDATE_FILE2 " update file found!");

                        for (;;);
                }

                vdp_gotoxy(4, 3);
                vdp_prints ("Please update your core!\n\n\n");
                vdp_setcolor(COLOR_RED, COLOR_BLACK, COLOR_WHITE);

                vdp_prints(  "You need at least core  v");
                sprintf(line, "%lu.%02lu.%02lu", (minimal >> 16) & 0xff, (minimal >> 8) & 0xff, minimal & 0xff);
                vdp_prints(line);

                vdp_prints("\nYou currently have core v");
                sprintf(line, "%lu.%02lu.%02lu", (current >> 16) & 0xff, (current >> 8) & 0xff, current & 0xff);
                vdp_prints(line);

                if (mach_id != HWID_ZXNEXT)
                {
                        for (;;) ;
                }

                vdp_prints("\n\n\nPress U to enter the updater now");
                vdp_prints(      " if you have copied the latest\n");
                vdp_prints(      "  TBBLUE.TBU to your SD card\n");

                ULAPORT = COLOR_RED;
                for(;;)
                {
                        if ((HROW5 & 0x08) == 0)
                        {
                                switchModule(FW_BLK_UPDATER);
                        }
                }
        }
}

void display_bootscreen()
{
        fwOpenAndSeek(FW_BLK_SCREENS);
        REG_NUM = REG_RAMPAGE;
        REG_VAL = RAMPAGE_ROMSPECCY;
        fwSeek((FSIZE_t)49152+FW_L2_PAL_SIZE+l);
        fwRead((unsigned char *)0x0000, 0x2800);
        REG_NUM = REG_RAMPAGE;
        REG_VAL = RAMPAGE_ROMSPECCY + 1;
        fwRead((unsigned char *)0x3f00, 0x0100);
        fwClose();

        current = get_core_ver();

        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_WHITE);
        vdp_reveal(0x4000, 'z' + ((RAMPAGE_ROMSPECCY >> 1) << 8));

        vdp_gotoxy(1, 16);
        vdp_prints("For video mode selection press:");
        vdp_gotoxy(1, 17);
        vdp_prints("A=All, D=Digital, V=VGA, R=RGB");

        vdp_gotoxy(15, 21);
        vdp_prints("Firmware v");
        vdp_prints(FW_version);

        vdp_gotoxy(19, 22);
        vdp_prints("Core v");
        sprintf(line, "%lu.%02lu.%02lu", (current >> 16) & 0xff, (current >> 8) & 0xff, current & 0xff);
        vdp_prints(line);
}

void init_registers()
{
        unsigned char hwenables[4];
        unsigned int i;

        // Set peripheral config.
        REG_NUM = REG_PERIPH1;
        opc = ((settings[eSettingJoystick1] & 3) << 6)
                | ((settings[eSettingJoystick2] & 3) << 4);     // bits 7-6 and 5-4 (joysticks LSBs)
        if (settings[eSettingJoystick1] & 4)    opc |= 0x08;    // bit 3 = joystick 1 MSB
        if (settings[eSettingFreq5060])         opc |= 0x04;    // bit 2
        if (settings[eSettingJoystick2] & 4)    opc |= 0x02;    // bit 1 = joystick 2 MSB
        if (settings[eSettingScandoubler])      opc |= 0x01;    // bit 0
        REG_VAL = opc;

        REG_NUM = REG_PERIPH2;
        opc = settings[eSettingPSGMode];                        // bits 1-0
        if (settings[eSettingTurboKey])         opc |= 0x80;    // bit 7
        if (settings[eSettingBEEPMode])         opc |= 0x40;    // bit 6
        if (settings[eSettingDivMMC])           opc |= 0x10;    // bit 4
        if (settings[eSettingMF])               opc |= 0x08;    // bit 3
        if (settings[eSettingPS2])              opc |= 0x04;    // bit 2
        REG_VAL = opc;

        REG_NUM = REG_PERIPH3;
        opc = 0;
        if (settings[eSettingStereoMode])       opc |= 0x20;    // bit 5
        if (settings[eSettingSpeakerMode])      opc |= 0x10;    // bit 4
        if (settings[eSettingDAC])              opc |= 0x08;    // bit 3
        if (settings[eSettingTimex])            opc |= 0x04;    // bit 2
        if (settings[eSettingTurboSound])       opc |= 0x02;    // bit 1
        if (settings[eSettingIss23])            opc |= 0x01;    // bit 0
        REG_VAL = opc;

        REG_NUM = REG_PERIPH4;
        opc = settings[eSettingScanlines] & 3;                  // bits 1-0
        if (settings[eSettingHDMISound] == 0)   opc |= 0x04;    // bit 2
        REG_VAL = opc;

        REG_NUM = REG_PERIPH5;
        opc = settings[eSettingMouseDPI] & 3;                   // bits 1-0
        if (settings[eSettingMouseBtnSwap])     opc |= 0x08;    // bit 3
        if (settings[eSettingDivMMC])           opc |= 0x10;    // bit 4
        opc |= mftype << 6;                                     // bits 6-7
        REG_VAL = opc;

        // NOTE: With bit 31 of hwenables[3] set to 0, the internal port
        //       hw disables won't be reinitialised on a soft reset.
        hwenables[3] = 0x00;
        if (settings[eSettingULAplus] != 0)
        {
                hwenables[3] |= 0x01;
        }
        if (settings[eSettingDMA] != 0)
        {
                hwenables[3] |= 0x02;
        }

        if (settings[eSettingDAC] != 0)
        {
                // If DACs requested, enable AY and all DACs.
                hwenables[2] = 0xff;
        }
        else
        {
                // Otherwise just enable AY.
                hwenables[2] = 0x01;
        }

        hwenables[1] = 0x00;
        if (settings[eSettingDivPorts] != 0)
        {
                hwenables[1] |= 0x09;
        }
        if (settings[eSettingMF] != 0)
        {
                hwenables[1] |= 0x02;
        }
        if (settings[eSettingUARTI2C] != 0)
        {
                hwenables[1] |= 0x14;
        }
        if (settings[eSettingKMouse] != 0)
        {
                hwenables[1] |= 0x20;
        }

        // Disable main hardware ports according to machine type.
        switch (pMenu->mode)
        {
                // 48K
                case 0:
                        // Disable: ff/7ffd/dffd/1ffd/+3 FB/6b
                        hwenables[0] = 0xc0;

                        if (settings[eSettingAY48] == 0)
                        {
                                // Disable AY if not requested for 48K mode.
                                hwenables[2] &= 0xfe;
                        }
                break;

                // 128K
                case 1:
                        // Disable: ff/dffd/1ffd/+3 FB/6b
                        hwenables[0] = 0xc2;
                break;

                // +3
                case 2:
                        // Disable: ff/dffd/6b
                        hwenables[0] = 0xda;
                break;

                // Pentagon
                case 3:
                        // Disable: ff/1ffd/+3 FB/6b
                        hwenables[0] = 0xc6;
                        // Disable: Soundrive 2 DAC
                        hwenables[2] &= 0xfb;
                break;
        }

        for (i = 0; i < 4; i++)
        {
                REG_NUM = REG_DECODE_INT0 + i;
                REG_VAL = hwenables[i];
        }
}

void load_keymap()
{
        // Read and send Keymap
        vdp_prints("Loading keymap:\n");
        filename = KEYMAP_FILE;

        // NOTE: Keymap must be loaded before ROMs as it uses the same SRAM.
        loadFile(RAMPAGE_ROMSPECCY, 1, 1024);

        REG_NUM = REG_KMHA;
        REG_VAL = 0;
        REG_NUM = REG_KMLA;
        REG_VAL = 0;
        cont = 0;
        while (cont < 1024) {
                REG_NUM = REG_KMHD;
                REG_VAL = *((unsigned char *)cont++);
                REG_NUM = REG_KMLD;
                REG_VAL = *((unsigned char *)cont++);
        }
}

unsigned char keyjoy_default[11] = {
        0b00101000,     // P
        0b00101001,     // O
        0b00001000,     // A
        0b00010000,     // Q
        0b00111000,     // SPACE
        0b00111010,     // M
        0b00110000,     // ENTER
        0b00001001,     // S
        0b00101100,     // Y
        0b00000001,     // Z
        0b00000010,     // X
};

void main()
{
        // Always run at 28MHz.
        REG_NUM = REG_TURBO;
        REG_VAL = 3;

        // Start with PS/2 mode=keyboard until a personality is chosen.
        // This allows users with PS/2 keyboard only to enter settings and
        // change PS/2 mode. Those with just a PS/2 mouse will be using the
        // membrane keyboard, so will also be fine.
        // Anyone with both a PS/2 keyboard and mouse that has them connected
        // around the opposite way is on their own.
        REG_NUM = REG_PERIPH2;
        REG_VAL = 0xa0;

        vdp_init();
        disable_bootrom();

        // Read config.ini
        load_config();
        pMenu = &(menus[settings[eSettingMenuDefault]]);

        // Cycle through the modes if necessary
        if (videoTestActive())
        {
                // If a mode is chosen at this point it will also
                // override any menu line "override" for this boot. This
                // is useful if the default line won't display because of
                // an override.
                videoTestSet();
                switchModule(FW_BLK_TESTCARD);
        }
        else
        {
                // Honour the current scandoubler, 50/60Hz and scanline settings.
                update_video_settings();
        }

        if (getCoreBoot())
        {
                // Switch to cores module if alternative core requested.
                switchModule(FW_BLK_CORES);
        }

        // Show the boot screen
        detectBoard();
        check_coreversion();
        display_bootscreen();

        for(cont=0; cont < 0xffff; cont++)
        {
                if ((cont & 0xfff) == 0)
                {
                        if ((cont & 0x2000) == 0)
                        {
                                vdp_gotoxy(5, 11);
                                vdp_prints("Press SPACEBAR for menu\n");
                                vdp_gotoxy(5, 13);
                                vdp_prints("Press C for extra cores\n");
                        }
                        else
                        {
                                vdp_clear(5, 11, 23);
                                vdp_clear(5, 13, 23);
                        }
                }

                if (((HROW7 & 0x01) == 0) && ((HROW0 & 0x01) ==1))
                {
                        switchModule(FW_BLK_EDITOR);
                }

                if ((HROW0 & 0x08) == 0)
                {
                        switchModule(FW_BLK_CORES);
                }

                if (videoTestActive())
                {
                        // Enter video test if A/V/D/R pressed.
                        videoTestSet();
                        switchModule(FW_BLK_TESTCARD);
                }

                if ( ((HROW0 & 0x04) == 0) &&
                     ((HROW7 & 0x08) == 0) )
                {
                        // If N,X held down, reset config.ini to defaults.
                        switchModule(FW_BLK_RESET);
                }

                if ((HROW5 & 0x08) == 0)
                {
                        // If U held down, enter updater.
                        switchModule(FW_BLK_UPDATER);
                }
        }

        // Clear off the video mode selection prompts.
        vdp_clear(1, 16, 31);
        vdp_clear(1, 17, 31);
        vdp_gotoxy(0, 10);

        // Force MF and/or DivMMC if ROMs were specified.
        if (pMenu->mf_romfile[0])
        {
                if (strncmp(pMenu->mf_romfile, "<none>", 6) == 0)
                {
                        settings[eSettingMF] = 0;
                        pMenu->mf_romfile[0] = 0;
                }
                else
                {
                        settings[eSettingMF] = 1;
                }
        }

        if (pMenu->divmmc_romfile[0])
        {
                if (strncmp(pMenu->divmmc_romfile,"<none>", 6) == 0)
                {
                        settings[eSettingDivMMC] = 0;
                        pMenu->divmmc_romfile[0] = 0;
                }
                else
                {
                        settings[eSettingDivMMC] = 1;
                }
        }

        // NOTE: Keymap must be loaded before ROMs as it uses the same SRAM.
        load_keymap();
        load_keyjoys(keyjoy_default);
        load_roms();
        init_registers();

        // Set machine type
        REG_NUM = REG_MACHTYPE;
        REG_VAL = 0x80 | (pMenu->mode + 1) << 4 | (pMenu->mode + 1);

        // Pause.
        for (cont = 0; cont < 0xffff; cont++);

        REG_NUM = REG_RESET;
        if (settings[eSettingESPReset])
        {
                REG_VAL = RESET_ESPBUS | RESET_SOFT;
        }
        else
        {
                REG_VAL = RESET_SOFT;
        }

        for(;;);
}
