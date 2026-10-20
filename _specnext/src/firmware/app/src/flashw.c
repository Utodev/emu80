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

const char ce[5] = "\\|/-";
unsigned char cen = 0;
unsigned char sectBuffer[512];
unsigned char byteoffset, csb;
unsigned int cso, cs0, cs1;

void fileSeek(FIL *fp, unsigned long offset)
{
        FRESULT res = f_lseek(fp, offset);
        if (res != FR_OK)
        {
                display_error("Seek error!");
        }
}

void flashProgress()
{
        vdp_putchar(ce[cen]);
        vdp_putchar(8);
        cen = (cen + 1) & 0x03;
}

void erase32K(unsigned int blk32Id)
{
        SPI_sendcmd(cmd_write_enable);
        flashCmd(blk32Id, 0, 0, cmd_erase_block32, cmd_erase_block32_4b);
        SPI_cshigh();

        while ((SPI_sendcmd_recv(cmd_read_status) & 0x01) == 1) ;

        SPI_sendcmd(cmd_write_disable);
}

void programPage(unsigned int blk32Id, unsigned int pageId, unsigned char *buffer)
{
        SPI_sendcmd(cmd_write_enable);
        flashCmd(blk32Id, pageId, 0, cmd_page_program, cmd_page_program_4b);
        SPI_write(buffer);

        while ((SPI_sendcmd_recv(cmd_read_status) & 0x01) == 1) ;

        SPI_sendcmd(cmd_write_disable);
}

void eraseFlash(unsigned int blk32Id, unsigned int n)
{
        vdp_prints("Erasing Flash: ");

        for (unsigned int i = blk32Id ; i < (blk32Id + n); i++)
        {
                erase32K(i);
                flashProgress();
        }

        vdp_prints("OK\n");
}

void writeFlash(unsigned int blk32Id, FIL * fp, unsigned long secOffset, unsigned long secSize)
{
        unsigned int pageId = 0;

        fileSeek(fp, secOffset<<9);

        vdp_prints("Writing Flash: ");

        while (secSize--)
        {
                unsigned int bl;
                FRESULT res = f_read(fp, sectBuffer, 512, &bl);
                if (res != FR_OK)
                {
                        display_error("Error reading block!");
                }

                for (unsigned int i = 0; i < 2; i++)
                {
                        programPage(blk32Id, pageId++, sectBuffer+(i<<8));

                        if (pageId == 0x80)
                        {
                                blk32Id++;
                                pageId = 0;
                        }
                }

                flashProgress();
        }

        vdp_prints("OK\n");
}

void writeCore(unsigned char coreId, FIL * fp, unsigned long secOffset, unsigned long secSize)
{
        unsigned int coreBlocks = coreId ? boards[boardId].coreBlocks
                                         : boards[boardId].coreBlocks - 1;
        unsigned long coreSecs = coreBlocks * 64L;

        if (coreId >= boards[boardId].numCores)
        {
                sprintf(line, "Invalid core id: 0x%02x", coreId);
                display_error(line);
        }

        if (secSize > coreSecs)
        {
                sprintf(line, "Bad core length:\n%ld > %ld", secSize, coreSecs);
                display_error(line);
        }

        eraseFlash(coreId * boards[boardId].coreBlocks, coreBlocks);
        writeFlash(coreId * boards[boardId].coreBlocks, fp, secOffset, secSize);
}

void verifyChecksum(FIL * fp, unsigned long secOffset, unsigned long secSize, unsigned char csType, unsigned int cs)
{
        fileSeek(fp, secOffset<<9);

        vdp_prints("Verifying checksum: ");

        cs0 = cso;
        cs1 = cso;

        while (secSize--)
        {
                unsigned int bl;
                FRESULT res = f_read(fp, sectBuffer, 512, &bl);
                if (res != FR_OK || bl != 512)
                {
                        display_error("Error reading block!");
                }

                if (csType)
                {
                        for (unsigned int j = 0; j < 512; j++)
                        {
                                cs0 += sectBuffer[j];
                                if (cs0 >= 0xff)
                                {
                                        cs0 = (cs0 + 1) & 0xff;
                                }

                                cs1 += cs0;
                                if (cs1 >= 0xff)
                                {
                                        cs1 = (cs1 + 1) & 0xff;
                                }
                        }
                }
                else
                {
                        for (unsigned int j = 0; j < 512; j++)
                        {
                                csb ^= sectBuffer[j] + byteoffset;
                        }

                        cs0 = csb;
                        cs1 = 0;
                }

                flashProgress();
        }

        if (cs != (cs1 << 8) + cs0)
        {
                sprintf(line, "FAIL: %04X %04X", cs, (cs1 << 8) + cs0);
                display_error(line);
        }

        vdp_prints("OK\n");
}
