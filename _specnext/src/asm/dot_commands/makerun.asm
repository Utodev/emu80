; ***************************************************************************
; * Dot command to make a runnable directory                                *
; * .MAKERUN targetfile                                                     *
; ***************************************************************************

include "macros.def"
include "nexthw.def"
include "rom48.def"
include "sysvars.def"
include "bastoken.def"
include "esxapi.def"
include "nextzxos.def"


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************

        org     $2000

makerun_init:
        ld      (saved_sp),sp           ; save entry SP for error handler
        push    hl                      ; save address of arguments
        ld      a,(saved_sp+1)
        cp      $a0                     ; is SP < $a000?
        ld      a,nxr_mmu5
        jr      c,got_mmuid             ; if so, use MMU5 for banking
        ld      a,nxr_mmu3              ; otherwise, use MMU3
                                        ; NOTE: MMU3/5 are safe from being
                                        ;       paged out when making NextZXOS
                                        ;       calls (unlike MMU0/1/6/7)
got_mmuid:
        ld      (mmu_id),a
        ld      bc,next_reg_select
        out     (c),a
        inc     b
        in      a,(c)                   ; get bank currently bound to MMU
        ld      (saved_mmu_binding),a
        dec     b                       ; BC=next_reg_select again
        ld      a,nxr_turbo
        out     (c),a
        inc     b
        in      a,(c)                   ; get current turbo setting
        ld      (saved_turbo),a
        ld      a,turbo_max
        out     (c),a                   ; and set to maximum
        callesx m_dosversion
        jr      c,bad_nextzxos          ; must be esxDOS if error
        ld      (lang_code),hl          ; save language code
        ld      hl,'N'<<8+'X'
        sbc     hl,bc                   ; check NextZXOS signature
        jr      nz,bad_nextzxos
        ld      hl,$0206
        ex      de,hl
        sbc     hl,de                   ; check version number >= 2.06
        jr      c,bad_nextzxos
        ld      hl,stderr_handler
        callesx m_errh                  ; install error handler to reset turbo
        call    allocate_bank
        ld      (bank_input),a          ; allocate bank for tokenising
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
        ld      de,filename
        call    get_sizedarg            ; get first argument to filename
        jr      nc,show_usage           ; if none, just show usage
        ld      (filename_len),bc       ; store filename length
        ld      de,0                    ; further args to ROM
        call    get_sizedarg            ; check if any further args
        jr      nc,makefile_start       ; okay if not
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
        push    hl
        call    unbind_io_bank          ; restore bank originally bound to MMU
        ld      hl,bank_allocs
        call    dealloc_banks           ; de-allocate all i/o banks
        call    reclaim_line            ; reclaim any tokenised line from E_LINE
        ld      a,(saved_turbo)
        nxtrega nxr_turbo               ; restore entry turbo setting
        pop     hl
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
; * Create a runnable directory                                             *
; ***************************************************************************

makefile_start:
        ; Check we are in a subdirectory
        ld      a,'*'
        ld      hl,pathname
        push    hl
        callesx f_getcwd                ; get current path
        pop     de
        jp      c,error_handler
        ld      b,0
find_pathend_loop:
        ld      a,(de)
        and     a
        jr      z,got_pathend
        inc     de
        inc     b
        jr      find_pathend_loop
got_pathend:
        ld      a,b
        cp      2
        ld      hl,msg_notsub
        jr      c,err_custom            ; not subdirectory if path < 2 chars
        dec     de
        ld      a,(de)
        cp      '/'
        jr      nz,err_custom           ; must have terminating slash
        dec     de
        ld      a,(de)
        cp      ':'
        jr      z,err_custom            ; must not be root of a drive

        ; Check that the target file exists
        ld      a,'*'
        ld      hl,filename
        ld      b,esx_mode_read+esx_mode_open_exist
        callesx f_open                  ; open target file
        jr      c,error_handler         ; cause any error
        callesx f_close                 ; close target file again

        ; Read browser.cfg
        ld      a,'*'
        ld      hl,cfgfilename
        ld      b,esx_mode_read+esx_mode_open_exist
        callesx f_open                  ; open browser.cfg
        ld      hl,msg_badcfgfile
        jr      c,err_custom            ; error if couldn't open
        ld      (filehandle),a          ; save file handle
        ld      hl,filedata
        ld      de,filedata+1
        ld      (hl),0
        ld      bc,2048
        push    bc
        push    hl
        ldir                            ; fill filedata with terminator
        pop     hl
        pop     bc
        ld      a,(filehandle)
        callesx f_read                  ; read browser.cfg data
        push    af                      ; save error status
        ld      a,(filehandle)
        callesx f_close                 ; close browser.cfg
        pop     af
        ld      hl,msg_badcfgfile
        jp      c,err_custom            ; error if couldn't read

        ; Find extension of the target filename
        ld      hl,filename
        ld      de,0                    ; initialise extension start
        ld      c,0                     ; initialise extension length
