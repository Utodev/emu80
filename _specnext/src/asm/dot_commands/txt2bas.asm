; ***************************************************************************
; * Dot command to convert plain text .TXT files to BASIC .BAS format       *
; ***************************************************************************

include "macros.def"
include "nexthw.def"
include "rom48.def"
include "sysvars.def"
include "esxapi.def"
include "nextzxos.def"


; ***************************************************************************
; * Internal definitions                                                    *
; ***************************************************************************

MIN_NEXTZXOS_VER        equ     $0209   ; v2.09 needed for %CODE access
MAX_OUTPUT_BANKS        equ     8       ; allow for full 64K just in case ;)
MAX_BNKNAME             equ     32      ; should be plenty


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************

        org     $2000

txt2bas_init:
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
        jr      nz,bad_nextzxos
        ld      hl,MIN_NEXTZXOS_VER
        ex      de,hl
        sbc     hl,de                   ; check version number
        jr      c,bad_nextzxos
        ld      h,0                     ; get variable
        call    getset_code
        ld      (saved_code),de         ; save current %CODE value
        ld      a,1
        ld      (saved_code_valid),a    ; and mark as valid
        ld      de,0
        call    set_code                ; set %CODE to 0 initially
        ld      hl,stderr_handler
        callesx m_errh                  ; install error handler to reset turbo
        call    allocate_bank
        ld      (bank_input),a          ; allocate the input buffer bank
        call    allocate_bank
        ld      (bank_output0),a        ; allocate the first output buffer bank
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
        ld      de,fname_txt
        ldir                            ; use 1st arg as .TXT filename
        pop     bc
        pop     hl
        ld      de,progname
        ldir                            ; copy as default filename
parse_2ndarg:
        call    get_sizedarg            ; get an argument
        jp      nc,txt2bas_start        ; start processing if no more args
        call    check_options
        jr      z,parse_2ndarg          ; if it was an option, try again
        ld      hl,temparg
        inc     bc                      ; include null terminator
        ld      de,progname
        ldir                            ; use 2nd arg as program name
        ld      a,1
        ld      (progname_override),a   ; and indicate it has been specified
parse_remaining:
        call    get_sizedarg            ; get an argument
        jr      nc,txt2bas_start        ; start processing if no more args
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
        call    dealloc_banks           ; de-allocate all i/o banks
        call    reclaim_line            ; reclaim any tokenised line from E_LINE
        ld      a,(saved_turbo)
        nxtrega nxr_turbo               ; restore entry turbo setting
        ld      a,(saved_code_valid)
        and     a                       ; Fz=1 if %CODE wasn't saved
        ld      de,(saved_code)
        call    nz,set_code             ; restore original %CODE if needed
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

txt2bas_start:
        call    format_progname         ; strip extension
        ld      a,'*'
        ld      hl,fname_txt
        ld      b,esx_mode_read+esx_mode_open_exist
        callesx f_open                  ; open the .TXT file
        jr      c,error_handler
        ld      (fhandle_txt),a         ; save the handle
        ld      a,(mmu_id)              ; NXR_MMU3 (@ $6000)/NXR_MMU5 (@ $a000)
        sub     nxr_mmu0                ; A=3 or 5
        add     a,a                     ; A=$06 or $0a
        swapnib()                       ; A=$60 or $a0
        ld      h,a
        ld      l,0                     ; HL=$6000 or $a000
        ld      (mmu_addr),hl           ; save it
        ld      (bufin_addr),hl         ; initialise input buffer pointer
        ld      (bufin_end),hl          ; and end
        ld      (bufout_addr),hl        ; and output buffer pointer
txt2bas_loop:
        ld      a,(bank_input)
        call    bind_io_bank
txt2bas_getline:
        call    get_line                ; HL=address of untokenised line
        jp      z,txt2bas_end           ; on if no more lines
        ld      a,(hl)                  ; ignore completely empty lines (may
        cp      $0d                     ; be phantom line generated by the LF
        jr      z,txt2bas_getline       ; in a CR-LF line ending)
        ld      a,(verbose_output)
        and     a
        push    hl
        call    nz,printline            ; if verbose, print the line
        pop     hl
        ld      a,(hl)
        cp      '#'
        jr      nz,not_directive
        call    check_directive         ; process any directives
        jr      txt2bas_getline         ; and ignore the # line
not_directive:
        push    hl                      ; save start of line
        call    get_line_number         ; DE=line number
        push    hl                      ; save current address in line
        ld      hl,msg_badlinenum
        jr      c,err_bad_line_num      ; error if > 9999
        jr      z,err_bad_line_num      ; error if = 0
        ld      hl,(last_linenum)
        sbc     hl,de
        ld      (last_linenum),de       ; update last line number
        ld      hl,msg_dupline
        jr      z,err_bad_line_num      ; error if line number = last
        ld      hl,msg_badsequence
        jr      c,line_number_okay      ; okay if line number > last
