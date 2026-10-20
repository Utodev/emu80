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
#include "font.h"

/* Variables */
unsigned int faddr;
unsigned int vaddr;
unsigned int caddr;
unsigned char cx, cy;

/* Private functions */


/* Public functions */

/*******************************************************************************/
void set_ordered_palette()
{
        unsigned int c;

        REG_NUM = 64; 
        REG_VAL = 0;

        REG_NUM = 65; 

        for (c = 0; c<256;c++)
        {
                REG_VAL = c;
        }
}


void vdp_init()
{
        unsigned char v;
        unsigned int c;

        //set default ULA ink colours
        REG_NUM = 64; 
        REG_VAL = 0;    


        REG_NUM = 65; 

        //initial colours
        for (c = 0; c<16;c++)
        {
                REG_VAL = 0b00000000;
                REG_VAL = 0b00000010;
                REG_VAL = 0b10100000;
                REG_VAL = 0b10100010;
                REG_VAL = 0b00010100;
                REG_VAL = 0b00010110;
                REG_VAL = 0b10110100;
                REG_VAL = 0b10110110;

                REG_VAL = 0b00000000;
                REG_VAL = 0b00000011;
                REG_VAL = 0b11100000;
                REG_VAL = 0b11100111;
                REG_VAL = 0b00011100;
                REG_VAL = 0b00011111;
                REG_VAL = 0b11111100;
                REG_VAL = 0b11111111;
        }

        //set default ULA paper colours
        REG_NUM = 64; 
        REG_VAL = 128;  


        REG_NUM = 65; 

        //initial colours
        for (c = 0; c<16;c++)
        {
                REG_VAL = 0b00000000;
                REG_VAL = 0b00000010;
                REG_VAL = 0b10100000;
                REG_VAL = 0b10100010;
                REG_VAL = 0b00010100;
                REG_VAL = 0b00010110;
                REG_VAL = 0b10110100;
                REG_VAL = 0b10110110;

                REG_VAL = 0b00000000;
                REG_VAL = 0b00000011;
                REG_VAL = 0b11100000;
                REG_VAL = 0b11100111;
                REG_VAL = 0b00011100;
                REG_VAL = 0b00011111;
                REG_VAL = 0b11111100;
                REG_VAL = 0b11111111;
        }


        REG_NUM = 67; 
        REG_VAL = 16; //001 - Layer 2
        set_ordered_palette();

//      REG_NUM = 67; 
//      REG_VAL = 160; //101 - alternative layer 2
//      set_ordered_palette();

        REG_NUM = 67; 
        REG_VAL = 32; //010     - sprites
        set_ordered_palette();

//      REG_NUM = 67; 
//      REG_VAL = 192; //110 - alternative sprites
//      set_ordered_palette();

        cx = cy = 0;
        ULAPORT = COLOR_BLACK;
        //v = (0 << 7) | (1 << 6) | (COLOR_BLACK << 3) | COLOR_GRAY;
        v=0;
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
void vdp_putchar(unsigned char c)
{
        unsigned char i;

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
        ++cx;
}

/*******************************************************************************/
void vdp_prints(const char *str)
{
        char c;
        while ((c = *str++)) vdp_putchar(c);
}
