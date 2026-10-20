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
#include "ff.h"                         // read/write
#include "misc.h"
#include "config.h"

#define LI_ITEMS 4
#define MENU_LINES 19

const char YESNO[2][4] = {"NO ","YES"};
const char AYYM[4][4]  = {"YM ","AY ","---","OFF"};
const char JOYS[8][7]  = {"Sincl2","Kemps1","Cursor","Sincl1","Kemps2","MD 1  ","MD 2  ","Keyjoy"};
const char PS_2[2][6]  = {"Keyb.","Mouse"};
const char STEREO[2][4] = {"ABC","ACB"};
const char SCANL[4][6] = {"OFF  ","50%  ","25%  ","12.5%"};
const char ISS23[2][5] = {"Iss3","Iss2"};
const char BEEPMODE[2][4] = {"All","Int"};
const char DPIMODE[4][7] = {"Low   ","Normal","Medium","High  "};

unsigned char * help_joy[] =
                                { // 12345678901234567890123456789012
                                        "Maps to keys 1,2,3,4 and 5     ",
                                        "Kempston at port 31            ",
                                        "Maps to keys 5,6,7,8 and 0     ",
                                        "Maps to keys 6,7,8,9 and 0     ",
                                        "Kempston at port 55            ",
                                        "3 or 6 button joypad at port 31",
                                        "3 or 6 button joypad at port 55",
                                        "Keys (def: QAOP SPC M ENT SXYZ)"
                                };

/*
joystick types
000 = Sinclair 2 (67890)
001 = Kempston 1 (1f)
010 = Cursor
011 = Sinclair 1 (12345)
100 = Kempston 2 (5f)
101 = MD 1 (sega 3/6 at 1f)
110 = MD 2 (sega 3/6 at 5f)
*/

FATFS           FatFs;          /* FatFs work area needed for each volume */
FIL             Fil;            /* File object needed for each open file */
FRESULT         res;

unsigned char saved_settings[eSettingMAX];

unsigned char button_up = 0;
unsigned char button_down = 0;
unsigned char button_left = 0;
unsigned char button_right = 0;
unsigned char button_enter = 0;
unsigned char button_e = 0;
unsigned char button_c = 0;
unsigned char button_q = 0;
unsigned char button_space = 0;
unsigned char config_changed = 0;

unsigned char   mach_id, mach_version;
unsigned char   i, it, nl, l, c, t, r, lin, col, *value, type;
unsigned char   top, bottom, pagetop, opc, posc;
unsigned int    bl = 0;
unsigned char   mode = 0;

const char * editName[eSettingMAX] =
{
//       123456789
        "Scandoub.",            // eSettingScandoubler
        "60 Hz",                // eSettingFreq5060
        "Timex",                // eSettingTimex
        "PSG Mode",             // eSettingPsgMode
        "IntSpeak",             // eSettingSpeakerMode
        "Stereo M.",            // eSettingStereoMode
        "TurboSnd",             // eSettingTurboSound
        "DivmmcROM",            // eSettingDivMMC
        "Multiface",            // eSettingMF
        "Left joy",             // eSettingJoystick1
        "Right joy",            // eSettingJoystick2
        "PS2",                  // eSettingPS2
        "DMA",                  // eSettingDMA
        "Scanlines",            // eSettingScanlines
        "Turbo Key",            // eSettingTurboKey
        "Default",              // eSettingMenuDefault (not edited)
        "Timing",               // eSettingTiming (not edited)
        "Keyboard",             // eSettingIss23
        "Divmmc HW",            // eSettingDivPorts
        "DACs",                 // eSettingDAC,
        "AY in 48K",            // eSettingAY48
        "UART/I2C",             // eSettingUARTI2C
        "KMouse",               // eSettingKMouse
        "ULAplus",              // eSettingULAplus
        "HDMISound",            // eSettingHDMISound
        "BEEPer",               // eSettingBEEPMode
        "BtnSwap",              // eSettingMouseBtnSwap
        "MouseDPI",             // eSettingMouseDPI
        "ESP Reset",            // eSettingESPReset
};

// ZX Spectrum Next
const unsigned char linesNextZXOS = 5;
unsigned char peripheralsNext[] =
{
        // Settings honoured by NextZXOS
        eSettingPS2,            eSettingHDMISound,
        eSettingMouseDPI,       eSettingSpeakerMode,
        eSettingMouseBtnSwap,   eSettingBEEPMode,
        eSettingIss23,          eSettingStereoMode,
        eSettingScanlines,      eSettingESPReset,

        // Settings for other personalities only
        eSettingJoystick1,      eSettingTurboSound,
        eSettingJoystick2,      eSettingPSGMode,
        eSettingKMouse,         eSettingAY48,
        eSettingDivMMC,         eSettingDAC,
        eSettingDivPorts,       eSettingTimex,
        eSettingMF,             eSettingULAplus,
        eSettingDMA,            eSettingUARTI2C,
};

