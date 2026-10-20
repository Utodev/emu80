; ***************************************************************************
; * Dot command for displaying return stack information                     *
; * .ret                                                                    *
; ***************************************************************************

include "macros.def"
include "nexthw.def"
include "rom48.def"
include "esxapi.def"
include "sysvars.def"
include "bastoken.def"
include "nextzxos.def"


; ***************************************************************************
; * Internal definitions                                                    *
; ***************************************************************************

rsi_ref         equ     $01
rsi_end         equ     $3e
rsi_error       equ     $4b
rsi_saved_int   equ     $48
rsi_saved_array equ     $c2


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************
; Dot commands always start at $2000, with HL=address of command tail
; (terminated by $00, $0d or ':').

        org     $2000

        ld      (entry_sp),sp           ; save initial SP
        ld      a,h
        or      l
        jr      z,retstk_init           ; no tail provided if HL=0
show_usage:
        ld      hl,msg_help
        call    printmsg                ; else just show usage info
        and     a                       ; Fc=0, successful
        ret                             ; exit


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************

retstk_init:
        ld      hl,stderr_handler
        callesx m_errh                  ; install error handler
        ld      a,(entry_sp+1)
        cp      $a0                     ; is SP < $a000?
        ld      a,nxr_mmu5
        ld      hl,$a000
        jr      c,got_mmuid             ; if so, use MMU5 for banking
        ld      a,nxr_mmu3              ; otherwise, use MMU3
        ld      hl,$6000                ; NOTE: MMU3/5 are safe from being
                                        ;       paged out when making NextZXOS
                                        ;       calls (unlike MMU0/1/6/7)
got_mmuid:
        ld      (mmu_id),a
        ld      (mmu_addr),hl
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
        ld      (saved_speed),a         ; save it
        ld      a,turbo_max
        out     (c),a                   ; and increase to maximum
        callesx m_dosversion
        jr      c,bad_nextzxos          ; must be esxDOS if error
        ld      hl,'N'<<8+'X'
        sbc     hl,bc                   ; check NextZXOS signature
        jr      nz,bad_nextzxos
        ld      hl,$0208
        ex      de,hl
        sbc     hl,de                   ; check version number >= 2.08
        jr      nc,retstk_start
bad_nextzxos:
        ld      hl,msg_badnextzxos
        ; drop through to err_custom

; ***************************************************************************
; * Custom error generation                                                 *
; ***************************************************************************

err_custom:
        xor     a                       ; A=0, custom error
        scf                             ; Fc=1, error condition
        ; fall through to error_handler

; ***************************************************************************
; * Tidy up and exit with any error condition                               *
; ***************************************************************************

error_handler:
        ld      sp,(entry_sp)           ; restore original stack
restore_all:
        push    af                      ; save error status
        push    hl
        call    unbind_io_bank          ; restore bank originally bound to MMU
        ld      a,(iobank)
        and     a
        jr      z,nodealloc
        ld      e,a                     ; E=bank id to free
        ld      hl,$0003                ; free a ZX bank
        callp3d ide_bank,7
nodealloc:
        ld      a,(saved_speed)
        nxtrega nxr_turbo               ; restore original speed
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
; * Show return stack                                                       *
; ***************************************************************************

retstk_start:
        call    allocate_bank
        ld      (iobank),a              ; store allocated I/O bank
        call    get_intvals             ; get current (most local) integers
        ld      hl,(ERR_SP)
        inc     hl                      ; skip error return
        inc     hl
retstk_loop:
        inc     hl
        ld      a,(hl)
        cp      rsi_ref
        jr      z,retstk_refprv         ; REFs/PRIVATEs
        jr      c,retstk_local          ; local variables
        cp      rsi_end
        jr      z,error_handler         ; done if end marker found
        jp      c,retstk_struct         ; structures
        cp      rsi_error
        jp      z,retstk_struct         ; error handlers
        ; drop through to retstk_saved

; ***************************************************************************
; * Saved data                                                              *
; ***************************************************************************

