; ***************************************************************************
; * Dot command to reboot to an alternative core                            *
; ***************************************************************************

include "macros.def"
include "nexthw.def"
include "rom48.def"
include "esxapi.def"


; ***************************************************************************
; * Internal definitions                                                    *
; ***************************************************************************

MIN_NEXTZXOS_VER        equ     $0205   ; v2.05 needed for AltROMs


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************

        org     $2000

core_init:
        ld      (saved_sp),sp           ; save entry SP for error handler
        push    hl                      ; save address of arguments
        ld      bc,next_reg_select
        ld      a,nxr_turbo
        out     (c),a
        inc     b
        in      a,(c)                   ; get current turbo setting
        ld      (saved_turbo),a
        ld      a,turbo_max
        out     (c),a                   ; and set to maximum
        callesx m_dosversion
        jp      c,bad_nextzxos          ; must be esxDOS if error
        ld      hl,'N'<<8+'X'
        sbc     hl,bc                   ; check NextZXOS signature
        jp      nz,bad_nextzxos
        ld      hl,MIN_NEXTZXOS_VER
        ex      de,hl
        sbc     hl,de                   ; check version number
        jp      c,bad_nextzxos
        ld      hl,error_handler
        callesx m_errh                  ; install error handler to reset turbo
        pop     hl                      ; restore address of arguments
        ; drop through to parse_arguments

; ***************************************************************************
; * Argument parsing                                                        *
; ***************************************************************************
; Entry: HL=0, or address of command tail (terminated by $00, $0d or ':').

parse_arguments:
        ld      a,h
        or      l
        jr      z,show_usage            ; no tail provided if HL=0
        ld      (command_tail),hl       ; initialise pointer
parse_firstarg:
        call    get_sizedarg            ; get an argument
        jr      nc,show_usage           ; if none, just show usage
        call    check_options
        jr      z,parse_firstarg        ; if it was an option, try again
        ld      de,coreboot_dirname
        call    set_corearg             ; use 1st arg as core name
parse_2ndarg:
        call    get_sizedarg            ; get an argument
        jr      nc,core_start           ; start processing if no more args
        call    check_options
        jr      z,parse_2ndarg          ; if it was an option, try again
        ld      de,coreboot_filename
        call    set_corearg             ; use 2nd arg as launch filename
parse_remaining:
        call    get_sizedarg            ; get an argument
        jr      nc,core_start           ; start processing if no more args
        call    check_options
        jr      z,parse_remaining       ; if it was an option, try again
                                        ; if 3+ args provided, just show usage
show_usage:
        ld      hl,msg_help
        call    printmsg
        and     a                       ; Fc=0, successful
        jr      error_handler           ; exit via error handler to tidy up


; ***************************************************************************
; * Custom error generation                                                 *
; ***************************************************************************

bad_nextzxos:
        ld      hl,msg_badnextzxos
        ; drop through to err_custom
err_custom:
        xor     a                       ; A=0, custom error
        scf                             ; Fc=1, error condition
        ; drop through to error_handler

; ***************************************************************************
; * Exit with any error condition                                           *
; ***************************************************************************
; NOTE: It's not necessary to close any files that may be open, since NextZXOS
;       does this automatically when the dot command terminates.

error_handler:
        ld      sp,(saved_sp)           ; restore entry SP
        push    af
        ld      a,(saved_turbo)
        nxtrega nxr_turbo               ; restore entry turbo setting
        pop     af
        ret


; ***************************************************************************
; * Set a core name / file name argument                                    *
; ***************************************************************************
; Entry: DE=destination
;        BC=length, 1-255

set_corearg:
        ld      hl,temparg
        ld      a,c
        ld      b,a
        cp      16
        jr      c,set_corearg_copy
        ld      b,15                    ; limit to max 15 chars
set_corearg_copy:
        ld      a,(hl)
        inc     hl
        cp      'a'
        jr      c,set_corearg_notlower
        cp      'z'+1
        jr      nc,set_corearg_notlower
        and     $df                     ; make letters uppercase
set_corearg_notlower:
        ld      (de),a
        inc     de
        djnz    set_corearg_copy
        ret


; ***************************************************************************
; * Main operation                                                          *
; ***************************************************************************

core_start:
        ld      hl,coreboot_struct
        ld      b,127
        xor     a
core_checksum_loop:
        add     a,(hl)
        inc     hl
        djnz    core_checksum_loop
        sub     $cb
        neg
        ld      (hl),a                  ; ensure checksummed value is 0xCB
        ld      bc,coreboot_launcher_end-coreboot_launcher
        push    bc
        call48k BC_SPACES_r3            ; reserve space for launcher, at DE
        pop     bc
        ld      hl,coreboot_launcher
        push    de                      ; save address of workspace destination
        ldir                            ; copy launcher to workspace
        pop     hl                      ; HL=address of launcher
        exit_dot_to_hl()                ; terminate dot command and execute it


; ***************************************************************************
; * Print a message                                                         *
; ***************************************************************************

include "printmsgff.asm"


; ***************************************************************************
; * Argument parsing                                                        *
; ***************************************************************************

ARG_PARAMS_DEHL         equ     0
include "arguments.asm"
include "options.asm"


; ***************************************************************************
; * Options table                                                           *
; ***************************************************************************

        startopts()
        endopts()


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

; TAB 32 used within help message so it is formatted wide in 64/85 column mode.
msg_help:
        defm    "CORE v0.2 by Garry Lancaster",$0d
        defm    "Boot an alternative core",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    ".CORE [OPT] CORENAME [FILE]",$0d,$0d
        defm    "OPTIONS:",$0d
        defm    " -h, --help",23,32,0
        defm    "     Display this help",$0d,$0d
        defm    "Depending upon the core, a file",$0d
        defm    "located in the core's standard",$0d
        defm    "files directory (eg a game ROM)",$0d
        defm    "may be specified",$0d,$0d
        defm    "Examples:",$0d
        defm    "  .core atom",$0d
        defm    "  .core cpc6128 game.dsk",$0d,$0d
        defm    $ff

msg_badnextzxos:
        defm    "Requires NextZXOS v"
        defb    '0'+((MIN_NEXTZXOS_VER/$100)&$0f)
        defb    '.'
        defb    '0'+((MIN_NEXTZXOS_VER/$10)&$0f)
        defb    '0'+(MIN_NEXTZXOS_VER&$0f)
        defb    '+'+$80


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

saved_sp:
        defw    0

saved_turbo:
        defb    0

command_tail:
        defw    0

coreboot_launcher:
        di
        nxtregn nxr_altrom,$d0          ; lock AltROM0 for writing
        addhl_N coreboot_struct-coreboot_launcher
        ld      de,0
        ld      bc,128
        ldir                            ; copy struct into AltROM0
        ld      bc,next_reg_select
        ld      a,nxr_reset
        out     (c),a
        inc     b
        in      a,(c)                   ; get current reset settings
        and     %10000000               ; preserve exp bus reset
        or      %00000010               ; hard reset
        out     (c),a

coreboot_struct:
        defm    "COREBOOT"
coreboot_dirname:
        defs    16
coreboot_filename:
        defs    16
coreboot_padding:
        defs    87
coreboot_checksum:
        defb    0
coreboot_launcher_end:
