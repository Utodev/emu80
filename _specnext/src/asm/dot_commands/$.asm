; ***************************************************************************
; * Dot command with string argument executor                               *
; * .$                                                                      *
; ***************************************************************************

include "macros.def"
include "rom48.def"
include "sysvars.def"
include "esxapi.def"


; ***************************************************************************
; * Argument parsing                                                        *
; ***************************************************************************
; Dot commands always start at $2000, with HL=address of command tail
; (terminated by $00, $0d or ':').

        org     $2000

        push    hl
        ld      hl,zero_data_start
        ld      de,zero_data_start+1
        ld      bc,zero_data_end-zero_data_start-1
        ld      (hl),0
        ldir                            ; clear uninitialised data
        callesx m_dosversion            ; esxDOS or NextZXOS?
        jr      c,isesxdos              ; must be esxDOS if error
        ld      hl,'N'<<8+'X'
        sbc     hl,bc
        jr      z,isnextzxos
isesxdos:
        ld      hl,esxcmdname
        ld      de,commandname
        ld      bc,filename-commandname
        ldir                            ; replace "/DOT/" with "/BIN/"
        jr      notnextzxos
isnextzxos:
        callesx m_gethandle             ; close $'s handle, so the same handle
        callesx f_close                 ; will be used for the chained dot
notnextzxos:
        pop     hl
        ld      a,h
        or      l
        jr      z,show_usage            ; no tail provided if HL=0
        ld      de,filename
        call    get_sizedarg            ; get first argument to filename
        jr      nc,show_usage           ; if none, just go to show usage
        ld      (command_len),bc        ; store command length
        ld      de,varname
        call    get_sizedarg            ; get second argument to varname
        jr      nc,show_usage           ; if none, just go to show usage
        ld      (var_len),bc            ; store variable name length
        ld      de,varname
        ex      de,hl
        add     hl,bc
        dec     hl
        ex      de,hl
        ld      a,(de)
        cp      '$'                     ; last char must be '$'
        jr      nz,show_usage
        ld      de,0                    ; further args to ROM
        call    get_sizedarg            ; check if any further args
        jr      nc,string_start         ; okay if not
show_usage:
        ld      hl,msg_help
        call    printmsg
        and     a                       ; Fc=0, successful
        ret

string_start:
        ld      bc,(var_len)
        inc     bc
        call48k BC_SPACES_r3            ; reserve space for variable name
        dec     bc
        ld      hl,varname
        push    de
        ldir                            ; copy name to workspace
        ld      a,','                   ; append a delimiter
        ld      (de),a
        ld      hl,(CH_ADD)
        ex      (sp),hl
        ld      (CH_ADD),hl             ; set var name as interpretation pointer
        call48k LOOK_VARS_r3            ; search for the variable
        pop     de
        ld      (CH_ADD),de             ; restore interpretation pointer
        jr      nc,var_found
        call48k REPORT_2_r3             ; 2 Variable not found
var_found:
        ld      a,b
        and     %11100000
        cp      %01000000               ; must be a simple string
        jr      z,string_found
        call48k REPORT_A_r3             ; A Invalid argument
string_found:
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)                  ; BC=string length
        inc     hl                      ; HL=string address
trimstring:
        ld      a,b
        or      c
        jr      z,gotstring
        ld      a,(hl)
        cp      ' '
        jr      nz,gotstring            ; on when non-space encountered
        inc     hl                      ; trim the space
        dec     bc
        jr      trimstring
gotstring:
        ld      (string_len),bc         ; save string length
        inc     bc                      ; increment length for terminator
        push    hl
        push    bc
        ld      hl,routine_end-routine
        add     hl,bc                   ; add space for routine to load dot
        ld      bc,(command_len)
        add     hl,bc                   ; add space for command name
        inc     hl                      ; and a separating space
        ld      b,h
        ld      c,l
        call48k BC_SPACES_r3            ; reserve workspace for string
        ld      (name_addr),de          ; save start of command name in workspace
        ld      hl,filename
        ld      bc,(command_len)
        ldir                            ; copy command in
        ld      a,' '
        ld      (de),a                  ; insert separating space
        inc     de
        pop     bc
        pop     hl
        ld      (string_addr),de        ; save start of string in workspace
        ldir                            ; copy string+1 byte
        dec     de
        ld      a,$0d
        ld      (de),a                  ; place terminator in final byte
        inc     de                      ; DE=address after string
        push    de
        ld      hl,routine
        ld      bc,routine_end-routine
        ldir                            ; copy routine into RAM workspace
        ld      a,'$'
        ld      hl,commandname
        ld      b,esx_mode_read+esx_mode_open_exist
        callesx f_open                  ; attempt to open dot command
        pop     hl                      ; HL=address of RAM routine
        ret     c                       ; exit with any error
        jp      (hl)                    ; execute rest of routine in RAM


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
        ret


; ***************************************************************************
; * Print a message                                                         *
; ***************************************************************************

include "printmsg.asm"


; ***************************************************************************
; * Routine to be executed in main RAM workspace                            *
; ***************************************************************************

routine:
        ld      hl,(string_addr)
        push    hl                      ; save address of argument for command
        ld      hl,(name_addr)
        push    hl                      ; save address of full command line
        ld      hl,$2000
        ld      bc,$2000
        callesx f_read                  ; read dot command into dot area
        pop     bc                      ; BC=address of full command line
        pop     hl                      ; HL=address of argument
        ret     c                       ; exit if error reading
        jp      $2000                   ; jump to execute new dot command
routine_end:


; ***************************************************************************
; * Argument parsing                                                        *
; ***************************************************************************

ARG_PARAMS_DEHL         equ     1
include "arguments.asm"


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

msg_help:
        defm    "$ v1.4 by Garry Lancaster",$0d
        defm    "Executes any dot command with a",$0d
        defm    "string argument.",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    " .$ <COMMAND> <STRINGNAME>$",$0d,$0d
        defm    "INFO:",$0d
        defm    "eg:  LET x$=",'"',"myfile.dsk",'"',$0d
        defm    "     .$ DEFRAG x$",$0d,$0d
        defm    "does the same as:",$0d
        defm    "     .DEFRAG myfile.dsk",$0d,0


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

esxcmdname:
        defm    "/BIN/"

commandname:
        defm    "/DOT/"

; The following data is cleared to zeros at startup.
filename        equ     $
varname         equ     filename+256
routine_addr    equ     varname+256
name_addr       equ     routine_addr+2
string_addr     equ     name_addr+2
string_len      equ     string_addr+2
var_len         equ     string_len+2
command_len     equ     var_len+2

zero_data_start equ     filename
zero_data_end   equ     command_len+2
