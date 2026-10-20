; ***************************************************************************
; * Dot commands for creating data or swap partitions                       *
; * .mkdata filename [size]                                                 *
; * .mkswap filename [size]                                                 *
; ***************************************************************************

include "macros.def"
include "nexthw.def"
include "rom48.def"
include "esxapi.def"


; ***************************************************************************
; * Internal definitions                                                    *
; ***************************************************************************

if MKDATA
MAX_SIZE_MB             equ     16
else
MAX_SIZE_MB             equ     30
endif

BUFFER_SIZE             equ     4096    ; .P3D buffer, must divide
                                        ; into 16K and be divisible by (32*4)


; ***************************************************************************
; * Argument parsing                                                        *
; ***************************************************************************
; Dot commands always start at $2000, with HL=address of command tail
; (terminated by $00, $0d or ':').

        org     $2000

        ld      (entry_sp),sp           ; save initial SP
        ld      a,h
        or      l
        jr      z,show_usage            ; no tail provided if HL=0
        ld      de,filename
        call    get_sizedarg            ; get first argument to filename
        jr      nc,show_usage           ; if none, just go to show usage
        ld      de,sizeparam
        call    get_sizedarg            ; see if there is a size argument
        jr      nc,use_default_size     ; if not, just use the default
        ld      de,0                    ; further args to ROM
        call    get_sizedarg            ; check if any further args
        jr      nc,parse_size           ; okay if not
show_usage:
        ld      hl,msg_help
        call    printmsg
        and     a                       ; Fc=0, successful
        ret

parse_size:
        ld      hl,0                    ; initialise size to 0
        ld      de,sizeparam            ; start of argument
parse_size_loop:
        ld      a,(de)                  ; get next character from parameter
        inc     de
        and     a
        jr      z,got_size              ; on when reached the end
        sub     '0'                     ; put next digit in range 0..9
        jr      c,show_usage            ; if not a digit, show the help
        cp      10
        jr      nc,show_usage
        add     hl,hl                   ; HL=curvalue*2
        ld      b,h
        ld      c,l                     ; BC=curvalue*2
        add     hl,hl
        add     hl,hl                   ; HL=curvalue*8
        add     hl,bc                   ; HL=curvalue*10
        ld      b,0
        ld      c,a
        add     hl,bc                   ; add in new digit
        ld      a,h
        and     a
        jr      nz,show_usage           ; error if >=256
        jr      parse_size_loop

use_default_size:
        ld      hl,MAX_SIZE_MB          ; default size is the maximum
got_size:
        ld      a,l                     ; ensure valid size 1-MAX_SIZE_MB
        and     a
        jr      z,show_usage
        cp      MAX_SIZE_MB+1
        jr      nc,show_usage
        ld      (drivesize),a           ; save size for later
        ; fall through to mkp3d_init

; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************

mkp3d_init:
        di                              ; disable interrupts for the duration
        ld      bc,BUFFER_SIZE
        call48k BC_SPACES_r3            ; ensure enough space for 4K buffer
        ld      (bufferaddr),de         ; and save its address
        ld      bc,next_reg_select
        ld      a,nxr_turbo
        out     (c),a
        inc     b
        in      a,(c)                   ; get current turbo setting
        ld      (saved_speed),a         ; save it
        ld      a,turbo_max
        out     (c),a                   ; and increase to maximum
        ld      a,$80                   ; set do not erase with truncate
        callesx m_setcaps
        ld      a,e
        ld      (old_caps),a            ; save old capabilities for restoring
        callesx m_dosversion
        jr      c,bad_nextzxos          ; must be esxDOS if error
        ld      hl,'N'<<8+'X'
        sbc     hl,bc                   ; check NextZXOS signature
        jr      nz,bad_nextzxos
        ld      hl,$0202
        ex      de,hl
        sbc     hl,de                   ; check version number >= 2.02
        jr      nc,domkp3d
bad_nextzxos:
        ld      hl,msg_badnextzxos
        ; fall through to err_custom

; ***************************************************************************
; * Custom error generation                                                 *
; ***************************************************************************

err_custom:
        xor     a                       ; A=0, custom error
        scf                             ; Fc=1, error condition
        ; fall through to exit_error

; ***************************************************************************
; * Close file and exit with any error condition                            *
; ***************************************************************************

exit_error:
        ld      sp,(entry_sp)           ; restore original stack
        push    af                      ; save error status
        push    hl
        ld      a,(old_caps)
        callesx m_setcaps               ; restore original caps
        ld      a,(saved_speed)
        nxtrega nxr_turbo               ; restore original speed
        pop     hl                      ; restore error status
        pop     af
        ei                              ; re-enable interrupts
        ret


; ***************************************************************************
; * Create an unfragmented .P3D file                                        *
; ***************************************************************************

domkp3d:
        ld      a,(drivesize)
        call    createp3d               ; create the .P3D file
        and     a
        jp      exit_error              ; for now just close the file & exit


; ***************************************************************************
; * Library routines                                                        *
; ***************************************************************************

include "fragmentation.asm"
include "createp3d.asm"
include "printmsg.asm"

ARG_PARAMS_DEHL         equ     1
include "arguments.asm"


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

msg_help:
if MKDATA
        defm    "MKDATA v1.4 by Garry Lancaster",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    " .MKDATA FILENAME [SIZE]",$0d,$0d
        defm    "INFO:",$0d
        defm    "Creates a mountable +3DOS drive",$0d
        defm    "image, usable by NextZXOS & CP/M",$0d
        defm    "Optional size in MB is 1..16",$0d
        defm    "(default=16)",$0d,$0d
        defm    "For automounting at startup or",$0d
        defm    "when CP/M starts, name files as:",$0d
        defm    "    C:/NEXTZXOS/DRV-d.P3D",$0d
        defm    "    C:/NEXTZXOS/CPM-d.P3D",$0d
        defm    "where 'd' is drive letter A-P",$0d,$0d
        defm    "NextZXOS uses DRV-d files first,",$0d
        defm    "then CPM-d files. CP/M uses",$0d
        defm    "CPM-d files first, then DRV-d",$0d
        defm    "files",$0d,0
else
        defm    "MKSWAP v1.3 by Garry Lancaster",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    " .MKSWAP FILENAME [SIZE]",$0d,$0d
        defm    "INFO:",$0d
        defm    "Creates a swap file usable by",$0d
        defm    "NextZXOS machine-code programs",$0d,$0d
        defm    "Optional size in MB is 1..30",$0d
        defm    "(default=30)",$0d,$0d
        defm    "Swap files should be named:",$0d
        defm    "    C:/NEXTZXOS/SWP-n.P3S",$0d
        defm    "where 'n' is number 0-9",$0d,0
endif

msg_badnextzxos:
        defm    "Requires NextZXOS v2.02",'+'+$80


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

entry_sp:
        defw    0                       ; entry stack pointer

saved_speed:
        defb    0

old_caps:
        defb    0

sizeparam:
        defs    256

filename:
        defs    256
