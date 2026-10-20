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
FIL             Fil, DatFil;    /* File object needed for each open file */
FRESULT         res;
DIR             Dir;
FILINFO         FilInfo;

extern unsigned char sectBuffer[512];
unsigned char   k, l;
unsigned int    bl, i, j;
unsigned long   fsize, dsize;

#define MAX_DIR_NAME            COREBOOT_NAMES_SIZE
#define MAX_RES_NAME            COREBOOT_NAMES_SIZE
#define MAX_CORE_NAME           24
#define MAX_USER_NAME           24
#define MAX_BIT_NAME            80
#define MAX_DATE                11
#define MAX_TIME                9
#define RESERVED_SLOTS          8
#define MAX_CORE_SLOTS          (32-RESERVED_SLOTS)
#define MAX_FILE_ITEMS          80 // TODO not enough memory: 120
#define CORES_TITLE             "  ZX Spectrum Next Extra Cores  "
#define MENU_LINES              19
#define MAX_USER_FILES          16
#define MAX_CONFIG_ITEMS        32
#define FLASH_NAME_CHARS        16

#define CFG_OFFSET_GENCFG       0
#define CFG_OFFSET_FILES        16
#define CFG_OFFSET_DIR          32
#define CFG_OFFSET_CORECFG      64
#define CFG_SIZE                256

#define CHOOSE_CORE_HELP        "Press ENTER to start core    \n      SPACE to replace core  "

unsigned char resName[MAX_RES_NAME];

typedef struct {
        char            dirname[MAX_DIR_NAME];
        char            name[MAX_CORE_NAME];
        unsigned char   update;
        char            flashname[FLASH_NAME_CHARS];
} coreitem;

coreitem cores[MAX_CORE_SLOTS];

typedef struct {
        char            fname[MAX_RES_NAME];
        char            name[MAX_CORE_NAME];
} fileitem;

fileitem fileItems[MAX_FILE_ITEMS];

unsigned char   core_entry;
unsigned char   file_entry;
unsigned char   sram_page;
unsigned char   numFileItems;
unsigned char   curItem;
unsigned char   numUnmatchedSlots;

char            searchDir[3*(MAX_DIR_NAME+1)];
char *          file_name;

unsigned char   bit_name[MAX_BIT_NAME];
unsigned char   bit_date[MAX_DATE], tmp_date[MAX_DATE];
unsigned char   bit_time[MAX_TIME], tmp_time[MAX_TIME];

char            userDir[MAX_DIR_NAME];
char            userName[MAX_USER_NAME];
unsigned char   userPage;
unsigned char   userReq;
unsigned int    userOffset;
unsigned char   userFiles[MAX_USER_FILES];
unsigned int    numUserFiles;

unsigned char   configPage;
unsigned int    configOffset;
unsigned int    numConfigItems;


static unsigned char wait_resp() {
        unsigned char r = 0;
        unsigned char bts = 0;

        REG_NUM = REG_ANTIBRICK;

        while (1) {
                // key Y
                if ((HROW5 & (1 << 4)) == 0) {
                        r = 2;
                        while(!(HROW1 & 0x02));
                        break;
                }
                // key N
                if ((HROW7 & (1 << 3)) == 0) {
                        r = 3;
                        while(!(HROW7 & 0x08));
                        break;
                }

                bts = REG_VAL;


                if ( bts & 1 > 0) //MF button, same as N
                {
                        r = 3;
                        break;
                }

                if ( bts & 2 > 0) //Drive button, same as Y
                {
                        r = 2;
                        break;
                }


        }
        return r;
}

void getEnter() {
        unsigned char r = 0xff;

        do {
                k = HROW0 & 0x1f;
                k &= HROW1 & 0x1f;
                k &= HROW2 & 0x1f;
                k &= HROW3 & 0x1f;
                k &= HROW4 & 0x1f;
                k &= HROW5 & 0x1f;
                k &= HROW6 & 0x1f;
                k &= HROW7 & 0x1f;
        } while (k != 0x1f);

        do {
                if ((HROW6 & 0x01) == 0)
                {
                        while((HROW6 & 0x01) == 0);
                        return;
                }

        } while (1);
}

