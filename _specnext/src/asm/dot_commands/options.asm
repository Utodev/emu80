; ***************************************************************************
; * Option handling for dot commands                                        *
; ***************************************************************************


; ***************************************************************************
; * Macros                                                                  *
; ***************************************************************************

macro defopt,name,addr
local opt_start,opt_end
        defb    opt_end-opt_start
opt_start:
        defm    name
opt_end:
        defw    addr
endm

macro startopts
option_table:
endm

macro endopts
        defopt  "-h",show_usage
        defopt  "--help",show_usage
        defb    0
endm


; ***************************************************************************
; * Check for options                                                       *
; ***************************************************************************
; Entry: temparg contains argument, possibly option name
;        C=length of argument
; Exit:  C=length of argument (preserved if not an option)
;        Fz=1 if was an option (and has been processed)
;        Fz=0 if not an option

check_options:
        ld      a,(temparg)
        cp      '-'
        ret     nz                      ; exit with Fz=0 if not an option
        ld      hl,option_table
check_next_option:
        ld      a,(hl)
        inc     hl
        and     a
        jr      z,invalid_option        ; cause error if end of table
        cp      c
        jr      nz,skip_option          ; no match if lengths differ
        ld      b,a                     ; length to compare
        ld      de,temparg
check_option_name_loop:
        ld      a,(de)
        inc     de
        cp      'A'
        jr      c,check_opt_notupper
        cp      'Z'+1
        jr      nc,check_opt_notupper
        or      $20                     ; convert uppercase to lowercase
check_opt_notupper:
        cp      (hl)
        jr      nz,option_mismatch
        inc     hl
        djnz    check_option_name_loop
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; DE=routine address
        pushval perform_option_end
        push    de
        ret                             ; execute the option routine
perform_option_end:
        xor     a                       ; Fz=1, option was found
        ret
option_mismatch:
        ld      a,b                     ; A=remaining characters to skip
skip_option:
        addhl_A_badFc()                 ; skip the option name
        inc     hl                      ; and the routine address
        inc     hl
        jr      check_next_option

invalid_option:
        ld      hl,temparg-1
        ld      a,c
        addhl_A_badFc()
        set     7,(hl)                  ; set error terminator at end of option
        ld      hl,msg_unknownoption
        jp      err_custom


; ***************************************************************************
; * Messages & data                                                         *
; ***************************************************************************

msg_unknownoption:
        defm    "Unknown option: "
temparg:
        defs    256