findext_loop:
        ld      a,(hl)                  ; get next char
        inc     hl
        and     a
        jr      z,findext_end           ; done if terminator found
        inc     c                       ; increment possible extension length
        cp      '.'                     ; possible extension start?
        jr      nz,findext_notext       ; on if not
        ld      d,h
        ld      e,l                     ; DE=possible extension start
        ld      c,0                     ; C=current extension length
        jr      findext_loop
findext_notext:
        cp      ' '                     ; space in filename
        jr      nz,findext_loop
        ld      (name_spaces),a         ; note for future reference
        jr      findext_loop
findext_end:
        ld      (ext_addr),de           ; save address of extension
        ld      a,d
        and     a                       ; was an extension found
unsupported_ext:
        ld      hl,msg_unsupported
        jp      z,err_custom            ; error if not
        ld      a,c
        and     a
        jp      z,err_custom            ; or if zero length
        cp      4
        jp      nc,err_custom           ; or if length > 3

        ; Find the target file's extension in the browser.cfg data
        ld      hl,filedata
findhandler_loop:
        ld      a,(hl)                  ; get next char
        call    check_term              ; CR/LF/terminator?
        jr      z,checkend_skip_line    ; deal with blank lines/end of data
        ld      b,c                     ; number of chars in extension
        ld      de,(ext_addr)
        call    match_extension         ; does this line match our extension?
        jr      z,found_handler         ; on if so
checkend_skip_line:
        ld      a,(hl)                  ; get next char
        inc     hl
        call    check_eol               ; CR/LF?
        jr      z,findhandler_loop      ; back for next line if so
        and     a
        jr      z,unsupported_ext       ; failed if end of browser.cfg data
        jr      checkend_skip_line

        ; Generate untokenised command line
found_handler:
        inc     hl                      ; skip past hander separator
        ld      a,(bank_input)          ; bind bank to hold untokenised text
        call    bind_io_bank
        ld      a,(mmu_id)              ; NXR_MMU3 (@ $6000)/NXR_MMU5 (@ $a000)
        sub     nxr_mmu0                ; A=3 or 5
        add     a,a                     ; A=$06 or $0a
        swapnib()                       ; A=$60 or $a0
        ld      d,a
        ld      e,0                     ; HL=$6000 or $a000
gen_line_loop:
        ld      a,(hl)                  ; get next char of handler text
        inc     hl
        ld      (de),a                  ; copy to untokenised text bank
        cp      $0d
        jr      z,gen_line_done         ; finished if CR
        cp      $0a
        jr      z,gen_line_done         ; or LF
        and     a
        jr      z,gen_line_done         ; or terminator
        cp      $60                     ; backtick? (pound/currency symbol on ZX)
        jr      z,gen_currency          ; convert to currency code if so
        cp      $7f                     ; copyright symbol?
        jr      z,gen_sysdir            ; insert c:/nextzxos/ if so
        cp      '|'                     ; vertical bar? (insert filename)
        jr      z,gen_filename
gen_line_next_char:
        inc     de
        jr      gen_line_loop

gen_currency:
        ld      a,(lang_code)
        ld      (de),a                  ; replace $60 with 1st language code
        inc     de
        ld      a,(lang_code+1)
        ld      (de),a                  ; append 2nd language code char
        jr      gen_line_next_char

gen_sysdir:
        push    hl
        ld      hl,msg_sysdir
