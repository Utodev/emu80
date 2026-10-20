;ZX Spectrum Next Firmware
;Copyright 2020 Garry Lancaster
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

        .module vdplow
        .optsdcc -mz80

        .area   _CODE


_vdp_reveal::
        ld      hl,(0x0000)
        ld      de, # 0xaa55
        and     a
        sbc     hl,de
        jr      nz,vdprev1
        ld      hl,(0x0002)
        ld      de, # 0xa55a
        sbc     hl,de
        jr      z,vdprev2
vdprev1:
        scf
vdprev2:
        pop     bc
        pop     de
        pop     hl
        push    hl
        push    de
        push    bc
        ccf
        rl      h
        ld      bc, #0x243B
        ld      a, #0x04
        out     (c),a
        inc     b
        out     (c),h

        ld      (0x3ff0),sp

        ld      h,l
        ld      l,e
        dec     l
        res     5,h
        ex      de,hl
        ld      h,e
        inc     h
        ld      sp,hl
        pop     hl
        pop     af

        ld      bc, # 988
rloop:
        pop     hl
        dec     sp
        ld      a,l
        ld      i,a
        pop     hl
        push    hl
        xor     l
        rl      h
        rl      h
        adc     a,a
        ld      (de),a
        dec     de
        pop     hl
        ld      a,i
        xor     h
        pop     hl
        push    hl
        rl      l
        rl      l
        adc     a,a
        rl      l
        adc     a,a
        ld      (de),a
        dec     de
        pop     hl
        push    hl
        ld      a,i
        xor     l
        rl      h
        rl      h
        adc     a,a
        rl      h
        adc     a,a
        rl      h
        adc     a,a
        ld      (de),a
        dec     de
        pop     hl
        ld      a,i
        xor     h
        pop     hl
        push    hl
        rl      l
        rl      l
        adc     a,a
        rl      l
        adc     a,a
        rl      l
        adc     a,a
        rl      l
        adc     a,a
        ld      (de),a
        dec     de
        pop     hl
        push    hl
        ld      a,i
        xor     l
        rl      h
        rl      h
        adc     a,a
        rl      h
        adc     a,a
        rl      h
        adc     a,a
        rl      h
        adc     a,a
        rl      h
        adc     a,a
        ld      (de),a
        dec     de
        pop     hl
        ld      a,i
        xor     h
        pop     hl
        push    hl
        rl      l
        rl      l
        adc     a,a
        rl      l
        adc     a,a
        rl      l
        adc     a,a
        rl      l
        adc     a,a
        rl      l
        adc     a,a
        rl      l
        adc     a,a
        ld      (de),a
        dec     de
        pop     hl
        ld      a,i
        xor     h
        add     a,a
        rr      l
        rra
        ld      (de),a
        dec     de
        dec     bc
        ld      a,b
        or      c
        jp      nz,rloop
        ld      sp,(0x3ff0)
        ret
