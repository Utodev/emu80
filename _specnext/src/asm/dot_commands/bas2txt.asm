; ***************************************************************************
; * Dot command to convert .BAS files to plain text .TXT                    *
; ***************************************************************************
; NOTE: Output is currently written unbuffered, which saves having to worry
;       whether a detokenise operation will overflow the current output bank.

include "macros.def"
include "nexthw.def"
include "sysvars.def"
include "esxapi.def"
include "nextzxos.def"
include "bastoken.def"
include "rom48.def"


; ***************************************************************************
; * Internal definitions                                                    *
; ***************************************************************************

MIN_NEXTZXOS_VER        equ     $0201   ; v2.01 needed for IDE_TOKENISER


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************

        org     $2000

bas2txt_init:
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
        jp      c,bad_nextzxos          ; must be esxDOS if error
        ld      hl,'N'<<8+'X'
        sbc     hl,bc                   ; check NextZXOS signature
        jp      nz,bad_nextzxos
        ld      hl,MIN_NEXTZXOS_VER
        ex      de,hl
        sbc     hl,de                   ; check version number
        jp      c,bad_nextzxos
        ld      hl,stderr_handler
        callesx m_errh                  ; install error handler to reset turbo
        call    allocate_bank
        ld      (bank_input),a          ; allocate the input buffer bank
        call    allocate_bank
        ld      (bank_output0),a        ; allocate the output buffer bank
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
        ld      hl,temparg
        inc     bc                      ; include null terminator
        push    hl
        push    bc
        ld      de,fname_bas
        ldir                            ; use 1st arg as .BAS/.BNK filename
        pop     bc
        pop     hl
        ld      de,progname
        ldir                            ; and as default progname base
        call    format_progname         ; strip the extension
        ld      (output_ext),hl         ; store address of extension
        ld      de,progname
        and     a
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; BC=base length
        ex      de,hl
        ld      de,fname_txt
        jr      z,gen_fname_txt
        ldir                            ; copy base name to fname_txt
gen_fname_txt:
        ld      hl,msg_dottxt
        ld      bc,msg_dottxt_end-msg_dottxt
        ldir                            ; with ".txt" appended
parse_2ndarg:
        call    get_sizedarg            ; get an argument
        jr      nc,bas2txt_start        ; start processing if no more args
        call    check_options
        jr      z,parse_2ndarg          ; if it was an option, try again
        ld      hl,temparg
        inc     bc                      ; include null terminator
        ld      de,fname_txt
        ldir                            ; use 2nd arg as .TXT filename
parse_remaining:
        call    get_sizedarg            ; get an argument
        jr      nc,bas2txt_start        ; start processing if no more args
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
restore_all:
        push    af
        push    hl
        call    unbind_io_bank          ; restore bank originally bound to MMU
        ld      hl,bank_allocs
dealloc_loop:
        ld      a,(hl)
        inc     hl
        and     a
        jr      z,nodealloc             ; continue until unallocated/terminator
        push    hl
        ld      e,a                     ; E=bank id to free
        ld      hl,$0003                ; free a ZX bank
        callp3d ide_bank,7
        pop     hl
        jr      dealloc_loop
nodealloc:
        ld      a,(saved_turbo)
        nxtrega nxr_turbo               ; restore entry turbo setting
        ld      a,(process_bnks)
        cp      2
        jr      nz,error_done
        ld      a,(dir_handle)
        callesx f_close                 ; close any in-use directory handle
error_done:
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
; * Main operation                                                          *
; ***************************************************************************

