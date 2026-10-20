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
#include "hardware.h"
#include "vdp.h"
#include "misc.h"
#include "font.h"

unsigned char cx, cy, _flash, _bright, fg, bg;
unsigned int faddr;
unsigned int vaddr;
unsigned int caddr;
unsigned char vpdc, vpdf, vpdv;


/* Private functions */


/* Public functions */


/*******************************************************************************/
void vdp_init()
{
        unsigned char v;
        unsigned int c;

        // Turn off ZX Printer motor first, since early AB cores leave it
        // running at startup. This must not be done on cores < 3.00.04 which
        // don't properly support the expansion bus registers.
        // if (get_core_ver() >= (unsigned long)0x030004)
        {
                REG_NUM = REG_DECODE_EXP2;
                REG_VAL = 0xDB;
                REG_NUM = REG_EXPBUS_CTRL;
                REG_VAL = 0x80;
                ZXPRINTERPORT = 0x04;
                REG_NUM = REG_EXPBUS_CTRL;
                REG_VAL = 0x00;
                REG_NUM = REG_DECODE_EXP2;
                REG_VAL = 0xFF;
        }

        // Set timings to +3/Next to ensure display accurately matches Next mode.
        REG_NUM = REG_MACHTYPE;
        REG_VAL = 0xb0;

        cx = cy = 0;
        fg = COLOR_GRAY;
        bg = COLOR_BLACK;
        _flash = 0;
        _bright = 0;
        ULAPORT = COLOR_BLACK;
        v = (_flash << 7) | (_bright << 6) | (bg << 3) | fg;
        for (c = PIX_BASE; c < (PIX_BASE+6144); c++) {
                poke(c, 0);
        }
        for (c = CT_BASE; c < (CT_BASE+768); c++) {
                poke(c, v);
        }
}

/*******************************************************************************/
void vdp_setcolor(unsigned char border, unsigned char background, unsigned char foreground)
{
        _bright = (foreground & 0x08) ? 1 : 0;
        fg = foreground & 0x07;
        bg = background & 0x07;
        ULAPORT = (border & 0x07);
}

/*******************************************************************************/
void vdp_setborder(unsigned char border)
{
        ULAPORT = (border & 0x07);
}

/*******************************************************************************/
void vdp_setflash(unsigned char flash)
{
        _flash = flash ? 1 : 0;
}

/*******************************************************************************/
void vdp_setfg(unsigned char foreground)
{
        _bright = (foreground & 0x08) ? 1 : 0;
        fg = foreground & 0x07;
}

/*******************************************************************************/
void vdp_setbg(unsigned char background)
{
        bg = background & 0x07;
}

/*******************************************************************************/
void vdp_cls()
{
        unsigned int c;
        unsigned char v;

        cx = cy = 0;
        v = (_flash << 7) | (_bright << 6) | (bg << 3) | fg;
        for (c = PIX_BASE; c < (PIX_BASE+6144); c++)
                poke(c, 0);
        for (c = CT_BASE; c < (CT_BASE+768); c++)
                poke(c, v);
}

/*******************************************************************************/
void vdp_gotoxy(unsigned char x, unsigned char y)
{
        cx = x & 31;
        cy = y;
        if (cy > 23) cy = 23;
}

/*******************************************************************************/
void vdp_gotox(unsigned char x)
{
        cx = x & 31;
}

/*******************************************************************************/
unsigned char vdp_getx()
{
        return cx;
}

/*******************************************************************************/
unsigned char vdp_gety()
{
        return cy;
}

/*******************************************************************************/
void vdp_putchar(unsigned char c)
{
        unsigned char i;

        if (c == 10) {
                cx = 0;
                ++cy;
                if (cy > 23) {
                        cy = 23;
                }
                return;
        } else if (c == 8) {
                if (cx == 0) {
                        cx = 31;
                        if (cy > 0) {
                                --cy;
                        }
                } else {
                        --cx;
                }
                return;
        }
        faddr = (c-32)*8;
        vaddr = cy << 8;
        vaddr = (vaddr & 0x1800) | (vaddr & 0x00E0) << 3 | (vaddr & 0x0700) >> 3;
        vaddr = PIX_BASE + vaddr + cx;
        caddr = CT_BASE + (cy*32) + cx;

        for (i=0; i < 8; i++) {
                poke(vaddr, font[faddr]);
                vaddr += 256;
                faddr++;
        }
        poke(caddr, (_flash << 7) | (_bright << 6) | (bg << 3) | fg);
        ++cx;
        if (cx > 31) {
                cx = 0;
                ++cy;
                if (cy > 23) {
                        cy = 23;
                }
        }

}

/*******************************************************************************/
void vdp_prints(const char *str)
{
        char c;
        while ((c = *str++)) {
                vdp_putchar(c);
        }
}

/*******************************************************************************/
void vdp_clear(unsigned char x, unsigned char y, unsigned char n)
{
        unsigned char i;
        vdp_gotoxy(x, y);

        for (i = 0; i < n; i++)
        {
                vdp_putchar(' ');
        }
}

//------------------------------------------------------------------------------
void puthex(unsigned char nibbles, unsigned int v)
{
        signed char i = nibbles - 1;
        while (i >= 0) {
                unsigned int aux = (v >> (i << 2)) & 0x000F;
                unsigned char n = aux & 0x000F;
                if (n > 9)
                        vdp_putchar('A' + (n - 10));
                else
                        vdp_putchar('0' + n);
                i--;
        }
}

//------------------------------------------------------------------------------
void puthex8(unsigned char v)
{
        puthex(2, (unsigned int) v);
}

//------------------------------------------------------------------------------
void puthex16(unsigned int v)
{
        puthex(4, v);
}