err_bad_line_num:
        call    printmsg
        pop     hl                      ; discard current address in line
        pop     hl                      ; HL=start of line
        call    printline
        ld      hl,msg_numbererr        ; "Line numbering error"
        jp      err_custom
line_number_okay:
        ld      a,(header_buf)
        and     a
        jr      nz,done_autostart       ; banked sections ignore autostart
        ld      a,(autostart_set)       ; check if autostart needs setting
        and     a
        jr      nz,done_autostart
        inc     a
        ld      (autostart_set),a       ; signal autostart is set
        ld      (hdr_line),de           ; and store the line number
done_autostart:
        call    unbind_io_bank
        pop     hl                      ; HL=addr of untokenised line
        push    hl
        ld      a,h
        and     $1f                     ; convert address to bank offset
        ld      h,a
        ld      a,(bank_input)
        ld      c,a
        ld      b,0                     ; tokenise
        callp3d ide_tokeniser,0
        jr      nc,tokenise_error
        ld      (tokline_len),bc        ; save tokenised line length
        ld      (outline_len),bc        ; and as output line length
        ld      (outline_start),hl      ; and start
        pop     bc                      ; BC=addr of untokenised line
        pop     hl                      ; HL=addr of line start (pre-number)
        call    z,show_syntax_error     ; show any syntax error
        push    hl
        ld      hl,(outline_len)        ; HL=output line length, inc ENTER
        ld      (numlen_buf+2),hl       ; store length in 4-byte line header
        ld      bc,256-4+1              ; max length 256 including line number
        and     a                       ; & length fields (for banked sections)
        sbc     hl,bc
        pop     de
        jr      c,linelenokay           ; okay if shorter
        ld      a,(header_buf)
        and     a
        jr      z,linelenokay           ; okay if not a banked section
        ld      hl,msg_linetoolong
        call    printmsg
        ld      a,(bank_input)
        call    bind_io_bank
        ex      de,hl
        jp      err_badline             ; print the line and exit with error
linelenokay:
        ld      hl,(last_linenum)
        ld      a,h
        ld      h,l
        ld      l,a                     ; HL=line number, MSB first
        ld      (numlen_buf),hl         ; store in 4-byte line header
        ld      hl,numlen_buf
        ld      bc,4
        call    output_append           ; write line & length to output buffer
        ld      hl,(outline_start)
        ld      bc,(outline_len)
        call    output_append           ; write tokenised line to output buf
        call    unbind_io_bank
        call    reclaim_line            ; reclaim the tokenised line
        jp      txt2bas_loop            ; back for more lines

txt2bas_end:
        call    write_output_file       ; write the output
        ld      a,(fhandle_txt)
        callesx f_close                 ; close the input file
        ld      hl,(syntax_fails)
        ld      a,h
        or      l
        jp      z,error_handler         ; exit with Fc=0 if no syntax errors
        ld      hl,msg_synerrs          ; otherwise cause an error
        jp      err_custom

tokenise_error:
        ld      hl,msg_tokenfail
        jp      err_custom


; ***************************************************************************
; * Write the current output file                                           *
; ***************************************************************************

write_output_file:
        ld      hl,(auto_first)
        ld      (auto_number),hl        ; reset auto line-numbering
        ld      hl,0
        ld      (last_linenum),hl       ; reset last number in bank/program
        ld      hl,(syntax_fails)
        ld      a,h
        or      l
        ret     nz                      ; don't write output if syntax errors
        call    calc_output_length
        ld      a,h
        or      l
        ret     z                       ; or if nothing to write
        ld      a,(header_buf)
        and     a
        jr      z,write_unbanked        ; on if BASIC program type

        ld      bc,3
        add     hl,bc                   ; total length, inc 'BC' header and $80
        jr      c,banked_error
        ld      (hdr_len),hl            ; store total length
        ld      de,16384+1              ; max is 16K
        sbc     hl,de
        jr      nc,banked_error
        ld      hl,msg_bnkterminator
        ld      bc,1
        call    output_append           ; append the $80 terminator
        ld      hl,$c000
        ld      (hdr_line),hl           ; default load address
        ld      hl,use_bankfilename
        ld      a,(hl)
        and     a
        ld      (hl),0                  ; clear use_bankfilename flag
        ld      hl,bankfilename         ; if it was set, just open bankfilename
        jr      nz,open_banked_output
        ld      de,(output_ext)
        ld      a,'-'
        ld      (de),a                  ; append '-' to progname
        inc     de
        ld      hl,bankname
append_bankname_loop:
        ld      a,(hl)
        inc     hl
        and     a
        jr      z,append_bankname_end
        ld      (de),a                  ; append bankname
        inc     de
        jr      append_bankname_loop
append_bankname_end:
        ld      hl,msg_dotbnk
        ld      bc,msg_dotbnk_end-msg_dotbnk
        ldir                            ; append ".bnk",0
        ld      hl,progname
open_banked_output:
        ld      a,'*'
        ld      de,header_buf           ; 8-byte header info
        ld      b,esx_mode_write+esx_mode_use_header+esx_mode_creat_trunc
        callesx f_open                  ; create the .BNK file
        jp      c,error_handler
        push    af
        ld      hl,msg_bnkheader
        ld      bc,2
        callesx f_write                 ; write the "BC" header
        jp      c,error_handler
        pop     af
        jr      write_output_data

banked_error:
        ld      hl,msg_banklength
        jp      err_custom

write_unbanked:
        ld      a,1
        ld      (program_written),a     ; signal main program section written
        ld      (hdr_vars),hl           ; store VARS offset
        ld      (hdr_len),hl            ; store total length
        ld      hl,msg_dotbas
        ld      bc,msg_dotbas_end-msg_dotbas
        ld      de,(output_ext)
        ldir                            ; append ".bas",0 to progname
        ld      a,'*'
        ld      hl,progname
        ld      de,header_buf           ; 8-byte header info
        ld      b,esx_mode_write+esx_mode_use_header+esx_mode_creat_trunc
        callesx f_open                  ; create the .BAS file
        jp      c,error_handler

write_output_data:
        ld      hl,bank_output0         ; HL=address of first output bank
        ld      c,a                     ; C=file handle
        ld      a,(bufout_bank)
        ld      b,a                     ; B=offset of final output bank
        inc     b                       ; B=# remaining output banks
write_output_loop:
        ld      a,(hl)
        inc     hl
        call    bind_io_bank            ; bind next output bank
        push    hl
        ld      hl,(mmu_addr)           ; HL=address of bank start
        ld      a,c                     ; A=file handle
        dec     b                       ; Fz=1 if on last bank
        push    bc
        jr      z,write_output_last
        ld      bc,8192                 ; BC=length of full bank
        callesx f_write                 ; write a full bank
        jp      c,error_handler
        pop     bc
        pop     hl
        jr      write_output_loop
write_output_last:
        ex      de,hl
        ld      hl,(bufout_addr)
        and     a
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; BC=length of final bank
        jr      z,write_output_done     ; on if nothing in final bank
        ex      de,hl                   ; HL=address of bank start
        callesx f_write                 ; write the final bank
        jp      c,error_handler
write_output_done:
        pop     bc                      ; C=file handle
        pop     hl                      ; discard bank ids address
        ld      a,c
        callesx f_close                 ; close the file
        jp      c,error_handler
        ld      hl,bank_output0+1
        call    dealloc_banks           ; free all output banks except first
        xor     a
        ld      (bufout_bank),a         ; reset output to first bank
        ld      hl,(mmu_addr)
        ld      (bufout_addr),hl        ; reset output address to start
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
; * Get the number for the current line                                     *
; ***************************************************************************
; Entry: Input buffer must be bound
;        HL=address within input buffer
; Exit:  Fc=1 if line number > 9999 (HL/DE corrupted)
;        otherwise:
;          HL=updated address within input buffer
;          DE=line number
;          Fz=1 if line number = 0

get_line_number:
        ld      de,(auto_number)
        ld      a,d
        or      e
        jr      z,parse_line_number     ; get from line if not auto-numbering
        push    hl
        ld      hl,(auto_step)
        add     hl,de
        jr      nc,step_okay
        ld      hl,0                    ; turn off auto-numbering if > 65535
step_okay:
        ld      (auto_number),hl        ; update for next line
        pop     hl
        jr      check_line_number       ; on to validate range


; ***************************************************************************
; * Parse a line number from the input buffer                               *
; ***************************************************************************
; Entry: Input buffer must be bound
;        HL=address within input buffer
; Exit:  Fc=1 if line number > 9999 (HL/DE corrupted)
;        otherwise:
;          HL=updated address within input buffer
;          DE=line number
;          Fz=1 if line number = 0

parse_line_number:
        call    skip_spaces             ; skip any leading spaces
        ld      de,0                    ; initialise line number
calc_line_loop:
        ld      a,(hl)
        inc     hl
        cp      '0'
        jr      c,got_line_number
        cp      '9'+1
        jr      nc,got_line_number
        sub     '0'
        ex      de,hl
        add     hl,hl
        ret     c                       ; Fc=1, exit if any addition overflows
        ld      b,h
        ld      c,l                     ; BC=accumulated line*2
        add     hl,hl
        ret     c
        add     hl,hl                   ; HL=accumulated line*8
        ret     c
        add     hl,bc                   ; HL=accumulated line*10
        ret     c
        ld      b,0
        ld      c,a
        add     hl,bc                   ; HL=updated line, adding in new digit
        ret     c
        ex      de,hl
        jr      calc_line_loop
got_line_number:
        dec     hl                      ; HL points to first non-digit
        cp      ' '
        jr      nz,check_line_number
        inc     hl                      ; ignore first space after line num
check_line_number:
        push    hl                      ; save buffer address
        ld      hl,9999
        and     a
        sbc     hl,de
        pop     hl                      ; HL=addr after number
        ret     c                       ; exit with Fc=1 if line number>9999
        ld      a,d
        or      e
        ret                             ; exit with Fz=1 if line number=0


