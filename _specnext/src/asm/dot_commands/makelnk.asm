; ***************************************************************************
; * Dot command to make a .LNK file                                         *
; * .MAKELNK [options] targetfile [linkname]                                *
; ***************************************************************************

include "macros.def"
include "nexthw.def"
include "sysvars.def"
include "esxapi.def"


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************

        org     $2000

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
        jr      c,bad_nextzxos          ; must be esxDOS if error
        ld      hl,'N'<<8+'X'
        sbc     hl,bc                   ; check NextZXOS signature
        jr      nz,bad_nextzxos
        ld      hl,$0206
        ex      de,hl
        sbc     hl,de                   ; check version number >= 2.06
        jr      c,bad_nextzxos
        ld      hl,stderr_handler
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
        call    get_sizedarg            ; get first argument to filename
        jr      nc,show_usage           ; if none, just show usage
        call    check_options
        jr      z,parse_firstarg        ; if it was an option, try again
        ld      hl,temparg
        ld      de,target_name
        inc     bc                      ; include null terminator
        ldir                            ; use 1st arg as target name
parse_2ndarg:
        call    get_sizedarg            ; check if optional 2nd arg present
        jr      nc,lnk_start            ; done if not
        call    check_options
        jr      z,parse_2ndarg          ; if it was an option, try again
        ld      hl,temparg
        ld      de,link_name
        inc     bc                      ; include null terminator
        ldir                            ; use 2nd arg as link name
parse_3rdarg:
        call    get_sizedarg            ; check if any further args
        jr      nc,lnk_start            ; okay if not
        call    check_options
        jr      z,parse_3rdarg          ; if it was an option, try again
show_usage:
        ld      hl,msg_help
        call    printmsg
        and     a                       ; Fc=0, successful
        jr      error_handler           ; restore turbo setting and exit


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

error_handler:
        ld      sp,(saved_sp)           ; restore entry SP
restore_all:
        push    af
        ld      a,(file_handle)
        cp      $ff
        jr      z,restore_turbo
        callesx f_close                 ; close the file if necessary
restore_turbo:
        ld      a,(saved_turbo)
        nxtrega nxr_turbo               ; restore entry turbo setting
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
; * Create a link                                                           *
; ***************************************************************************

lnk_start:
        ; Find the target name in the target filespec
        ld      hl,target_name
new_target_segment:
        push    hl                      ; stack segment address
same_target_segment:
        ld      a,(hl)
        inc     hl
        and     a
        jr      z,got_target_segment    ; finished if end of filespec
        cp      '/'
        jr      z,got_segment_end
        cp      '\'
        jr      nz,same_target_segment  ; keep going within current segment
got_segment_end:
        pop     de                      ; discard previous segment start
        jr      new_target_segment      ; and back to stack new one

got_target_segment:
        pop     hl                      ; HL=start of target segment
        ld      (target_segstart),hl

        ; Get the path of the target
        ld      b,(hl)                  ; save first char of target segment
        ld      (hl),0                  ; and replace with 0 so not used as
        push    bc                      ; part of the path
        push    hl
        ld      a,$ff
        ld      de,target_name
        ld      hl,target_path
        callesx f_getcwd                ; get path for target file
        pop     hl
        pop     bc
        ld      (hl),b
        jr      c,error_handler

        ; Generate filespec for link file
        ld      de,link_fspec           ; DE=destination for filespec
        ld      a,(use_links)
        and     a
        jr      z,skip_links            ; on if not creating in c:/links
        ld      hl,msg_links
        push    de
        push    hl
        ld      a,'*'
        callesx f_mkdir                 ; create c:/links if it doesn't exist
        pop     hl
        pop     de
        ld      bc,msg_links_end-msg_links
        ldir                            ; prepend "c:/links"
        dec     de
        ld      a,'/'
        ld      (de),a                  ; now "c:/links/"
        inc     de
skip_links:
        ld      hl,link_name
        ld      a,(hl)
        and     a
        jr      nz,copy_link_name       ; use any provided link base name
        ld      hl,(target_segstart)    ; else use the target's name
copy_link_name:
        ld      a,(hl)
        ldi                             ; copy name
        and     a
        jr      nz,copy_link_name       ; until null terminator copied
        dec     de                      ; back up to null
        ld      hl,msg_dotlnk
        ld      bc,msg_dotlnk_end-msg_dotlnk
        ldir                            ; append ".lnk",0

        ; Create the .LNK file
        ld      a,'*'
        ld      hl,link_fspec
        ld      b,esx_mode_creat_trunc+esx_mode_write
        callesx f_open                  ; create the file
        jp      c,error_handler
        ld      (file_handle),a         ; save handle

        ; Generate the body of the .LNK file
        ld      hl,lnk_file_body
        ld      bc,261
        xor     a
        cpir                            ; find the null terminator of the path
        dec     hl
        ld      (hl),$0d                ; replace null with CR
        inc     hl
        ex      de,hl
        ld      hl,(target_segstart)
copy_target_loop:
        ld      a,(hl)
        ldi                             ; copy target name byte
        and     a
        jr      nz,copy_target_loop     ; until null copied
        ex      de,hl
        dec     hl
        ld      (hl),$0d                ; replace null with CR
        inc     hl
        ld      de,lnk_file_header      ; DE=start of file data
        sbc     hl,de                   ; HL=length

        ; Write the .LNK file data
        ex      de,hl
        ld      b,d
        ld      c,e
        ld      a,(file_handle)
        callesx f_write
        jp      c,error_handler

        ; Close the file and exit
        ld      a,(file_handle)
        callesx f_close
        jp      error_handler


; ***************************************************************************
; * Print a message                                                         *
; ***************************************************************************

include "printmsg.asm"


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
        defopt  "-l",option_links
        endopts()


; ***************************************************************************
; * -l                                                                      *
; ***************************************************************************

option_links:
        ld      a,1
        ld      (use_links),a
        ret


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

msg_help:
        defm    "MAKELNK v1.0 by Garry Lancaster",$0d
        defm    "Creates a .LNK file which,",$0d
        defm    "when selected in the Browser,",$0d
        defm    "will change to the target's",$0d
        defm    "directory and launch the file.",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    " .MAKELNK [OPT] TARGET [LINK]",$0d,$0d
        defm    "OPTIONS:",$0d
        defm    " -l",23,32,0
        defm    "   Make TARGET.LNK in C:/Links",$0d,$0d
        defm    $ff

msg_links:
        defm    "c:/links",0
msg_links_end:

msg_dotlnk:
        defm    ".lnk",0
msg_dotlnk_end:

msg_badnextzxos:
        defm    "Requires NextZXOS mod",'e'+$80


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

saved_sp:
        defw    0

saved_turbo:
        defb    0

file_handle:
        defb    $ff

target_name:
        defs    256

link_name:
        defs    256

use_links:
        defb    0                       ; 1 if link to be created in c:/links

target_segstart:
        defw    0

link_fspec:
        defs    9+256+4                 ; max is "c:/links/"+TARGETNAME+".lnk"

lnk_file_header:
        defm    "NextLink",$0d          ; header
lnk_file_body:
target_path:
        defs    261+1                   ; line with path
        defs    256+1                   ; line with target

command_tail:
        defw    0

data_end:

if (data_end > $4000)
.ERROR data_end exceeds available dot command space
endif
