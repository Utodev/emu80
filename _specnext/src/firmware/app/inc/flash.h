/*
ZX Spectrum Next Firmware
Copyright 2022 Garry Lancaster, Fabio Belavenuto & Victor Trucco

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

#ifndef _FLASH_H
#define _FLASH_H

#define NUM_BOARD_TYPES 3
#define MAX_BOARD_NAME  16

typedef struct {
        unsigned char   boardId;
        char            boardName[MAX_BOARD_NAME];
        unsigned char   addr4b;
        unsigned char   numCores;
        unsigned int    coreBlocks;
} boardItem;

void detectBoard();
void flashCmd(unsigned int blk32Id, unsigned char startPage, unsigned char offset, unsigned char cmdId, unsigned char cmdId4b);
void readFlash(unsigned int blk32Id, unsigned char startPage, unsigned char offset, unsigned char *pBuffer, unsigned int pages);
void flashProgress();
void eraseFlash(unsigned int blk32Id, unsigned int n);
void writeFlash(unsigned int blk32Id, FIL * fp, unsigned long secOffset, unsigned long secSsize);
void writeCore(unsigned char coreId, FIL * fp, unsigned long secOffset, unsigned long secSize);
void verifyChecksum(FIL * fp, unsigned long secOffset, unsigned long secSize, unsigned char csType, unsigned int cs);

extern boardItem boards[NUM_BOARD_TYPES];
extern unsigned char cmdbuf[5];
extern unsigned char machineAB, machineId, boardId;
extern unsigned char byteoffset;
extern unsigned int cso;

#endif // _FLASH_H