retstk_saved:
        dec     hl
        ld      b,(hl)                  ; B=name for integer data
        cp      rsi_saved_int
        call    z,retstk_intvar
        cp      rsi_saved_array
        call    z,retstk_intarray
        res     6,a
        addhl_A_badFc()                 ; skip the saved data
        jr      retstk_loop


; ***************************************************************************
; * Local variables                                                         *
; ***************************************************************************

retstk_local:
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    de
        push    hl
        ld      hl,msg_local
        call    printmsg
        pop     hl
        push    hl
        call    print_varname
        call    print_varval
        ld      a,$0d
        print_char()
        pop     hl
        pop     de
        add     hl,de
        jr      retstk_loop


; ***************************************************************************
; * REF/PRIVATEs                                                            *
; ***************************************************************************

retstk_refprv:
        dec     hl
        ld      b,(hl)
        inc     hl
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    de
        push    hl
        ld      hl,msg_private
        djnz    rrp_showtype
        ld      hl,msg_ref
rrp_showtype:
        call    printmsg
        pop     hl
        push    hl
        call    print_varname           ; show name (including any '$')
        call    print_arraytype         ; show '()' for array references
        ld      a,(hl)
        and     a
        jr      z,rrp_private
        push    hl
        ld      hl,msg_refers
        call    printmsg
        pop     hl
rrp_refname:
        inc     hl
        ld      a,(hl)
        call48k ALPHANUM_r3
        jr      nc,rrp_refname_end
        print_char()
        jr      rrp_refname
rrp_refname_end:
        call    print_strarrtype        ; show '$' and '()' if appropriate
        jr      rrp_end

rrp_private:
        inc     hl
        inc     hl
        inc     hl
        inc     hl
        call    print_numeric           ; show private value
rrp_end:
        ld      a,$0d
        print_char()
        pop     hl
        pop     de
        add     hl,de
        jp      retstk_loop


; ***************************************************************************
; * Integer variables                                                       *
; ***************************************************************************
; Entry:        A=item type
;               HL=item address
;               B=variable name

retstk_intvar:
        push    af
        push    hl
        push    bc
        ld      hl,msg_local
        call    printmsg
        ld      a,'%'
        print_char()
        pop     af                      ; A=name
        push    af
        add     a,'A'
        print_char()
        ld      a,'='
        print_char()
        pop     af
        push    af
        add     a,a
        ld      hl,integer_vars
        addhl_A_badFc()
        push    hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; DE=current value
        ex      de,hl
        call    print_hl
        pop     bc
        pop     de
        pop     hl                      ; HL=item address
        push    hl
        push    de
        push    bc
        inc     hl
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; DE=saved value
        pop     hl
        ld      (hl),e                  ; replace current value
        inc     hl
        ld      (hl),d
retstk_int_end:
        ld      a,$0d
        print_char()
        pop     bc
        pop     hl
        pop     af
        ret


; ***************************************************************************
; * Integer arrays                                                          *
; ***************************************************************************
; Entry:        A=item type
;               HL=item address
;               B=variable name

retstk_intarray:
        push    af
        push    hl
        push    bc
        ld      hl,msg_local
        call    printmsg
        ld      a,'%'
        print_char()
        pop     af                      ; A=name
        push    af
        add     a,'A'
        print_char()
        call    print_parentheses
        jr      retstk_int_end


; ***************************************************************************
; * Structures                                                              *
; ***************************************************************************

retstk_struct:
        dec     hl
        ld      e,(hl)                  ; E=bank
        addhl_N 8
        ld      c,(hl)
        inc     hl
        ld      b,(hl)                  ; BC=line
        inc     hl
        ld      d,(hl)                  ; D=statement
        inc     hl
        push    hl
        push    de
        push    bc
        ld      a,e
        cp      $fe
        jr      nc,rss_nobank
        ex      de,hl
        ld      h,0
        call    print_hl                ; print bank
        ld      a,':'
        print_char()
