;    ZXZVM: Z-Code interpreter for the Z80 processor
;    Copyright (C) 1998-9,2006,2016  John Elliott <seasip.webmaster@gmail.com>
;
;    This program is free software; you can redistribute it and/or modify
;    it under the terms of the GNU General Public License as published by
;    the Free Software Foundation; either version 2 of the License, or
;    (at your option) any later version.
;
;    This program is distributed in the hope that it will be useful,
;    but WITHOUT ANY WARRANTY; without even the implied warranty of
;    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;    GNU General Public License for more details.
;
;    You should have received a copy of the GNU General Public License
;    along with this program; if not, write to the Free Software
;    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

; 2019-05-17, Garry Lancaster: New file


; ***************************************************************************
; * Macros for Z80N instructions on the ZX Spectrum Next                    *
; ***************************************************************************


macro swapnib
        defb    $ed,$23
endm

macro mirror
        defb    $ed,$24
endm

macro test_N,val
        defb    $ed,27,(val)
endm

macro bsla
        defb    $ed,$28
endm

macro bsra
        defb    $ed,$29
endm

macro bsrl
        defb    $ed,$2a
endm

macro bsrf
        defb    $ed,$2b
endm

macro brlc
        defb    $ed,$2c
endm

macro mul_de
        defb    $ed,$30
endm

macro addhl_A
        defb    $ed,$31
endm

macro addde_A
        defb    $ed,$32
endm

macro addbc_A
        defb    $ed,$33
endm

macro addhl_N,val
        defb    $ed,$34,(val)&$ff,(val)/$100
endm

macro addde_N,val
        defb    $ed,$35,(val)&$ff,(val)/$100
endm

macro addbc_N,val
        defb    $ed,$36,(val)&$ff,(val)/$100
endm

macro pushval,val
        ; NOTE: PUSHVAL is big-endian
        defb    $ed,$8a,(val)/$100,(val)&$ff
endm

macro outinb
        defb    $ed,$90
endm

macro nxtregn,reg,val
        defb    $ed,$91,reg,val
endm

macro nxtrega,val
        defb    $ed,$92,val
endm

macro pixeldn
        defb    $ed,$93
endm

macro pixelad
        defb    $ed,$94
endm

macro setae
        defb    $ed,$95
endm

macro jp_in_c
        defb    $ed,$98
endm

macro ldix
        defb    $ed,$a4
endm

macro ldws
        defb    $ed,$a5
endm

macro lddx
        defb    $ed,$ac
endm

macro ldirx
        defb    $ed,$b4
endm

macro ldpirx
        defb    $ed,$b7
endm

macro lddrx
        defb    $ed,$bc
endm