; ***************************************************************************
; * Skip spaces in the input buffer                                         *
; ***************************************************************************
; Entry: Input buffer must be bound
;        HL=address within input buffer
; Exit:  HL=updated address within input buffer

skip_spaces:
        ld      a,(hl)
        inc     hl
        cp      ' '                     ; ignore leading spaces
        jr      z,skip_spaces
        dec     hl                      ; HL=address of first non-space
        ret                             ; exit with Fz=0


; ***************************************************************************
; * Get next non-empty, non-comment line from input buffer                  *
; ***************************************************************************
; Entry: Input buffer must be bound
; Exit: Fz=1 if no more lines, otherwise:
;       HL=address of line start
;       (bufin_addr) updated to start of next line
;
; NOTE: Each TAB char within the input line is converted to a single space
;       Any LF char is treated as a CR

get_line:
        ld      hl,(bufin_addr)
        ld      bc,(bufin_end)
        ld      d,0                     ; no chars found
get_line_findcr_loop:
        call    get_input_byte          ; A=next byte, Fz=1 if none
        jr      z,get_line_nocr         ; on if no more chars
        cp      $0d                     ; line ends at a CR
        jr      z,get_line_foundcr
        cp      $0a                     ; also accept a LF
        jr      z,get_line_foundlf
        ld      d,1                     ; chars found
        cp      ' '
        jr      nc,get_line_findcr_loop ; and loop unless another control char
        dec     hl
        ld      (hl),$0d                ; replace control with CR
        ld      hl,msg_badcontrol
        call    printmsg
        ld      hl,(bufin_addr)
        call    printline
        ld      hl,msg_badline
        jp      err_custom

get_line_foundlf:
        dec     hl
        ld      (hl),$0d                ; replace a LF with a CR
        inc     hl
get_line_foundcr:
        ld      de,(bufin_addr)         ; DE=start of current line
        ld      (bufin_addr),hl         ; update to start of next line
        ex      de,hl                   ; HL=start of current line
        xor     a                       ; Fz=1
        inc     a                       ; Fz=0
        ret

; At this point, a refill failed but we know there are fewer than 8192 chars
; in the buffer (as otherwise an error will have been generated).
; Therefore just append a CR (assuming the line contains any non-spaces).

get_line_nocr:
        inc     d
        dec     d                       ; Fz=1 if nothing on final line
        ret     z                       ; and exit
        ld      (hl),$0d                ; else append the CR
        inc     hl
        ld      (bufin_end),hl          ; and update buffer_end to include it
        jr      get_line_foundcr


; ***************************************************************************
; * Directive checking                                                      *
; ***************************************************************************
; A line beginning with '#' may be either a comment or a directive
; Entry: Input buffer must be bound
;        HL=address of '#' in input buffer

check_directive:
        ld      de,directive_table
        push    hl
        pop     ix                      ; IX=start of line
check_directive_next:
        push    ix
        pop     hl                      ; HL=start of line
        inc     hl                      ; skip '#'
check_directive_loop:
        ld      a,(hl)                  ; next char
        cp      ' '+1                   ; reached a space or CR?
        jr      c,check_dir_endword
        inc     hl
        cp      'A'
        jr      c,check_dir_notupper
        cp      'Z'+1
        jr      nc,check_dir_notupper
        or      $20                     ; convert to lowercase
check_dir_notupper:
        ex      de,hl
        cp      (hl)                    ; test char match
        ex      de,hl
        inc     de
        jr      z,check_directive_loop  ; loop until difference
        dec     de                      ; back up in case terminator checked
check_dir_skip:
        ld      a,(de)
        inc     de
        and     a
        jr      nz,check_dir_skip       ; skip to null-terminator
        inc     de                      ; ignore address
        inc     de
        ld      a,(de)
        and     a                       ; end of directive table?
        jr      nz,check_directive_next
        ret

; At this point, a space or CR has been read from the line.

check_dir_endword:
        ld      a,(de)
        inc     de
        and     a                       ; was the directive finished?
        jr      nz,check_dir_skip       ; if not, skip to end and try next
        ld      a,(de)
        ld      c,a
        inc     de
        ld      a,(de)
        ld      b,a                     ; BC=address of directive routine
        push    bc
        ret                             ; execute it


; ***************************************************************************
; * Table of directives                                                     *
; ***************************************************************************

directive_table:
        defm    "autostart",0
        defw    dir_autostart
        defm    "autoline",0
        defw    dir_autoline
        defm    "program",0
        defw    dir_program
        defm    "bank",0
        defw    dir_bank
        defm    "bankfile",0
        defw    dir_bankfile
        defm    "code",0
        defw    dir_code
        defb    0


; ***************************************************************************
; * Autostart directive                                                     *
; ***************************************************************************
; #autostart NNNN                       ; auto-start at line NNNN
; #autostart                            ; auto-start at next line