unsigned char parseBitstream(const char *bitptr)
{
        if ((bitptr[0] == 0x00) && (bitptr[1] == 0x09)
                && (bitptr[11] == 0x00) && (bitptr[12] == 0x01)
                && (bitptr[13] == 'a'))
        {
                bl = (bitptr[14] << 8) + bitptr[15];

                if (bl > MAX_BIT_NAME)
                {
                        return 0;
                }

                strncpy(line, bitptr+16, MAX_BIT_NAME);

                bitptr += 16 + bl;

                if (bitptr[0] != 'b')
                {
                        return 0;
                }

                bl = (bitptr[1] << 8) + bitptr[2];
                bitptr += 3 + bl;

                if ((bitptr[0] != 'c') || (bitptr[1] != 0x00) || (bitptr[2] != MAX_DATE))
                {
                        return 0;
                }

                strncpy(tmp_date, bitptr+3, MAX_DATE);

                bitptr += 14;

                if ((bitptr[0] != 'd') || (bitptr[1] != 0x00) || (bitptr[2] != MAX_TIME))
                {
                        return 0;
                }

                strncpy(tmp_time, bitptr+3, MAX_TIME);

                return 1;
        }

        return 0;
}

unsigned char readCoreHeader(unsigned char coreId)
{
        readFlash(coreId * boards[boardId].coreBlocks, 0, 0, sectBuffer, 1);
        return parseBitstream(sectBuffer);
}

unsigned char findBitstreamSlot()
{
        unsigned char id;

        if (numUnmatchedSlots)
        {
                sprintf(line, "/machines/%s/core.bit", FilInfo.fname);

                res = f_open(&Fil, line, FA_READ);
                if (res == FR_OK)
                {
                        res = f_read(&Fil, sectBuffer, 256, &bl);
                        f_close(&Fil);
                        if ((res == FR_OK) & (bl == 256) && parseBitstream(sectBuffer))
                        {
                                strncpy(bit_name, line, MAX_BIT_NAME);
                                strncpy(bit_date, tmp_date, MAX_DATE);
                                strncpy(bit_time, tmp_time, MAX_TIME);

                                for (id = 0; id < boards[boardId].numCores - RESERVED_SLOTS; id++)
                                {
                                        if (cores[id].dirname[0] == 0)
                                        {
                                                if (strncmp(bit_name, cores[id].flashname, FLASH_NAME_CHARS) == 0)
                                                {
                                                        if (readCoreHeader(RESERVED_SLOTS+id))
                                                        {
                                                                if (strncmp(bit_name, line, MAX_BIT_NAME) == 0)
                                                                {
                                                                        numUnmatchedSlots--;
                                                                        return RESERVED_SLOTS+id;
                                                                }
                                                        }
                                                }
                                        }
                                }
                        }
                }
        }

        return 0;
}

void eraseCore(unsigned char entry)
{
        unsigned char coreId = RESERVED_SLOTS+entry;

        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_WHITE);
        vdp_cls();
        vdp_setbg(COLOR_BLUE);
        vdp_prints(CORES_TITLE);
        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_WHITE);

        sprintf(line, "\n\nErasing core slot:  %02d\n\n", coreId);
        vdp_prints(line);

        if ((coreId < RESERVED_SLOTS) || (coreId >= boards[boardId].numCores))
        {
                vdp_prints("Invalid core id!\n");
                vdp_prints("\n\nPress ENTER");
                getEnter();
                return;
        }

        eraseFlash(coreId * boards[boardId].coreBlocks, 1);

        vdp_prints("\n\nPress ENTER");
        getEnter();
}