gen_sysdir_loop:
        ld      a,(hl)
        ld      (de),a                  ; copy path character
        inc     hl
        inc     de
        and     a
        jr      nz,gen_sysdir_loop      ; until null-terminator
        dec     de                      ; back up to replace terminator
        pop     hl
        jr      gen_line_loop

gen_filename:
        push    hl                      ; save handler address
        dec     de
        ld      a,(de)
        inc     de
        cp      '"'                     ; was last char a quote?
        jr      z,gen_filename_ok       ; okay if so
        ld      a,(name_spaces)
        and     a                       ; does filename contain spaces?
        ld      hl,msg_nospaces
        jp      nz,err_custom           ; not supportable if so
gen_filename_ok:
        ld      hl,filename
gen_filename_loop:
        ld      a,(hl)                  ; get next filename char
        inc     hl
        and     a
        jr      z,gen_filename_done     ; finish copy if end of name
        ld      (de),a                  ; copy into untokenised text
        inc     de
        jr      gen_filename_loop
gen_filename_done:
        pop     hl                      ; restore handler address
        jr      gen_line_loop

gen_line_done:
        ld      a,$0d
        ld      (de),a                  ; ensure last char is CR
        call    unbind_io_bank          ; unbind the bank

        ; Tokenise the command line and generate RUN.BAS file
        ld      hl,$0000                ; offset in bank
        ld      a,(bank_input)
        ld      c,a                     ; bank id
        ld      b,0                     ; tokenise
        callp3d ide_tokeniser,0         ; call IDE_TOKENISER
        jr      nc,tokenise_bad
        jr      nz,tokenise_okay
tokenise_bad:
        ld      hl,msg_tokenfail        ; report any call or syntax error
        jp      err_custom
tokenise_okay:
        push    bc                      ; save tokenised line data length
        inc     bc                      ; body will be prefixed with ':'
        ld      (tokline_len),bc        ; save total line length
                                        ; in BASIC program image
        ld      de,basic_linebody
        ldir                            ; copy tokenised line
        pop     hl
        addhl_N basic_linebody-basic_program    ; total length of BASIC program
        ld      (basic_proglength),hl   ; store in +3DOS header fields
        ld      (basic_filelength),hl
        push    hl                      ; save total length
        ld      a,'*'
        ld      hl,runname
        ld      de,basic_header
        ld      b,esx_mode_write+esx_mode_use_header+esx_mode_creat_trunc
        callesx f_open                  ; create RUN.BAS
        jp      c,error_handler
        ld      (outhandle),a           ; save file handle
        ld      hl,basic_program
        pop     bc                      ; BC=total length
        callesx f_write                 ; write contents of RUN.BAS
        push    af                      ; save error status
        ld      a,(outhandle)
        callesx f_close                 ; close RUN.BAS
        jp      c,error_handler
        pop     af                      ; restore error status from write
        jp      c,error_handler

        ; Find any documentation file
        ld      hl,tbl_doctypes
        push    hl                      ; undo next pop
next_doctype:
        pop     hl                      ; restore location in doctypes table
        ld      de,(ext_addr)
        ld      a,(hl)
        and     a
        jp      z,rename_directory      ; on if no more doctypes to try
copy_doctype:
        ld      a,(hl)                  ; copy each char
        inc     hl
        ld      (de),a
        inc     de
        and     a
        jr      nz,copy_doctype         ; until terminator copied
        push    hl                      ; save location in doctypes table
        ld      a,'*'
        ld      hl,filename
        ld      b,esx_mode_read+esx_mode_open_exist
        callesx f_open                  ; try to open documentation type
        jr      c,next_doctype          ; back for other types if failed
        ld      (filehandle),a          ; save file handle
        ld      a,'*'
        ld      hl,gdename
        ld      b,esx_mode_write+esx_mode_creat_trunc
        callesx f_open                  ; create RUN.GDE
        jp      c,docopen_error
        ld      (outhandle),a           ; save file handle
        xor     a                       ; Fc=0 for SBC below, A=0
        ld      (linelen),a             ; current line length
        pop     hl                      ; HL=location in doctypes table
        ld      bc,tbl_doctype_gde_end
        sbc     hl,bc
        ld      a,h
        or      l
        ld      (doctype),a             ; save doc type (0=.GDE)
        jr      z,copy_doc_loop         ; on if it's a .GDE
        ld      hl,dummy_node
        ld      bc,dummy_node_end-dummy_node
        ld      a,(outhandle)
        callesx f_write                 ; write dummy node for other types
        jr      c,docwrite_error
