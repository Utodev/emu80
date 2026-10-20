; ***************************************************************************
; * Argument handling for dot commands                                      *
; ***************************************************************************
; In order to include this file in dot command sources, a "show_usage"
; routine must be present.
;
; This routine will parse quoted or unquoted arguments from the command tail.
; Within a quoted argument, \ can be used to escape a quote.

; Define the variable ARG_PARAMS_DEHL before including:
; ARG_PARAMS_DEHL       equ     1       ; on entry: HL=tail address
                                        ;           DE=argument dest
; ARG_PARAMS_DEHL       equ     0       ; on entry: (command_tail)=tail addr
                                        ;           argument stored at temparg


; ***************************************************************************
; * Parse an argument from the command tail                                 *
; ***************************************************************************
; Entry: HL or (command_tail)=remaining command tail
;        argument is parsed to memory at DE or temparg
; Exit:  Fc=0 if no argument
;        Fc=1: parsed argument has been copied and null-terminated
;              command tail address is updated to after this argument
;        BC=length of argument
; NOTE: BC is validated to be 1..255; if not, it does not return but instead
;       exits via show_usage.

get_sizedarg:
if !ARG_PARAMS_DEHL
        ld      hl,(command_tail)
        ld      de,temparg
endif ; !ARG_PARAMS_DEHL
        ld      bc,0                    ; initialise size to zero
get_sizedarg_loop:
        ld      a,(hl)
        inc     hl
        and     a
        ret     z                       ; exit with Fc=0 if $00
        cp      $0d
        ret     z                       ; or if CR
        cp      ':'
        ret     z                       ; or if ':'
        cp      ' '
        jr      z,get_sizedarg_loop     ; skip any spaces
        cp      '"'
        jr      z,get_sizedarg_quoted   ; on for a quoted arg
get_sizedarg_unquoted:
        ld      (de),a                  ; store next char into dest
        inc     de
        inc     c                       ; increment length
        jr      z,get_sizedarg_badsize  ; don't allow >255
        ld      a,(hl)
        and     a
        jr      z,get_sizedarg_complete ; finished if found $00
        cp      $0d
        jr      z,get_sizedarg_complete ; or CR
        cp      ':'
        jr      z,get_sizedarg_complete ; or ':'
        cp      '"'
        jr      z,get_sizedarg_complete ; or '"' indicating start of next arg
        inc     hl
        cp      ' '
        jr      nz,get_sizedarg_unquoted; continue until space
get_sizedarg_complete:
        xor     a
        ld      (de),a                  ; terminate argument with NULL
        ld      a,b
        or      c
        jr      z,get_sizedarg_badsize  ; don't allow zero-length args
if !ARG_PARAMS_DEHL
        ld      (command_tail),hl       ; update command tail pointer
endif ; !ARG_PARAMS_DEHL
        scf                             ; Fc=1, argument found
        ret
get_sizedarg_quoted:
        ld      a,(hl)
        and     a
        jr      z,get_sizedarg_complete ; finished if found $00
        cp      $0d
        jr      z,get_sizedarg_complete ; or CR
        inc     hl
        cp      '"'                     ; if a quote, need to check if escaped or not
        jr      z,get_sizedarg_checkendquote
        ld      (de),a                  ; store next char into dest
        inc     de
        inc     c                       ; increment length
        jr      z,get_sizedarg_badsize  ; don't allow >255
        jr      get_sizedarg_quoted
get_sizedarg_badsize:
        pop     af                      ; discard return address
        jp      show_usage

get_sizedarg_checkendquote:
        inc     c
        dec     c
        jr      z,get_sizedarg_complete ; definitely endquote if no chars yet
        dec     de
        ld      a,(de)
        inc     de
        cp      '\'                     ; was it escaped?
        jr      nz,get_sizedarg_complete; if not, was an endquote
        dec     de
        ld      a,'"'
        ld      (de),a                  ; otherwise replace \ with "
        inc     de
        jr      get_sizedarg_quoted