const unsigned char itemsCountNext = sizeof(peripheralsNext) / sizeof(unsigned char);

unsigned char *peripherals;
unsigned char itemsCount;


static void waitforanykey()
{
        while(1)
        {
                if ( ((HROW0 & 0x1f) != 0x1f) ||
                        ((HROW1 & 0x1f) != 0x1f) ||
                        ((HROW2 & 0x1f) != 0x1f) ||
                        ((HROW3 & 0x1f) != 0x1f) ||
                        ((HROW4 & 0x1f) != 0x1f) ||
                        ((HROW5 & 0x1f) != 0x1f) ||
                        ((HROW6 & 0x1f) != 0x1f) ||
                        ((HROW7 & 0x1f) != 0x1f) )
                {
                        while ( ((HROW0 & 0x1f) != 0x1f) ||
                                ((HROW1 & 0x1f) != 0x1f) ||
                                ((HROW2 & 0x1f) != 0x1f) ||
                                ((HROW3 & 0x1f) != 0x1f) ||
                                ((HROW4 & 0x1f) != 0x1f) ||
                                ((HROW5 & 0x1f) != 0x1f) ||
                                ((HROW6 & 0x1f) != 0x1f) ||
                                ((HROW7 & 0x1f) != 0x1f) );

                        return;
                }
        }
}

static void display_about(void)
{
        vdp_setcolor(COLOR_BLUE, COLOR_BLACK, COLOR_LYELLOW);
        vdp_cls();

        vdp_gotoxy(2, 2); vdp_prints("The Next Team");
        vdp_setcolor(COLOR_BLUE, COLOR_BLACK, COLOR_GRAY);
        vdp_gotoxy(2, 3); vdp_prints("Victor Trucco");
        vdp_gotoxy(2, 4); vdp_prints("Fabio Belavenuto");
        vdp_gotoxy(2, 5); vdp_prints("Henrique Olifiers");
        vdp_gotoxy(2, 6); vdp_prints("Rick Dickinson");
        vdp_gotoxy(2, 7); vdp_prints("Phil Candy");
        vdp_gotoxy(2, 8); vdp_prints("Jim Bagley");

        vdp_setcolor(COLOR_BLUE, COLOR_BLACK, COLOR_LYELLOW);
        vdp_gotoxy(2, 10); vdp_prints("The Folks Who Made It Happen");
        vdp_setcolor(COLOR_BLUE, COLOR_BLACK, COLOR_GRAY);
        vdp_gotoxy(2, 11); vdp_prints("Allen Albright");
        vdp_gotoxy(2, 12); vdp_prints("Mike Cadwallader");
        vdp_gotoxy(2, 13); vdp_prints("Phoebus Dokos");
        vdp_gotoxy(2, 14); vdp_prints("Garry Lancaster");

        vdp_setcolor(COLOR_BLUE, COLOR_BLACK, COLOR_LYELLOW);
        vdp_gotoxy(2, 16); vdp_prints("The Super Backers");
        vdp_setcolor(COLOR_BLUE, COLOR_BLACK, COLOR_GRAY);
        vdp_gotoxy(2, 17); vdp_prints("Paul Howes");
        vdp_gotoxy(2, 18); vdp_prints("Jake Warren");
        vdp_gotoxy(2, 19); vdp_prints("Steve Brown (aka Gilby)");
        vdp_gotoxy(2, 20); vdp_prints("Dan Birch");
        vdp_gotoxy(2, 21); vdp_prints("Bob Bazley");

        while ((HROW0 & 0x08) == 0);    // ignore still-pressed C key
        waitforanykey();
}

static void printVal(unsigned char help)
{

        switch (type)
        {
                case eTypeYesNo:
                        vdp_prints(YESNO[*value]);
                break;

                case eTypePSGMode:
                        vdp_prints(AYYM[*value]);
                break;

                case eTypeJoystickMode:
                        vdp_prints(JOYS[*value]);
                break;

                case eTypePS2Mode:
                        vdp_prints(PS_2[*value]);
                break;

                case eTypeStereoMode:
                        vdp_prints(STEREO[*value]);
                break;

                case eTypeScanlines:
                        vdp_prints(SCANL[*value]);
                break;

                case eTypeIss23:
                        vdp_prints(ISS23[*value]);
                break;

                case eTypeBEEPMode:
                        vdp_prints(BEEPMODE[*value]);
                break;

                case eTypeDPI:
                        vdp_prints(DPIMODE[*value]);
                break;
        }

        if (help)
        {
                vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_WHITE);
                vdp_setflash(0);

                vdp_gotoxy(0, 20);
                vdp_prints("                                ");
                vdp_gotoxy(0, 20);

                if (type == eTypeJoystickMode)
                {
                        vdp_prints(help_joy[*value]);
                }
        }
}

static unsigned char getItemLine(unsigned char item)
{
        lin = (item >> 1);
        if (lin < linesNextZXOS)
        {
                lin += LI_ITEMS;
        }
        else
        {
                lin += LI_ITEMS + 3;
        }
        return lin;
}


static void show_peripherals()
{
        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_WHITE);
        vdp_cls();
        vdp_setbg(COLOR_BLUE);
        vdp_prints(TITLE);
        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_LCYAN);
        vdp_gotoxy(0, 2);
        vdp_prints("Options (always used):\n");
        vdp_gotoxy(0, 5 + linesNextZXOS);
        vdp_prints("Options (not used by NextZXOS):\n");
        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_CYAN);
        vdp_gotoxy(0, 22);
                //  12345678901234567890123456789012
        vdp_prints("Move with cursors; SPACE=change ");
        vdp_gotoxy(0, 23);
                //  12345678901234567890123456789012
        vdp_prints("ENTER=accept changes, Q=abort   ");
        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_GRAY);

        for (i = 0; i < itemsCount; i++)
        {
                lin = getItemLine(i);
                col = ((i & 1) == 0) ? 0 : 16;
                vdp_gotoxy(col, lin);
                vdp_setfg(COLOR_WHITE);
                vdp_prints(editName[peripherals[i]]);
                vdp_setfg(COLOR_LRED);
                vdp_gotox(col+9);
                value = &(settings[peripherals[i]]);
                type = settingType[peripherals[i]];
                printVal(0); // without help text
        }
}

static void readkeyb()
{
        button_up = 0;
        button_down = 0;
        button_left = 0;
        button_right = 0;
        button_enter = 0;
        button_e = 0;
        button_c = 0;
        button_q = 0;
        button_space = 0;

        while(1)
        {
                if ((HROW0 & 0x08) == 0) {
                        button_c = 1;
                        while(!(HROW0 & 0x08));
                        return;
                }
                if ((HROW2 & 0x01) == 0) {
                        button_q = 1;
                        while(!(HROW2 & 0x01));
                        return;
                }
                if ((HROW2 & 0x04) == 0) {
                        button_e = 1;
                        while(!(HROW2 & 0x04));
                        return;
                }
                if (((HROW7 & 0x01) == 0) && ((HROW0 & 0x01) ==1)) {
                        button_space = 1;
                        while(!(HROW7 & 0x01));
                        return;
                }
                if ((HROW3 & 0x10) == 0) {
                        button_left = 1;
                        while(!(HROW3 & 0x10));
                        return;
                }
                t = HROW4;
                if ((t & 0x10) == 0) {
                        button_down = 1;
                        while(!(HROW4 & 0x10));
                        return;
                }
                if ((t & 0x08) == 0) {
                        button_up = 1;
                        while(!(HROW4 & 0x08));
                        return;
                }
                if ((t & 0x04) == 0) {
                        button_right = 1;
                        while(!(HROW4 & 0x04));
                        return;
                }
                if ((HROW6 & 0x01) == 0) {
                        button_enter = 1;
                        while(!(HROW6 & 0x01));
                        return;
                }
        }
}

static unsigned char iedit()
{
        r = 0;
        lin = getItemLine(it);
        col = (c == 0) ? 9 : 25;
        while(1) {
                vdp_gotoxy(col, lin);
                vdp_setflash(1);
                vdp_setfg(COLOR_RED);
                printVal(1); // with the help text
                vdp_setflash(0);
                vdp_putchar(' ');
                readkeyb();
                if (i == 1) {
                        break;
                }
                if (button_space == 1) {
                        if (*value < settingMaxValue[peripherals[it]])
                        {
                                *value = *value + 1;
                        }
                        else
                        {
                                *value = 0;
                        }
                } else if (button_up == 1) {
                        r = 1;
                        break;
                } else if (button_down == 1) {
                        r = 2;
                        break;
                } else if (button_left == 1) {
                        r = 3;
                        break;
                } else if (button_right == 1) {
                        r = 4;
                        break;
                } else if (button_enter == 1) {
                        r = 5;
                        break;
                } else if (button_q == 1) {
                        r = 6;
                        break;
                }
        }
        vdp_gotoxy(col, lin);
        vdp_setflash(0);
        vdp_setfg(COLOR_LRED);
        printVal(0); //no help text
        vdp_prints(" ");

        vdp_gotoxy(0, 20);
        vdp_prints("                                ");

        return r;
}

static void mode_edit() {

        r = 0;
        it = 0;
        nl = (itemsCount - 1) >> 1;

        memcpy(&saved_settings, &settings, sizeof(settings));

        while (1) {
                l = it >> 1;
                c = it & 1;
                type = settingType[peripherals[it]];
                value = &(settings[peripherals[it]]);
                r = iedit();
                if (r == 0) {
                        show_peripherals();
                } else if (r == 1 && l > 0) {           // UP
                        it -= 2;
                } else if (r == 2 && l < nl) {          // DOWN
                        it += 2;
                } else if (r == 3 && c == 1) {          // LEFT
                        --it;
                } else if (r == 4 && c == 0) {          // RIGHT
                        ++it;
                } else if (r == 5) {                    // ENTER
                        break;
                } else if (r == 6) {                    // Q
                        memcpy(&settings, &saved_settings, sizeof(settings));
                        break;
                }
                if (it == itemsCount) {
                        --it;
                }
        }

        config_changed = 1;

        // Honour any changes to scandoubler, 50/60Hz and scanlines.
        update_video_settings();
}

static void show_menu(unsigned char numitems)
{
        top = 0;
        pagetop = 0;
        bottom = numitems-1;
        posc = settings[eSettingMenuDefault];
        if (posc > bottom)
                posc = bottom;
init:
        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_WHITE);
        vdp_cls();
        vdp_setbg(COLOR_BLUE);
        vdp_prints(TITLE);
        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_CYAN);
        vdp_gotoxy(0, 22);
        vdp_prints("  Press SPACE to edit options  ");
        vdp_gotoxy(0, 23);
        vdp_prints("         'C'  for credits screen");
        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_GRAY);
        while(1) {
                vdp_setfg(COLOR_LGREEN);

                if (posc < pagetop)
                {
                        pagetop = posc;
                }

                if (posc > (pagetop + (MENU_LINES-1)))
                {
                        pagetop = posc - (MENU_LINES-1);
                }

                for (i = 0; i < MENU_LINES; i++) {
                        if ((pagetop+i) <= bottom)
                        {
                                vdp_gotoxy(2, i+2);
                                vdp_setflash((pagetop+i) == posc);
                                vdp_prints(menus[pagetop+i].title);
                                vdp_setflash(0);
                                while (vdp_gety() == (i+2))
                                {
                                        vdp_putchar(' ');
                                }
                        }
                }

                readkeyb();
                vdp_setfg(COLOR_LGREEN);
                if (button_c) {
                        display_about();
                        goto init;
                }
                else if (button_space) {
                        show_peripherals();
                        mode_edit();
                        goto init;
                } else if (button_up) {
                        if (posc > top) {
                                --posc;
                        }
                } else if (button_down) {
                        if (posc < bottom) {
                                ++posc;
                        }
                } else if (button_left) {
                        if (posc >= MENU_LINES)
                        {
                                posc = posc - MENU_LINES;
                        }
                        else
                        {
                                posc = 0;
                        }
                } else if (button_right) {
                        if ((posc + MENU_LINES) <= bottom)
                        {
                                posc = posc + MENU_LINES;
                        }
                        else
                        {
                                posc = bottom;
                        }
                } else if (button_enter) {
                        if (posc != settings[eSettingMenuDefault]) {
                                settings[eSettingMenuDefault] = posc;
                                config_changed = 1;
                        }
                        break;
                }
        }
}

void main()
{
        REG_NUM = REG_MACHID;
        mach_id = REG_VAL;
        REG_NUM = REG_VERSION;
        mach_version = REG_VAL;

        vdp_init();
        disable_bootrom();

        // Read config.ini
        load_config();

        // Honour the current scandoubler, 50/60Hz and scanline settings.
        update_video_settings();

        if ( ((mach_id & 0x0f) == (HWID_ZXNEXT & 0x0f))
                || (mach_id == HWID_EMULATORS) )
        {
                peripherals = peripheralsNext;
                itemsCount = itemsCountNext;
        }
        else
        {
                display_error("Unsupported machine ID!");
        }

        vdp_setcolor(COLOR_BLACK, COLOR_BLUE, COLOR_WHITE);
        vdp_prints(TITLE);
        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_LGREEN);

        show_menu(menu_cont);

        if (config_changed)
        {
                save_config();
        }

        REG_NUM = REG_RESET;
        REG_VAL = RESET_HARD;                           // Hard-reset
}
