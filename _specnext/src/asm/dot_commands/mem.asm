; ***************************************************************************
; * Dot command for showing memory allocation                               *
; * .mem                                                                    *
; ***************************************************************************

include "macros.def"
include "rom48.def"
include "esxapi.def"
include "p3dos.def"
include "nextzxos.def"


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************
; Dot commands always start at $2000, with HL=address of command tail
; (terminated by $00, $0d or ':').

        org     $2000

        ld      hl,msg_help
        call    printmsg
        ld      hl,msg_basicworkspace
        call    printmsg
        call48k FREE_MEM_r3             ; BC=-approx free bytes
        ld      hl,0
        and     a
        sbc     hl,bc                   ; HL=approx free bytes
        call    print_number
        ld      hl,msg_bytes
        call    printmsg
        callesx m_dosversion
        jr      c,bad_nextzxos          ; must be esxDOS if error
        jr      nz,bad_nextzxos         ; need to be in NextZXOS mode
        ld      hl,'N'<<8+'X'
        sbc     hl,bc                   ; check NextZXOS signature
        jr      nz,bad_nextzxos
        ld      hl,$0198
        ex      de,hl
        sbc     hl,de                   ; check version number >= 1.98
        jr      nc,good_nextzxos
bad_nextzxos:
        ld      hl,msg_badnextzxos
        xor     a                       ; A=0, custom error
        scf                             ; Fc=1, error condition
        ret


; ***************************************************************************
; * Memory display                                                          *
; ***************************************************************************

good_nextzxos:
        ld      hl,msg_zxtotal
        call    printmsg
        ld      hl,$0000                ; ZX banks, total
        call    do_idebank
        call    print_banks
        ld      hl,msg_free
        call    printmsg
        ld      hl,$0004                ; ZX banks, available
        call    do_idebank
        call    print_banks
        ld      hl,msg_mmctotal
        call    printmsg
        ld      hl,$0100                ; DivMMC banks, total
        call    do_idebank
        call    print_banks
        ld      hl,msg_free
        call    printmsg
        ld      hl,$0104                ; DivMMC banks, available
        call    do_idebank
        call    print_banks
        ld      hl,msg_lineend
        call    printmsg
        and     a                       ; success
        ret


; ***************************************************************************
; * Display number of 8K banks, and memory total                            *
; ***************************************************************************
; Entry: E=# banks

print_banks:
        ex      de,hl
        ld      h,0                     ; HL=#banks
        push    hl
        call    print_number            ; display number
        ld      hl,msg_banks
        call    printmsg                ; " banks ("
        pop     hl
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; HL=8*banks
        call    print_number            ; display number
        ld      hl,msg_memk
        call    printmsg                ; "K)"
        ret


; ***************************************************************************
; * Make a call to IDE_BANK                                                 *
; ***************************************************************************
; Entry: EHL=parameters for IDE_BANK
; Exit:  E=return value
;        Fc=1 if call failed with rc_inuse
; Does not return if call failed for any other reason

do_idebank:
        callp3d ide_bank,7
        ccf
        ret     nc                      ; exit with Fc=0 if call successful
        cp      rc_inuse
        scf
        ret     z                       ; exit with Fc=1 for rc_inuse error
        pop     hl                      ; discard return address
        ld      hl,msg_idebankfail
        xor     a                       ; A=0, custom error
        scf                             ; Fc=1, error condition
        ret                             ; terminate dot command


; ***************************************************************************
; * Display number in HL, aligned                                           *
; ***************************************************************************
; Entry: HL=number

print_number:
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
        ret


; ***************************************************************************
; * Print a message                                                         *
; ***************************************************************************

include "printmsg.asm"


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

msg_help:
        defm    "MEM v1.1 by Garry Lancaster",$0d,$0d,0

msg_zxtotal:
        defm    "Main memory:",$0d
        defm    "Total: ",0

msg_mmctotal:
        defm    $0d,"DivMMC memory:",$0d
        defm    "Total: ",0

msg_free:
        defm    " Free: ",0

msg_banks:
        defm    " x 8K banks (",0

msg_memk:
        defm    "K)"
msg_lineend:
        defm    $0d,0

msg_basicworkspace:
        defm    "Available BASIC workspace:",$0d,0

msg_bytes:
        defm    " bytes (approx)",$0d,$0d,0

msg_badnextzxos:
        defm    "Requires NextZXOS mod",'e'+$80

msg_idebankfail:
        defm    "IDE_BANK parameter fai",'l'+$80


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************