copy_doc_loop:
        ld      hl,basic_linebody
        ld      bc,2048
        ld      a,(filehandle)
        callesx f_read                  ; read next 2K of documentation, BC=size
        jr      c,docwrite_error
        ld      a,b
        or      c
        jr      z,copy_doc_end          ; finished if nothing read
        ld      hl,basic_linebody
        ld      a,(doctype)
        and     a
        jr      z,copy_doc_fullbuf      ; if .GDE, copy entire buffer
        push    hl                      ; TOS=address to write from
        ld      a,(linelen)             ; A=length of current line
copy_doc_newline:
        ld      de,0                    ; DE=size to write
copy_doc_parseloop:
        ex      af,af'                  ; A'=length of current line
        ld      a,b
        or      c
        jr      z,copy_doc_nextbuf      ; refill buffer if processed
        dec     bc
        inc     de
        ld      a,(hl)
        inc     hl
        cp      $0d
        jr      z,copy_doc_endline
        cp      $0a
        jr      nz,copy_doc_gotchar
copy_doc_endline:
        xor     a                       ; reset current line length
        jr      copy_doc_parseloop
copy_doc_gotchar:
        ex      af,af'
        inc     a                       ; increment current line length
        cp      81
        jr      c,copy_doc_parseloop    ; okay unless exceeds 80
        dec     hl                      ; back up to char 81
        inc     bc                      ; and allow it to be re-parsed
        ld      a,(hl)                  ; save for later
        ld      (hl),$0d                ; and replace with CR
        ex      (sp),hl                 ; HL=address to write from
        push    af                      ; save replaced char
        push    bc                      ; save bytes left to parse
        ld      b,d
        ld      c,e                     ; BC=bytes to write
        ld      a,(outhandle)
        callesx f_write                 ; write section, including CR
        jr      c,docwrite_error
        pop     bc                      ; restore bytes left to parse
        pop     de
        pop     hl
        push    hl
        ld      (hl),d                  ; restore replaced char
        xor     a                       ; reset current line length
        jr      copy_doc_newline        ; back to process remainder of buffer
copy_doc_nextbuf:
        pop     hl                      ; HL=position to write from
        ex      af,af'
        ld      (linelen),a             ; save current line length
        ld      a,d
        or      e
        jr      z,copy_doc_loop         ; nothing more to write in this buffer
        ld      b,d
        ld      c,e                     ; BC=bytes to write
copy_doc_fullbuf:
        ld      a,(outhandle)
        callesx f_write                 ; write remainder of buffer
        jr      nc,copy_doc_loop        ; back for more
docwrite_error:
        push    af
        ld      a,(outhandle)
        callesx f_close                 ; close the output file
        pop     af
docopen_error:
        push    af
        ld      a,(filehandle)
        callesx f_close                 ; close the input file
        pop     af
        jp      error_handler
copy_doc_end:
        ld      a,(filehandle)
        callesx f_close                 ; close the input file
        ld      a,(outhandle)
        callesx f_close                 ; close the output file
        jp      c,error_handler         ; and cause any error

        ; Rename the directory to .run
rename_directory:
        ld      a,'*'
        ld      hl,msg_parent
        ld      b,esx_mode_lfn_only+esx_mode_use_wildcards
        callesx f_opendir               ; open parent's directory handle
        jp      c,error_handler
        ld      (dirhandle),a
        ld      hl,pathname
        ld      d,h                     ; initialise pointer to dir name
        ld      e,l
find_dirname:
        ld      a,(hl)
        inc     hl
        cp      ':'                     ; check for each new segment
        jr      z,dir_newseg
        cp      '/'
        jr      z,dir_newseg
        and     a
        jr      nz,find_dirname         ; until terminator found
        jr      got_dirname
dir_newseg:
        ld      a,(hl)                  ; does terminator follow?
        and     a
        jr      z,dir_gotend
        ld      d,h                     ; if not update DE to new segment
        ld      e,l
        jr      find_dirname
dir_gotend:
        dec     hl
        ld      (hl),0                  ; strip terminating '/'
got_dirname:
        ld      a,(dirhandle)
        ld      hl,dirname_long
        callesx f_readdir               ; read entry using short dirname as wildcard
        push    af                      ; save any error return
        ld      a,(dirhandle)
        callesx f_close                 ; close directory handle
        pop     af
        jp      c,error_handler
        and     a
        ld      hl,msg_nodirname        ; error if no entry returned
        jp      z,err_custom
        ld      hl,dirname_long         ; long name
        ld      (hl),'/'                ; replace attributes with '/'
        ld      b,-1
find_dirname_end_loop:
        ld      a,(hl)                  ; get next char
        inc     hl
        inc     b                       ; increment name length
        and     a
        jr      nz,find_dirname_end_loop; until null terminator
        dec     hl
        push    hl                      ; save terminator address
        ld      a,b
        cp      5                       ; if <5 chars, doesn't already have .run
        jr      c,append_dotrun
        dec     hl
        ld      a,(hl)                  ; check for existing .run or .RUN
        cp      'n'
        jr      z,append_check_u
        cp      'N'
        jr      nz,append_dotrun
append_check_u:
        dec     hl
        ld      a,(hl)
        cp      'u'
        jr      z,append_check_r
        cp      'U'
        jr      nz,append_dotrun
append_check_r:
        dec     hl
        ld      a,(hl)
        cp      'r'
        jr      z,append_check_dot
        cp      'R'
        jr      nz,append_dotrun
append_check_dot:
        dec     hl
        ld      a,(hl)
        cp      '.'
        jp      z,error_handler         ; exit with success if already .run
append_dotrun:
        pop     de                      ; DE=address to append .run
        ld      hl,msg_dotrun
        ld      bc,msg_dotrun_end-msg_dotrun
        ldir                            ; append .run
        ld      a,'*'
        ld      hl,pathname
        ld      de,dirname_withdots
        callesx f_rename                ; rename the directory
        jp      error_handler           ; exit with any error from rename


; ***************************************************************************
; * Match an extension                                                      *
; ***************************************************************************
; Entry: DE=extension of file
;        B=extension length
;        HL=string to match with (case-insensitive, may include ? or *)
; Exit:  Fz=0, extension did not match
;        Fz=1, extension did match and:
;          HL=address after extension string
;          BC,DE preserved

match_extension:
        push    bc              ; save extension length
        push    de              ; save extension address
me_extloop:
        ld      a,(hl)
        cp      '*'             ; all remaining chars matched by *
        inc     hl
        jr      z,me_skipothers ; exit with Fz=1, HL after * if so
        call    make_lower      ; convert to lower-case
        ld      c,a
        ld      a,(de)          ; get next extension character to check
        inc     de
        call    make_lower      ; convert to lower-case
        cp      c               ; check for match
        jr      z,me_matchchar
        ld      a,c
        cp      '?'             ; any character is matched by ?
        jr      nz,me_trynext   ; on to try another ext if chars didn't match
me_matchchar:
        djnz    me_extloop      ; until all chars matched
me_skipothers:
        pop     de              ; restore extension address
        pop     bc              ; and length
        ld      a,(hl)
        cp      ','             ; another extension?
        ; if not, exit via check for separator, which must follow ext list
        jr      nz,check_sep
me_skipext:
        inc     hl
        ld      a,(hl)
        call    check_sep
        ret     z               ; exit once separator found
        call    check_term
        jr      nz,me_skipext   ; keep going unless EOL/terminator
me_fail:
        xor     a
        inc     a               ; Fz=0,failed
        ret

me_trynext:
        pop     de              ; restore extension address
        pop     bc              ; and length
me_trynext_loop:
        ld      a,(hl)
        cp      ','                     ; another extension?
        inc     hl
        jr      z,match_extension       ; if so, back to try it
        call    check_sep
        jr      z,me_fail               ; fail if separator found
        call    check_term
        jr      z,me_fail               ; or of EOL/terminator found
        jr      me_trynext_loop


; ***************************************************************************
; * Convert letters to lower-case                                           *
; ***************************************************************************
; Entry: A=character
; Exit:  A=character, modified if necessary

make_lower:
        cp      'A'
        ret     c
        cp      'Z'+1
        ret     nc
        set     5,a             ; convert upper-case letters to lower-case
        ret


; ***************************************************************************
; * Check for end-of-extension separator                                    *
; ***************************************************************************
; Entry: A=character
; Exit:  Fz=1 if ':', ';' or '<'

check_sep:
        cp      ':'
        ret     z
        cp      ';'
        ret     z
        cp      '<'
        ret


; ***************************************************************************
; * Check for end-of-line, terminator                                       *
; ***************************************************************************
; Enter: A=char
; Exit:  Fz=1 if $0d, $0a (and null-terminator if entering at check_term)

check_term:
        and     a
        ret     z
check_eol:
        cp      $0d
        ret     z
        cp      $0a
        ret


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
; * Allocate a bank                                                         *
; ***************************************************************************
; Exit: A=bank id

allocate_bank:
        ld      hl,$0001                ; allocate a ZX bank
        callp3d ide_bank,7
        ld      a,e                     ; A=bank id
        ret     c                       ; exit if successfull
out_of_memory:
        ld      hl,msg_oom
        jp      err_custom              ; error if allocation failed


; ***************************************************************************
; * Deallocate banks                                                        *
; ***************************************************************************
; Entry: HL=address of bank id list to deallocated, terminated with 0

dealloc_banks:
        ld      a,(hl)
        and     a
        ret     z                       ; exit when terminator found
        push    hl
        ld      e,a                     ; E=bank id to free
        ld      hl,$0003                ; free a ZX bank
        callp3d ide_bank,7
        pop     hl
        ld      (hl),0                  ; clear bank id
        inc     hl
        jr      dealloc_banks


; ***************************************************************************
; * Bind the I/O bank into memory                                           *
; ***************************************************************************
; Entry: A=bank id

bind_io_bank:
        push    bc
        push    af
        ld      bc,next_reg_select
        ld      a,(mmu_id)
        out     (c),a
        inc     b
        pop     af
        out     (c),a                   ; bind bank to MMU
        pop     bc
        ret


; ***************************************************************************
; * Unbind the I/O bank from memory                                         *
; ***************************************************************************

unbind_io_bank:
        push    bc
        ld      bc,next_reg_select
        ld      a,(mmu_id)
        out     (c),a
        inc     b
        ld      a,(saved_mmu_binding)
        out     (c),a                   ; bind original binding to MMU
        pop     bc
        ret


; ***************************************************************************
; * Reclaim the tokenised or partly-tokenised line                          *
; ***************************************************************************
; NOTE: It is important to ensure this is always done before returning to
;       BASIC, because the newly-tokenised line is inserted at the start of
;       the E_LINE area, with the original contents directly following it.
;       Reclaiming the space ensures that the original contents of E_LINE
;       (ie the current direct command) are restored.
;       Therefore we also call this as part of our error handler.

reclaim_line:
        ld      hl,(E_LINE)
        ld      bc,(tokline_len)
        ld      a,b
        or      c
        ret     z                       ; exit if nothing to reclaim
        call48k RECLAIM_2
        ld      hl,0
        ld      (tokline_len),hl
        ret


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

msg_help:
        defm    "MAKERUN v1.1 by Garry Lancaster",$0d
        defm    "Converts the current directory",$0d
        defm    "into a runnable directory.",$0d,$0d
        defm    "A RUN.BAS file that loads the",$0d
        defm    "target file (any supported by",$0d
        defm    "the Browser) is created and",$0d
        defm    "the directory is renamed with",$0d
        defm    "a .run extension.",$0d,$0d
        defm    "Any file with the same name",$0d
        defm    "and a .gde, .txt, .doc or .md",$0d
        defm    "extension will be copied to a",$0d
        defm    "RUN.GDE file as documentation.",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    " .MAKERUN targetfile",$0d,0

msg_parent:
        defm    "..",0

msg_dotrun:
        defm    ".run",0
msg_dotrun_end:

msg_badnextzxos:
        defm    "Requires NextZXOS mod",'e'+$80

msg_badcfgfile:
        defm    "Error reading browser.cf",'g'+$80

msg_notsub:
        defm    "Not a subdirector",'y'+$80

msg_unsupported:
        defm    "Unsupported file typ",'e'+$80

msg_oom:
        defm    "Out of memor",'y'+$80

msg_nospaces:
        defm    "Type disallows spaces in nam",'e'+$80

msg_tokenfail:
        defm    "Tokenisation faile",'d'+$80

msg_nodirname:
        defm    "No directory nam",'e'+$80

msg_sysdir:
        defm    "c:/nextzxos/",0


; ***************************************************************************
; * Table of supported documentation types                                  *
; ***************************************************************************

tbl_doctypes:
        defm    "GDE",0
tbl_doctype_gde_end:
        defm    "TXT",0
        defm    "DOC",0
        defm    "MD",0
        defb    0                       ; table terminator

; Dummy node for non-.GDE types

dummy_node:
        defm    "@node main",$0d,$0a
dummy_node_end:


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

saved_sp:
        defw    0

saved_turbo:
        defb    0

saved_mmu_binding:
        defb    0

mmu_id:
        defb    0

mmu_addr:
        defw    0

bank_input:
        defb    0
bank_terminator:
        defb    0

bank_allocs     equ     bank_input      ; first bank for dealloction loop

lang_code:
        defw    0

filename_len:
        defw    0

filename:
        defs    256+3                   ; with space to replace extensions

ext_addr:
        defw    0

filehandle:
        defb    0

outhandle:
        defb    0

dirhandle:
        defb    0

linelen:
        defb    0

doctype:
        defb    0

name_spaces:
        defb    0                       ; non-zero if filename contains spaces

runname:
        defm    "run.bas",0

gdename:
        defm    "run.gde",0

cfgfilename:
        defm    "c:/nextzxos/browser.cfg",0

; This data forms the 8-byte +3DOS header for the BASIC program

basic_header:
        defb    0                       ; type 0=BASIC program
basic_filelength:
        defw    0                       ; full file length
        defw    10                      ; auto-start line 10
basic_proglength:
        defw    0                       ; length excluding variables
        defb    0                       ; unused

; This data forms the BASIC program that gets saved

basic_program:
        defb    0,10                    ; line 10 (MSB first)
        defw    line10_end-line10_start
line10_start:
        defb    token_randomize,token_usr,token_val,'"'
        defm    "(6+",token_peek,"23637+256*",token_peek,"23638)"
        defb    '"',$0d
line10_end:
        defb    0,20                    ; line 20 (MSB first)
        defw    line20_end-line20_start
line20_start:
        defm    token_rem
        defb    $0d
line20_exec:
        push    bc                      ; save address of line 20 number
        call    SET_MIN                 ; clear E_LINE and other workspace
        pop     hl                      ; HL=address of line 20 number
        addhl_N tokline_len-line20_exec
        ld      c,(hl)
        inc     hl
        ld      b,(hl)                  ; BC=length of tokenised line
        dec     bc                      ; excluding CR which is already in E_LINE
        inc     hl                      ; HL=address of tokenised line data
        push    bc
        push    hl
        ld      hl,(E_LINE)
        call    MAKE_ROOM               ; make required space at E_LINE
        pop     hl
        pop     bc
        ld      de,(E_LINE)
        push    de
        ldir                            ; copy tokenised line to E_LINE
        pop     hl
        ld      (CH_ADD),hl             ; store as current interpretation pointer
        ld      hl,-2
        ld      (PPC),hl                ; "direct command" line number
        ld      hl,(WORKSP)
        dec     hl
        ld      (NXTLIN),hl             ; "next" line is $80 marker in E_LINE
        ld      bc,0                    ; value for RANDOMIZE
        ret                             ; exit to interpret tokenised line
        defb    $0d
line20_end:

        defb    0,30                    ; line 30 (MSB first)
tokline_len:
        defw    0                       ; length of tokenised line
        defb    ':'                     ; ends previous command
basic_linebody:
        defs    2048+256+1              ; enough space for full filename plus
                                        ; browser.cfg just in case, + CR

; Re-use BASIC line body space for browser.cfg filedata which needs less space.
filedata        equ     basic_linebody

pathname:
        defs    261

dirname_withdots:
        defm    ".."
dirname_long:
        defs    1+261+8                 ; readdir returns: attr byte, filename,
                                        ; 8 bytes of further data
dirname_long_end:

if (dirname_long_end > $4000)
.ERROR dirname_long exceeds available dot command space
endif