dir_autostart:
        call    parse_line_number       ; DE=specified line or zero
        jr      c,bad_directive         ; must be 0-9999
        ld      a,d
        or      e
        ld      (autostart_set),a       ; if=0, next line will be used
        jr      z,check_eol
        ld      (hdr_line),de           ; otherwise store in header
check_eol:
        call    skip_spaces             ; ignore trailing spaces
        ld      a,(hl)
        cp      $0d                     ; is it the end-of-line?
        ret     z                       ; okay if so
bad_directive:
        ld      hl,msg_baddirective
        call    printmsg
        push    ix
        pop     hl                      ; HL=directive line
        ; drop through to printline to output it and exit

; ***************************************************************************
; * Print a line                                                            *
; ***************************************************************************
; Entry: HL=line

printline:
        ld      a,(hl)
        print_char()                    ; print a character
        ld      a,(hl)
        inc     hl
        cp      $0d
        jr      nz,printline            ; until CR printed
        ret


; ***************************************************************************
; * Autoline directive                                                      *
; ***************************************************************************
; #autoline NNNN                        ; auto-number from NNNN, step 10
; #autoline NNNN,SSSS                   ; auto-number from NNNN, step SSSS
; #autoline                             ; turn off auto-numbering

dir_autoline:
        call    parse_line_number       ; DE=specified line or zero
        jr      c,bad_directive         ; must be 0-9999
        ld      (auto_first),de         ; remember starting line
        ld      (auto_number),de        ; save as next number (0=disable)
        jr      z,check_eol             ; no further params for disable
        ld      de,10
        ld      (auto_step),de          ; step defaults to 10
        call    skip_spaces             ; skip any spaces after 1st param
        ld      a,(hl)
        cp      ','
        jr      nz,check_eol            ; on if no second parameter
        inc     hl                      ; skip comma
        call    parse_line_number       ; get step
        jr      c,bad_directive         ; must be 1-9999
        jr      z,bad_directive
        ld      (auto_step),de
        jr      check_eol


; ***************************************************************************
; * Bankfile directive                                                      *
; ***************************************************************************
; #bankfile BANKFILENAME                ; output as banked section (.BNK)

dir_bankfile:
        ld      de,bankfilename         ; destination will be bankfilename
        ld      a,1                     ; flag for use_bankfilename
        jr      dir_banksection


; ***************************************************************************
; * Banked directive                                                        *
; ***************************************************************************
; #bank BANKNAME                        ; output as banked section (.BNK)

dir_bank:
        ld      de,bankname             ; destination will be bankname
        xor     a                       ; flag for use_bankfilename
dir_banksection:
        push    af
        push    de
        push    ix
        push    hl
        call    write_output_file       ; if any output so far, write its file
        pop     hl
        pop     ix
        ld      a,(bank_input)
        call    bind_io_bank            ; re-bind the input file
        ld      a,3
        ld      (header_buf),a          ; CODE type for banked sections
        call    skip_spaces
        pop     de                      ; DE=destination for name
        pop     af                      ; A=flag for use_bankfilename
        ld      (use_bankfilename),a
        ld      a,(hl)
        cp      $0d
        call    z,bad_directive         ; error if no name provided
        ld      b,MAX_BNKNAME
        ; drop through to copyname, to copy to bankname and exit

; ***************************************************************************
; * Copy $0d-terminated name to null-terminated destination                 *
; ***************************************************************************
; Entry: HL=addr of $0d-terminated source
;        DE=addr for null-terminated dest
;        B=max chars to copy (excluding terminator)

copy_name:
        ld      a,(hl)
        inc     hl
        cp      $0d
        jr      z,copy_name_end
        ld      (de),a                  ; copy name to destination
        inc     de
        djnz    copy_name
copy_name_end:
        xor     a
        ld      (de),a                  ; null-terminate
        ret


; ***************************************************************************
; * Program directive                                                       *
; ***************************************************************************
; #program PRGNAME                      ; set prog name, output as main (.BAS)

dir_program:
        push    hl
        ld      a,(program_written)
        and     a
        ld      hl,msg_progwritten
        jp      nz,err_custom
        ld      hl,progname_count
        ld      a,(hl)
        inc     (hl)
        and     a
        ld      hl,msg_toomanyprognames
        jp      nz,err_custom
        ld      a,(header_buf)
        and     a
        call    nz,write_output_file    ; if current output is bank, write it
        pop     hl
        xor     a
        ld      (header_buf),a          ; BASIC type for main program
        call    skip_spaces
        ld      a,(hl)
        cp      $0d
        jp      z,bad_directive         ; error if no name provided
        ld      a,(progname_override)   ; do nothing further if a program
        and     a                       ; name was specified on the command
        ret     nz                      ; line
        ld      de,progname
        ld      b,255                   ; allow 255 chars
        call    copy_name               ; copy into progname
        ; drop through to format_progname to strip any path and extension

; ***************************************************************************
; * Strip path and extension to form base name for output files             *
; ***************************************************************************

