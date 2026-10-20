/*
ZX Spectrum Next Firmware
Copyright 2022 Garry Lancaster

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

#include <stdio.h>
#include "hardware.h"
#include "vdp.h"
#include "ff.h"
#include "spi.h"
#include "flash.h"
#include "misc.h"

unsigned char machineAB = 0;
unsigned char machineId, boardId;
unsigned char cmdbuf[5];

boardItem boards[NUM_BOARD_TYPES] =
{
        // ZXN Issue 2
        {
                0,                      // boardId
                "ZX Next Issue 2",      // boardName
                0,                      // addr4b
                32,                     // numCores
                16,                     // coreBlocks
        },

        // ZXN Issue 3
        {
                1,                      // boardId
                "ZX Next Issue 3",      // boardName
                0,                      // addr4b
                32,                     // numCores
                16,                     // coreBlocks
        },

        // ZXN Issue 4
        {
                2,                      // boardId
                "ZX Next Issue 4",      // boardName
                1,                      // addr4b
                15,                     // numCores
                68,                     // coreBlocks
        },
};

void detectBoard()
{
        GET_NEXTREG(REG_MACHID, machineId);
        GET_NEXTREG(REG_BOARDID, boardId);

        if (machineId == HWID_ZXNEXT_AB)
        {
                machineId = HWID_ZXNEXT;
                machineAB = 1;
        }

        if (boardId >= NUM_BOARD_TYPES)
        {
                sprintf(line, "Unknown board id: 0x%02x", boardId);
                display_error(line);
        }
}

void flashCmd(unsigned int blk32Id, unsigned char startPage, unsigned char offset, unsigned char cmdId, unsigned char cmdId4b)
{
        if (boards[boardId].addr4b)
        {
                cmdbuf[0] = cmdId4b;
                cmdbuf[1] = blk32Id >> 9;
                cmdbuf[2] = (blk32Id >> 1) & 0xff;
                cmdbuf[3] = ((blk32Id & 0x01) << 7) + startPage;
                cmdbuf[4] = offset;
                SPI_send5bytes(cmdbuf);
        }
        else
        {
                cmdbuf[0] = cmdId;
                cmdbuf[1] = (blk32Id >> 1) & 0xff;
                cmdbuf[2] = ((blk32Id & 0x01) << 7) + startPage;
                cmdbuf[3] = offset;
                SPI_send4bytes(cmdbuf);
        }
}

void readFlash(unsigned int blk32Id, unsigned char startPage, unsigned char offset, unsigned char *pBuffer, unsigned int pages)
{
        flashCmd(blk32Id, startPage, offset, cmd_read_bytes, cmd_read_bytes_4b);
        SPI_receive(pBuffer, pages);
        SPI_cshigh();
}
