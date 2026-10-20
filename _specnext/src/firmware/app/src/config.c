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

const char * settingName[eSettingMAX] =
{
        "scandoubler",          // eSettingScandoubler
        "50_60hz",              // eSettingFreq5060
        "timex",                // eSettingTimex
        "psgmode",              // eSettingPsgMode
        "intsnd",               // eSettingIntSnd
        "stereomode",           // eSettingStereoMode
        "turbosound",           // eSettingTurboSound
        "divmmc",               // eSettingDivMMC
        "mf",                   // eSettingMF
        "joystick1",            // eSettingJoystick1
        "joystick2",            // eSettingJoystick2
        "ps2",                  // eSettingPS2
        "dma",                  // eSettingDMA
        "scanlines",            // eSettingScanlines
        "turbokey",             // eSettingTurboKey
        "default",              // eSettingMenuDefault
        "timing",               // eSettingTiming
        "keyb_issue",           // eSettingIss23
        "divports",             // eSettingDivPorts
        "dac",                  // eSettingDAC
        "ay48",                 // eSettingAY48
        "uart_i2c",             // eSettingUARTI2C
        "kmouse",               // eSettingKMouse
        "ulaplus",              // eSettingULAplus
        "hdmisound",            // eSettingHDMISound
        "beepmode",             // eSettingBEEPMode
        "buttonswap",           // eSettingMouseBtnSwap
        "mousedpi",             // eSettingMouseDPI
        "espreset",             // eSettingESPReset
};

const unsigned char settingMaxValue[eSettingMAX] =
{
        MAX_SCANDOUBLER,        // eSettingScandoubler
        MAX_FREQ5060,           // eSettingFreq5060
        MAX_TIMEX,              // eSettingTimex
        MAX_PSGMODE,            // eSettingPsgMode
        MAX_INTSND,             // eSettingIntSnd
        MAX_STEREOMODE,         // eSettingStereoMode
        MAX_TURBOSOUND,         // eSettingTurboSound
        MAX_DIVMMC,             // eSettingDivMMC
        MAX_MF,                 // eSettingMF
        MAX_JOYSTICK1,          // eSettingJoystick1
        MAX_JOYSTICK2,          // eSettingJoystick2
        MAX_PS2,                // eSettingPS2
        MAX_DMA,                // eSettingDMA
        MAX_SCANLINES,          // eSettingScanlines
        MAX_TURBOKEY,           // eSettingTurboKey
        255,                    // eSettingMenuDefault (don't clamp)
        MAX_TIMING,             // eSettingTiming
        MAX_ISS23,              // eSettingIss23
        MAX_DIVPORTS,           // eSettingDivPorts
        MAX_DAC,                // eSettingDAC
        MAX_AY48,               // eSettingAY48
        MAX_UARTI2C,            // eSettingUARTI2C
        MAX_KMOUSE,             // eSettingKMouse
        MAX_ULAPLUS,            // eSettingULAplus
        MAX_HDMISOUND,          // eSettingHDMISound
        MAX_BEEPMODE,           // eSettingBEEPMode
        MAX_BUTTONSWAP,         // eSettingMouseBtnSwap
        MAX_MOUSEDPI,           // eSettingMouseDPI
        MAX_ESPRESET,           // eSettingESPReset
};

const unsigned char settingDefaults[eSettingMAX] =
{
        1,                      // eSettingScandoubler
        0,                      // eSettingFreq5060
        1,                      // eSettingTimex
        1,                      // eSettingPsgMode
        1,                      // eSettingIntSnd
        0,                      // eSettingStereoMode
        1,                      // eSettingTurboSound
        0,                      // eSettingDivMMC
        0,                      // eSettingMF
        1,                      // eSettingJoystick1
        3,                      // eSettingJoystick2
        1,                      // eSettingPS2
        0,                      // eSettingDMA
        0,                      // eSettingScanlines
        1,                      // eSettingTurboKey
        0,                      // eSettingMenuDefault
        8,                      // eSettingTiming
        0,                      // eSettingIss23
        1,                      // eSettingDivPorts
        1,                      // eSettingDAC
        0,                      // eSettingAY48
        1,                      // eSettingUARTI2C
        1,                      // eSettingKMouse
        1,                      // eSettingULAplus
        1,                      // eSettingHDMISound
        0,                      // eSettingBEEPMode
        0,                      // eSettingMouseBtnSwap
        1,                      // eSettingMouseDPI
        0,                      // eSettingESPReset
};

const unsigned char settingType[eSettingMAX] =
{
        eTypeYesNo,             // eSettingScandoubler
        eTypeYesNo,             // eSettingFreq5060
        eTypeYesNo,             // eSettingTimex
        eTypePSGMode,           // eSettingPSGMode
        eTypeYesNo,             // eSettingIntSnd
        eTypeStereoMode,        // eSettingStereoMode
        eTypeYesNo,             // eSettingTurboSound
        eTypeYesNo,             // eSettingDivMMC
        eTypeYesNo,             // eSettingMF
        eTypeJoystickMode,      // eSettingJoystick1
        eTypeJoystickMode,      // eSettingJoystick2
        eTypePS2Mode,           // eSettingPS2
        eTypeYesNo,             // eSettingDMA
        eTypeScanlines,         // eSettingScanlines
        eTypeYesNo,             // eSettingTurboKey
        0,                      // eSettingMenuDefault (not edited)
        0,                      // eSettingTiming (not edited)
        eTypeIss23,             // eSettingIss23
        eTypeYesNo,             // eSettingDivPorts
        eTypeYesNo,             // eSettingDAC
        eTypeYesNo,             // eSettingAY48
        eTypeYesNo,             // eSettingUARTI2C
        eTypeYesNo,             // eSettingKMouse
        eTypeYesNo,             // eSettingULAplus
        eTypeYesNo,             // eSettingHDMISound
        eTypeBEEPMode,          // eSettingBEEPMode
        eTypeYesNo,             // eSettingMouseBtnSwap
        eTypeDPI,               // eSettingMouseDPI
        eTypeYesNo,             // eSettingESPReset
};

unsigned char settings[eSettingMAX];
unsigned char menu_cont = 0;
mnuitem menus[MAX_MENU_ITEMS];

char temp[16];
const char *pLine, *comma;
mnuitem *pMenu;

void parsestring(char *pDest, unsigned int maxlen)
{
        memset(pDest, 0, maxlen);
        comma = strchr(pLine, ',');

        if (comma == 0)
        {
                strncpy(pDest, pLine, maxlen-1);
                pLine = "\0";
        }
        else
        {
                strncpy(pDest, pLine, MIN(comma-pLine,maxlen-1));
                pLine = comma + 1;
        }
}

void parsenumber(unsigned char *pValue)
{
        parsestring(temp, 16);
        *pValue = atoi(temp);
}

void parseword(unsigned int *pValue)
{
        parsestring(temp, 16);
        *pValue = atoi(temp);
}

void set_video_mode(unsigned char timing, unsigned char freq, unsigned char doubler)
{
        unsigned char vl, vh;
        unsigned char opc = 0xfa;       // keyjoy modes
        if (freq)       opc |= 0x04;
        if (doubler)    opc |= 0x01;

        // Waiting until line 230 helps prevent monitors becoming confused
        // when a mode change occurs.
        do {
                REG_NUM = REG_VIDEOLINE_HI;
                vh = REG_VAL;
                REG_NUM = REG_VIDEOLINE_LO;
                vl = REG_VAL;
        } while ((vh != 0) && (vl != 230));

        REG_NUM = REG_VIDEOT;
        REG_VAL = (timing & 0x07) | 0x80;

        REG_NUM = REG_PERIPH1;
        REG_VAL = opc;
}

void update_video_settings()
{
        unsigned char tim = settings[eSettingTiming];

        if ((menu_cont > 0) && (settings[eSettingMenuDefault] < menu_cont))
        {
                pMenu = &(menus[settings[eSettingMenuDefault]]);

                // If timing override is specified, use it.
                if (pMenu->video_timing < 8)
                {
                        tim = pMenu->video_timing;
                }
        }

        set_video_mode(tim, settings[eSettingFreq5060], settings[eSettingScandoubler]);

        REG_NUM = REG_PERIPH4;
        REG_VAL = settings[eSettingScanlines] & 3;
}