rss_nobank:
        pop     hl                      ; HL=line
        push    hl
        bit     7,h
        jr      z,rss_not0
        ld      hl,0
rss_not0:
        call    print_hl                ; print line number
        ld      a,':'
        print_char()
        pop     bc
        pop     hl                      ; H=statement
        push    hl
        push    bc
        ld      l,h
        ld      h,0
        call    print_hl                ; print statement
        ld      a,' '
        print_char()
        pop     bc                      ; BC=line
        pop     de                      ; D=statement, E=bank
        ld      (saved_sp),sp
        ld      sp,tempstack            ; switch to internal stack
        ld      hl,(PROG)               ; unbanked program start
        ld      a,e
        cp      $fe
        jp      z,rss_lost
        jr      nc,rss_unbanked
        add     a,a                     ; A=low 8K bank id
        nxtrega nxr_mmu6                ; page bank to MMU6/7
        inc     a
        nxtrega nxr_mmu7
        ld      hl,$c002                ; banked program start
rss_unbanked:
        push    de
rss_find_line:
        ld      d,(hl)
        inc     hl
        ld      e,(hl)                  ; DE=next line number
        inc     hl
        ld      a,d
        cp      $28
        jp      nc,rss_lost             ; "statement lost" if end of program
        ex      de,hl
        and     a
        sbc     hl,bc
        ex      de,hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; DE=line length
        jr      z,rss_found_line        ; on if found correct line
        jp      nc,rss_lost             ; "statement lost" if line too large
        inc     hl
        add     hl,de                   ; address of next line
        jr      rss_find_line

rss_s_hl_number:
        addhl_N 5                       ; skip embedded number
        jr      rss_s_hl_2
rss_found_line:
        pop     de                      ; D=statement to find, HL=line body-1
rss_stmt_hl:
        ld      c,0                     ; "quotes off"
rss_s_hl_1:
        dec     d
        jr      z,rss_found_stmt
rss_s_hl_2:
        inc     hl
        ld      a,(hl)                  ; next character
        cp      $0d
        jp      z,rss_lost
        cp      $0e
        jr      z,rss_s_hl_number
        cp      '"'
        jr      nz,rss_s_hl_4
        dec     c                       ; flip quotes flag
        jr      rss_s_hl_2
rss_s_hl_4:
        cp      ':'
        jr      z,rss_s_hl_5
        cp      token_then
        jr      z,rss_s_hl_5
        cp      token_else
        jr      nz,rss_s_hl_2
rss_s_hl_5:
        bit     0,c                     ; if not in quotes, reached new stmt
        jr      z,rss_s_hl_1
        jr      rss_s_hl_2

rss_found_stmt:                         ; HL=statement body-1
        ld      de,(mmu_addr)           ; copying to start of I/O bank
rss_copy_stmt:
        inc     hl
        ld      a,(hl)
        cp      $0e
        jr      z,rss_num_skipcopy
        call    bind_io_bank
        ld      (de),a                  ; copy a byte
        inc     de
        call    unbind_io_bank
        cp      $0d
        jr      z,rss_copied_stmt
        cp      '"'
        jr      nz,rss_copy_notquote
        dec     c                       ; flip quotes flag
        jr      rss_copy_stmt
rss_copy_notquote:
        cp      ':'
        jr      nz,rss_copy_stmt
        bit     0,c
        jr      nz,rss_copy_stmt
        call    bind_io_bank
        ld      a,$0d
        dec     de
        ld      (de),a                  ; replace ':' with CR
        call    unbind_io_bank
        jr      rss_copied_stmt

rss_num_skipcopy:
        addhl_N 5                       ; skip embedded number
        jr      rss_copy_stmt

rss_copied_stmt:
        nxtregn nxr_mmu6,0              ; page out any banked program
        nxtregn nxr_mmu7,1
        ld      sp,(saved_sp)           ; restore SP
        call    bind_io_bank            ; bind in the I/O bank
        ld      de,(mmu_addr)           ; DE=address of tokenised statement
        ld      hl,$1000                ; HL=offset for detokenised statement
        ld      a,(iobank)
        ld      c,a                     ; C=I/O bank
        ld      b,1                     ; detokenise
        callp3d ide_tokeniser,0
        call    unbind_io_bank
        jr      nc,rss_lost             ; treat as "lost" if error detokenising
        ld      hl,(mmu_addr)
        addhl_N $1000                   ; HL=detokenised statement
rss_print_stmt:
        call    bind_io_bank
        ld      a,(hl)                  ; get next char
        inc     hl
        call    unbind_io_bank
        push    af
        print_char()
        pop     af
        cp      $0d                     ; until CR printed
        jr      nz,rss_print_stmt
rss_end:
        pop     hl
        jp      retstk_loop

rss_lost:
        nxtregn nxr_mmu6,0              ; page out any banked program
        nxtregn nxr_mmu7,1
        ld      sp,(saved_sp)           ; restore SP
        call    unbind_io_bank
        ld      hl,msg_lost             ; "statement lost"
        call    printmsg
        jr      rss_end


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
; * Bind the I/O bank to memory                                             *
; ***************************************************************************

bind_io_bank:
        push    af
        push    bc
        ld      bc,next_reg_select
        ld      a,(mmu_id)
        out     (c),a
        inc     b
        ld      a,(iobank)
        out     (c),a                   ; bind bank to MMU
        pop     bc
        pop     af
        ret

; ***************************************************************************
; * Unbind the I/O bank from memory                                         *
; ***************************************************************************

unbind_io_bank:
        push    af
        push    bc
        ld      bc,next_reg_select
        ld      a,(mmu_id)
        out     (c),a
        inc     b
        ld      a,(saved_mmu_binding)
        out     (c),a                   ; bind original binding to MMU
        pop     bc
        pop     af
        ret


; ***************************************************************************
; * Get current (most local) integer variable values                        *
; ***************************************************************************

get_intvals:
        ld      hl,integer_vars
        ld      bc,$1a00                ; 26 values, starting at 0
get_intvals_loop:
        push    bc
        push    hl
        ld      b,0
        ld      h,b
        callp3d ide_integer_var,0       ; get current value to DE
        pop     hl
        pop     bc
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        inc     c
        djnz    get_intvals_loop
        ret


; ***************************************************************************
; * Print a variable name                                                   *
; ***************************************************************************
; Entry:        HL=address of variable name
; Exit:         HL=address of variable contents
;               E=discriminator

print_varname:
        ld      a,(hl)
        inc     hl
        cp      $7f
        jr      z,print_var_long
        call    print_discrim           ; E=discriminator, now printed
        ld      a,e
        and     %11100000
        cp      %10100000
        jr      nz,print_var_type       ; on if short name
        jr      print_var_long_loop
print_var_long:
        ld      a,(hl)
        inc     hl
        call    print_discrim           ; E=discriminator, now printed
print_var_long_loop:
        ld      a,(hl)
        and     $7f                     ; clear bit 7
        or      $20                     ; ensure bit 5 set, in case long loop var
        print_char()
        bit     7,(hl)
        inc     hl
        jr      z,print_var_long_loop
print_var_type:
        bit     5,e
        ret     nz                      ; finished if simple numeric
        bit     6,e
        ret     z                       ; or numeric array
        ld      a,'$'
        print_char()
        ret

print_discrim:
        ld      e,a                     ; E=discriminator
        and     $1f
        jr      z,print_discrim_bad     ; invalid (lost) if bits 4..0=0
        cp      27
        jr      nc,print_discrim_bad    ; or if >26
        or      $40                     ; make first letter into capital
        print_char()
        ret
print_discrim_bad:
        push    hl
        ld      hl,msg_varlost          ; "(variable lost) ?"
        call    printmsg
        pop     hl
        ret


; ***************************************************************************
; * Print variable value                                                    *
; ***************************************************************************
; Entry:        E=discriminator
;               HL=address of variable contents