format_progname:
        ld      hl,progname
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
set_output_ext:
        ld      (output_ext),hl         ; store address to append ".bas" or
                                        ; "-bankname.bnk"
        ret
found_extension:
        pop     af                      ; discard address of null terminator
        jr      set_output_ext


; ***************************************************************************
; * Code directive                                                          *
; ***************************************************************************
; #code N                               ; set %CODE options

dir_code:
        call    parse_line_number       ; DE=options value
set_code:
        ld      h,1                     ; set variable to DE
getset_code:
        ld      bc,$0200                ; special variable 0 (%CODE)
        callp3d ide_integer_var,0
        ret


; ***************************************************************************
; * Get next byte from input buffer                                         *
; ***************************************************************************
; Entry: HL=current position in buffer
;        BC=(bufin_end)=address after last char in buffer
;        (bufin_addr)=address of current line start in buffer
; Exit:  HL=updated position in buffer
;        BC=(bufin_end)=updated address after last char in buffer
;        (bufin_addr)=updated address of current line start in buffer
;        Fz=1 if no more characters
;        Fz=0 if byte was available, and:
;               A=byte
;        DE is preserved

get_input_byte:
        push    hl
        and     a
        sbc     hl,bc
        pop     hl
        call    z,refill_input          ; refill the buffer if no more chars
        ret     z                       ; and exit with Fz=1 if still none
        ld      a,(hl)                  ; A=byte
        inc     hl
        cp      9
        ret     nz                      ; exit with A=byte, Fz=0 if not TAB
        ld      a,' '                   ; replace TAB with space
        and     a                       ; set Fz=0
        ret


; ***************************************************************************
; * Refill the input buffer                                                 *
; ***************************************************************************
; Entry: HL=current position in buffer
;        BC=(bufin_end)=address after last char in buffer
;        (bufin_addr)=address of current line start in buffer
; Exit:  HL=updated position in buffer
;        BC=(bufin_end)=updated address after last char in buffer
;        (bufin_addr)=address of current line start in buffer (buffer start)
;        Fz=1 if no further characters were read from the file
;
;        DE is preserved

refill_input:
        push    de                      ; must preserve DE
        push    hl
        ld      de,(bufin_addr)         ; DE=current line start
        ld      hl,(bufin_end)          ; HL=address after buffer end
        and     a
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; BC=bytes to shift down
        ex      de,hl                   ; HL=current line start
        ld      de,(mmu_addr)           ; DE=start of input bank
        push    de                      ; save
        jr      z,refill_skipshift
        ldir                            ; copy data down to start
refill_skipshift:
        ; Currently: DE=address to read further data to
        ;            & current line now starts at (mmu_addr), on TOS
        ld      hl,(mmu_addr)
        ld      bc,8192
        add     hl,bc                   ; HL=end of input bank
        and     a
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; BC=max bytes to read
        ex      de,hl                   ; HL=address
        jr      nz,refill_okay          ; on unless buffer still full
        dec     hl
        ld      (hl),$0d                ; put CR at byte 8191
        ld      hl,msg_linetoolong
        call    printmsg
        ld      hl,(mmu_addr)
err_badline:
        call    printline
        ld      hl,msg_badline
        jp      err_custom
refill_okay:
        ld      a,(fhandle_txt)
        callesx f_read                  ; read more data
        jp      c,error_handler
        ld      (bufin_end),hl          ; store new end of buffer
        ld      hl,(bufin_addr)         ; HL=old line start
        pop     de                      ; DE=new line start (buffer start)
        ld      (bufin_addr),de         ; store new line start
        sbc     hl,de
        ex      de,hl                   ; DE=offset of old from new
        pop     hl                      ; HL=previous buffer position
        sbc     hl,de                   ; HL=new buffer position
        ld      a,b
        or      c                       ; Fz=1 if nothing read from file
        ld      bc,(bufin_end)          ; BC=new buffer end
        pop     de                      ; restore DE
        ret


; ***************************************************************************
; * Calculate current length of output buffer                               *
; ***************************************************************************
; Exit: HL=total output length, 0-65535

calc_output_length:
        ld      hl,(bufout_addr)
        ld      de,(mmu_addr)
        and     a
        sbc     hl,de                   ; HL=length in current output bank
        ld      a,(bufout_bank)
        ld      b,a                     ; B=current output bank offset
        xor     a                       ; A=first output bank offset
        ld      de,8192                 ; DE=size of data in a full bank
calc_output_len_loop:
        cp      b
        ret     nc                      ; exit when reached current bank
        inc     a
        add     hl,de
        jr      nc,calc_output_len_loop
        jp      out_of_memory           ; out of memory if > 65535 bytes


; ***************************************************************************
; * Append data to output buffer                                            *
; ***************************************************************************
; Entry: HL=data address
;        BC=length

output_append:
        push    bc
        pop     ix                      ; IX=length
        ld      de,bank_output0
        ld      a,(bufout_bank)
        addde_A_badFc()
        ld      a,(de)
        ld      b,a                     ; B=current output buffer bank id
        ld      de,(bufout_addr)        ; DE=current output buffer address
output_append_loop:
        call    unbind_io_bank          ; bind standard memory
        ld      a,ixh
        or      ixl
        jr      z,output_append_done    ; finished if no more data
        bit     5,d                     ; reached MMU4 ($8000) or MMU6 ($c000)?
        call    z,new_output_bank       ; extend output buffer if so
        ld      c,(hl)                  ; C=next byte
        inc     hl
        dec     ix
        ld      a,b
        call    bind_io_bank            ; bind in current output buffer bank
        ld      a,c
        ld      (de),a                  ; store byte
        inc     de
        jr      output_append_loop
output_append_done:
        ld      (bufout_addr),de        ; update current output buffer addr
        ret


; ***************************************************************************
; * Extend output buffer with another bank                                  *
; ***************************************************************************
; Entry: B=current output buffer bank id
;        DE=address after end of current buffer bank ($8000 or $c000)
; Exit:  B=new output buffer bank id
;        DE=address of start of current buffer bank ($6000 or $a000)
;
; Preserves HL,IX

new_output_bank:
        push    ix
        push    hl
        ld      de,bank_output0
        ld      hl,bufout_bank
        inc     (hl)                    ; increment offset of bank in buffer
        ld      a,(hl)
        cp      MAX_OUTPUT_BANKS
        jr      nc,out_of_memory        ; don't allocate too many banks
        addde_A_badFc()                 ; DE=address to store bank id
        push    de
        call    allocate_bank           ; get a new bank
        pop     de
        ld      (de),a                  ; store it
        ld      b,a                     ; update B
        ld      de,(mmu_addr)           ; update address
        pop     hl
        pop     ix
        ret


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
; * Show line which caused a syntax failure                                 *
; ***************************************************************************
; Entry: DE=count of successfully processed chars in untokenised line
;        HL=address of start of line (before line number) in bank_input
;        BC=address of untokenised line in bank_input

show_syntax_error:
        ld      a,(bank_input)
        call    bind_io_bank
        push    hl
        ld      hl,msg_syntaxerr
        call    printmsg
        pop     hl
show_line_number_loop:
        push    hl
        and     a
        sbc     hl,bc
        pop     hl
        jr      z,show_syntax_error_start; on when untokenised start reached
        ld      a,(hl)
        inc     hl
        print_char()
        jr      show_line_number_loop
show_syntax_error_start:
        push    bc                      ; save untokenised text start
        ld      bc,0                    ; total length so far
show_syntax_error_loop:
        ld      a,d
        or      e                       ; Fz=1 if that char is the failure
        dec     de
        push    hl
        ld      hl,msg_synmarker
        call    z,printmsg
        pop     hl
        ld      a,(hl)                  ; A=char
        print_char()
        ld      a,(hl)                  ; fetch char again
        inc     hl
        inc     bc
        cp      $0d                     ; keep going until ENTER processed
        jr      nz,show_syntax_error_loop
        ld      a,(always_output)       ; always generate output files?
        and     a
        jr      nz,insert_rem_error
        ld      hl,(syntax_fails)       ; if not,
        inc     hl                      ; increment lines that failed syntax
        ld      (syntax_fails),hl
show_syntax_end:
        pop     hl                      ; HL=untokenised text, after line
        call    unbind_io_bank
        ret

insert_rem_error:
        ld      hl,msg_syntax_rem_text-msg_syntax_rem
        add     hl,bc
        ld      (outline_len),hl        ; store length to write to output
        ld      hl,msg_syntax_rem
        ld      (outline_start),hl      ; store address to write from
        ld      hl,msg_syntax_rem_text_end-msg_syntax_rem_text
        and     a
        sbc     hl,bc
        jp      c,out_of_memory         ; if line too long, just say OOM
        pop     hl
        push    hl
        ld      de,msg_syntax_rem_text
        ldir                            ; copy text into DivMMC RAM
        jr      show_syntax_end


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
        defopt  "-a",option_always_write
        defopt  "--always-write",option_always_write
        endopts()


; ***************************************************************************
; * -v, --verbose                                                           *
; ***************************************************************************

option_verbose:
        ld      a,1
        ld      (verbose_output),a
        ret


; ***************************************************************************
; * -a, --always-write                                                      *
; ***************************************************************************

option_always_write:
        ld      a,1
        ld      (always_output),a
        ret


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

; TAB 32 used within help message so it is formatted wide in 64/85 column mode.
msg_help:
;                01234567890123456789012345678901
        defm    "TXT2BAS v1.7 by Garry Lancaster",$0d
        defm    "Convert text file to BASIC",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    ".TXT2BAS [OPT] TXTFILE [BASFILE]",$0d,$0d
        defm    "OPTIONS:",$0d
        defm    " -v, --verbose",23,32,0
        defm    "   Show lines during processing",$0d
        defm    " -a, --always-write",23,32,0
        defm    "   Write even if syntax errors",$0d
        defm    " -h, --help",23,32,0
        defm    "   Display this help",$0d,$0d
        defm    "Supported directives in text:",$0d,$0d
        defm    " #program PRGNAME",23,32,0
        defm    "   Start of main BASIC code",$0d
        defm    "   (file is PRGNAME.BAS)",$0d,$0d
        defm    " #bank BNKNAME",23,32,0
        defm    "   Start of banked section",$0d
        defm    "   (file is PRGNAME-BNKNAME.BNK)",$0d,$0d
        defm    " #bankfile BNKFILENAME",23,32,0
        defm    "   Start of banked section",$0d
        defm    "   (file is BNKFILENAME)",$0d,$0d
        defm    " #autostart LINE",23,32,0
        defm    "   Program autostarts at LINE",$0d,$0d
        defm    " #autostart",23,32,0
        defm    "   Autostarts at following line",$0d,$0d
        defm    " #autoline LINE,STEP",23,32,0
        defm    "   Start auto-numbering",$0d,$0d
        defm    " #autoline LINE",23,32,0
        defm    "   Start auto-numbering(step=10)",$0d,$0d
        defm    " #autoline",23,32,0
        defm    "   Stop auto-numbering",$0d,$0d
        defm    " #code N",23,32,0
        defm    "   Set %CODE options",$0d,$0d
        defm    "(Other lines starting # ignored)",$0d
        defm    $ff

msg_synmarker:
        defb    20,1,'?',20,0,$ff

msg_baddirective:
        defm    "Bad directive:",$0d,$ff

msg_syntaxerr:
        defm    "Syntax error:",$0d,$ff

msg_badlinenum:
        defm    "Line not in range 1-9999:",$0d,$ff

msg_badsequence:
        defm    "Line not in order:",$0d,$ff

msg_dupline
        defm    "Duplicate line number:",$0d,$ff

msg_badcontrol:
        defm    "Invalid control char in line:",$0d,$ff

msg_linetoolong:
        defm    "Line too long:",$0d,$ff

msg_badnextzxos:
        defm    "Requires NextZXOS v"
        defb    '0'+((MIN_NEXTZXOS_VER/$100)&$0f)
        defb    '.'
        defb    '0'+((MIN_NEXTZXOS_VER/$10)&$0f)
        defb    '0'+(MIN_NEXTZXOS_VER&$0f)
        defb    '+'+$80

msg_oom:
        defm    "Out of memor",'y'+$80

msg_tokenfail:
        defm    "Tokenisation faile",'d'+$80

msg_numbererr:
        defm    "Line numbering erro",'r'+$80

msg_badline:
        defm    "Bad line tex",'t'+$80

msg_banklength:
        defm    "Too large for ban",'k'+$80

msg_synerrs:
        defm    "Syntax error",'s'+$80

msg_progwritten:
msg_toomanyprognames:
        defm    "Multiple program section",'s'+$80

msg_dotbas:
        defm    ".bas",0
msg_dotbas_end:

msg_dotbnk:
        defm    ".bnk",0
msg_dotbnk_end:

msg_bnkheader:
        defm    "BC"

msg_bnkterminator:
        defb    $80

msg_syntax_rem:
        defm    "; Syntax error: "
msg_syntax_rem_text:
        defs    1024
msg_syntax_rem_text_end:


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

saved_sp:
        defw    0

saved_turbo:
        defb    0

saved_mmu_binding:
        defb    0

saved_code:
        defw    0

saved_code_valid:
        defb    0

mmu_id:
        defb    0

mmu_addr:
        defw    0

bank_input:
        defb    0
bank_output0:
        defs    MAX_OUTPUT_BANKS
bank_terminator:
        defb    0

bank_allocs     equ     bank_input      ; first bank for dealloction loop

bufout_bank:
        defb    0

bufout_addr:
        defw    0

fhandle_txt:
        defb    $ff

fname_txt:
        defs    256

; Four asterisks here ensure format_progname can't accidentally match an
; "extension" prior to the name itself.
        defm    "****"
progname:                       ; allow appending "-bankname.bnk" or ".bas"
        defs    256+1+MAX_BNKNAME+4

bankname:
        defs    MAX_BNKNAME+1

bankfilename:
        defs    256

use_bankfilename:
        defb    0

output_ext:
        defw    0               ; address to append "-bankname.bnk" or ".bas"

progname_override:
        defb    0               ; set if overridden by command-line

program_written:
        defb    0               ; set if main program written

progname_count:
        defb    0               ; incremented when #program seen

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

numlen_buf:
        defs    4               ; buffer for line number and length

auto_first:
        defw    0

auto_number:
        defw    0

auto_step:
        defw    0

autostart_set:
        defb    1               ; cleared to zero if hdr_line should be set

verbose_output:
        defb    0

always_output:
        defb    0

syntax_fails:
        defw    0

last_linenum:
        defw    0

tokline_len:
        defw    0

tokline_start:
        defw    0

outline_len:
        defw    0

outline_start:
        defw    0

command_tail:
        defw    0
