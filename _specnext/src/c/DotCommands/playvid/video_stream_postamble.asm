
;; move to next file fragment within video player

;; The rst $08 interface for stream open and stream close was adding a lot of extra cycles
;; that ate into the number of allowable file fragments per frame.
;;
;; So this code from Garry Lancaster is extracted from the esx api to inline the stream open
;; and stream close functions.
;;
;; The original and untested rst $08 version appears at the end of this file for reference.

; minor modification of code provided by Garry Lancaster

   ; enter :  hl = must preserve
   ;          ix = must preserve
   ;
   ; exit  :   c = 0xeb
   ;          de = LSW of sector count
   ;          iy = MSW of sector count

   PORT_SPI_CS  = 0xe7
   PORT_SPI_DAT = 0xeb
   
   SD_CS0 = 0xfe
   SD_CS1 = 0xfd
   
   CMD12_STOP_TRANSMISSION   = 12 | 0x40
   CMD18_READ_MULTIPLE_BLOCK = 18 | 0x40
   
   push hl
   
   ; end stream
   
   ld a,(__esx_stream_card_flags)
   and 0x01                    ; z for card 0, nz for card 1
   
   ld a,CMD12_STOP_TRANSMISSION
   call sd_send_command_noparam
   
   ld b,8+1                    ; read up to 8 bytes and then $ff token

nf_stop_transmission:

   in a,(PORT_SPI_DAT)
   djnz nf_stop_transmission
   
   ld a,0xff
   out (PORT_SPI_CS),a         ; deselect sd card
   in a,(PORT_SPI_DAT)         ; clock cards
   ;;nop
   ;;nop
   ld hl,(_v_file_fragment)    ; upcoming file fragment
   in a,(PORT_SPI_DAT)
   
   ; gather next file fragment address and length
   
   ld e,(hl)
   inc hl
   ld d,(hl)
   inc hl
   ld c,(hl)
   inc hl
   ld b,(hl)                   ; bcde = sector count
   inc hl

   ; sectors are counted by decrementing lsw before zero check
   ; so we need to adjust the count for correct number of iterations

   ld a,d
   or e
   jp nz, nf_no_adjust
   
   dec bc

nf_no_adjust:

   push de                     ; LSW sector count
   push bc                     ; MSW sector count
   
   ld e,(hl)
   inc hl
   ld d,(hl)
   inc hl
   ld c,(hl)
   inc hl
   ld b,(hl)                   ; bcde = sd card address
   inc hl
   
   ld (_v_file_fragment),hl    ; store next file fragment

   ld l,c
   ld h,b

   ; open stream

   ; hlde = sd card address
   
   ld a,(__esx_stream_card_flags)
   and 0x01                    ; z for card 0, nz for card 1
   
   ld a,CMD18_READ_MULTIPLE_BLOCK
   call sd_send_command
   
   ; c = 0xeb
   
   jr nz, nf_error
   
nf_ready:

   in a,(PORT_SPI_DAT)
   inc a
   jr z, nf_ready
   
   inc a                       ; check token (z/nz)

   ; all done

nf_error:

   ;;ld c,0xeb
   
   pop iy                      ; iy = MSW sector count
   pop de                      ; de = LSW sector count

   pop hl                      ; restore hl
   ret z

   ld a,0xff
   out (PORT_SPI_CS),a         ; deselect sd card
   in a,(PORT_SPI_DAT)         ; clock cards

   pop hl                      ; junk return address
   
   ld a,255                    ; indicate stream error
   ret


sd_send_command_noparam:

   ld h,0
   ld l,h
   ld d,h
   ld e,h

sd_send_command:

   ld b,$ff

sd_send_command_with_crc:

   ld c,a
   
   ld a,SD_CS0
   jr z, cs_set
   ld a,SD_CS1

cs_set:

   out (PORT_SPI_CS),a
   in a,(PORT_SPI_DAT)         ; clock cards
   
   ld a,c                      ; command code is the first byte to be sent
   ld c,PORT_SPI_DAT           ; OUT via (C) to ensure 16T per byte
   
   out (c),a
   ld a,h
   out (c),a
   ld a,l
   out (c),a
   ld a,d
   out (c),a
   ld a,e
   out (c),a
   ld a,b                      ; checksum (needed only for CMD0 and CMD8)
   out (c),a
   nop
   
cmd_response:

   in a,(PORT_SPI_DAT)
   inc a
   jr z, cmd_response
   
   dec a                       ; z = no error (expect 0x00 response)
   ret


;;
;; The original file fragment code using rst $08 interface
;;
;
;   ; enter :  hl = must preserve
;   ;          ix = must preserve
;   ;
;   ; exit  :   c = 0xeb
;   ;          de = LSW of sector count
;   ;          iy = MSW of sector count
;
;   push hl
;
;   ; end current stream
;   
;   ld a,(__esx_stream_card_flags)
;
;   rst 0x08
;   defb 0x87 ; (stream end)
;
;   ; start new one from next sd location
;
;   ld hl,(_file_fragment)      ; upcoming file fragment
;   
;   ld e,(hl)
;   inc hl
;   ld d,(hl)
;   inc hl
;   ld c,(hl)
;   inc hl
;   ld b,(hl)                   ; bcde = sector count
;   inc hl
;   
;   push de                     ; LSW sector count
;   push bc                     ; MSW sector count
;   
;   ld e,(hl)
;   inc hl
;   ld d,(hl)
;   inc hl
;   ld c,(hl)
;   inc hl
;   ld b,(hl)                   ; bcde = sd card address
;   inc hl
;   
;   ld (_file_fragment),hl      ; store next file fragment
;
;   ld l,c
;   ld h,b
;   
;   ld a,(__esx_stream_card_flags)
;   
;   rst 0x08                    ; DOT COMMAND CALL SO PARAM IN IX NOT NECESSARY
;   defb 0x86 ; (stream start)  ; c = 0xeb on exit
;   
;   ; place sector count in registers
;   
;   pop iy                      ; iy = MSW sector count
;   pop de                      ; de = LSW sector count
;   
;   ; restore hl
;   
;   pop hl
;   ret nc
;   
;   ; stream error
;   
;   pop hl                      ; dump return address
;
;   ; return to video player caller
;   
;   ld a,255                    ; indicate stream error
;   ret