print_varval:
        bit     5,e
        jr      nz,print_numeric        ; on for simple numeric
        bit     7,e
        jr      nz,print_array
        ld      a,'='
        print_char()
        ld      c,(hl)
        inc     hl
        ld      b,(hl)                  ; BC=string length
        inc     hl
        ex      de,hl                   ; DE=string address
print_string:
        ld      a,'"'
        print_char()
        call48k PR_STRING_r3            ; print the string
        ld      a,'"'
        print_char()
        ret

print_numeric:
        ld      a,'='
        print_char()
        call48k STACK_NUM_r3            ; stack the number
        call48k PRINT_FP_r3             ; and print it
        ret

; For arrays, we print only the dimensions, not the contents.
print_array:
        push    de
        push    hl
        inc     hl
        inc     hl
        ld      b,(hl)                  ; B=number of dimensions
        inc     hl
        ld      a,'('
print_dims_loop:
        print_char()                    ; print '(' or ','
        push    bc
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; DE=next dimension
        inc     hl
        push    hl
        ex      de,hl
        call    print_hl                ; print dimension
        pop     hl
        pop     bc
        ld      a,','
        djnz    print_dims_loop
        ld      a,')'
        print_char()
        pop     hl
        pop     de
        ret


; ***************************************************************************
; * Show '$' and '()' if appropriate for variable type                      *
; ***************************************************************************
; Entry:        E=discriminator

print_strarrtype:
        bit     5,e
        ret     nz                      ; nothing to do if simple numeric
        bit     6,e
        jr      z,print_arraytype
        ld      a,'$'
        print_char()
print_arraytype:
        bit     5,e
        ret     nz                      ; nothing to do if simple numeric
        bit     7,e
        ret     z
print_parentheses:
        ld      a,'('                   ; show '()' for array references
        print_char()
        ld      a,')'
        print_char()
        ret


; ***************************************************************************
; * Print the number in HL                                                  *
; ***************************************************************************
; Entry:        HL=number

print_hl:
        ld      e,$ff                   ; no leading spaces
        ld      bc,-10000
        call48k OUT_SP_NO_r3            ; output 10000s
        ld      bc,-1000
        call48k OUT_SP_NO_r3            ; output 1000s
        ld      bc,-100
        call48k OUT_SP_NO_r3            ; output 100s
        ld      c,-10
        call48k OUT_SP_NO_r3            ; output 10s
        ld      a,l
        call48k OUT_CODE_r3             ; output units
        ret


; ***************************************************************************
; * Print a message                                                         *
; ***************************************************************************

include "printmsg.asm"


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

msg_help:
        defm    "RET v1.0 by Garry Lancaster",$0d
        defm    "Shows return stack contents",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    " .RET",$0d,$0d
                ;12345678901234567890123456789012
        defm    "Items are shown with the most-",$0d
        defm    "recently encountered first.",$0d,$0d
        defm    "Procedure parameters display as",$0d
        defm    "LOCALs or REFs in reverse order",$0d
        defm    "(ie most recent parameter first)",$0d
        defm    "and the procedure call follows.",$0d,0

msg_lost:
        defm    "(statement lost)",$0d,0

msg_varlost:
        defm    "(variable lost) ?",0

msg_local:
        defm    "LOCAL: ",0

msg_private:
        defm    "PRIVATE: ",0

msg_ref:
        defm    "REF: ",0

msg_refers:
        defm    " --> ",0

msg_badnextzxos:
        defm    "Requires NextZXOS v2.0",'8'+$80

msg_oom:
        defm    "Out of memor",'y'+$80


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

entry_sp:
        defw    0                       ; entry stack pointer

saved_speed:
        defb    0

saved_mmu_binding:
        defb    0

mmu_id:
        defb    0

mmu_addr:
        defw    0

iobank:
        defb    0                       ; allocated 8K bank id

saved_sp:
        defw    0                       ; current stack pointer

integer_vars:
        defs    26*2                    ; current integer variable values

        defs    128                     ; temporary stack
tempstack:
