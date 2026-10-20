; ***************************************************************************
; * Print a message                                                         *
; ***************************************************************************
; Entry: HL=$ff-terminated message address

printmsg:
        ld      a,(hl)
        inc     hl
        inc     a
        ret     z                       ; exit if terminator
        dec     a
        print_char()
        jr      printmsg
