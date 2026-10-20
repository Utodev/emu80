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

#ifndef _CONFIG_H
#define _CONFIG_H

#define MIN(a,b)        (((a)<(b))?(a):(b))
#define MAX(a,b)        (((a)>(b))?(a):(b))
#define CLAMP(a,b)      ((MAX(0,(MIN(a,b)))))

#define ERR_CHECK(x) if (res == FR_OK) { res = x; }
#define ERR_CHECK_PF(x) if (res == FR_OK) { res = (x<0) ? FR_DISK_ERR : FR_OK; }

#define MAX_SCANDOUBLER 1
#define MAX_FREQ5060    1
#define MAX_TIMEX       1
#define MAX_PSGMODE     3
#define MAX_INTSND      1
#define MAX_STEREOMODE  1
#define MAX_TURBOSOUND  1
#define MAX_DIVMMC      1
#define MAX_MF          1
#define MAX_JOYSTICK1   7
#define MAX_JOYSTICK2   7
#define MAX_PS2         1
#define MAX_DMA         1
#define MAX_SCANLINES   3
#define MAX_TURBOKEY    1
#define MAX_TIMING      8
#define MAX_ISS23       1
#define MAX_DIVPORTS    1
#define MAX_DAC         1
#define MAX_AY48        1
#define MAX_UARTI2C     1
#define MAX_KMOUSE      1
#define MAX_ULAPLUS     1
#define MAX_HDMISOUND   1
#define MAX_BEEPMODE    1
#define MAX_BUTTONSWAP  1
#define MAX_MOUSEDPI    3
#define MAX_ESPRESET    1

#define MAX_TITLE       31      // inc null; 2 spaces get printed to left
#define MAX_ROMNAME     15

#define MAX_MENU_ITEMS  24

enum {
        eSettingScandoubler = 0,
        eSettingFreq5060,
        eSettingTimex,
        eSettingPSGMode,
        eSettingSpeakerMode,
        eSettingStereoMode,
        eSettingTurboSound,
        eSettingDivMMC,
        eSettingMF,
        eSettingJoystick1,
        eSettingJoystick2,
        eSettingPS2,
        eSettingDMA,
        eSettingScanlines,
        eSettingTurboKey,
        eSettingMenuDefault,
        eSettingTiming,
        eSettingIss23,
        eSettingDivPorts,
        eSettingDAC,
        eSettingAY48,
        eSettingUARTI2C,
        eSettingKMouse,
        eSettingULAplus,
        eSettingHDMISound,
        eSettingBEEPMode,
        eSettingMouseBtnSwap,
        eSettingMouseDPI,
        eSettingESPReset,

        eSettingMAX
};

enum {
        eTypeYesNo = 0,
        eTypePSGMode,
        eTypeJoystickMode,
        eTypePS2Mode,
        eTypeStereoMode,
        eTypeScanlines,
        eTypeIss23,
        eTypeBEEPMode,
        eTypeDPI,
};

typedef struct {
        char            title[MAX_TITLE];
        unsigned char   mode;
        unsigned char   video_timing;
        char            romfile[MAX_ROMNAME];
        char            divmmc_romfile[MAX_ROMNAME];
        char            mf_romfile[MAX_ROMNAME];
} mnuitem;

extern FATFS FatFs;
extern FIL Fil;
extern FRESULT res;

extern const char * settingName[eSettingMAX];
extern const unsigned char settingMaxValue[eSettingMAX];
extern const unsigned char settingType[eSettingMAX];
extern unsigned char settings[eSettingMAX];
extern unsigned char menu_cont;
extern mnuitem menus[MAX_MENU_ITEMS];
extern char temp[16];
extern const char *pLine, *comma;
extern mnuitem *pMenu;

void parsestring(char *pDest, unsigned int maxlen);
void parsenumber(unsigned char *pValue);
void parseword(unsigned int *pValue);
void set_video_mode(unsigned char timing, unsigned char freq, unsigned char doubler);
void update_video_settings();
void load_keyjoys(unsigned char *pKeyjoy);
void reset_settings();
void load_config();
void save_config();

#endif // _CONFIG_H
