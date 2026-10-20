; ***************************************************************************
; * Print a message                                                         *
; ***************************************************************************
; Entry: HL=null-terminated message address

printmsg:
        ld      a,(hl)
        inc     hl
        and     a
        ret     z                       ; exit if terminator
        print_char()
        jr      printmsg
