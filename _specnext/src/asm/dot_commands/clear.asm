; ***************************************************************************
; * Dot command for clearing user-installed drivers, allocated memory etc   *
; * .clear                                                                  *
; ***************************************************************************

include "macros.def"
include "nexthw.def"
include "rom48.def"
include "bastoken.def"
include "sysvars.def"
include "esxapi.def"
include "nextzxos.def"


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************
; Dot commands always start at $2000, with HL=address of command tail
; (terminated by $00, $0d or ':').

        org     $2000

        ld      bc,next_reg_select
        ld      a,nxr_turbo
        out     (c),a
        inc     b
        in      a,(c)                   ; get current turbo setting
        ld      (saved_turbo),a
        ld      a,turbo_max
        out     (c),a                   ; and set to maximum
        ld      a,h
        or      l
        jr      z,clear_start           ; no tail provided if HL=0
        ld      de,0                    ; any args to ROM
        call    get_sizedarg            ; get first argument to filename
        jr      nc,clear_start          ; if none, perform clear
show_usage:
        ld      hl,msg_help
        call    printmsg
clear_finish:
        ld      a,(saved_turbo)
        nxtrega nxr_turbo               ; restore entry turbo setting
        and     a                       ; Fc=0, successful
        ret

clear_start:

; ***************************************************************************
; * Uninstall drivers                                                       *
; ***************************************************************************

        ld      bc,$817f                ; C=max driver id; B=$81, shutdown
uninstall_loop:
        push    bc
        callesx m_drvapi                ; shut down the driver, if need be
        pop     bc
        push    bc
        ld      e,c                     ; E=driver ID
        ld      bc,$0200                ; C=0, driver API; B=$02, uninstall
        callesx m_drvapi                ; uninstall the driver
        pop     bc
        dec     c
        jr      nz,uninstall_loop

; ***************************************************************************
; * Restore default interrupt modes, turn off expansion                     *
; ***************************************************************************

        im      1                       ; interrupt mode 1
        nxtregn nxr_lineint_control,0   ; standard ULA interrupt only
        nxtregn nxr_int_en0,$81         ; ULA interrupts, exp /INT
        nxtregn nxr_int_en1,0           ; no CTC interrupts
        nxtregn nxr_int_en2,0           ; no UART interrupts
        nxtregn nxr_dmaint_en0,0        ; no DMA interruptions
        nxtregn nxr_dmaint_en1,0        ; no DMA interruptions
        nxtregn nxr_dmaint_en2,0        ; no DMA interruptions
        nxtregn nxr_expbus_enable,0     ; disable expansion bus
        nxtregn nxr_expbus_ctrl,0

; ***************************************************************************
; * Deallocate ZX memory allocated for non-BASIC purposes                   *
; ***************************************************************************

        ld      hl,$0000                ; get total number of ZX banks
        callp3d ide_bank,7              ; E=total number of ZX banks
dealloczx_loop:
        push    de
        dec     e                       ; E=next bank id
        ld      a,(CACHEBK)             ; don't deallocate the cache bank
        cp      e
        jr      z,dealloczx_skip
        ld      hl,$0003                ; free ZX bank
        callp3d ide_bank,7              ; free ZX bank E
dealloczx_skip:
        pop     de
        dec     e
        jr      nz,dealloczx_loop

; ***************************************************************************
; * Deallocate ZX memory allocated for BASIC purposes                       *
; ***************************************************************************
; NOTE: When using IDE_BASIC, the workspace pointers are reset so that the
;       calculator stack will overwrite the space we are reserving. Work
;       around this by ensuring there is enough space for calculator usage
;       before the area we actually use.

CALCULATOR_USAGE        equ     40              ; enough for 8 calculator entries

        ld      bc,msg_bankclear_end-msg_bankclear+CALCULATOR_USAGE
        call48k BC_SPACES_r3            ; DE=workspace address
        addde_N CALCULATOR_USAGE
        ld      hl,msg_bankclear
        ld      bc,msg_bankclear_end-msg_bankclear
        push    de
        ldir                            ; copy command to RAM buffer
        pop     hl                      ; command address
        callp3d ide_basic,0             ; release BASIC-allocated banks
        jp      clear_finish


; ***************************************************************************
; * Print a message                                                         *
; ***************************************************************************

include "printmsg.asm"


; ***************************************************************************
; * Argument parsing                                                        *
; ***************************************************************************

ARG_PARAMS_DEHL         equ     1
include "arguments.asm"


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

saved_turbo:
        defb    0


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

msg_help:
        defm    "CLEAR v1.4 by Garry Lancaster",$0d
        defm    "Releases all allocated resources",$0d
        defm    "leaving maximum available memory",$0d,$0d
        defm    "NOTE: Uses integer register %a",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    " .CLEAR",$0d,0

msg_bankclear:
        defm    token_layer,token_bank,"%9,%9:"
        defm    token_for,"%a=%12",token_to,"%",token_peek
        defm    "23401:",token_bank,"%a",token_clear,":"
        defm    token_next,"%a:%a=%0",$0d
msg_bankclear_end:
