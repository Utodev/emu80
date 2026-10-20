;ZX Spectrum Next Firmware
;Copyright 2020 Garry Lancaster, Fabio Belavenuto & Victor Trucco
;
;This program is free software: you can redistribute it and/or modify
;it under the terms of the GNU General Public License as published by
;the Free Software Foundation, either version 3 of the License, or
;(at your option) any later version.
;
;This program is distributed in the hope that it will be useful,
;but WITHOUT ANY WARRANTY; without even the implied warranty of
;MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;GNU General Public License for more details.
;
;You should have received a copy of the GNU General Public License
;along with this program.  If not, see <http://www.gnu.org/licenses/>.
;

        .module switch
        .optsdcc -mz80

        .area   _CODE

_switch_routine::
        ld      hl, #_switch_start
        ld      de, # 0x4000
        ld      bc, #(_switch_end-_switch_start)
        ldir
        jp      0x4000
_switch_start:
        ld      bc, # 0x243B
        ld      a, # 0x04
        out     (c),a
        inc     b
        ld      a, # 8          ; RAM_DIVMMC
        out     (c),a
        ld      hl, # 0x0000
        ld      de, # 0x6000
        ld      bc, # 0x4000
        ldir
        ld      bc, # 0x243B
        ld      a, # 0x04
        out     (c),a
        inc     b
        ld      a, # 9          ; RAM_DIVMMC + 1
        out     (c),a
        ld      hl, # 0x0000
        ld      de, # 0xa000
        ld      bc, # 0x4000
        ldir
        ld      bc, # 0x243B
        ld      a, # 0x04
        out     (c),a
        inc     b
        ld      a, # 10         ; RAM_DIVMMC + 2
        out     (c),a
        ld      hl, # 0x0000
        ld      de, # 0xe000
        ld      bc, # 0x2000
        ldir
        jp      0x6000
_switch_end:
