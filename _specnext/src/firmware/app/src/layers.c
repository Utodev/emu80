/*
ZX Spectrum Next Firmware
Copyright 2020 Garry Lancaster

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

#include "hardware.h"
#include "layers.h"

static unsigned char l2_x;
static unsigned char l2_y;
static unsigned char l2_ink;
static unsigned char l2_paper;
static unsigned int l2_ch;
extern unsigned char font[];

void l2_gotoxy(unsigned char x, unsigned char y)
{
        l2_x = x;
        l2_y = y;
}

void l2_setcolours(unsigned char i, unsigned char p)
{
        l2_ink = i;
        l2_paper = p;
}

// NOTE: This code assumes that a character will not straddle a 16K
//       bank boundary.
void l2_putchar(unsigned char ch)
{
        l2_ch = ch - 32;

        // Bind the correct layer2 bank for writing at 0x0000..0x3fff
        REG_NUM = REG_RAMPAGE;
        REG_VAL = RAMPAGE_RAMSPECCY + L2_BANK + (l2_y >> 6);

        __asm;
        // Form address to write to in DE
        ld      a,(_l2_y)
        and     # 0x3f
        ld      d,a
        ld      a,(_l2_x)
        ld      e,a
        // Update x coordinate for next character
        add     a, # 8
        ld      (_l2_x),a
        // Form address of character data in HL
        ld      hl,(_l2_ch)
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      bc, # _font
        add     hl,bc
        // DE=character data, HL=screen address
        ex      de,hl
        // 8 pixel rows
        ld      c, # 8
_l2_putchar_row_loop:
        // Get character data for row
        ld      a,(de)
        inc     de
        push    de
        push    hl
        // E=ink, D=paper
        ld      de,(_l2_ink)
        // 8 pixels per row
        ld      b, # 8
_l2_putchar_pixel_loop:
        rlca
        ld      (hl),d
        jr      nc,_l2_putchar_pixel_set
        ld      (hl),e
_l2_putchar_pixel_set:
        inc     l
        djnz    _l2_putchar_pixel_loop
        // Next pixel row
        pop     hl
        inc     h
        pop     de
        dec     c
        jr      nz,_l2_putchar_row_loop
        __endasm;
}

void l2_prints(unsigned char *str)
{
        while (*str)
        {
                l2_putchar(*str++);
        }
}

void setPalette(unsigned char palId, unsigned char * pData)
{
        unsigned int i;

        REG_NUM = REG_PAL_CTRL;
        REG_VAL = palId;

        REG_NUM = REG_PAL_INDEX;
        REG_VAL = 0;

        for (i = 0; i < 256; i++)
        {
                REG_NUM = REG_PAL_VALUE_9;
                REG_VAL = *pData++;
                REG_VAL = *pData++;
        }
}

void setOrderedPalette(unsigned char palId)
{
        unsigned int i;

        REG_NUM = REG_PAL_CTRL;
        REG_VAL = palId;

        REG_NUM = REG_PAL_INDEX;
        REG_VAL = 0;

        for (i = 0; i < 256; i++)
        {
                REG_NUM = REG_PAL_VALUE_8;
                REG_VAL = i;
        }
}

