; ***************************************************************************
; * File defragmentation routines                                           *
; ***************************************************************************
; Before including, define BUFFER_SIZE (min 1542 bytes) to the size of a buffer
; provided at the address to be stored in buffer_addr.
; The name of the final file should be stored at "filename".


; ***************************************************************************
; * Internal definitions                                                    *
; ***************************************************************************

FILEMAP_SIZE            equ     257     ; allows for 4GB if each
                                        ; span is 32768 sectors
                                        ; (256*32768*0.5K)

if ((FILEMAP_SIZE*6) > BUFFER_SIZE)
.ERROR Filemap exceeds allocated buffer space
endif


; ***************************************************************************
; * Create an unfragmented file                                             *
; ***************************************************************************
; Entry: 32-bit filesize stored at file_size
;        OR fstat_buffer filled in by a call to F_FSTAT/F_STAT.
; Exit:  tmpfilehandle contains handle of (open) created file
; Does not return unless successful

create_unfrag_file:
        ld      hl,msg_findingspace
        call    printmsg                ; "Finding space..."
unfrag_search_loop:
        ld      a,'.'
        print_char()
        ld      hl,(temp_num)
        inc     hl                      ; HL=next temporary file number
        ld      (temp_num),hl
        call    settempfilename         ; set up the temporary file name
        ld      hl,msg_tmpfilename
        ld      b,esx_mode_write+esx_mode_read+esx_mode_creat_trunc
        ld      a,'*'
        callesx f_open                  ; create new temporary file
        jp      c,unfrag_failed_creatent; if failed, delete temps & exit
        ld      (tmpfilehandle),a
        ld      de,(file_size)
        ld      bc,(file_size+2)
        callesx f_ftruncate             ; expand to required size
        jp      c,unfrag_failed_expand  ; if failed, delete temps & exit
        ld      a,(tmpfilehandle)
        call    check_fragmentation     ; is it fragmented?
        jp      c,unfrag_failed_fragm   ; if failed, delete temps & exit
        ret     z                       ; finished if now unfragmented
        ld      a,(tmpfilehandle)
        callesx f_close                 ; close the temporary file
        jr      unfrag_search_loop      ; back for more


; ***************************************************************************
; * Delete temporary files                                                  *
; ***************************************************************************

delete_tmps:
        ld      hl,msg_deletingtemps
        call    printmsg                ; "Deleting temporary files"
delete_tmps_loop:
        ld      a,'.'
        print_char()
        ld      hl,(temp_num)           ; get next temp file to delete
        ld      a,h
        or      l
        jr      z,delete_tmps_done      ; exit once none left
        call    settempfilename         ; set up the file name
        ld      a,'*'
        ld      hl,msg_tmpfilename
        callesx f_unlink                ; delete the file
        ld      hl,(temp_num)
        dec     hl
        ld      (temp_num),hl
        jr      delete_tmps_loop
delete_tmps_done:
        ld      hl,msg_okay
        jp      printmsg                ; print OK and exit


; ***************************************************************************
; * Generate temporary filename                                             *
; ***************************************************************************
; Entry: HL=temp file number (preserved)

settempfilename:
        ld      de,msg_tmpfilename_num
        ld      a,h
        call    sethighnibble
        ld      a,h
        call    setlownibble
        ld      a,l
        call    sethighnibble
        ld      a,l
        jr      setlownibble
sethighnibble:
        rrca
        rrca
        rrca
        rrca
setlownibble:
        and     $0f
        add     a,'0'
        cp      '9'+1
        jr      c,gothexnibble
        add     a,'a'-('9'+1)
gothexnibble:
        ld      (de),a
        inc     de
        ret


; ***************************************************************************
; * Check if file is fragmented                                             *
; ***************************************************************************
; Entry: A=handle
; Exit(failure):  Fc=1, A=error
; Exit(success):  Fc=0, Fz=1 if unfragmented

check_fragmentation:
        push    af
        ld      bc,0
        ld      de,0
        ld      l,esx_seek_set
        callesx f_seek                  ; seek to start of file
        pop     af
        push    af
        ld      hl,(bufferaddr)
        ld      bc,1
        callesx f_read                  ; read 1 byte to ensure starting cluster
        pop     af
        ld      hl,(bufferaddr)
        ld      de,FILEMAP_SIZE
        callesx disk_filemap
        ret     c
        push    hl                      ; save address after last buffer entry
        ld      hl,(bufferaddr)
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    de                      ; TOS,BC=4-byte card address
check_frag_loop:
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; DE=sector count
        inc     hl
        ex      de,hl                   ; DE=buffer address, HL=sector count
        bit     1,a
        jr      nz,check_frag_add_blocks
check_frag_add_bytes:
        ; If byte-addressed, add 512*sector count to the card address
        push    hl
        ld      h,l
        ld      l,0
        ex      (sp),hl
        pop     ix
        ld      l,h
        ld      h,0                     ; HLIX=256*sector count
        add     ix,ix
        adc     hl,hl                   ; HLIX=512*sector count
        add     ix,bc
        pop     bc
        adc     hl,bc                   ; HLIX=following card address
        jr      check_frag_test_next
check_frag_add_blocks:
        ; If block-addressed, add sector count to the card address
        add     hl,bc
        push    hl
        pop     ix
        pop     bc
        ld      hl,0
        adc     hl,bc                   ; HLIX=following card address
check_frag_test_next:
        ; HLIX=next card address
        ; DE=buffer address after current entry
        ; TOS=buffer address after last entry
        ex      (sp),hl                 ; HL=buffer address after last entry
        and     a
        sbc     hl,de
        pop     bc
        ret     z                       ; exit with Fc=0, Fz=1 if done
        push    bc
        add     hl,de                   ; reform address
        ex      (sp),hl                 ; and re-stack
        ex      de,hl                   ; HL=buffer address after current
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        push    ix
        ex      (sp),hl
        and     a
        sbc     hl,bc                   ; is low word of card addr the same?
        jr      nz,check_frag_failed    ; if not, file is fragmented
        pop     hl
        push    bc
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        ex      de,hl
        and     a
        sbc     hl,bc                   ; is high word of card addr the same?
        jr      nz,check_frag_failed    ; if not, file is fragmented
        pop     hl
        push    bc
        ld      b,h
        ld      c,l                     ; TOS,BC=4-byte card address
        ex      de,hl                   ; HL=buffer address of sector count
        jr      check_frag_loop
check_frag_failed:
        pop     bc                      ; discard values
        pop     bc
        xor     a
        inc     a                       ; Fc=0, Fz=0, fragmented
        ret


; ***************************************************************************
; * Image creation failed                                                   *
; ***************************************************************************

unfrag_failed_creatent:
        ld      hl,msg_failed_create
        jr      unfrag_failed_notmp
unfrag_failed_expand:
        ld      de,msg_failed_expand
        jr      unfrag_failed_all
unfrag_failed_fragm:
        ld      de,msg_failed_fragm
        jr      unfrag_failed_all
unfrag_failed_write:
        ld      de,msg_failed_write
        jr      unfrag_failed_all
unfrag_failed_wrsize:
        ld      de,msg_failed_writesize
        jr      unfrag_failed_all
unfrag_failed_newclose:
        ld      de,msg_failed_newclose
        jr      unfrag_failed_all
unfrag_failed_rename:
        ld      de,msg_failed_rename
        jr      unfrag_failed_all

unfrag_failed_all:
        push    de
        push    af
        ld      a,(tmpfilehandle)
        callesx f_close                 ; close the temporary file
        pop     af
        pop     hl
unfrag_failed_notmp:
        push    af                      ; save error status
        call    printmsg
        ld      hl,msg_origfile
        call    printmsg
        ld      hl,filename
        call    printmsg
        ld      hl,msg_newfile
        call    printmsg
        ld      hl,msg_tmpfilename
        call    printmsg
        ld      hl,msg_endfilenames
        call    printmsg
        call    delete_tmps             ; delete all temporary files
        pop     af
        jp      exit_error


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

msg_findingspace:
        defm    "Finding space..",0

msg_deletingtemps:
        defm    "Erasing temps.",0

msg_failed_create:
        defm    $0d," - FAILED creating tmp file",$0d,0

msg_failed_expand:
        defm    $0d," - FAILED reserving space",$0d,0

msg_failed_fragm:
        defm    $0d," - FAILED checking fragmentation",$0d,0

msg_failed_write:
        defm    $0d," - FAILED writing file",$0d,0

msg_failed_writesize:
        defm    $0d," - FAILED file write size",$0d,0

msg_failed_newclose:
        defm    $0d," - FAILED closing new file",$0d,0

msg_failed_rename:
        defm    $0d," - FAILED renaming new file",$0d,0

msg_origfile:
        defm    "Final file: '",0

msg_newfile:
        defm    "'",$0d,"Temp file: '",0

msg_endfilenames:
        defm    "'",$0d,0

msg_okay:
        defm    "OK    ",$0d,0

msg_tmpfilename:
        defm    "$$$unfrag_tmp"
msg_tmpfilename_num:
        defm    "0000$$$",0


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

temp_num:
        defw    0                       ; number of current temporary file

bufferaddr:
        defw    0                       ; address of buffer in main RAM

tmpfilehandle:
        defb    $ff

fstat_buffer:
        defb    0                       ; drive
        defb    0                       ; drive details
        defb    0                       ; attributes
        defw    0,0                     ; time, date
file_size:
        defw    0,0                     ; filesize