bas2txt_start:
        ld      a,'*'
        ld      hl,fname_txt
        ld      b,esx_mode_write+esx_mode_creat_trunc
        callesx f_open                  ; create the .TXT file
        jr      c,error_handler
        ld      (fhandle_txt),a         ; save the handle
        ld      a,(mmu_id)              ; NXR_MMU3 (@ $6000)/NXR_MMU5 (@ $a000)
        sub     nxr_mmu0                ; A=3 or 5
        add     a,a                     ; A=$06 or $0a
        swapnib()                       ; A=$60 or $a0
        ld      h,a
        ld      l,0                     ; HL=$6000 or $a000
        ld      (mmu_addr),hl           ; save it
        ld      (bufout_addr),hl        ; initialise output buffer pointer
open_new_input:
        ld      a,'*'
        ld      hl,fname_bas
        ld      de,header_buf
        ld      b,esx_mode_read+esx_mode_use_header+esx_mode_open_exist
        callesx f_open                  ; open the .BAS file
        jr      c,error_handler
        ld      (fhandle_bas),a         ; save the handle
        ld      hl,(mmu_addr)
        ld      (bufin_addr),hl         ; initialise input buffer pointer
        ld      (bufin_end),hl          ; and end
        ld      hl,first_file
        ld      a,(hl)                  ; only the first file can be .BAS -
        and     a                       ; subsequent ones must be .BNK sections
        ld      a,(header_buf)
        jr      z,check_bnktype
        and     a                       ; should be type 0 (BASIC program)
        jr      z,checked_bastype
        ld      hl,process_bnks         ; if first file is not .BAS, signal
        ld      (hl),0                  ; not to search for additional .BNKs
check_bnktype:
        cp      3
notbasic_nz_proxy:
        ld      hl,msg_notbasic
        jp      nz,err_custom           ; if not CODE, isn't a banked section
        ld      a,(bank_input)
        call    bind_io_bank
        ld      bc,2
        call    get_input_addr          ; HL=address of 2 bytes of signature
        jp      nc,err_eof              ; error if not enough data
        ld      a,(hl)
        inc     hl
        and     $7f                     ; bit 7 may be set, so clear it
        cp      'B'                     ; must be 'B'
        jr      nz,notbasic_nz_proxy
        ld      a,(hl)
        and     $7f                     ; bit 7 may be set, so clear it
        cp      'C'                     ; then 'C'
        jr      nz,notbasic_nz_proxy
        ld      hl,$8000
        ld      (hdr_line),hl           ; banked sections have no autostart
        ld      hl,first_file
        ld      a,(hl)
        and     a                       ; first file?
        ld      (hl),0                  ; clear first file flag
        jr      z,use_bnkname           ; on subsequent files extract the name
        ld      hl,fname_bas            ; use entire filename
        ld      bc,0
        xor     a
        cpir                            ; find filename null-terminator
        dec     hl                      ; HL=address of null
        ld      de,msg_bankfile_directive
        jr      append_section_name     ; append "#bankfile FILENAME"
use_bnkname:
        ld      hl,(bank_name)          ; start of bank name in filespec
        push    hl
        call    format_name_hl          ; find addr of "." or terminator
        ld      (hl),0                  ; strip any extension
        pop     hl
        ld      de,msg_bank_end
        ld      bc,msg_bank_end-msg_bank; length of "#bank "
copy_bnkname_loop:
        ld      a,(hl)                  ; get next bankname character
        inc     hl
        inc     bc
        and     a
        jr      z,copied_bnkname
        ld      (de),a                  ; copy into directive
        inc     de
        jr      copy_bnkname_loop
copied_bnkname:
        ld      a,$0d                   ; use $0d instead of null to terminate
        ld      (de),a
        ld      hl,msg_bank
        call    append_directive        ; append "#bank BANKNAME"
        jr      output_autoline
checked_bastype:
        dec     (hl)                    ; set first_file=0
        ld      hl,(output_ext)
        ld      de,msg_program_directive
append_section_name:
        ld      (hl),$0d                ; append CR after base name
        inc     hl
        and     a
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; BC=length of line inc CR
        ex      de,hl
        call    append_directive        ; append "#program BASENAME"
