; ***************************************************************************
; * Dot command for defragmenting files                                     *
; * .defrag filename                                                        *
; ***************************************************************************

include "macros.def"
include "nexthw.def"
include "rom48.def"
include "esxapi.def"


; ***************************************************************************
; * Internal definitions                                                    *
; ***************************************************************************

BUFFER_SIZE             equ     4096            ; size of RAM copy buffer
                                                ; (also used for filemap)


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************
; Dot commands always start at $2000, with HL=address of command tail
; (terminated by $00, $0d or ':').

        org     $2000

        ld      (entry_sp),sp           ; save initial SP
        ld      a,h
        or      l
        jr      z,show_usage            ; no tail provided if HL=0
        ld      de,filename
        call    get_sizedarg            ; get first argument to filename
        jr      nc,show_usage           ; if none, just go to show usage
        ld      de,0                    ; further args to ROM
        call    get_sizedarg            ; check if any further args
        jr      nc,defrag_init          ; okay if not
show_usage:
        ld      hl,msg_help
        call    printmsg                ; else just show usage info
        and     a                       ; Fc=0, successful
        ret                             ; exit


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************

defrag_init:
        di                              ; disable interrupts for the duration
        ld      bc,buffer_size
        call48k BC_SPACES_r3            ; ensure enough space for 4K buffer
        ld      (bufferaddr),de         ; and save its address
        ld      bc,next_reg_select
        ld      a,nxr_turbo
        out     (c),a
        inc     b
        in      a,(c)                   ; get current turbo setting
        ld      (saved_speed),a         ; save it
        ld      a,turbo_max
        out     (c),a                   ; and increase to maximum
        ld      a,$80                   ; set do not erase with truncate
        callesx m_setcaps
        ld      a,e
        ld      (old_caps),a            ; save old capabilities for restoring
        callesx m_dosversion
        jr      c,bad_nextzxos          ; must be esxDOS if error
        ld      hl,'N'<<8+'X'
        sbc     hl,bc                   ; check NextZXOS signature
        jr      nz,bad_nextzxos
        ld      hl,$0198
        ex      de,hl
        sbc     hl,de                   ; check version number >= 1.98
        jr      nc,good_nextzxos
bad_nextzxos:
        ld      hl,msg_badnextzxos
        jp      err_custom


; ***************************************************************************
; * Open file                                                               *
; ***************************************************************************

good_nextzxos:
        ld      a,'*'                   ; default drive
        ld      hl,filename
        ld      b,esx_mode_read+esx_mode_open_exist
        callesx f_open                  ; attempt to open the file
        jr      c,exit_error            ; exit with any error

        ld      (filehandle),a          ; store the filehandle for later
        call    check_fragmentation     ; is it fragmented?
        jr      c,exit_error
        jr      nz,dodefrag             ; on if it is
        ld      hl,msg_notfragmented    ; report that file is unfragmented
        call    printmsg
        and     a                       ; successful
        jr      exit_error              ; close file and exit


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
        ld      sp,(entry_sp)           ; restore original stack
        push    af                      ; save error status
        push    hl
        ld      a,(filehandle)
        callesx f_close                 ; close the file
        ld      a,(old_caps)
        callesx m_setcaps               ; restore original caps
        ld      a,(saved_speed)
        nxtrega nxr_turbo               ; restore original speed
        pop     hl                      ; restore error status
        pop     af
        ei                              ; re-enable interrupts
        ret


; ***************************************************************************
; * Get the file size                                                       *
; ***************************************************************************

dodefrag:
        ld      a,(filehandle)
        ld      hl,fstat_buffer
        callesx f_fstat                 ; get file information, inc file_size
        jr      c,exit_error
        call    create_unfrag_file      ; create an unfragmented file
        ld      a,(filehandle)
        ld      bc,0
        ld      de,0
        ld      l,esx_seek_set
        callesx f_seek                  ; seek to start of source file
        ld      a,(tmpfilehandle)
        ld      bc,0
        ld      de,0
        ld      l,esx_seek_set
        callesx f_seek                  ; seek to start of dest file
        ld      hl,msg_okay
        call    printmsg
        ld      hl,msg_copyingdata
        call    printmsg                ; "Copying data"
        ld      bc,0                    ; no bytes copied initially
copy_loop:
        ld      hl,(file_size)
        ld      de,(file_size+2)
        and     a
        sbc     hl,bc                   ; subtract bytes copied last iteration
        ld      (file_size),hl
        jr      nc,size_adjusted
        dec     de
        ld      (file_size+2),de
size_adjusted:
        ld      a,d
        or      e
        or      h
        or      l
        jr      z,copy_finished         ; on if 0 bytes left
        push    hl
        push    de
        call    print_byte_size
        pop     de
        pop     hl
        ld      bc,buffer_size          ; 4K to copy
        ld      a,h
        and     $f0
        or      d
        or      e
        jr      nz,got_copy_size
        ld      b,h                     ; just copy remaining bytes if <4K
        ld      c,l
got_copy_size:
        push    bc
        ld      a,(filehandle)
        ld      hl,(bufferaddr)
        callesx f_read                  ; read data from the original file
        jp      c,defrag_failed_read    ; exit if error
        pop     hl
        push    hl
        and     a
        sbc     hl,bc                   ; were all bytes read?
        scf
        ld      a,esx_eio
        jp      nz,defrag_failed_rdsize ; error if not
        ld      a,(tmpfilehandle)
        ld      hl,(bufferaddr)
        callesx f_write                 ; write data to the new file
        jp      c,unfrag_failed_write
        pop     hl
        push    hl
        and     a
        sbc     hl,bc                   ; were all bytes written?
        scf
        ld      a,esx_eio
        jp      nz,unfrag_failed_wrsize ; error if not
        ld      hl,msg_erasesize
        call    printmsg
        pop     bc                      ; BC=#bytes just copied
        jr      copy_loop
copy_finished:
        ld      a,(tmpfilehandle)
        callesx f_close                 ; close the new file
        jp      c,unfrag_failed_newclose
        ld      a,(filehandle)
        callesx f_close                 ; close the original file
        jp      c,defrag_failed_oldclose
        ld      a,'*'
        ld      hl,filename
        callesx f_unlink                ; delete the original file
        jp      c,defrag_failed_delete
        ld      a,'*'
        ld      hl,msg_tmpfilename
        ld      de,filename
        callesx f_rename                ; rename temp to original
        jp      c,unfrag_failed_rename
        ld      hl,msg_okay
        call    printmsg
        call    delete_tmps             ; delete remaining temporary files
        and     a
        jp      exit_error              ; for now just close the file & exit


; ***************************************************************************
; * Defragmented file creation                                              *
; ***************************************************************************

include "fragmentation.asm"


defrag_failed_read:
        ld      de,msg_failed_read
        jp      unfrag_failed_all
defrag_failed_rdsize:
        ld      de,msg_failed_readsize
        jp      unfrag_failed_all
defrag_failed_oldclose:
        ld      de,msg_failed_oldclose
        jp      unfrag_failed_all
defrag_failed_delete:
        ld      de,msg_failed_delete
        jp      unfrag_failed_all


; ***************************************************************************
; * Display size in K/M, aligned                                            *
; ***************************************************************************
; Entry: DEHL=size in bytes

print_byte_size:
        ld      bc,$0a00+'K'    ; >>10 for capacity in KB
        ld      a,d             ; if below 32MB
        cp      2
        jr      c,shift_to_units
        ld      bc,$1400+'M'    ; >>20 for capacity in MB
shift_to_units:
        xor     a               ; no truncation occurred
shift_to_units_loop:
        srl     d               ; calculate HL=capacity in appropriate units
        rr      e
        rr      h
        rr      l
        adc     a,0             ; A=A+Fc
        djnz    shift_to_units_loop
        and     a
        jr      z,no_rounding
        inc     hl              ; increment if anything got shifted out
no_rounding:
        push    bc
        ld      e,' '
        ld      bc,$d8f0        ; -10000
        call48k OUT_SP_NO_r3    ; output 10000s
        ld      bc,$fc18        ; -1000
        call48k OUT_SP_NO_r3    ; output 1000s
        ld      bc,$ff9c        ; -100
        call48k OUT_SP_NO_r3    ; output 100s
        ld      c,$f6           ; -10
        call48k OUT_SP_NO_r3    ; output 10s
        ld      a,l
        call48k OUT_CODE_r3     ; output units
        pop     bc
        ld      a,c
        print_char()            ; "K" or "M"
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
; * Messages                                                                *
; ***************************************************************************

msg_help:
        defm    "DEFRAG v1.7 by Garry Lancaster",$0d
        defm    "Defragments a file",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    " .DEFRAG FILE",$0d,0

msg_notfragmented:
        defm    "File is already defragmented!",$0d,$0d,0

msg_copyingdata:
        defm    "Copying data....",0

msg_erasesize:
        defm    8,8,8,8,8,8,0

msg_failed_read:
        defm    $0d," - FAILED reading file",$0d,0

msg_failed_readsize:
        defm    $0d," - FAILED file read size",$0d,0

msg_failed_oldclose:
        defm    $0d," - FAILED closing old file",$0d,0

msg_failed_delete:
        defm    $0d," - FAILED deleting old file",$0d,0

msg_badnextzxos:
        defm    "Requires NextZXOS v1.98",'+'+$80


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

entry_sp:
        defw    0                       ; entry stack pointer

saved_speed:
        defb    0

old_caps:
        defb    0

filehandle:
        defb    $ff

filename:
        defs    256
