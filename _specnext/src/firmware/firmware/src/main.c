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

/* Defines */
#define NUMMODULES 8
#define NUMSCREENS 1

#define MAX_PATH 254
/* Variables */

const char moduledirectory[] = "..//app//";
const char screendirectory[] = "..//screen//";
const char *module_files[NUMMODULES] = {
        "boot.bin",             // FW_BLK_BOOT
        0,                      // FW_BLK_OLD_EDITOR
        "updater.bin",          // FW_BLK_UPDATER
        0,                      // FW_BLK_OLD_CORES
        "editor.bin",           // FW_BLK_EDITOR
        "cores.bin",            // FW_BLK_CORES
        "videotest.bin",        // FW_BLK_TESTCARD
        "reset.bin",            // FW_BLK_RESET
};
const char *screen_files[NUMSCREENS] = {
        "screens.bin",          // FW_BLK_SCREENS
};

static unsigned char pB[512];
static int blockA=0, cb=0;

/* Public functions */

// =============================================================================

int addFile(FILE *fileFw, const char *filename)
{
        FILE *fileBin;
        unsigned char buffer[512];
        int size, blocks, c;

        if (!(fileBin = fopen(filename, "rb"))) {
                fprintf(stderr, "Error opening '%s'\n", filename);
                return -1;
        }

        fseek(fileBin, 0, SEEK_END);
        size = ftell(fileBin);
        fseek(fileBin, 0, SEEK_SET);

        printf("Processing file '%s', filesize %d\n", filename, size);
        printf("Block id: 0x%02x, file block number 0x%04x\n", cb/4, blockA);

        blocks = (size + 511) / 512;
        pB[cb++] = blockA % 256;        pB[cb++] = blockA / 256;
        pB[cb++] = blocks % 256;        pB[cb++] = blocks / 256;
        blockA += blocks;
        c = 0;
        while(c < size) {
                memset(buffer, 0, 512);
                fread(buffer, 1, 512, fileBin);
                fwrite(buffer, 1, 512, fileFw);
                c += 512;
        }

        fclose(fileBin);
        return 0;
}


int main(int argc, char *argv[]) {
        FILE *fileFw = NULL;
        char path[MAX_PATH];
        int i;

        if (!(fileFw = fopen("TBBLUE.FW", "wb"))) {
                fprintf(stderr, "Error creating TBBLUE.FW file\n");
                return -1;
        }

        memset(pB, 0, 512);
        fwrite(pB, 1, 512, fileFw);

        // Embed modules
        for (i = 0; i < NUMMODULES; i++) {

                if (module_files[i])
                {
                        strcpy(path, moduledirectory);
                        strcat(path, module_files[i]);

                        if (addFile(fileFw, path) != 0)
                        {
                                fclose(fileFw);
                                return -1;
                        }
                }
                else
                {
                        // Alias blocks that old loaders may load to boot.
                        // This ensures the loader can only load boot or updater.
                        pB[cb++] = pB[0];
                        pB[cb++] = pB[1];
                        pB[cb++] = pB[2];
                        pB[cb++] = pB[3];
                }
        }

        // Embed screens
        for (i = 0; i < NUMSCREENS; i++) {
                strcpy(path, screendirectory);
                strcat(path, screen_files[i]);

                if (addFile(fileFw, path) != 0)
                {
                        fclose(fileFw);
                        return -1;
                }
        }

        fseek(fileFw, 0, SEEK_SET);
        fwrite(pB, 1, 512, fileFw);
        fclose(fileFw);

        printf("TBBLUE.FW created!\n");

        return 0;
}