output_autoline:
        ld      a,(strip_numbers)       ; check if numbers to be stripped
        and     a
        ld      hl,msg_autoline
        ld      bc,msg_autoline_end-msg_autoline
        call    nz,append_directive     ; if so, add "#autoline 1,1"
bas2txt_loop:
        ld      a,(bank_input)
        call    bind_io_bank
        ld      bc,1
        call    get_input_addr          ; HL=address of next byte of input
        jp      nc,bas2txt_inputend     ; finished if no more data
        ld      a,(hl)
        ld      d,a
        and     $c0                     ; variables marker?
        jp      nz,bas2txt_inputend     ; on if so
        push    de                      ; save high byte of line number
        ld      bc,3
        call    get_input_addr          ; HL=addr of 3 more line header bytes
        jp      nc,err_eof              ; error if not enough data
        pop     de
        ld      e,(hl)                  ; DE=line number
        inc     hl
        push    de
        push    hl
        ld      hl,(hdr_line)
        and     a
        ex      de,hl
        sbc     hl,de                   ; is autostart line > this line?
        jr      c,not_autostart         ; if so, not yet reached
        ld      hl,msg_autostart
        ld      bc,msg_autostart_end-msg_autostart
        call    append_directive        ; otherwise append "#autostart"
        ld      hl,$8000
        ld      (hdr_line),hl           ; clear the autostart so it is not
                                        ; generated again
not_autostart:
        pop     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)                  ; BC=length of line body, inc CR
        pop     hl                      ; HL=line number
        ld      a,b
        or      c
        jr      z,bas2txt_loop          ; ignore zero-length lines
        push    bc                      ; save tokenised line length
        ld      ix,(bufout_addr)
        ld      a,(strip_numbers)       ; check if numbers to be stripped
        and     a
        jr      nz,skip_linenum
        ld      a,(bank_output0)
        call    bind_io_bank
        call    gen_linenum             ; optionally append line number
        ld      (ix+0),' '              ; and space
        inc     ix
        ld      a,(bank_input)
        call    bind_io_bank
skip_linenum:
        pop     bc                      ; BC=tokenised line length
        push    ix                      ; save output buffer address
        call    get_input_addr
        jr      nc,err_eof              ; error if not enough data
        push    hl
        call    check_deffns            ; check for new/legacy DEF FNs
        pop     de                      ; DE=addr of line body in input bank
        ld      a,(bank_output0)
        ld      c,a                     ; C=8K bank for untokenised line
        pop     hl
        ld      a,h
        and     $1f
        ld      h,a                     ; HL=offset for untokenised line
        ld      b,1                     ; detokenise
        callp3d ide_tokeniser,0
        jr      nc,err_tokenfail
        ld      a,(bank_output0)
        call    bind_io_bank
        ld      de,(bufout_addr)
        push    de
        ld      a,d
        and     $1f                     ; convert buffer address to offset
        ld      d,a
        sbc     hl,de                   ; subtract from final offset
        ld      b,h
        ld      c,l                     ; BC=length of text in buffer
        pop     hl                      ; HL=text buffer start
        call    adjust_lineend          ; select CR/LF/CRLF as required
        ld      a,(fhandle_txt)
        callesx f_write                 ; write the detokenised line
        jp      c,error_handler
        jp      bas2txt_loop

err_eof:
        ld      hl,msg_endoffile
        jp      err_custom

err_tokenfail:
        ld      hl,msg_tokenfail
        jp      err_custom

bas2txt_inputend:
        ld      a,(fhandle_bas)
        callesx f_close                 ; close the input file
        ld      a,(process_bnks)
        and     a                       ; process additional .BNK files?
        jr      z,bas2txt_finish        ; if not, nothing more to do
        dec     a
        jr      nz,got_dirhandle
        ld      a,'*'
        ld      hl,fname_bas            ; use temporarily for CWD
        push    hl
        callesx f_getcwd                ; get the current directory
        pop     hl
        ld      a,'*'
        ld      b,esx_mode_lfn_only+esx_mode_use_wildcards
        callesx f_opendir               ; open the directory
        jr      c,bas2txt_finish        ; finish if unable to
        ld      (dir_handle),a          ; save directory handle
        ld      a,2
        ld      (process_bnks),a        ; and mark as in-use