unsigned char keyjoy_firmware[11] = {
        0b00100010,     // right=8
        0b00011100,     // left=5
        0b00100100,     // down=6
        0b00100011,     // up=7
        0b00111000,     // fire/B=SPACE
        0b00110000,     // fire2/C=ENTER
        0b00001000,     // A=A
        0b00101011,     // S=U
        0b00101100,     // Y=Y
        0b00111011,     // Z=N
        0b00000011,     // X=C
};

void load_keyjoys(unsigned char *pKeyjoy)
{
        unsigned int i, k;

        for (i = 0; i < 2; i++)
        {
                REG_NUM = REG_KMHA;
                REG_VAL = 0x80;
                REG_NUM = REG_KMLA;
                REG_VAL = i << 4;

                for (k = 0; k < 11; k++)
                {
                        REG_NUM = REG_KMLD;
                        REG_VAL = pKeyjoy[k];
                }
        }
}

void reset_settings()
{
        unsigned char opc;

        // Default all options to something sensible
        memcpy(&settings, &settingDefaults, sizeof(settings));

        // Hold the ESP in reset to start with
        REG_NUM = REG_RESET;
        REG_VAL = RESET_ESPBUS;

        // Set the joystick ports to keyjoys
        REG_NUM = REG_PERIPH1;
        opc = REG_VAL;
        REG_VAL = opc | 0xfa;

        // Initialise the keyjoys
        load_keyjoys(keyjoy_firmware);
}

void load_config()
{
        unsigned int i;

        // Default all options to something sensible
        reset_settings();

        // Give a work area to the default drive
        res = f_mount(&FatFs, "", 0);
        if (res != FR_OK)
        {
                //             12345678901234567890123456789012
                display_error("Error mounting SD card!");
        }

        res = f_open(&Fil, CONFIG_FILE, FA_READ);
        if (res == FR_OK)
        {
                // Read configuration
                while(f_eof(&Fil) == 0)
                {
                        if (!f_gets(line, 255, &Fil))
                        {
                                //             12345678901234567890123456789012
                                display_error("Error reading file data!");
                        }

                        // Ensure correct parsing even if no EOL on last line
                        if (line[strlen(line)-1] == '\n')
                        {
                                line[strlen(line)-1] = '\0';
                        }
                        else
                        {
                                line[strlen(line)] = '\0';
                        }

                        for (i = 0; i < eSettingMAX; i++)
                        {
                                unsigned int len = strlen(settingName[i]);
                                if ((line[len] == '=') && strncmp(line, settingName[i], len) == 0)
                                {
                                        settings[i] = CLAMP(atoi(line + len + 1), settingMaxValue[i]);
                                        break;
                                }
                        }
                }

                f_close(&Fil);
        }

        res = f_open(&Fil, MENU_FILE, FA_READ);
        if (res != FR_OK)
        {
                res = f_open(&Fil, MENU_DEFAULT_FILE, FA_READ);

                if (res != FR_OK)
                {
                        //             12345678901234567890123456789012
                        display_error("Error opening 'menu.ini/.def'!");
                }
        }

        // Read menu
        while(f_eof(&Fil) == 0)
        {
                if (!f_gets(line, 255, &Fil))
                {
                        //             12345678901234567890123456789012
                        display_error("Error reading file data!");
                }

                // Ensure correct parsing even if no EOL on last line
                if (line[strlen(line)-1] == '\n')
                {
                        line[strlen(line)-1] = '\0';
                }
                else
                {
                        line[strlen(line)] = '\0';
                }

                if ( strncmp ( line, "menu=", 5) == 0)
                {
                        if (menu_cont < MAX_MENU_ITEMS) {
                                pMenu = &(menus[menu_cont]);
                                pLine = line + 5;
                                parsestring(pMenu->title, MAX_TITLE);
                                parsenumber(&(pMenu->mode));
                                parsenumber(&(pMenu->video_timing));
                                parsestring(pMenu->romfile, MAX_ROMNAME);
                                parsestring(pMenu->divmmc_romfile, MAX_ROMNAME);
                                parsestring(pMenu->mf_romfile, MAX_ROMNAME);

                                if (pMenu->romfile[0])
                                {
                                        ++menu_cont;
                                }
                        }
                }
        }

        f_close(&Fil);

        if (menu_cont == 0) {
                //             12345678901234567890123456789012
                display_error("No menu line read!");
        }

        if (settings[eSettingMenuDefault] >= menu_cont) {
            settings[eSettingMenuDefault] = menu_cont - 1;
        }
}