unsigned char upgradeCore(unsigned char entry, unsigned char *pName, unsigned char *pDirname)
{
        unsigned char coreId = RESERVED_SLOTS+entry;

        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_WHITE);
        vdp_cls();
        vdp_setbg(COLOR_BLUE);
        vdp_prints(CORES_TITLE);
        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_WHITE);

        sprintf(line, "\n\nFlashing core:\n\n  \%02d: %s\n\n", coreId, pName);
        vdp_prints(line);

        if ((coreId < RESERVED_SLOTS) || (coreId >= boards[boardId].numCores))
        {
                vdp_prints("Invalid core id!\n");
                vdp_prints("\n\nPress ENTER");
                getEnter();
                return 0;
        }

        sprintf(line,"/machines/%s/core.bit", pDirname);
        res = f_open(&Fil, line, FA_READ);

        if (res != FR_OK)
        {
                sprintf(line,"Error opening core file:\n/machines/%s/core.bit", pDirname);
                vdp_setcolor(COLOR_RED, COLOR_BLACK, COLOR_WHITE);
                vdp_prints(line);
                vdp_prints("\n\nPress ENTER");
                getEnter();
                return 0;
        }
        else
        {
                unsigned long coreSecs = (f_size(&Fil)+511) >> 9;

                if (coreId == 0)
                {
                        display_error("Attempt to flash AB core!");
                }

                writeCore(coreId, &Fil, 0, coreSecs);
                vdp_prints("Updated!\n");
                f_close(&Fil);
        }

        vdp_prints("\n\nPress ENTER");
        getEnter();

        return 1;
}

void readCores() {
        unsigned char id;

        numFileItems = 0;
        numUnmatchedSlots = 0;

        memset(cores, 0, MAX_CORE_SLOTS * sizeof(coreitem));
        memset(fileItems, 0, MAX_FILE_ITEMS * sizeof(fileitem));

        for (id = 0; id < boards[boardId].numCores - RESERVED_SLOTS; id++)
        {
                if (readCoreHeader(RESERVED_SLOTS+id))
                {
                        strncpy(cores[id].flashname, line, FLASH_NAME_CHARS);
                        numUnmatchedSlots++;
                }
        }

        f_opendir(&Dir, "/machines");

        do {
                f_readdir(&Dir, &FilInfo);
                flashProgress();

                if (FilInfo.fname[0] && strncmp(FilInfo.fname, "NEXT", MAX_DIR_NAME))
                {
                        id = findBitstreamSlot();

                        if (id)
                        {
                                curItem = id - RESERVED_SLOTS;
                                strncpy(cores[curItem].dirname, FilInfo.fname, MAX_DIR_NAME);

                                if (strncmp(bit_date, tmp_date, MAX_DATE)
                                        || strncmp(bit_time, tmp_time, MAX_TIME))
                                {
                                        cores[curItem].update = 1;
                                }
                        }
                        else
                        {
                                if (numFileItems < MAX_FILE_ITEMS)
                                {
                                        strncpy(fileItems[numFileItems].fname, FilInfo.fname, MAX_RES_NAME);
                                        curItem = numFileItems + MAX_CORE_SLOTS;
                                        numFileItems++;
                                }
                                else
                                {
                                        continue;
                                }
                        }
                }

        } while (FilInfo.fname[0]);

        f_closedir(&Dir);
}

/* TODO Hacked from editor.c */
unsigned char button_up = 0;
unsigned char button_down = 0;
unsigned char button_left = 0;
unsigned char button_right = 0;
unsigned char button_enter = 0;
unsigned char button_space = 0;

static void readkeyb()
{
        button_up = 0;
        button_down = 0;
        button_left = 0;
        button_right = 0;
        button_enter = 0;
        button_space = 0;

        while(1)
        {
                if ((HROW3 & 0x10) == 0) {
                        button_left = 1;
                        while(!(HROW3 & 0x10));
                        return;
                }
                k = HROW4;
                if ((k & 0x10) == 0) {
                        button_down = 1;
                        while(!(HROW4 & 0x10));
                        return;
                }
                if ((k & 0x08) == 0) {
                        button_up = 1;
                        while(!(HROW4 & 0x08));
                        return;
                }
                if ((k & 0x04) == 0) {
                        button_right = 1;
                        while(!(HROW4 & 0x04));
                        return;
                }
                if ((HROW6 & 0x01) == 0) {
                        button_enter = 1;
                        while(!(HROW6 & 0x01));
                        return;
                }
                if (((HROW7 & 0x01) == 0) && ((HROW0 & 0x01) ==1)) {
                        button_space = 1;
                        while(!(HROW7 & 0x01));
                        return;
                }
        }
}

unsigned char chooseItem(
                const char *pChooseHelp,
                unsigned int validItems,
                void (*displayFn)(unsigned char),
                unsigned char (*selectFn)(unsigned char),
                unsigned char (*utilityFn)(unsigned char) )
{
        unsigned char reshow = 1;
        unsigned int top = 0;
        unsigned int bottom = validItems ? (validItems - 1) : 0;
        unsigned int pagetop = 0;
        unsigned int posc = 0;
        unsigned int newposc = 0;

        while(1) {

                if (newposc < pagetop)
                {
                        pagetop = pagetop - MENU_LINES;
                        reshow = 1;
                }
                if (newposc >= (pagetop + MENU_LINES))
                {
                        pagetop = pagetop + MENU_LINES;
                        reshow = 1;
                }

                if ((reshow == 0) && (newposc != posc))
                {
                        vdp_gotoxy(2, 2+posc-pagetop);
                        (*displayFn)(posc);

                        posc = newposc;

                        vdp_gotoxy(2, 2+posc-pagetop);
                        vdp_setflash(1);
                        (*displayFn)(posc);
                        vdp_setflash(0);
                }

                if (reshow)
                {
                        posc = newposc;

                        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_WHITE);
                        vdp_cls();
                        vdp_setbg(COLOR_BLUE);
                        vdp_prints(CORES_TITLE);
                        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_CYAN);
                        vdp_gotoxy(0, 22);
                        vdp_prints(pChooseHelp);
                        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_GRAY);
                        vdp_setfg(COLOR_LGREEN);

                        for (i = 0; i < MENU_LINES; i++) {
                                if ( ((pagetop+i) <= bottom) &&
                                        ((pagetop+i) < validItems) )
                                {
                                        vdp_gotoxy(2, i+2);
                                        vdp_setflash((pagetop+i) == posc);
                                        (*displayFn)(pagetop+i);
                                        vdp_setflash(0);
                                        while (vdp_gety() == (i+2))
                                        {
                                                vdp_putchar(' ');
                                        }
                                }
                        }

                        reshow = 0;
                }

                readkeyb();
                vdp_setfg(COLOR_LGREEN);
                if (button_space) {
                        newposc = ((*utilityFn)(posc));
                        if (newposc != posc)
                        {
                                return newposc;
                        }
                        reshow = 1;
                } else if (button_up) {
                        if (posc > top) {
                                newposc = posc-1;
                        }
                } else if (button_down) {
                        if (posc < bottom) {
                                newposc = posc+1;
                        }
                } else if (button_left) {
                        if (pagetop >= MENU_LINES)
                        {
                                newposc = posc - MENU_LINES;
                        }
                        else
                        {
                                newposc = 0;
                        }
                } else if (button_right) {
                        if ((pagetop + MENU_LINES) <= bottom)
                        {
                                newposc = posc + MENU_LINES;
                                if (newposc > bottom)
                                {
                                        newposc = bottom;
                                }
                        }
                        else
                        {
                                newposc = bottom;
                        }
                } else if (button_enter) {
                        if (((*selectFn)(posc)) == posc)
                        {
                                return posc;
                        }
                }
        }
}

void loadResource(const char *pName, unsigned char pageId)
{
        sprintf(line,"\nLoading %s...", pName);
        vdp_prints(line);

        sprintf(line, "%s/%s", searchDir, pName);
        res = f_open(&DatFil, line, FA_READ);

        if (res == FR_OK)
        {
                dsize = 0;

                do {
                        // Prevent overwrite of RAM used by firmware.
                        if ((pageId == (RAMPAGE_RAMSPECCY + 5)) ||
                                (pageId == (RAMPAGE_RAMSPECCY + 2)) ||
                                (pageId == (RAMPAGE_RAMSPECCY + 0)) )
                        {
                                break;
                        }

                        REG_NUM = REG_RAMPAGE;
                        REG_VAL = pageId;

                        res = f_read(&DatFil, (unsigned char *)0, 16384, &bl);
                        if (res != FR_OK)
                        {
                                vdp_setcolor(COLOR_RED, COLOR_BLACK, COLOR_WHITE);
                                vdp_prints("ERROR");
                                for (;;);
                        }

                        pageId++;
                        dsize += bl;

                } while (bl == 16384);

                sprintf(line, "%uK", dsize >> 10);
                vdp_prints(line);

                f_close(&DatFil);
        }
        else
        {
                vdp_setcolor(COLOR_RED, COLOR_BLACK, COLOR_WHITE);
                vdp_prints("ERROR");
                for (;;);
        }
}

unsigned char utilityNoop(unsigned char entry)
{
        return entry;
}

unsigned char utilityExit(unsigned char entry)
{
        return MAX_FILE_ITEMS+(entry-entry);
}

void parseCoreName(char *pName, char *pDirname)
{
        if (pName[0] == 0)
        {
                strncpy(pName, pDirname, MAX_CORE_NAME);
                sprintf(line, "/machines/%s/core.cfg", pDirname);

                res = f_open(&Fil, line, FA_READ);
                if (res == FR_OK)
                {
                        while (f_eof(&Fil) == 0)
                        {
                                if (!f_gets(line, 255, &Fil))
                                {
//                                              //             12345678901234567890123456789012
//                                              display_error("Error reading core.cfg data!");
                                        break;
                                }

                                if (line[0] == ';')
                                        continue;

                                // Ensure correct parsing even if no EOL on last line
                                if (line[strlen(line)-1] == '\n')
                                {
                                        line[strlen(line)-1] = '\0';
                                }
                                else
                                {
                                        line[strlen(line)] = '\0';
                                }

                                if ( strncmp ( line, "name=", 5) == 0)
                                {
                                        pLine = line + 5;
                                        parsestring(pName, MAX_CORE_NAME);
                                }
                        }

                        f_close(&Fil);
                }
        }
}

void displayFileName(unsigned char entry)
{
        parseCoreName(fileItems[entry].name, fileItems[entry].fname);
        vdp_prints(fileItems[entry].name);
}

void displayCoreName(unsigned char entry)
{
        if (cores[entry].dirname[0])
        {
                parseCoreName(cores[entry].name, cores[entry].dirname);
                unsigned char ch = cores[entry].update ? '*' : ' ';
                sprintf(line, "%02d%c %s", RESERVED_SLOTS+entry, ch, cores[entry].name);
        }
        else
        {
                sprintf(line, "%02d", RESERVED_SLOTS+entry);
        }

        vdp_prints(line);
}

unsigned char selectCore(unsigned char entry)
{
        if (cores[entry].dirname[0] == 0)
        {
                return MAX_CORE_SLOTS;
        }

        return entry;
}

unsigned char flashCore(unsigned char entry)
{
        file_entry = chooseItem("Press ENTER to select new core\nPress SPACE to erase slot",
                        numFileItems, displayFileName, utilityNoop, utilityExit);

        if (file_entry == MAX_FILE_ITEMS)
        {
                eraseCore(entry);

                if ((numFileItems < MAX_FILE_ITEMS) && cores[entry].dirname[0])
                {
                        strncpy(fileItems[numFileItems].fname, cores[entry].dirname, MAX_DIR_NAME);
                        strncpy(fileItems[numFileItems].name, cores[entry].name, MAX_CORE_NAME);
                        numFileItems++;
                }

                cores[entry].dirname[0] = cores[entry].name[0] = 0;
        }
        else if (file_entry < numFileItems)
        {
                if (upgradeCore(entry, fileItems[file_entry].name, fileItems[file_entry].fname))
                {
                        strncpy(cores[entry].name, fileItems[file_entry].name, MAX_CORE_NAME);
                        strncpy(cores[entry].dirname, fileItems[file_entry].fname, MAX_DIR_NAME);
                        cores[entry].update = 0;

                        if ((file_entry+1) < MAX_FILE_ITEMS)
                        {
                                memcpy(&fileItems[file_entry], &fileItems[file_entry+1], sizeof(fileitem)*(MAX_FILE_ITEMS-(file_entry+1)));
                        }

                        numFileItems--;
                }
        }

        return entry;
}

unsigned char chooseCore()
{
        return chooseItem(CHOOSE_CORE_HELP, MAX_CORE_SLOTS, displayCoreName, selectCore, flashCore);
}
/* TODO END Hacked from editor.c */