got_dirhandle:
        ld      hl,msg_bnkwildcard
        ld      de,(output_ext)
        ld      bc,msg_bnkwildcard_end-msg_bnkwildcard
        ldir                            ; append "-*.bnk" to base name
        ld      hl,progname
        push    hl
find_base_start_loop:
        ld      a,(hl)                  ; search through base name
        inc     hl
        and     a
        jr      z,found_base_start
        cp      ':'
        jr      z,update_base_start
        cp      '\'
        jr      z,update_base_start
        cp      '/'
        jr      nz,find_base_start_loop
update_base_start:
        pop     af                      ; discard previous start address
        push    hl                      ; save address following : / or \
        jr      find_base_start_loop
found_base_start:
        pop     de                      ; DE=wildcard name, after any path
        push    de
        ld      a,(dir_handle)
        ld      hl,attrs_bas
        push    hl
        callesx f_readdir               ; get the next match
        pop     hl
        pop     de
        jr      c,bas2txt_finish        ; finished if error getting match
        and     a
        jr      z,bas2txt_finish        ; or if no further matches
        ld      a,(hl)                  ; A=MSDOS attributes
        ld      (hl),' '                ; reinstate end of '#bankfile '
        inc     hl                      ; HL=address of filename
        and     $18                     ; ignore volumes and directories
        jr      nz,found_base_start
find_bankname_start:
        ld      a,(de)                  ; get next character from wild spec
        inc     de
        inc     hl
        cp      '*'
        jr      nz,find_bankname_start  ; keep going until wildcard part
        dec     hl                      ; HL points to start of bankname
        ld      (bank_name),hl
        jp      open_new_input

bas2txt_finish:
        ld      a,(fhandle_txt)
        callesx f_close                 ; close the output file
        jp      error_handler           ; and exit with its error status


; ***************************************************************************
; * Generate ASCII representation of line number                            *
; ***************************************************************************
; Entry: HL=address of line in input buffer

check_deffns:
        ld      de,(CH_ADD)
        push    de                      ; save (CH_ADD)
        dec     hl                      ; back up to char before line body
check_deffns_loop:
        ld      de,token_deffn          ; check 256 statements for DEF FN
        call48k EACH_STMT_r3
        jr      c,check_deffns_end      ; on if end-of-line
        jr      z,check_deffns_loop     ; more statements if not DEF FN
        call48k NEXT_CHAR_r3            ; A=function name
check_deffns_skip:
        call48k NEXT_CHAR_r3            ; skip function name
        cp      '$'
        jr      z,check_deffns_skip     ; also skip '$' for string functions
        cp      '('
        jr      nz,check_deffns_new     ; on if long function name: new DEF FN
        call48K NEXT_CHAR_r3            ; skip '('
        cp      ')'
        jr      z,check_deffns_new      ; on if no parameters: new DEF FN
check_deffns_skip2:
        inc     hl                      ; skip parameter name
        ld      a,(hl)
        cp      $0e
        jr      z,check_deffns_old      ; on if hidden number: old DEF FN
        cp      ' '+1
        jr      c,check_deffns_skip2    ; ignore other control characters
        cp      '$'
        jr      z,check_deffns_skip2    ; also skip '$' for string parameters
check_deffns_new:
        ld      a,'0'                   ; %CODE value should be 0
        jr      check_deffns_setcode
check_deffns_old:
        ld      a,'4'                   ; %CODE value should be 4
check_deffns_setcode:
        ld      hl,code_setting
        cp      (hl)
        jr      z,check_deffns_end      ; nothing to do if %CODE is the same
        ld      (hl),a                  ; update %CODE setting
        ld      hl,msg_code_directive
        ld      bc,msg_code_directive_end-msg_code_directive
        call    append_directive        ; write "#code 0" or "#code 4"
check_deffns_end:
        pop     hl
        ld      (CH_ADD),hl             ; restore (CH_ADD)
        ret


; ***************************************************************************
; * Generate ASCII representation of line number                            *
; ***************************************************************************
; Entry: HL=number (0-9999)
;        IX=buffer
;        If entering at gen_linenum_lead_e:
;          E=leading character (space or '0'), or $ff for no leading chars
; Exit:  IX=buffer after number

gen_linenum:
        ld      e,' '                   ; leading spaces
gen_linenum_lead_e:
        ld      bc,-1000
        call    gen_digit
        ld      bc,-100
        call    gen_digit
        ld      bc,-10
        call    gen_digit
        ld      a,l
        jr      gen_digit_nonzero


; ***************************************************************************
; * Generate ASCII representation of digit                                  *
; ***************************************************************************
; Entry: HL=number (0-9999)
;        BC=-1000,-100,-10
;        E=leading character (space or '0'), or $ff for no leading chars
;        IX=buffer
; Exit:  IX=buffer after digit
;        E=updated leading character

gen_digit:
        xor     a
gen_digit_loop:
        add     hl,bc
        inc     a                       ; count subtractions
        jr      c,gen_digit_loop
        sbc     hl,bc                   ; restore failed subtraction
        dec     a
        jr      nz,gen_digit_nonzero
        ld      a,e                     ; use leading space or zero
        and     a
        ret     m                       ; ignore if $ff
        jr      gen_digit_append
gen_digit_nonzero:
        ld      e,'0'                   ; subsequent zeros must print
        add     a,e                     ; form ASCII digit
gen_digit_append:
        ld      (ix+0),a                ; use leading space or zero
        inc     ix
        ret


; ***************************************************************************
; * Write a directive to the output file                                    *
; ***************************************************************************
; Entry: HL=address of message
;        BC=length

append_directive:
        call    adjust_lineend          ; adjust to LF or CRLF if needed
        ld      a,(fhandle_txt)
        callesx f_write                 ; write the detokenised line
        jp      c,error_handler
        ret


; ***************************************************************************
; * Adjust line ending                                                      *
; ***************************************************************************
; Entry: HL=address of line start
;        BC=length of line, including CR
; Exit:  HL preserved
;        CR possibly replaced with LF or CRLF
;        BC=adjusted length of line

adjust_lineend:
        ld      a,(lineend_type)
        and     a
        ret     z                       ; do nothing for default (CR)
        push    hl
        add     hl,bc
        dec     hl                      ; HL=final character (CR)
        dec     a
        jr      z,adjust_tolf           ; on if replacing CR with LF
        inc     hl                      ; move back past CR
        inc     bc                      ; increment length for appended LF
adjust_tolf:
        ld      (hl),$0a                ; insert LF
        pop     hl                      ; restore start address
        ret


; ***************************************************************************
; * Strip extension to form base name for output files                      *
; ***************************************************************************
; Exit: HL=address of null-terminator or "." of extension

format_progname:
        ld      hl,progname
format_name_hl:
        ld      bc,0
        xor     a
        cpir                            ; find null terminator
        dec     hl                      ; HL=address of null terminator
        push    hl
        ld      b,4
find_extension_loop:
        dec     hl
        ld      a,(hl)
        cp      '.'
        jr      z,found_extension
        djnz    find_extension_loop
        pop     hl                      ; HL=address of null terminator
        ret
found_extension:
        pop     af                      ; discard address of null terminator
        ret                             ; return with HL=address of "."


; ***************************************************************************
; * Get address of data in input buffer                                     *
; ***************************************************************************
; Entry: Input buffer must be bound
;        BC=# of bytes that should be available
; Exit:  Fc=1, success
;          HL=address in input buffer
;        Fc=0, not enough bytes available

get_input_addr:
        ld      hl,(bufin_addr)
        push    hl
        push    bc
        add     hl,bc
        ld      (bufin_addr),hl         ; update position following data
        dec     hl                      ; HL=last byte that is needed
        and     a
        ld      bc,(bufin_end)
        sbc     hl,bc
        pop     bc
        pop     hl
        ret     c                       ; okay if end of buffer is larger

        ; Must refill the buffer
        push    bc                      ; save space needed
        ex      de,hl                   ; DE=current data start
        ld      hl,(bufin_end)          ; HL=address after buffer end
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; BC=bytes to shift down
        ex      de,hl                   ; HL=current data start
        ld      de,(mmu_addr)           ; DE=start of input bank
        push    de                      ; save
        jr      z,refill_skipshift
        ldir                            ; copy data down to start
refill_skipshift:
        ; Currently: DE=address to read further data to
        ;            & current data now starts at (mmu_addr), on TOS
        ld      hl,(mmu_addr)
        ld      bc,8192
        add     hl,bc                   ; HL=end of input bank
        and     a
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; BC=max bytes to read
        ld      hl,msg_linetoolong
        jp      z,err_custom            ; tokenised line > 8K!!
        ex      de,hl                   ; HL=address
        ld      a,(fhandle_bas)
        callesx f_read                  ; read more data
        jp      c,error_handler
        ld      (bufin_end),hl          ; store new end of buffer
        pop     de                      ; DE=new start of data (buffer start)
        ld      (bufin_addr),de
        sbc     hl,de                   ; HL=length in buffer
        pop     bc                      ; BC=size needed
        sbc     hl,bc
        ccf
        ret     nc                      ; exit if still not enough, EOF found
        jr      get_input_addr          ; otherwise back to get the address


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
; * Bind an I/O bank into memory                                            *
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
        defopt  "-z",option_cr
        defopt  "--cr",option_cr
        defopt  "-u",option_lf
        defopt  "--lf",option_lf
        defopt  "-c",option_crlf
        defopt  "--crlf",option_crlf
        defopt  "-s",option_strip
        defopt  "--strip",option_strip
        defopt  "-n",option_nobnk
        defopt  "--nobnk",option_nobnk
        endopts()


; ***************************************************************************
; * -z, --cr                                                                *
; ***************************************************************************

option_cr:
        xor     a
        ld      (lineend_type),a
        ret


; ***************************************************************************
; * -u, --lf                                                                *
; ***************************************************************************

option_lf:
        ld      a,1
        ld      (lineend_type),a
        ret


; ***************************************************************************
; * -c, --crlf                                                              *
; ***************************************************************************

option_crlf:
        ld      a,2
        ld      (lineend_type),a
        ret


; ***************************************************************************
; * -s, --strip                                                             *
; ***************************************************************************

option_strip:
        ld      a,1
        ld      (strip_numbers),a
        ret


; ***************************************************************************
; * -n, --nobnk                                                             *
; ***************************************************************************

option_nobnk:
        xor     a
        ld      (process_bnks),a
        ret


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

; TAB 32 used within help message so it is formatted wide in 64/85 column mode.
msg_help:
        defm    "BAS2TXT v1.4 by Garry Lancaster",$0d
        defm    "Convert BASIC file to text",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    ".BAS2TXT [OPT] BASFILE [TXTFILE]",$0d,$0d
        defm    "OPTIONS:",$0d
        defm    " -h, --help",23,32,0
        defm    "     Display this help",$0d
        defm    " -s, --strip",23,32,0
        defm    "     Strip line numbers",$0d
        defm    " -z, --cr",23,32,0
        defm    "     ZX (CR) line-ends (default)",$0d
        defm    " -u, --lf",23,32,0
        defm    "     Unix (LF) line-ends",$0d
        defm    " -c, --crlf",23,32,0
        defm    "     CP/M & Win (CRLF) line-ends",$0d
        defm    " -n, --nobnk",23,32,0
        defm    "     Don't process extra .BNKs",$0d,$0d
        defm    "For an input file EXAMPLE.BAS,",23,32,0
        defm    "files named EXAMPLE-*.BNK will",$0d
        defm    "be processed as banked sections",$0d,$0d
        defm    "Individual banked sections can",23,32,0
        defm    "be processed if desired, eg",$0d
        defm    "  .BAS2TXT EXAMPLE.BNK",$0d
        defm    $ff

msg_badnextzxos:
        defm    "Requires NextZXOS v"
        defb    '0'+((MIN_NEXTZXOS_VER/$100)&$0f)
        defb    '.'
        defb    '0'+((MIN_NEXTZXOS_VER/$10)&$0f)
        defb    '0'+(MIN_NEXTZXOS_VER&$0f)
        defb    '+'+$80

msg_oom:
        defm    "Out of memor",'y'+$80

msg_notbasic:
        defm    "Invalid BASIC fil",'e'+$80

msg_linetoolong:
        defm    "Line too lon",'g'+$80

msg_tokenfail:
        defm    "Detokenisation faile",'d'+$80

msg_endoffile:
        defm    "End of file encountere",'d'+$80

msg_dottxt:
        defm    ".txt",0
msg_dottxt_end:

msg_bnkwildcard:
        defm    "-*.bnk",0
msg_bnkwildcard_end:

msg_autoline:
        defm    "#autoline 1,1",$0d
msg_autoline_end:
        defs    1               ; allow for conversion to CRLF

msg_autostart:
        defm    "#autostart",$0d
msg_autostart_end:
        defs    1               ; allow for conversion to CRLF

msg_bank:
        defm    "#bank "
msg_bank_end:
        defs    256-6           ; space for name copied from within fname_bas
                                ; exclusing "-" and ".bnk",0
        defs    2               ; space for CRLF

msg_program:
        defm    "#program "
msg_program_name:
        defs    255
msg_program_end:
        defs    2               ; allow space for CRLF


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
bank_output0:
        defb    0               ; only one output bank
bank_terminator:
        defb    0               ; terminator for deallocation loop

bank_allocs     equ     bank_input      ; first bank for dealloction loop

lineend_type:
        defb    0               ; 0=CR, 1=LF, 2=CRLF

strip_numbers:
        defb    0

process_bnks:
        defb    1               ; 0=no, 1=yes, 2=yes and dir_handle initialised

dir_handle:
        defb    0

bank_name:
        defw    0

first_file:
        defb    1

fhandle_bas:
        defb    $ff

fhandle_txt:
        defb    $ff

msg_code_directive:
        defm    "#code "
code_setting:
        defm    "0",$0d
msg_code_directive_end:
        defb    0               ; allow conversion to CRLF

msg_bankfile_directive:
        defm    "#bankfile"
attrs_bas:
        defm    " "             ; temporarily replaced with attributes
                                ; when scanning directory for next match
fname_bas:
        defs    256

fname_txt:
        defs    256+4           ; allow appending ".txt"

; The message prepended here also ensures format_progname can't accidentally
; match an "extension" prior to the name itself.
msg_program_directive:
        defm    "#program "
progname:                       ; allow appending "-*.bnk"
        defs    256+6

output_ext:
        defw    0

bufout_addr:
        defw    0

bufin_addr:
        defw    0
bufin_end:
        defw    0

header_buf:
        defb    0               ; type=BASIC
hdr_len:
        defw    0               ; file length
hdr_line:
        defw    $8000           ; auto-start line ($8000=none)
hdr_vars:
        defw    0               ; VARS offset
        defb    0               ; unused
        defs    8

command_tail:
        defw    0

