        ;
        ; crc32  Dot command which calculates the CRC32 of
        ;               a given file.
        ;
        ; Written by Janko Stamenović, 2024.
        ;
        ; - since v2.0: Uses esx streams for minimal overhead:
        ;               crc32 of 1 MB file in 5 seconds.
        ; - since v1.1: Faster lookup table.
        ;------------------------------------------------------

        ;------------------------------------------------------
        ; the lookup table address must be decided in advance.
        ; It must start on a 256-aligned address
        ;
ORG_LOOKUPTABLE         equ     $2000 + 5 * 256

        ;------------------------------------------------------
        ; Number of streamable entries in one obtained set
        ;
        ; In the worst case every 2K of a target file could
        ; need a separate entry. Here, 42 entries fit in 256 B,
        ; and using this number makes just ~2% of overhead by
        ; given API calls, compared to using a buffer of
        ; infinite size, so that's enough.
        ;
n_a_entries             equ     42
        ;
        ; The size in bytes for a set of 6-byte sized entries
        ; to be obtained in a single disk_filemap call.
        ;
CB_A_ENTRIES            equ     6*n_a_entries
        ;------------------------------------------------------

        ;------------------------------------------------------
        ; common definitions
include "macros.def"
include "esxapi.def"
include "rom48.def"
include "nexthw.def"
        ; end of common definitions
        ;------------------------------------------------------

        ;------------------------------------------------------
        ; Dot commands: start at $2000,
        ;       Input: HL = 0 or
        ;                   an address of the "command tail"
        org     $2000
Entry:
        ld      (initial_sp),sp         ; preserve the SP
        ld      a,h
        or      l
        jr      z,show_usage            ; 0: no "tail", no args
        ld      de,filename
        call    get_sizedarg
        jr      nc,show_usage           ; no arg
        ld      a,c                     ;
        and     a                       ; a zero-length arg
        jr      z,show_usage

        callesx m_dosversion
        jr      c,bad_nextzxos          ; e.g. esxDOS
        ld      hl,'N'<<8+'X'           ; NextZXOS signature
        sbc     hl,bc
        jr      nz,bad_nextzxos
        ex      de,hl
        ld      bc,$0202
        sbc     hl,bc                   ; version < 2.02 ?
        jr      c,bad_nextzxos

        ld      bc,CB_A_ENTRIES         ; for a_entries
        call48k BC_SPACES_r3            ; get the space
        ld      (a_entries),de          ; store that address

        ld      hl,saved_speed
        ld      a,nxr_turbo             ; store the speed
        call    read_store_nextreg
        ld      a,turbo_max
        out     (c),a                   ; set it to the max

        ; Disable Multiface during streaming: activated by a
        ; button, filesystem access could cause system
        ; instabilities.
        ;
        ld      hl,saved_periph2
        ld      a,nxr_peripheral2
        call    read_store_nextreg
        and     $ff-(1<<3)              ; zero the bit 3
                                        ; to disable multiface
        out     (c),a                   ; update it

        jp      crc32_main
        ;------------------------------------------------------
        ; end of crc32_initCont

show_usage:
        ld      hl,msg_help
        call    printmsg_until_bit7
        and     a                       ; Fc 0: success (!)
        ret

bad_nextzxos:
        ld      hl,msg_badnextzxos      ; custom error msg
        xor     a                       ; A  0: custom error
        scf                             ; Fc 1: "error"
        ret

read_store_nextreg:
        ld      bc,next_reg_select
        out     (c),a
        inc     b
        in      a,(c)
        ld      (hl),a
        ret

        ;------------------------------------------------------
        ; Subroutines used by main

        ;------------------------------------------------------
get_one_set:
        ; reads up to N of 6-byte "streamable" entries for a
        ; file. It is to be called only if more entries should
        ; exist: when no entries returned, exits with an error
        ;
        ld      de,(a_entries)          ;
        ld      (next_entry),de         ; reset the next_entry
        ;
        ld      a,(filehandle)          ; get entries for file
        ld      hl,(a_entries)          ; HL must be >= $4000
        ld      de,n_a_entries          ; up to n of them
        callesx disk_filemap
        ret     c
		     ; HL=address after the last written entry
        ld      (end_entries), hl       ; store the end ptr
        ld      (cardflags),a           ; store the cardflags

        and     a                       ;
        sbc     hl,de                   ; got 0 entries?

        jr      z,error_empty_fill
        and     a                       ; return Fc 0: all OK
        ret
error_empty_fill:
        ; at least one entry was expected, so
        ; prepare to exit and report failure
        ld      hl,msg_no_entries       ; custom error msg
        xor     a                       ; A  0: custom error
        scf                             ; Fc 1: "error"
        ret

        ;------------------------------------------------------
start_disk_stream:
        ; Starts streaming from a given disk stream entry
        ; updating all the variables which track the progress
        ;
        ld      hl,(next_entry)
        ld      e,(hl)                  ; disk address low
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      c,(hl)                  ; disk address high
        inc     hl
        ld      b,(hl)
        inc     hl
        push    bc                      ; push hi disk a.
        ld      c,(hl)                  ; cBlocks
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      (next_entry),hl         ; pointer updated
        pop     hl                      ; pop hi disk a. to HL
        push    bc                      ; push cBlocks
        ld      a,(cardflags)
        ;
        ; now in: HLDE: disk address, BC: cBlocks, A: cardflags
        or      $80     ; "will check before the first read"
                        ; available since NextZXOS v2.01
        callesx disk_strmstart
        pop     ix                      ; pop cBlocks to ix
        ret     c                       ; exit as error if Fc
        ld      a,c
        ld      (disk_data_port),a
        ld      a,b
        ld      (disk_protocol),a
        ret

        ;------------------------------------------------------
end_disk_stream:
        ; each started streaming session _must_ be ended!
        ;
        ld      a,(cardflags)           ; needs cardflags in A
        callesx disk_strmend
        ret

        ;------------------------------------------------------
printmsg_until_bit7:
        ld      a,(hl)
        and     a
        ret     m                       ; bit 7: finish
        inc     hl
        print_char()
        jr      printmsg_until_bit7
        ; printmsg_until_bit7 ends here

        ;------------------------------------------------------
print_long_hex:
        ;
        ; HL has to point to the MSB
        ld      b,4
print_byte_hex:
        ld      a,(hl)                  ; current byte
        swapnib
        call    print_nibble            ; upper
        ld      a,(hl)                  ; same byte, again
        call    print_nibble            ; lower
        dec     hl                      ; down
        djnz    print_byte_hex
        ret
print_nibble:
        and     $0F
        cp      10
        jr      nc, print_a_to_f
        add     a,'0'
        print_char()
        ret
print_a_to_f:
        add     a,'a'-10
        print_char()
        ret

        ;------------------------------------------------------
is_hl_p_w_zero:
        ; to check if the word at HL+1 is also 0 when A is
        ;
        inc     hl
        or      (hl)
        ret     nz
        inc     hl
        or      (hl)
        ret

        ;------------------------------------------------------
store_cpl_crc:
        ; store the complemented crc to the alternate regs
        ;
        exx                             ; the alternate crc set
        ld      a,e
        cpl                             ; ~ and store
        ld      (crc),a
        ld      a,d
        cpl
        ld      (crc+1),a
        ld      a,c
        cpl
        ld      (crc+2),a
        ld      a,b
        cpl
        ld      (crc+3),a
        exx                             ; back from the crc set
        ret

        ;------------------------------------------------------
        ; lookup table related
        ;
ORG_LOOKUPTABLE_HI equ (ORG_LOOKUPTABLE >> 8)
ORG_LOOKUPTABLE_LO equ (ORG_LOOKUPTABLE & $ff)

 if 0 != ORG_LOOKUPTABLE_LO
.error Lookup table address must be aligned to 256
 endif
        ;------------------------------------------------------

        ;------------------------------------------------------
M_CALC_ONE MACRO
        ; a single byte crc32 calc pass
        ;
        ; allows reuse and an unroll in the tightest path
        ;
        in      a,(c)                   ; read the byte
        exx                             ; go into the crc set
        xor     e                       ; a = a xor crc lsb
        ld      l,a                     ; lut addr calc
        ld      h, ORG_LOOKUPTABLE_HI
        ld      a,(hl)                  ; lut[i] lsb
        inc     h
        xor     d                       ; xor the crc lsb+1
        ld      e,a                     ; to crc lsb
        ld      a,(hl)                  ; lut[i] lsb+1
        inc     h
        xor     c                       ; xor the crc lsb+2
        ld      d,a                     ; to crc lsb+1
        ld      a,(hl)                  ; lut[i] lsb+2
        inc     h
        xor     b                       ; xor crc lsb+3
        ld      c,a                     ; to crc lsb+2
        ld      b,(hl)                  ; lut[i] msb to crc msb
        exx                             ; out from the crc set
ENDM
        ;------------------------------------------------------

        ;------------------------------------------------------
crc32_calc_b:
        ; "in" B bytes doing a CRC32 step on each
        ;
        M_CALC_ONE                      ; m. expanded here
        djnz    crc32_calc_b
        ret
        ;------------------------------------------------------

        ;------------------------------------------------------
        ; the "main"

        ;------------------------------------------------------
crc32_main:
        ld      hl,filename
        ld      a,'*'                   ; default drive
        ld      b,esx_mode_read         ; read, open existing
        callesx f_open
        ld      (filehandle),a          ; store the file handle
        jp      c,exit_with_code

        ld      hl,0                    ; crc = 0
        ld      (crc),hl
        ld      (crc+2),hl

        ld      a,(filehandle)          ; get dw bytes in file
        ld      hl,fstat_data
        callesx f_fstat
        jp      c,close_and_exit_a

        ld      hl,(fstat_data+7)       ; init dwBytesLeft
        ld      (dwBytesLeft),hl
        ld      hl,(fstat_data+9)
        ld      (dwBytesLeft+2),hl
                                        ; check if 0 left
        jp      next_set_check_0        ; if not, then each set
        ; -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
        ;
        ; the loops in main
        ; -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
        ; each set of entries
calc_next_set:
        ; here we know we need more entries
        call    get_one_set
        jp      c,close_and_exit_a        ; no entries: error
        ; -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
        ; each entry
calc_next_entry:
        call    start_disk_stream
        jp      c,close_and_exit_a

        exx                             ; the alternate set:
        ld      a,(crc)                 ; load the ~crc there
        cpl                             ; (will be used while
        ld      e,a                     ; this stream lasts)
        ld      a,(crc+1)
        cpl
        ld      d,a
        ld      a,(crc+2)
        cpl
        ld      c,a
        ld      a,(crc+3)
        cpl
        ld      b,a
        exx                             ; back from the crc set
        ; -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
        ; each block
next_block:
        ld      a,(disk_data_port)
        ld      c,a                     ; C must be the port

        ld      hl,dwBytesLeft+1        ; is dwBytesLeft
        ld      a,(hl)                  ; at least 512?
        and     $fe
        jr      nz,more_or_512          ; more often
        inc     hl                      ; less often
        or      (hl)                    ;
        inc     hl
        or      (hl)
        jp      z,less_than_512_left

more_or_512:
        ld      a,(disk_protocol)
        and     a                       ; 0: must wait before
                                        ;       the next block
        jr      nz,init_tight
wait_ready_1:
        in      a,(c)                   ; in a:
        inc     a                       ; was -1? "not ready"
        jr      z,wait_ready_1          ; then wait more
        inc     a                       ; was -2? "ready"
        jp      nz,error_in_wait        ; others: error

init_tight:
        ld      b,512/4                 ; 512 B, 4B in one pass
        ; -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
next_4_bytes:                           ; the tight loop start
        M_CALC_ONE                      ; m. expanded here
        M_CALC_ONE                      ; m. expanded here
        M_CALC_ONE                      ; m. expanded here
        M_CALC_ONE                      ; m. expanded here
        djnz    next_4_bytes            ; the tight loop end
        ; -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
        ld      hl,(dwBytesLeft)        ; certainly >= 512
        ld      de,512                  ; dwBytesInFile -= 512
        and     a
        sbc     hl,de
        ld      (dwBytesLeft),hl
        jr      nc,get_disk_crc_in

        ld      hl,(dwBytesLeft+2)      ; upper part
        ld      de,0
        sbc     hl,de
        ld      (dwBytesLeft+2),hl

get_disk_crc_in:
        ld      a,(disk_protocol)
        and     a                       ; 0: get crc and wait
        jr      nz,simpler_prot         ; other: simpler
                         ; get the 2-byte CRC of the disk block
        in      a,(c)        ;  after a 12T "in", a 4T NOP is
        nop                  ; _necessary_ before the next "in"
        in      a,(c)
simpler_prot:
        ld      hl,dwBytesLeft          ; if some bytes left
        ld      a,(hl)                  ; inc the lower word
        inc     hl
        or      (hl)
        jr      nz,more_bytes           ; then continue
        call    is_hl_p_w_zero
        jp      z,store_and_finish      ; 0 left? store,finish

more_bytes:
        dec     ix                      ; block count--
        ld      a,ixl
        or      ixh
        jp      nz,next_block           ; until all blocks
        ; -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
        call    store_cpl_crc

        call    end_disk_stream
        jp      c,close_and_exit_a        ; could also fail?

        ld      de,(next_entry)         ; next_entry
        ld      hl,(end_entries)
        and     a
        sbc     hl,de                   ; reached an end?
        jp      nz,calc_next_entry      ; no, next entry
        ; -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
next_set_check_0:
        ld      hl,dwBytesLeft          ; zero bytes left?
        ld      a,(hl)                  ; in low word
        inc     hl
        or      (hl)
        jp      nz,calc_next_set        ; not: next set
        call    is_hl_p_w_zero          ; or in high word
        jp      nz,calc_next_set        ; not: next set
        ; -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
        jr      print_crc_and_exit
        ; -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

less_than_512_left:
        ld      a,(disk_protocol)       ; protocol:
        and     a                       ; 0: must wait
        jr      nz,more_or_256          ; non 0: skip the wait

wait_ready_2:
        in      a,(c)                   ; in:
        inc     a                       ; was -1? "not ready"
        jr      z,wait_ready_2          ; then wait more
        inc     a                       ; was -2? "ready"!
        jp      nz,error_in_wait        ; other values error

more_or_256:                            ; at least 256 B left?
        ld      a,(dwBytesLeft+1)       ; (also can't be more
        and     a                       ; than 511)
        jr      z,less_than_256_left

        ld      b,0                     ; calc 256 bytes
        call    crc32_calc_b

less_than_256_left:
        ld      a,(dwBytesLeft)         ; still something
        and     a                       ; left?
        jr      z,store_and_finish      ; no, store, finish

        ld      b,a                     ; calc what's left
        call    crc32_calc_b

store_and_finish:
        call    store_cpl_crc           ; store crc32
        call    end_disk_stream         ; the final
        jr      c,close_and_exit_a        ; could fail even
                                        ; the last time
        ; fall through to  print_crc_and_exit
        ;
print_crc_and_exit:
        ld      hl,crc+3                ; addr of the msb
        call    print_long_hex
        ld      a,$0d                   ; CR
        print_char()
        and     a                       ; return code: OK
        ; fall through close_and_exit_a
        ; - - - - - - - - - - - - - - - - - - - - - - - - - - -
close_and_exit_a:
        ld      sp,(initial_sp)         ; restore the stack
        push    hl                      ; (close the
        push    af                      ; file: needed if
        ld      a,(filehandle)          ; this dot command
        callesx f_close                 ; is called by
        pop     af                      ; another dot
        pop     hl                      ; command)
        ; fall thru to exit_with_code
       ; - - - - - - - - - - - - - - - - - - - - - - - - - - -
exit_with_code:
        ld      sp,(initial_sp)         ; restore the stack
        push    af
        push    hl
        ld      hl,(a_entries)
        ld      a,h
        or      l
        jr      Z,skip_reclaim
        ld      bc,CB_A_ENTRIES
        call48k RECLAIM_2
skip_reclaim:
        ld      a,(saved_periph2)       ; restore multiface
        nxtrega nxr_peripheral2
        ld      a,(saved_speed)         ; restore speed
        nxtrega nxr_turbo
        pop     hl
        pop     af
        ; - - - - - - - - - - - - - - - - - - - - - - - - - - -
        ; the program exits here        ; file closed outside
        ret                             ; ret; if Fc, an error
        ;------------------------------------------------------

error_in_wait:
        call    end_disk_stream         ; must end it!
        ld      hl,error_waiting        ; custom error msg
        xor     a                       ; A  0: custom error
        scf                             ; Fc 1: "error"
        jr      exit_with_code

        ;------------------------------------------------------
        ; end of the "main"

ARG_PARAMS_DEHL equ     1
include "arguments.asm"

        ;------------------------------------------------------
        ; messages
        ;------------------------------------------------------
msg_badnextzxos:
        defm    "Required NextZXOS v2.02 or later",'+'+$80
msg_no_entries:
        defm    "Filemap entries missin","g"+$80
error_waiting:
        defm    "Wait on disk block faile","d"+$80
msg_help:
        defm    "crc32 v2.1 by Janko Stamenovic"
        defm                 21,1,8 ; an attempt to create
        defm               "'",21,0 ; approx. "c with Acute"
                                    ; (U+0106) appearance. Uses
                                    ; zero inside: $80 ends all
        defm    $d
        defm    "  Calculates the CRC32 of a",$0d
        defm    "  given file",$0d,$0d
        defm    "SYNOPSYS:",$0d
        defm    " .crc32 FILENAME",$0d,$80  ; needed $80 as end

        ;------------------------------------------------------
        ; variables
        ;------------------------------------------------------
initial_sp:     defw    0               ; initial stack pointer


saved_speed:    defb    0               ; initial speed
saved_periph2:  defb    0               ; i. peripheral2 state
filehandle:     defb    0               ; file handle
cardflags:      defb    0               ; used by disk_strm*
disk_data_port: defb    0               ; used in "in"
disk_protocol:  defb    0               ; keeps the protocol

a_entries:      defw    0               ; entries table addr
end_entries:    defw    0               ; ptr behind last
next_entry:     defw    0               ; ptr to next entry

crc:            defw    0, 0            ; 4-byte crc value
dwBytesLeft:    defw    0, 0            ; 4-byte counter

fstat_data:     defs    11              ; fstat structure

filename:       defs    256             ; filename

end_of_code:

include "crc32_lut.asm"
        ;------------------------------------------------------
        ; end of crc32  Dot command which calculates the CRC32