unsigned char chooseUserFile()
{
        numFileItems = 0;

        sprintf(searchDir, "/machines/%s/%s", cores[core_entry].dirname, userDir);
        f_opendir(&Dir, searchDir);
        curItem = 0;

        do {
                f_readdir(&Dir, &FilInfo);

                if (FilInfo.fname[0])
                {
                        strncpy(fileItems[numFileItems].fname, FilInfo.fname, MAX_RES_NAME);
                        strncpy(fileItems[numFileItems].name, FilInfo.fname, MAX_CORE_NAME);
                        numFileItems++;
                }

        } while ((numFileItems < MAX_FILE_ITEMS) && (FilInfo.fname[0]));

        f_closedir(&Dir);

        if (numFileItems)
        {
                if (userReq)
                {
                        sprintf(line, "Press ENTER to select %s", userName);
                        file_entry = chooseItem(line, numFileItems, displayFileName, utilityNoop, utilityNoop);
                }
                else
                {
                        sprintf(line, "Press ENTER to select %s\nPress SPACE for none", userName);
                        file_entry = chooseItem(line, numFileItems, displayFileName, utilityNoop, utilityExit);
                }
        }
        else
        {
                file_entry = MAX_FILE_ITEMS;
        }

        return (file_entry != MAX_FILE_ITEMS);
}

void showBootCoreScreen()
{
        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_WHITE);
        vdp_cls();
        vdp_setbg(COLOR_BLUE);
        vdp_prints(CORES_TITLE);
        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_WHITE);

        if (cores[core_entry].update)
        {
                sprintf(line, "\n\nUpdate %s (Y/N)? ", cores[core_entry].name);
                vdp_prints(line);

                while (1)
                {
                        if ((HROW5 & 16) == 0)
                        {
                                vdp_prints("Y");
                                while ((HROW5 & 16) == 0);
                                upgradeCore(core_entry, cores[core_entry].name, cores[core_entry].dirname);
                                break;
                        }

                        if ((HROW7 & 8) == 0)
                        {
                                vdp_prints("N");
                                while ((HROW7 & 8) == 0);
                                break;
                        }
                }
        }

        sprintf(line, "\n\nStarting %s...\n", cores[core_entry].name);
        vdp_prints(line);
}

void bootCore()
{
        numUserFiles = 0;
        numConfigItems = 0;
        configPage = 255;
        configOffset = 0;

        showBootCoreScreen();
        memset(userFiles, 0, MAX_USER_FILES * sizeof(unsigned char));

        sprintf(line, "/machines/%s/core.cfg", cores[core_entry].dirname);
        res = f_open(&Fil, line, FA_READ);
        if (res == FR_OK)
        {
                while (f_eof(&Fil) == 0)
                {
                        if (!f_gets(line, 255, &Fil))
                        {
                                //             12345678901234567890123456789012
                                display_error("Error reading core.cfg data!");
                        }

                        if (line[0] == ';')
                                continue;

                        // Ensure correct parsing even if no EOL on last line
                        if (line[strlen(line)-1] == '\n')
                        {
                                line[strlen(line)-1] = '\0';
                        }
                        else
                        {
                                line[strlen(line)] = '\0';
                        }

                        if ( strncmp(line, "config=", 7) == 0)
                        {
                                pLine = line + 7;
                                parsenumber(&configPage);
                                parseword(&configOffset);
                        }

                        if ( strncmp(line, "resource=", 9) == 0)
                        {
                                pLine = line + 9;
                                parsestring(resName, MAX_RES_NAME);
                                parsenumber(&sram_page);

                                sprintf(searchDir, "/machines/%s", cores[core_entry].dirname);
                                loadResource(resName, sram_page);
                        }

                        if ((numUserFiles < MAX_USER_FILES) &&
                                (strncmp(line, "userfile=", 9) == 0))
                        {
                                pLine = line + 9;
                                parsestring(userDir, MAX_DIR_NAME);
                                parsestring(userName, MAX_USER_NAME);
                                parsenumber(&userPage);
                                parsenumber(&userReq);
                                parseword(&userOffset);

                                if (file_name == 0)
                                {
                                        if (chooseUserFile())
                                        {
                                                file_name = fileItems[file_entry].fname;
                                        }

                                        showBootCoreScreen();
                                }

                                if (file_name)
                                {
                                        if (userReq & 0x02)
                                        {
                                                REG_NUM = REG_RAMPAGE;
                                                REG_VAL = userPage;

                                                strncpy((char *)userOffset, file_name, MAX_RES_NAME);
                                        }
                                        else
                                        {
                                                vdp_prints("\n");
                                                sprintf(searchDir, "/machines/%s/%s", cores[core_entry].dirname, userDir);
                                                loadResource(file_name, userPage);
                                        }

                                        userFiles[numUserFiles] = 1;
                                }
                                else
                                {

                                        sprintf(line, "\n\nNo %s found!", userName);
                                        vdp_prints(line);

                                        if (userReq & 0x01)
                                        {
                                                for (;;) ;
                                        }
                                }

                                numUserFiles++;
                                file_name = 0;
                        }
                }

                f_close(&Fil);
        }

        // Write the config details
        if (configPage != 255)
        {
                unsigned char *pCfg;

                REG_NUM = REG_RAMPAGE;
                REG_VAL = configPage;

                memset((unsigned char *)configOffset, 0, CFG_SIZE);

                pCfg = (unsigned char *)(configOffset + CFG_OFFSET_GENCFG);
                pCfg[0] = settings[eSettingTiming];
                pCfg[1] = settings[eSettingScandoubler];
                pCfg[2] = settings[eSettingFreq5060];
                pCfg[3] = settings[eSettingPS2];
                pCfg[4] = settings[eSettingScanlines];
                pCfg[5] = settings[eSettingSpeakerMode];
                pCfg[6] = settings[eSettingHDMISound];

                memcpy((unsigned char *)(configOffset+CFG_OFFSET_FILES), userFiles, MAX_USER_FILES);

                sprintf((char *)(configOffset+CFG_OFFSET_DIR), "/MACHINES/%s/", cores[core_entry].dirname);
        }

        // Pause a bit.
        REG_NUM = REG_TURBO;
        REG_VAL = 0;
        for (i=0; i < 50000; i++) ;

        // Boot the core.
        REG_NUM = REG_ANTIBRICK;
        REG_VAL = 0x80 | (RESERVED_SLOTS+core_entry);

        // Should never reach here.
        for (;;) ;
}

void main()
{
        vdp_init();
        detectBoard();

        if ((boardId != 0) || (machineId != HWID_ZXNEXT))
        {
                display_error("Only supported on issue 2!");
        }

        if (machineAB)
        {
                //can't work with AB, so hang
                while (1){}
        }

        vdp_setcolor(COLOR_BLACK, COLOR_BLUE, COLOR_WHITE);
        vdp_prints(CORES_TITLE);

        vdp_setcolor(COLOR_BLACK, COLOR_BLACK, COLOR_WHITE);
        vdp_gotoxy(2, 2);
        vdp_prints("Reading core information: ");

	// Read config.ini for the video settings.
        // Don't need to change the mode here, because it has already been
        // done by the boot module (the AB loader cannot directly start this
        // module).
        load_config();

        memset(sectBuffer, 0, 512);
        f_mount(&FatFs, "", 0);

        readCores();
        file_name = 0;

        if (getCoreBoot())
        {
                coreboot *pCoreBoot = (coreboot *)0x0000;

                // Invalidate the magic for next time around.
                pCoreBoot->magic[0] = 0;

                for (core_entry = 0; core_entry < boards[boardId].numCores - RESERVED_SLOTS; core_entry++)
                {
                        if (strncmp(pCoreBoot->dirname, cores[core_entry].dirname, COREBOOT_NAMES_SIZE) == 0)
                        {
                                if (pCoreBoot->filename[0])
                                {
                                        strncpy(sectBuffer, pCoreBoot->filename, COREBOOT_NAMES_SIZE);
                                        file_name = sectBuffer;
                                }

                                bootCore();
                        }
                }
        }

        core_entry = chooseCore();
        bootCore();

}
