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

#ifndef _LAYERS_H
#define _LAYERS_H

#define L2_BANK 8

void l2_gotoxy(unsigned char x, unsigned char y);
void l2_setcolours(unsigned char i, unsigned char p);
void l2_putchar(unsigned char ch);
void l2_prints(unsigned char *str);
void setPalette(unsigned char palId, unsigned char * pData);
void setOrderedPalette(unsigned char palId);

#endif // _LAYERS_H
