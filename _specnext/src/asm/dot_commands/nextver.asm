; ***************************************************************************
; * Dot command to return version of NextZXOS running                       *
; ***************************************************************************

include "macros.def"
include "rom48.def"
include "sysvars.def"
include "esxapi.def"


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************

        org     $2000

nextver_init:
        ld      (saved_sp),sp           ; save entry SP for error handler
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
        jr      nc,no_argument
        call    check_options
        jr      z,parse_firstarg        ; if it was an option, try again
        ld      (var_len),bc            ; save variable name length
        ld      hl,temparg
        ld      de,var_name
        ldir                            ; copy variable name argument
parse_remaining:
        call    get_sizedarg            ; get an argument
        jr      nc,nextver_start        ; okay if none
        call    check_options
        jr      z,parse_remaining       ; okay if a valid option
show_usage:
        ld      hl,msg_help
        call    printmsg
        and     a                       ; Fc=0, successful
        jr      error_handler           ; restore turbo setting and exit


; ***************************************************************************
; * Custom error generation                                                 *
; ***************************************************************************

err_custom:
        xor     a                       ; A=0, custom error
        scf                             ; Fc=1, error condition
        ; drop through to error_handler

; ***************************************************************************
; * Exit with any error condition                                           *
; ***************************************************************************

error_handler:
        ld      sp,(saved_sp)           ; restore entry SP
        ret


; ***************************************************************************
; * Calculator routine                                                      *
; ***************************************************************************
; This routine is executed from RAM with ROM 3 in place.
; It expects: MAJOR,MIDDLE,MINOR on the calculator stack and returns
; with the floating point value MAJOR+((MIDDLE+(MINOR/10))/10).

calc_routine:
        rst     $28                     ; engage FP calculator
        defb    $a4                     ; stk-10
        defb    $05                     ; division
        defb    $0f                     ; addition
        defb    $a4                     ; stk-10
        defb    $05                     ; division
        defb    $0f                     ; addition
        defb    $38                     ; end-calc
        ret
calc_routine_end:


; ***************************************************************************
; * No argument, but possibly --verbose option                              *
; ***************************************************************************

no_argument:
        ld      a,(display_ver)
        and     a
        jr      z,show_usage            ; if not verbose, show usage
        ; drop through to nextver_start

; ***************************************************************************
; * Main operation                                                          *
; ***************************************************************************

nextver_start:
        ; Reserve some workspace for the calculator routine/variable assignment.
        ld      bc,(var_len)
        addbc_N calc_routine_end-calc_routine+1
        call48k BC_SPACES_r3            ; reserve the space, at DE
        ld      (workspace_addr),de

        ; Obtain the NextZXOS version.
        callesx m_dosversion
        ld      ix,$0000                ; use version 0.00 if not NextZXOS
        jr      c,got_version           ; must be esxDOS if error
        jr      nz,got_version          ; need to be in NextZXOS mode
        ld      hl,'N'<<8+'X'
        sbc     hl,bc                   ; check NextZXOS signature
        jr      nz,got_version
        push    de
        pop     ix                      ; IX=version passed in DE
got_version:
        push    ix                      ; save version for later display
        ld      hl,(var_len)
        ld      a,h
        or      l
        jr      z,skip_assign           ; skip if variable not provided
        ld      a,ixh
        call48k STACK_A_r3              ; CALC: major
        ld      a,ixl
        rrca
        rrca
        rrca
        rrca
        and     $0f
        call48k STACK_A_r3              ; CALC: major,middle
        ld      a,ixl
        and     $0f
        call48k STACK_A_r3              ; CALC: major,middle,minor
        ld      hl,calc_routine
        ld      de,(workspace_addr)
        ld      bc,calc_routine_end-calc_routine
        ldir                            ; copy routine into workspace
        ld      hl,(workspace_addr)
        call48k CALL_JUMP_r3            ; execute routine with ROM3 in place

        ; Assign the stacked value to the desired variable.
        ld      hl,(CH_ADD)
        push    hl
        ld      hl,(workspace_addr)
        ld      (CH_ADD),hl             ; temporarily move CH_ADD into workspace
        ex      de,hl
        ld      hl,var_name
        ld      bc,(var_len)
        ldir                            ; and store variable name there
        ld      a,'='
        ld      (de),a                  ; followed by '=' to stop name matching
        call48k CLASS_01_r3             ; initiate the assignment
        call48k LET_r3                  ; perform the assignment
        pop     hl
        ld      (CH_ADD),hl             ; restore CH_ADD

skip_assign:

        ; If verbose mode, display the version.
        pop     ix                      ; IX=version
        ld      a,(display_ver)
        and     a
        jr      z,finished
        ld      a,ixh
        add     a,'0'                   ; major
        print_char()
        ld      a,'.'
        print_char()
        ld      a,ixl
        rrca
        rrca
        rrca
        rrca
        and     $0f
        add     a,'0'                   ; middle
        print_char()
        ld      a,ixl
        and     $0f
        add     a,'0'                   ; minor
        print_char()
        ld      a,$0d
        print_char()

finished:
        and     a                       ; completed successfully
        jp      error_handler           ; exit via err handler to restore turbo


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
        defopt  "-v",option_verbose
        defopt  "--verbose",option_verbose
        endopts()


; ***************************************************************************
; * -v, --verbose                                                           *
; ***************************************************************************

option_verbose:
        ld      a,1
        ld      (display_ver),a
        ret


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

; TAB 32 used within help message so it is formatted wide in 64/85 column mode.
msg_help:
        defm    "NEXTVER v1.1 by Garry Lancaster",$0d
        defm    "Set variable to NextZXOS version",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    " .NEXTVER [OPTION]... VARIABLE",$0d
        defm    "OPTIONS:",$0d
        defm    " -h, --help",23,32,0
        defm    "     Display this help",$0d
        defm    " -v, --verbose",23,32,0
        defm    "     Display the version",$0d
        defm    "INFO:",$0d
        defm    "Returns 0 if not NextZXOS mode",$0d
        defm    $ff


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

saved_sp:
        defw    0

workspace_addr:
        defw    0

var_name:
        defs    256

var_len:
        defw    0

display_ver:
        defb    0

command_tail:
        defw    0
