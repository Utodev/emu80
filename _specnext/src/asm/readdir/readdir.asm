; ***************************************************************************
; * Dot command to test F_OPENDIR, F_READDIR, F_TELLDIR, F_SEEKDIR etc      *
; ***************************************************************************
; Assemble with:
;   pasmo readdir.asm readdir.dot readdir.sym
; Can be executed from Browser or from command-line with:
;   ../readdir.dot


macro call48k,address
        rst     $18
        defw    address
endm

macro callesx,hook
        rst     $8
        defb    hook
endm

macro print_char
        rst     $10
endm


; ***************************************************************************
; * esxDOS API and other definitions required                               *
; ***************************************************************************

; Calls
m_dosversion            equ     $88
m_errh                  equ     $95
f_opendir               equ     $a3
f_readdir               equ     $a4
f_telldir               equ     $a5
f_seekdir               equ     $a6
f_rewinddir             equ     $a7
f_close                 equ     $9b

; Mode bits for f_opendir
esx_mode_sf_enable      equ     $80
esx_mode_use_header     equ     $40
esx_mode_use_wildcards  equ     $20
esx_mode_short_only     equ     $00
esx_mode_lfn_only       equ     $10
esx_mode_lfn_and_short  equ     $18

; Sort/filter modes
esx_sf_exclude_files    equ     $80
esx_sf_exclude_dirs     equ     $40
esx_sf_exclude_dots     equ     $20

esx_sf_sort_enable      equ     $08
esx_sf_sort_reverse     equ     $04

esx_sf_sort_mask        equ     $03
esx_sf_sort_lfn         equ     $00
esx_sf_sort_short       equ     $01
esx_sf_sort_date        equ     $02
esx_sf_sort_size        equ     $03

; 48K ROM routines
BC_SPACES_r3            equ     $0030           ; allocate workspace
OUT_CODE_r3             equ     $15ef           ; digit output
CHAN_OPEN_r3            equ     $1601           ; open stream to channel
OUT_SP_NO_r3            equ     $192a           ; numeric place output

; System variables
RAMRST                  equ     $5b5d

; Next registers
next_reg_select         equ     $243b
nxr_turbo               equ     $07
turbo_max               equ     $03


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************
; Dot commands always start at $2000, with HL=address of command tail
; (terminated by $00, $0d or ':').

        org     $2000

        ld      (saved_sp),sp           ; save entry SP for error handler
        ld      bc,RAMSPACE_SIZE
        call48k BC_SPACES_r3            ; ensure enough working space
        ld      (ramspace_addr),de      ; and save its address
        ld      bc,next_reg_select
        ld      a,nxr_turbo
        out     (c),a
        inc     b
        in      a,(c)                   ; get current turbo setting
        ld      (saved_speed),a         ; save it
        ld      a,turbo_max
        out     (c),a                   ; and increase to maximum
        callesx m_dosversion
        jr      c,bad_nextzxos          ; must be esxDOS if error
        ld      hl,'N'<<8+'X'
        sbc     hl,bc                   ; check NextZXOS signature
        jr      nz,bad_nextzxos
        ld      hl,$0207
        ex      de,hl
        sbc     hl,de                   ; check version number >= 2.07
        jr      nc,good_nextzxos
bad_nextzxos:
        ld      hl,msg_badnextzxos
        ; drop through to err_custom

; ***************************************************************************
; * Custom error generation                                                 *
; ***************************************************************************

err_custom:
        xor     a                       ; A=0, custom error
        scf                             ; Fc=1, error condition
        ; fall through to error_handler

; ***************************************************************************
; * Close file and exit with any error condition                            *
; ***************************************************************************

error_handler:
        ld      sp,(saved_sp)           ; restore entry SP
restore_all:
        push    af                      ; save error status
        push    hl
        ld      a,(dirhandle)
        cp      $ff
        jr      z,exit_nodir
        callesx f_close                 ; close the directory
exit_nodir:
        ld      bc,next_reg_select
        ld      a,nxr_turbo
        out     (c),a
        inc     b
        ld      a,(saved_speed)
        out     (c),a                   ; restore original speed
        pop     hl                      ; restore error status
        pop     af
        ret


; ***************************************************************************
; * Error handler for standard BASIC errors                                 *
; ***************************************************************************
; This handler is entered if a standard BASIC error occurs during a call to
; ROM3.

stderr_handler:
        call    restore_all             ; restore entry conditions
        ld      h,a
        ld      l,$cf                   ; RST8 instruction
        ld      (RAMRST),hl             ; store RST8;error in sysvars
        ld      hl,0
        callesx m_errh                  ; disable error handler
        call48k RAMRST                  ; generate the BASIC error


; ***************************************************************************
; * Main test code                                                          *
; ***************************************************************************

good_nextzxos:
        ld      hl,stderr_handler
        callesx m_errh                  ; install error handler to tidy up
        ld      a,2
        call48k CHAN_OPEN_r3            ; direct output to the screen

        ld      hl,test_list
test_loop:
        ld      a,(hl)
        and     a
        jp      z,error_handler         ; done if end of tests (Fc=0, success)
        call    print_z                 ; show test title
        ld      a,13
        print_char()
        ld      a,13
        print_char()
        ld      a,(hl)
        inc     hl
        push    hl
        and     a                       ; use DivMMC or main RAM?
        jr      nz,test_with_main       ; on for main RAM

        ld      hl,path_start           ; set addresses in our DivMMC RAM
        ld      (path_addr),hl
        ld      hl,wild_start
        ld      (wild_addr),hl
        ld      hl,divspace
        ld      (entry_addr),hl
        jr      do_test

test_with_main:
        ld      hl,path_start
        ld      de,(ramspace_addr)
        ld      (path_addr),de
        ld      bc,path_end-path_start
        ldir                            ; copy path to main RAM
        ld      hl,wild_start
        ld      (wild_addr),de
        ld      bc,wild_end-wild_start
        ldir                            ; copy wildcard to main RAM
        ld      (entry_addr),de         ; entry will be loaded to main RAM

do_test:
        pop     hl
        ld      b,(hl)                  ; B=access mode
        inc     hl
        ld      c,(hl)                  ; C=sort/filter mode
        inc     hl
        ld      (sort_flags),bc
        push    hl
        ld      a,'*'
        ld      hl,(path_addr)
        ld      de,(wild_addr)
        callesx f_opendir
        jp      c,error_handler
        ld      (dirhandle),a           ; store directory handle
        ld      bc,0                    ; count entries from 0
        push    bc

read_loop:
        call    showanentry             ; show each entry
        pop     bc
        inc     bc                      ; next entry number
        push    bc
        jp      c,error_handler
        jr      z,no_more_entries
        ld      a,(sort_flags)
        and     esx_sf_sort_mask
        cp      esx_sf_sort_short       ; if sorting on short names, also test
                                        ; tell/seek/rewind
        jr      nz,read_loop            ; else loop back for more
        ld      a,b
        and     a
        jr      nz,read_loop
        ld      a,c
        cp      2
        jr      nz,entry_not_2
        ld      a,(dirhandle)
        callesx f_telldir               ; get BCDE=dir pointer for 3rd entry
        ld      (entry3ptr),de          ; and save it
        ld      (entry3ptr+2),bc
        jr      read_loop
entry_not_2:
        cp      5
        jr      nz,entry_not_5
        ld      a,(dirhandle)
        ld      de,(entry3ptr)
        ld      bc,(entry3ptr+2)
        callesx f_seekdir               ; seek back to 3rd entry after 6th entry
        ld      hl,msg_seek
        call    print_z
        jr      read_loop
entry_not_5:
        cp      10
        jr      nz,read_loop
        ld      a,(dirhandle)
        callesx f_rewinddir             ; rewind to start after 11th entry
        ld      hl,msg_rewind
        call    print_z
        jr      read_loop               ; loop back for more

no_more_entries:
        pop     bc                      ; discard entry number
        ld      a,(dirhandle)
        callesx f_close                 ; close directory handle
        push    af
        ld      a,$ff
        ld      (dirhandle),a           ; no dirhandle open
        pop     af
        jp      c,error_handler

        pop     hl
        jp      test_loop               ; back for remaining tests


; ***************************************************************************
; * List of test operations                                                 *
; ***************************************************************************

test_list:
        ;        012345678901234567890123456789012
        defm    "DivMMC/nosort/nofilt/short/nohd",0
        defb    0                       ; use DivMMC RAM
        defb    esx_mode_short_only
        defb    0

        defm    "MainRAM/nosort/nofilt/short/nohd",0
        defb    1                       ; use main RAM
        defb    esx_mode_short_only
        defb    0

        defm    "DivMMC/nosort/*.b*/both/hdrs",0
        defb    0                       ; use DivMMC RAM
        defb    esx_mode_lfn_and_short+esx_mode_use_header+esx_mode_use_wildcards
        defb    0

        defm    "MainRAM/nosort/*.b*/both/hdrs",0
        defb    1                       ; use main RAM
        defb    esx_mode_lfn_and_short+esx_mode_use_header+esx_mode_use_wildcards
        defb    0

        defm    "DivMMC/+lfn/*.b*/lfn/nohd",0
        defb    0                       ; use DivMMC RAM
        defb    esx_mode_lfn_only+esx_mode_sf_enable+esx_mode_use_wildcards
        defb    esx_sf_sort_enable+esx_sf_sort_lfn

        defm    "MainRAM/-lfn/*.b*/lfn/nohd",0
        defb    1                       ; use main RAM
        defb    esx_mode_lfn_only+esx_mode_sf_enable+esx_mode_use_wildcards
        defb    esx_sf_sort_enable+esx_sf_sort_lfn+esx_sf_sort_reverse

        defm    "DivMMC/+date/nofiles/lfn/nohd",0
        defb    0                       ; use DivMMC RAM
        defb    esx_mode_lfn_only+esx_mode_sf_enable
        defb    esx_sf_sort_enable+esx_sf_sort_date+esx_sf_exclude_files

        defm    "MainRAM/-date/nodots/lfn/nohd",0
        defb    1                       ; use main RAM
        defb    esx_mode_lfn_only+esx_mode_sf_enable
        defb    esx_sf_sort_enable+esx_sf_sort_date+esx_sf_sort_reverse+esx_sf_exclude_dots

        defm    "DivMMC/+size/nodirs/lfn/nohd",0
        defb    0                       ; use DivMMC RAM
        defb    esx_mode_lfn_only+esx_mode_sf_enable
        defb    esx_sf_sort_enable+esx_sf_sort_size+esx_sf_exclude_dirs

        defm    "MainRAM/-size/nodirs/lfn/nohd",0
        defb    1                       ; use main RAM
        defb    esx_mode_lfn_only+esx_mode_sf_enable
        defb    esx_sf_sort_enable+esx_sf_sort_size+esx_sf_sort_reverse+esx_sf_exclude_dirs

        defm    "DivMMC/nosort/nofilt/short/nohd",0
        defb    0                       ; use DivMMC RAM
        defb    esx_mode_short_only
        defb    esx_sf_sort_short       ; NOTE: not really sorting, just use to
                                        ;       flag testing of tell/seek/rewind

        defm    "MainRAM/+short/nofilt/short/nohd",0
        defb    1                       ; use main RAM
        defb    esx_mode_short_only+esx_mode_sf_enable
        defb    esx_sf_sort_enable+esx_sf_sort_short
                                        ; NOTE: short sorting, plus flag
                                        ;       testing of tell/seek/rewind

        defb    0                       ; end of list


; ***************************************************************************
; * Show next file entry                                                    *
; ***************************************************************************

showanentry:
        ld      hl,(entry_addr)
        ld      de,(wild_addr)
        ld      a,(dirhandle)
        callesx f_readdir
        ret     c                       ; Fc=1; failure
        and     a
        ret     z                       ; Fc=0, Fz=1; no matches
        ld      hl,(entry_addr)
        ld      a,(hl)                  ; A=attribute
        inc     hl
        call    print_hex_byte          ; show attribute
        ld      a,' '
        print_char()
        call    print_z                 ; show filename
        ld      a,13
        print_char()                    ; new line
        ld      a,(open_flags)
        and     esx_mode_lfn_and_short
        cp      esx_mode_lfn_and_short
        jr      nz,one_filename
        call    print_z                 ; show short name if both LFN/short
        ld      a,13
        print_char()                    ; new line
one_filename:
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; DE=time
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)                  ; BC=date
        inc     hl
        push    hl
        call    print_date_time         ; show date and time
        pop     hl
        ld      a,' '
        print_char()
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; DEBC=filesize
        inc     hl
        push    hl
        ld      h,b
        ld      l,c                     ; DEHL=filesize
        call    print_filesize          ; show file size
        pop     hl
        ld      a,13
        print_char()
        ld      a,(open_flags)
        and     esx_mode_use_header
        jr      z,no_header
        ld      a,(hl)                  ; A=file type
        inc     hl
        call    print_hex_byte          ; show header type byte
        ld      b,3                     ; 3 header words to show
show_header_word_loop:
        ld      a,' '
        print_char()
        push    bc
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        call    print_hex_word          ; show each header word
        pop     bc
        djnz    show_header_word_loop
        ld      a,13
        print_char()
no_header:
        ld      a,13
        print_char()
        xor     a
        inc     a                       ; Fc=0, Fz=0; success
        ret


; ***************************************************************************
; * Print hex word                                                          *
; ***************************************************************************
; Entry: BC=word

print_hex_word:
        push    bc
        ld      a,b
        call    print_hex_byte          ; print high byte
        pop     bc
        ld      a,c
        ; drop through to print_hex_byte to print low byte

; ***************************************************************************
; * Print hex byte                                                          *
; ***************************************************************************
; Entry: A=byte

print_hex_byte:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    print_hex_nibble        ; print high nibble
        pop     af
        ; drop through to print_hex_nibble to print low nibble

; ***************************************************************************
; * Print hex nibble                                                        *
; ***************************************************************************
; Entry: A(bits 3..0)=nibble

print_hex_nibble:
        and     $0f                     ; mask nibble value
        cp      10                      ; Fc=1 if 0..9
        sbc     a,$69                   ; half-carry=1 if 0..9
        daa                             ; ASCII conversion
        print_char()
        ret


; ***************************************************************************
; * Print null-terminated string                                            *
; ***************************************************************************

print_z:
        ld      a,(hl)
        inc     hl
        and     a
        ret     z
        print_char()
        jr      print_z


; ***************************************************************************
; * Print decimal number                                                    *
; ***************************************************************************
; Entry: HL=number
;        E=$ff for no leading spaces, $20 for leading spaces

print_num:
        push    hl
        ld      bc,$d8f0        ; -10000
        call48k OUT_SP_NO_r3    ; output 10000s
        ld      bc,$fc18        ; -1000
        call48k OUT_SP_NO_r3    ; output 1000s
        ld      bc,$ff9c        ; -100
        call48k OUT_SP_NO_r3    ; output 100s
print2digits:
        ld      c,$f6           ; -10
        call48k OUT_SP_NO_r3    ; output 10s
        ld      a,l             ; units
        call48k OUT_CODE_r3     ; output units
        pop     hl              ; restore number
        ret


; ***************************************************************************
; * Print date/time segment                                                 *
; ***************************************************************************
; Entry: print_date_seg: A=number
;        print_dt_seg:   L=number, A=leading character

print_date_seg:
        ld      l,a
        ld      a,'-'
print_dt_seg:
        ld      h,0             ; high byte is always zero
        print_char()            ; print leading character
        push    hl
        ld      e,'0'           ; leading zeroes
        jr      print2digits


; ***************************************************************************
; * Print a date and time.                                                  *
; ***************************************************************************
; Entry: BC=date and DE=time (MS-DOS formats)

print_date_time:
        push    de
        push    bc
        ld      l,b
        ld      h,0
        srl     l               ; HL=year-1980
        ld      bc,1980
        add     hl,bc
        ld      e,$ff
        call    print_num       ; print year
        pop     hl
        ld      a,l             ; top 3 bits of A=low 3 bits of month
        push    af              ; save A with bottom 5 bits=day
        srl     h
        rra                     ; top nibble of A=month
        rrca
        rrca
        rrca
        rrca
        and     $0f             ; A=month
        call    print_date_seg  ; print month with a leading '-'
        pop     af
        and     $1f             ; A=day
        call    print_date_seg  ; print day with a leading '-'
        pop     hl              ; retrieve time
        push    hl
        ld      a,h             ; top 5 bits of A=hour
        rrca
        rrca
        rrca
        and     $1f             ; A=hour
        ld      l,a
        ld      a,' '
        call    print_dt_seg    ; print hour with a leading ' '
        pop     hl              ; minutes are in bits 5..10
        add     hl,hl
        add     hl,hl
        add     hl,hl           ; bottom 6 bits of H=minutes
        ld      a,h
        and     $3f
        ld      l,a             ; L=minutes
        ld      a,':'
        jr      print_dt_seg    ; print minutes with a leading ':' and exit


; ***************************************************************************
; * Print file size, right-aligned                                          *
; ***************************************************************************
; Entry: DEHL=file size

print_filesize:
        ld      ix,pfs_units_table
        ld      a,' '
        ld      b,9
pfs_loop:
        push    bc
        bit     7,(ix+3)
        jr      z,pfs_nocomma
        cp      ' '
        ld      c,a
        jr      z,pfs_setcomma          ; use a space if no digits yet
        ld      c,','                   ; otherwise use separator
pfs_setcomma:
        push    af
        ld      a,c
        print_char()                    ; print space/separator
        pop     af
pfs_nocomma:
pfs_success:
        ld      c,(ix+0)
        ld      b,(ix+1)
        and     a
        sbc     hl,bc
        ex      de,hl
        ld      c,(ix+2)
        ld      b,(ix+3)
        res     7,b
        sbc     hl,bc
        ex      de,hl
        jr      c,pfs_fail
        inc     a
        cp      ' '+1
        jr      nz,pfs_success
        ld      a,'1'
        jr      pfs_success
pfs_fail:
        ld      c,(ix+0)
        ld      b,(ix+1)
        add     hl,bc
        ex      de,hl
        ld      c,(ix+2)
        ld      b,(ix+3)
        res     7,b
        adc     hl,bc
        ex      de,hl
        push    af
        print_char()                    ; print space/digit
        pop     af
        cp      ' '
        jr      z,pfs_stillspace
        ld      a,'0'
pfs_stillspace:
        ld      bc,4
        add     ix,bc
        pop     bc
        djnz    pfs_loop
        ld      a,l
        add     a,'0'
        print_char()                    ; print unit value
        ret

pfs_units_table:
        defb    $00,$ca,$9a,$3b         ; 1,000,000,000
        defb    $00,$e1,$f5,$05+$80     ;   100,000,000
        defb    $80,$96,$98,$00         ;    10,000,000
        defb    $40,$42,$0f,$00         ;     1,000,000
        defb    $a0,$86,$01,$00+$80     ;       100,000
        defb    $10,$27,$00,$00         ;        10,000
        defb    $e8,$03,$00,$00         ;         1,000
        defb    $64,$00,$00,$00+$80     ;           100
        defb    $0a,$00,$00,$00         ;            10


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

msg_badnextzxos:
        defm    "Requires NextZXOS v2.07",'+'+$80

msg_seek:
        defm    "Seeking back to 3rd entry",13,13,0

msg_rewind:
        defm    "Rewinding back to start",13,13,0


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

path_start:
        defm    "c:/nextzxos",0
path_end:

PATH_SIZE       equ     path_end-path_start

wild_start:
        defm    "*.b*",0
wild_end:

WILD_SIZE       equ     wild_end-wild_start

saved_sp:
        defw    0

saved_speed:
        defb    0

dirhandle:
        defb    $ff

path_addr:
        defw    0

wild_addr:
        defw    0

entry_addr:
        defw    0

sort_flags:
        defb    0
open_flags:
        defb    0

entry3ptr:
        defw    0,0

; Space for a file entry
FILE_ENTRY_SIZE equ     1+261+13+4+4+8  ; attrib,LFN,short name,date/time,size,header

; Space required for operation in RAM
RAMSPACE_SIZE   equ     PATH_SIZE+WILD_SIZE+FILE_ENTRY_SIZE

divspace:
        defs    FILE_ENTRY_SIZE         ; space for 1 file entry in DivMMC

ramspace_addr:
        defw    0                       ; address of workspace in main RAM
