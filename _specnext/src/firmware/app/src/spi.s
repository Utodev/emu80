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

        .module spi
        .optsdcc -mz80

        .area   _CODE

PORTCFG         = 0xE7
PORTSPI         = 0xEB


; ------------------------------------------------
; Send 1 byte to flash
; ------------------------------------------------
; void SPI_sendcmd(unsigned char cmd)
; void SPI_cshigh(void)
_SPI_sendcmd::
        ld              hl, #2
        add             hl, sp
        ld              l, (hl)

        ld              a, #0x7F
        out             (PORTCFG), a                    ; /CS = 0
        ld              a, l
        out             (PORTSPI), a
_SPI_cshigh::
        ld              a, #0xFF
        out             (PORTCFG), a                    ; /CS = 1
        ret

; ------------------------------------------------
; Send 1 byte to flash and receive answer
; ------------------------------------------------
; unsigned char SPI_sendcmd_recv(unsigned char cmd)
_SPI_sendcmd_recv::
        ld              hl, #2
        add             hl, sp
        ld              l, (hl)

        ld              c, #PORTSPI
        ld              a, #0x7F
        out             (#PORTCFG), a                   ; /CS = 0       11 T-States
        ld              a, l                            ;                4 T-States
        out             (c), a                          ;               12 T-States
        nop                                             ;                4 T-States
        in              a, (c)                          ;               12 T-States
        nop                                             ;                4 T-States
        in              l, (c)                          ;               12 T-States
        ld              a, #0xFF
        out             (#PORTCFG), a                   ; /CS = 1
        ret

; ------------------------------------------------
; Send 4 bytes to flash
; ------------------------------------------------
; void SPI_send4bytes(unsigned char *buffer)
_SPI_send4bytes::
        pop             bc
        pop             hl
        push    hl
        push    bc

        ld              c, #PORTSPI
        ld              a, #0x7F
        out             (#PORTCFG), a                   ; /CS = 0       11 T-States
        .rept 4
        outi                                            ;               16 T-States
        .endm
        ret

; ------------------------------------------------
; Send 5 bytes to flash
; ------------------------------------------------
; void SPI_send5bytes(unsigned char *buffer)
_SPI_send5bytes::
        pop             bc
        pop             hl
        push    hl
        push    bc

        ld              c, #PORTSPI
        ld              a, #0x7F
        out             (#PORTCFG), a                   ; /CS = 0       11 T-States
        .rept 5
        outi                                            ;               16 T-States
        .endm
        ret

; ------------------------------------------------
; Receive up to 256 bytes from flash
; ------------------------------------------------
; void SPI_receive(unsigned char *buffer, unsigned char pages)
_SPI_receive::
        pop     bc
        pop     hl
        pop     de
        push    de
        push    hl
        push    bc

        ld      c, #PORTSPI
        in      a,(c)                   ; clock chip
spirecvloop:
        ld      b, #0                   ; B=size of 1 page
        nop
        inir                            ; read bytes
        dec     e
        jr      nz,spirecvloop
        ret

; ------------------------------------------------
; Writing data in flash (256 bytes)
; ------------------------------------------------
; void SPI_write(unsigned char *buffer)
_SPI_write::
        pop             bc
        pop             hl
        push    hl
        push    bc

        ld              c, #PORTSPI
        .rept 256
        outi                                            ;               16 T-States
        .endm
        ld              a, #0xFF
        out             (#PORTCFG), a                   ; /CS = 1
        ret
