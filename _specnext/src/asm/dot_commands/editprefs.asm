; ***************************************************************************
; * Dot command to change the Editor preferences                            *
; ***************************************************************************

include "macros.def"
include "nexthw.def"
include "rom48.def"
include "sysvars.def"
include "bastoken.def"
include "esxapi.def"
include "nextzxos.def"


; ***************************************************************************
; * Internal definitions                                                    *
; ***************************************************************************

; Size of a colour scheme
colour_scheme_size      equ     32+(32*2)       ; 32 attributes, 32 palette entries

; Size of an integer array
int_array_size          equ     64*2

; Use some main RAM below $c000 for buffers to pass to IDE_BROWSER.
; The stack will also be located here
ram_buffer              equ     $6000
; Space for colour scheme, integer array plus a 128-byte stack
RAM_BUFFER_SIZE         equ     colour_scheme_size+int_array_size+128


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************

        org     $2000

editprefs_init:
        ld      (saved_sp),sp           ; save entry SP for error handler
        push    hl                      ; save address of arguments
        ld      bc,next_reg_select
        ld      a,nxr_turbo
        out     (c),a
        inc     b
        in      a,(c)                   ; get current turbo setting
        ld      (saved_turbo),a
        ld      a,turbo_max
        out     (c),a                   ; and set to maximum
        callesx m_dosversion
        jr      c,bad_nextzxos          ; must be esxDOS if error
        jr      nz,bad_nextzxos         ; need to be in NextZXOS mode
        ld      hl,'N'<<8+'X'
        sbc     hl,bc                   ; check NextZXOS signature
        jr      nz,bad_nextzxos
        ld      hl,$0207
        ex      de,hl
        sbc     hl,de                   ; check version number >= 2.07
        ld      hl,msg_badnextver
        jr      c,err_custom
        ld      hl,stderr_handler
        callesx m_errh                  ; install error handler to reset turbo
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
        jr      nc,show_usage           ; if none, just go to show usage
        call    check_options
        jr      nz,show_usage           ; if not an option, go to show usage
parse_remaining:
        call    get_sizedarg            ; get an argument
        jr      nc,editprefs_start    ; okay if none
        call    check_options
        jr      z,parse_remaining       ; okay if a valid option
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
; * Restore turbo setting and exit with any error condition                 *
; ***************************************************************************

error_handler:
        ld      sp,(saved_sp)           ; restore entry SP
restore_all:
        push    af
        ld      a,(saved_turbo)
        nxtrega nxr_turbo               ; restore entry turbo setting
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
; NOTE: When using IDE_BASIC, the workspace pointers are reset so that the
;       calculator stack will overwrite the space we are reserving. Work
;       around this by ensuring there is enough space for calculator usage
;       before the area we actually use.

CALCULATOR_USAGE        equ     40              ; enough for 8 calculator entries

editprefs_start:
        ; Allocate workspace for IDE_BASIC usage
        ld      bc,msg_spectrum_chrS_end-msg_spectrum_chrS+CALCULATOR_USAGE
        call48k BC_SPACES_r3            ; DE=workspace address
        addde_N CALCULATOR_USAGE

        ; Set chars per line
        ld      a,(chars_per_line)
        and     a
        jr      z,cpl_end
        ld      hl,msg_spectrum_chrS
        ld      bc,msg_spectrum_chrS_end-msg_spectrum_chrS
        push    de
        ldir                            ; copy command to RAM buffer
        pop     hl                      ; command address
        callp3d ide_basic,0             ; set chars per line

cpl_end:

        ; Save data in the main RAM buffer
        ; The stack is also relocated into the main RAM buffer so it is
        ; below $c000 and safe for use with +3DOS calls.
        ld      hl,ram_buffer
        ld      de,saved_ram
        ld      bc,RAM_BUFFER_SIZE
        ldir                            ; save some RAM below $c000
        ld      sp,ram_buffer+RAM_BUFFER_SIZE

        ; Set Editor colours
        ld      hl,(colour_settings)
        ld      a,h
        or      l
        jr      z,editprefs_noset       ; no colour data to set
        ld      de,ram_buffer
        push    de
        ld      bc,colour_scheme_size
        ldir                            ; copy colour scheme
        pop     hl                      ; colour data address
        ld      de,0                    ; get/set Browser/Editor settings
        ld      a,7                     ; A=7, change Editor colours
        callp3d ide_browser,7           ; set Editor colours

editprefs_noset:
        ld      hl,(save_addr)
        ld      a,h
        or      l
        jr      z,editprefs_end         ; don't want to fetch current scheme
        push    hl
        ld      hl,ram_buffer
        push    hl
        ld      de,0                    ; get/set Browser/Editor settings
        ld      a,6                     ; A=6, get Editor colours
        callp3d ide_browser,7           ; get Editor colours
        pop     hl                      ; HL=ram_buffer
        pop     de                      ; DE=(save_addr)
        ld      a,d
        and     a
        jr      z,editprefs_setarray    ; on if dest is integer array
        ld      bc,colour_scheme_size
        ldir                            ; else just copy to memory address
        jr      editprefs_end
editprefs_setarray:
        ; First the scheme must be converted to 64 x 16-bit values
        ld      de,ram_buffer+colour_scheme_size
        push    de
        ld      b,32                    ; 32 x 8-bit attributes to convert
esa_convattr_loop:
        ld      a,(hl)
        inc     hl
        ld      (de),a                  ; copy attribute as low byte
        inc     de
        xor     a
        ld      (de),a                  ; set high byte to zero
        inc     de
        djnz    esa_convattr_loop
        ld      a,32                    ; 32 x 16-bit palette values to convert
esa_convpal_loop:
        ld      c,(hl)                  ; C=RRRGGGBB
        inc     hl
        ld      b,(hl)                  ; B=0000000B
        inc     hl
        srl     b                       ; B=0, Fc=blue low bit
        rl      c                       ; C=RRGGGBBB, Fc=red high bit
        rl      b                       ; BC=0000000R RRGGGBBB
        ex      de,hl
        ld      (hl),c                  ; store converted palette value
        inc     hl
        ld      (hl),b
        inc     hl
        ex      de,hl
        dec     a
        jr      nz,esa_convpal_loop
        pop     hl                      ; HL=address of converted data
        ; Now set the 64 integer array elements
        ld      a,(save_addr)
        dec     a
        ld      c,a                     ; C=array id 0..25
        ld      b,64                    ; 64 elements
esa_set_loop:
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; DE=value
        inc     hl
        push    bc
        push    hl
        ld      a,64
        sub     b
        ld      l,a                     ; L=array index 0..63
        ld      h,1                     ; H=1, set
        ld      b,h                     ; B=1, array; C=array id 0..25
        callp3d ide_integer_var,7       ; set array element
        pop     hl
        pop     bc
        djnz    esa_set_loop

editprefs_end:

        ; Restore the main RAM that we saved
        ld      sp,temp_stack           ; move SP to temp area in DivMMC RAM
        ld      hl,saved_ram
        ld      de,ram_buffer
        ld      bc,RAM_BUFFER_SIZE
        ldir                            ; restore the RAM we used
        ld      sp,(saved_sp)           ; restore SP to that set by BASIC
        and     a                       ; completed successfully
        jp      error_handler           ; exit via err handler to restore turbo


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
        defopt  "-c",option_chars
        defopt  "--chars",option_chars
        defopt  "--scheme",option_scheme
        defopt  "--scheme-file",option_scheme_file
        defopt  "--get-scheme",option_get_scheme
        endopts()


; ***************************************************************************
; * --scheme NAME                                                           *
; ***************************************************************************

option_scheme:
        call    get_sizedarg            ; get scheme name into temparg
        ld      a,c
option_scheme_fail:
        ld      hl,msg_badscheme
        and     a
        jp      z,err_custom
        ld      hl,colour_scheme_names
        ld      b,0
check_next_scheme:
        ld      de,temparg
        ld      a,(hl)
        and     a
        jr      z,option_scheme_fail
check_scheme_loop:
        ld      a,(de)
        inc     de
        and     a
        jr      z,check_scheme_end
        or      $20                     ; make lower-case
        cp      (hl)
        inc     hl
        jr      z,check_scheme_loop     ; until char mismatch
        dec     hl
skip_scheme_loop:
        ld      a,(hl)                  ; skip remainder of scheme name
        inc     hl
        and     a
        jr      nz,skip_scheme_loop
        inc     b                       ; next scheme id
        jr      check_next_scheme

check_scheme_end:
        cp      (hl)                    ; match name must also end
        jr      nz,skip_scheme_loop
        ld      d,b
        ld      e,colour_scheme_size
        mul_de()
        ld      hl,colour_scheme_data
        add     hl,de
        ld      (colour_settings),hl
        ret


; ***************************************************************************
; * --scheme-file FILE                                                      *
; ***************************************************************************

option_scheme_file:
        call    get_sizedarg            ; get file name into temparg
        ld      a,'*'
        ld      hl,temparg
        ld      de,fileheader
        ld      b,esx_mode_read+esx_mode_open_exist+esx_mode_use_header
        callesx f_open                  ; attempt to open the file
        jp      c,error_handler         ; exit with any error
        push    af                      ; save handle
        ld      hl,colour_scheme_default; read over default scheme so short
        ld      bc,colour_scheme_size   ; files retain original palette data
        ld      (colour_settings),hl
        callesx f_read
        pop     bc                      ; B=handle
        push    af                      ; save error condition
        ld      a,b
        callesx f_close
        pop     af
        jp      c,error_handler         ; exit if error reading file
        ret


; ***************************************************************************
; * --get-scheme ADDR / LETTER                                              *
; ***************************************************************************

option_get_scheme:
        call    get_sizedarg            ; get addr/letter into temparg
        dec     c
        jr      z,ogs_letter            ; length=1, must be a letter
        inc     c
        call    get_number
        ex      de,hl                   ; DE=numeric value
        ld      hl,msg_bad_dest
        jp      c,err_custom            ; error if invalid number
        ld      a,d                     ; don't allow address < $6200, to
        cp      $62                     ; distinguish from letter and prevent
        jp      c,err_custom            ; clash with ram_buffer at $6000
        ld      (save_addr),de
        ret
ogs_letter:
        ld      a,(temparg)
        and     $df                     ; make letter upper-case
        sub     'A'
        ld      hl,msg_bad_dest
        jp      c,err_custom            ; error if not a letter
        cp      26
        jp      nc,err_custom
        inc     a                       ; A=1..26
        ld      (save_addr),a
        ret


; ***************************************************************************
; * -c N, --chars N                                                         *
; ***************************************************************************

option_chars:
        call    get_sizedarg            ; get N into temparg
        call    get_number
        ex      de,hl                   ; DE=numeric value
        ld      hl,msg_bad_cpl
        jp      c,err_custom            ; error if invalid number
        ld      a,d
        and     a
        jp      nz,err_custom           ; error if >255
        ld      a,e
        cp      32
        jr      z,set_cpl
        cp      64
        jr      z,set_cpl
        cp      85
        jp      nz,err_custom           ; error if not a supported value
set_cpl:
        ld      (chars_per_line),a
        ret


; ***************************************************************************
; * Parse the current argument as a number                                  *
; ***************************************************************************
; Entry:        C=argument length
; Exit:         Fc=1, error
;               Fc=0, success and HL=number

get_number:
        ld      a,c
        cp      1
        ret     c                       ; Fc=1, error if argument length 0
        ld      de,temparg
        ld      hl,0                    ; initialise number
        ld      ixl,c                   ; IXl=loop counter
get_number_loop:
        add     hl,hl                   ; HL=current value*2
        ret     c                       ; error if overflow
        ld      b,h
        ld      c,l                     ; BC=current value*2
        add     hl,hl
        ret     c
        add     hl,hl
        ret     c
        add     hl,bc                   ; HL=current value*10
        ret     c
        ld      a,(de)
        inc     de
        sub     '0'
        ret     c                      ; error if non-numeric char
        cp      10
        ccf
        ret     c
        ld      b,0
        ld      c,a
        add     hl,bc                   ; add in new digit
        ret     c                       ; error if overflow
        dec     ixl
        jr      nz,get_number_loop
        ret                             ; exit with Fc=0, success


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

; TAB 32 used within help message so it is formatted wide in 64/85 column mode.
msg_help:
        defm    "EDITPREFS v1.2",23,32,0
        defm    "by Garry Lancaster",$0d
        defm    "Sets Editor preferences",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    " .EDITPREFS [OPTION]...",$0d
        defm    "OPTIONS:",$0d
        defm    " -h, --help",23,32,0
        defm    "     Display this help",$0d
        defm    " -c N, --chars N",23,32,0
        defm    "     Set N chars per line",$0d
        defm    "     Allowable values:",23,32,0
        defm    "      32, 64, 85",$0d
        defm    " --scheme NAME",23,32,0
        defm    "     Choose colour scheme",$0d
        defm    "     Available scheme names:",23,32,0
        defm    "      default, dark, grey, zx128",$0d
        defm    " --scheme-file FILE",23,32,0
        defm    "     Use colour scheme in FILE",$0d
        defm    " --get-scheme ADDRESS",23,32,2
        defm    "     Get scheme to memory",$0d
        defm    " --get-scheme LETTER",23,32,2
        defm    "     Get scheme to integer array",$0d
        defm    $0d
        defm    "Settings not specified are left",23,32,0,"unchanged",$0d
        defm    $ff

msg_badnextzxos:
        defm    "Requires NextZXOS mod",'e'+$80

msg_badnextver:
        defm    "Requires NextZXOS v2.07",'+'+$80

msg_badscheme:
        defm    "Unknown colour schem",'e'+$80

msg_bad_cpl:
        defm    "Invalid number of char",'s'+$80

msg_bad_dest:
        defm    "Invalid address/arra",'y'+$80

msg_spectrum_chrS:
        defm    token_spectrum,token_chrS,'0'
        defb    $0e,0,0                 ; $0e="number", 0=small int, 0=positive
chars_per_line:
        defb    0                       ; replaced with 32/64/85
        defb    0,0                     ; high byte=0, 0
        defb    $0d
msg_spectrum_chrS_end:


; ***************************************************************************
; * Colour schemes                                                          *
; ***************************************************************************

colour_scheme_names:
        defm    "default",0
        defm    "dark",0
        defm    "grey",0
        defm    "zx128",0
        defb    0

colour_scheme_data:

        ; default
colour_scheme_default:
        defb    7<<3+0                  ; base:                 black on white
        defb    2<<3+0+64               ; stripe 0:     BRIGHT  black on red
        defb    2<<3+6+64               ; stripe 1:     BRIGHT  yellow on red
        defb    4<<3+6+64               ; stripe 2:     BRIGHT  yellow on green
        defb    4<<3+5+64               ; stripe 3:     BRIGHT  cyan on green
        defb    0<<3+5+64               ; stripe 4:     BRIGHT  cyan on black
        defb    0<<3+7+64               ; hl bar:       BRIGHT  white on black
        defb    0<<3+7                  ; bg bar:               white on black
        defb    5<<3+0+64               ; hl menu:      BRIGHT  black on cyan
        defb    7<<3+0+64               ; bg menu:      BRIGHT  black on white
        defb    5<<3+1+64               ; hl shortcut:  BRIGHT  blue on cyan
        defb    7<<3+1+64               ; bg shortcut:  BRIGHT  blue on white
        defb    5<<3+1                  ; hl shortcut2:         blue on cyan
        defb    7<<3+1                  ; bg shortcut2:         blue on white
        defb    1<<3+7+64+128           ; L cursor:     FL/BR   blue/white
        defb    4<<3+7+64+128           ; E cursor:     FL/BR   green/white
        defb    3<<3+7+64+128           ; G cursor:     FL/BR   magenta/white
        defb    5<<3+7+64+128           ; C cursor:     FL/BR   cyan/white
        defb    2<<3+7+64+128           ; error cursor: FL/BR   red/white
        defb    7<<3+5                  ; line number:          cyan on white
        defb    7<<3+0                  ; token:                black on white
        defb    7<<3+3                  ; graphic/UDG:          magenta on white
        defb    7<<3+4                  ; string:               green on white
        defb    7<<3+2                  ; comment:              red on white
        defb    7<<3+1                  ; alpha:                blue on white
        defb    7<<3+5                  ; numeric:              cyan on white
        defb    7<<3+0                  ; symbol:               black on white
        defb    7<<3+0                  ; dot command:          black on white
        defs    4                       ; rsvd
        ; palette for default (standard)
        defb    %00000000,0             ; INK 0                 black
        defb    %00000010,1             ; INK 1                 blue
        defb    %10100000,0             ; INK 2                 red
        defb    %10100010,1             ; INK 3                 magenta
        defb    %00010100,0             ; INK 4                 green
        defb    %00010110,1             ; INK 5                 cyan
        defb    %10110100,0             ; INK 6                 yellow
        defb    %10110110,1             ; INK 7                 white
        defb    %00000000,0             ; BRIGHT INK 0          black
        defb    %00000011,1             ; BRIGHT INK 1          bright blue
        defb    %11100000,0             ; BRIGHT INK 2          bright red
        defb    %11100111,1             ; BRIGHT INK 3          bright magenta
        defb    %00011100,0             ; BRIGHT INK 4          bright green
        defb    %00011111,1             ; BRIGHT INK 5          bright cyan
        defb    %11111100,0             ; BRIGHT INK 6          bright yellow
        defb    %11111111,1             ; BRIGHT INK 7          bright white
        defb    %00000000,0             ; PAPER 0               black
        defb    %00000010,1             ; PAPER 1               blue
        defb    %10100000,0             ; PAPER 2               red
        defb    %10100010,1             ; PAPER 3               magenta
        defb    %00010100,0             ; PAPER 4               green
        defb    %00010110,1             ; PAPER 5               cyan
        defb    %10110100,0             ; PAPER 6               yellow
        defb    %10110110,1             ; PAPER 7               white
        defb    %00000000,0             ; BRIGHT PAPER 0        black
        defb    %00000011,1             ; BRIGHT PAPER 1        bright blue
        defb    %11100000,0             ; BRIGHT PAPER 2        bright red
        defb    %11100111,1             ; BRIGHT PAPER 3        bright magenta
        defb    %00011100,0             ; BRIGHT PAPER 4        bright green
        defb    %00011111,1             ; BRIGHT PAPER 5        bright cyan
        defb    %11111100,0             ; BRIGHT PAPER 6        bright yellow
        defb    %11111111,1             ; BRIGHT PAPER 7        bright white

        ; dark
colour_scheme_dark:
        defb    0<<3+7                  ; base:                 white on black
        defb    2<<3+7+64               ; stripe 0:     BRIGHT  white on red
        defb    2<<3+6+64               ; stripe 1:     BRIGHT  yellow on red
        defb    4<<3+6+64               ; stripe 2:     BRIGHT  yellow on green
        defb    4<<3+5+64               ; stripe 3:     BRIGHT  cyan on green
        defb    7<<3+5+64               ; stripe 4:     BRIGHT  cyan on white
        defb    7<<3+0+64               ; hl bar:       BRIGHT  black on white
        defb    7<<3+0+64               ; bg bar:       BRIGHT  black on white
        defb    5<<3+7                  ; hl menu:              white on cyan
        defb    1<<3+7                  ; bg menu:              white on blue
        defb    5<<3+1                  ; hl shortcut:          blue on cyan
        defb    1<<3+5                  ; bg shortcut:          cyan on blue
        defb    5<<3+0                  ; hl shortcut2:         black on cyan
        defb    0<<3+5                  ; bg shortcut2:         cyan on black
        defb    1<<3+7+64+128           ; L cursor:     FL/BR   blue/white
        defb    4<<3+7+64+128           ; E cursor:     FL/BR   green/white
        defb    3<<3+7+64+128           ; G cursor:     FL/BR   magenta/white
        defb    5<<3+7+64+128           ; C cursor:     FL/BR   cyan/white
        defb    2<<3+7+64+128           ; error cursor: FL/BR   red/white
        defb    0<<3+5                  ; line number:          cyan on black
        defb    0<<3+7                  ; token:                white on black
        defb    0<<3+3                  ; graphic/UDG:          magenta on black
        defb    0<<3+4                  ; string:               green on black
        defb    0<<3+2                  ; comment:              red on black
        defb    0<<3+7+64               ; alpha:        BRIGHT  white on black
        defb    0<<3+5+64               ; numeric:      BRIGHT  cyan on black
        defb    0<<3+6                  ; symbol:               yellow on black
        defb    0<<3+6+64               ; dot command:  BRIGHT  yellow on black
        defs    4                       ; rsvd
        ; palette for dark (standard)
        defb    %00000000,0             ; INK 0                 black
        defb    %00000010,1             ; INK 1                 blue
        defb    %10100000,0             ; INK 2                 red
        defb    %10100010,1             ; INK 3                 magenta
        defb    %00010100,0             ; INK 4                 green
        defb    %00010110,1             ; INK 5                 cyan
        defb    %10110100,0             ; INK 6                 yellow
        defb    %10110110,1             ; INK 7                 white
        defb    %00000000,0             ; BRIGHT INK 0          black
        defb    %00000011,1             ; BRIGHT INK 1          bright blue
        defb    %11100000,0             ; BRIGHT INK 2          bright red
        defb    %11100111,1             ; BRIGHT INK 3          bright magenta
        defb    %00011100,0             ; BRIGHT INK 4          bright green
        defb    %00011111,1             ; BRIGHT INK 5          bright cyan
        defb    %11111100,0             ; BRIGHT INK 6          bright yellow
        defb    %11111111,1             ; BRIGHT INK 7          bright white
        defb    %00000000,0             ; PAPER 0               black
        defb    %00000010,1             ; PAPER 1               blue
        defb    %10100000,0             ; PAPER 2               red
        defb    %10100010,1             ; PAPER 3               magenta
        defb    %00010100,0             ; PAPER 4               green
        defb    %00010110,1             ; PAPER 5               cyan
        defb    %10110100,0             ; PAPER 6               yellow
        defb    %10110110,1             ; PAPER 7               white
        defb    %00000000,0             ; BRIGHT PAPER 0        black
        defb    %00000011,1             ; BRIGHT PAPER 1        bright blue
        defb    %11100000,0             ; BRIGHT PAPER 2        bright red
        defb    %11100111,1             ; BRIGHT PAPER 3        bright magenta
        defb    %00011100,0             ; BRIGHT PAPER 4        bright green
        defb    %00011111,1             ; BRIGHT PAPER 5        bright cyan
        defb    %11111100,0             ; BRIGHT PAPER 6        bright yellow
        defb    %11111111,1             ; BRIGHT PAPER 7        bright white

        ; grey
colour_scheme_grey:
        defb    6<<3+0                  ; base:                 black on mid white
        defb    2<<3+0                  ; stripe 0:             black on mid grey
        defb    2<<3+4                  ; stripe 1:             very light grey on mid grey
        defb    1<<3+4                  ; stripe 2:             very light grey on dark grey
        defb    1<<3+3                  ; stripe 3:             light grey on dark grey
        defb    0<<3+3                  ; stripe 4:             light grey on black
        defb    0<<3+7                  ; hl bar:               bright white on black
        defb    0<<3+6                  ; bg bar:               mid white on black
        defb    3<<3+0                  ; hl menu:              black on light grey
        defb    7<<3+0                  ; bg menu:              black on bright white
        defb    3<<3+2                  ; hl shortcut:          mid grey on light grey
        defb    7<<3+2                  ; bg shortcut:          mid grey on bright white
        defb    2<<3+3                  ; hl shortcut2:         light grey on mid grey
        defb    2<<3+7                  ; bg shortcut2:         bright white on mid grey
        defb    1<<3+7+64+128           ; L cursor:     FL/BR   bright white/dark grey
        defb    4<<3+7+64+128           ; E cursor:     FL/BR   bright white/very light grey
        defb    3<<3+7+64+128           ; G cursor:     FL/BR   bright white/light grey
        defb    5<<3+7+64+128           ; C cursor:     FL/BR   bright white/dull white
        defb    2<<3+7+64+128           ; error cursor: FL/BR   bright white/mid grey
        defb    6<<3+4                  ; line number:          very light grey on mid white
        defb    6<<3+2                  ; token:                mid grey on mid white
        defb    6<<3+3                  ; graphic/UDG:          light grey on mid white
        defb    6<<3+5                  ; string:               dull white on mid white
        defb    6<<3+3                  ; comment:              light grey on mid white
        defb    6<<3+0                  ; alpha:                black on mid white
        defb    6<<3+4                  ; numeric:              very light grey on mid white
        defb    6<<3+2                  ; symbol:               mid grey on mid white
        defb    6<<3+1                  ; dot command           dark grey on mid white
        defs    4                       ; rsvd
        ; palette for grey
        defb    %00000000,0             ; INK 0                 black
        defb    %00100100,1             ; INK 1                 dark grey
        defb    %01001001,0             ; INK 2                 mid grey
        defb    %01101101,1             ; INK 3                 light grey
        defb    %10010010,1             ; INK 4                 very light grey
        defb    %10110110,1             ; INK 5                 dull white
        defb    %11011011,0             ; INK 6                 mid white
        defb    %11111111,1             ; INK 7                 bright white
        defb    %00000000,0             ; BRIGHT INK 0          black
        defb    %00100100,1             ; BRIGHT INK 1          dark grey
        defb    %01001001,0             ; BRIGHT INK 2          mid grey
        defb    %01101101,1             ; BRIGHT INK 3          light grey
        defb    %10010010,1             ; BRIGHT INK 4          very light grey
        defb    %10110110,1             ; BRIGHT INK 5          dull white
        defb    %11011011,0             ; BRIGHT INK 6          mid white
        defb    %11111111,1             ; BRIGHT INK 7          bright white
        defb    %00000000,0             ; PAPER 0               black
        defb    %00100100,1             ; PAPER 1               dark grey
        defb    %01001001,0             ; PAPER 2               mid grey
        defb    %01101101,1             ; PAPER 3               light grey
        defb    %10010010,1             ; PAPER 4               very light grey
        defb    %10110110,1             ; PAPER 5               dull white
        defb    %11011011,0             ; PAPER 6               mid white
        defb    %11111111,1             ; PAPER 7               bright white
        defb    %00000000,0             ; BRIGHT PAPER 0        black
        defb    %00100100,1             ; BRIGHT PAPER 1        dark grey
        defb    %01001001,0             ; BRIGHT PAPER 2        mid grey
        defb    %01101101,1             ; BRIGHT PAPER 3        light grey
        defb    %10010010,1             ; BRIGHT PAPER 4        very light grey
        defb    %10110110,1             ; BRIGHT PAPER 5        dull white
        defb    %11011011,0             ; BRIGHT PAPER 6        mid white
        defb    %11111111,1             ; BRIGHT PAPER 7        bright white

        ; zx128
colour_scheme_zx128:
        defb    7<<3+0                  ; base:                 black on white
        defb    2<<3+0+64               ; stripe 0:     BRIGHT  black on red
        defb    2<<3+6+64               ; stripe 1:     BRIGHT  yellow on red
        defb    4<<3+6+64               ; stripe 2:     BRIGHT  yellow on green
        defb    4<<3+5+64               ; stripe 3:     BRIGHT  cyan on green
        defb    0<<3+5+64               ; stripe 4:     BRIGHT  cyan on black
        defb    0<<3+7+64               ; hl bar:       BRIGHT  white on black
        defb    0<<3+7                  ; bg bar:               white on black
        defb    5<<3+0+64               ; hl menu:      BRIGHT  black on cyan
        defb    7<<3+0+64               ; bg menu:      BRIGHT  black on white
        defb    5<<3+1+64               ; hl shortcut:  BRIGHT  blue on cyan
        defb    7<<3+1+64               ; bg shortcut:  BRIGHT  blue on white
        defb    5<<3+1                  ; hl shortcut2:         blue on cyan
        defb    7<<3+1                  ; bg shortcut2:         blue on white
        defb    1<<3+7+64+128           ; L cursor:     FL/BR   blue/white
        defb    4<<3+7+64+128           ; E cursor:     FL/BR   green/white
        defb    3<<3+7+64+128           ; G cursor:     FL/BR   magenta/white
        defb    5<<3+7+64+128           ; C cursor:     FL/BR   cyan/white
        defb    2<<3+7+64+128           ; error cursor: FL/BR   red/white
        defb    7<<3+0                  ; line number:          black on white
        defb    7<<3+0                  ; token:                black on white
        defb    7<<3+0                  ; graphic/UDG:          black on white
        defb    7<<3+0                  ; string:               black on white
        defb    7<<3+0                  ; comment:              black on white
        defb    7<<3+0                  ; alpha:                black on white
        defb    7<<3+0                  ; numeric:              black on white
        defb    7<<3+0                  ; symbol:               black on white
        defb    7<<3+0                  ; dot command:          black on white
        defs    4                       ; rsvd
        ; palette for zx128 (standard)
        defb    %00000000,0             ; INK 0                 black
        defb    %00000010,1             ; INK 1                 blue
        defb    %10100000,0             ; INK 2                 red
        defb    %10100010,1             ; INK 3                 magenta
        defb    %00010100,0             ; INK 4                 green
        defb    %00010110,1             ; INK 5                 cyan
        defb    %10110100,0             ; INK 6                 yellow
        defb    %10110110,1             ; INK 7                 white
        defb    %00000000,0             ; BRIGHT INK 0          black
        defb    %00000011,1             ; BRIGHT INK 1          bright blue
        defb    %11100000,0             ; BRIGHT INK 2          bright red
        defb    %11100111,1             ; BRIGHT INK 3          bright magenta
        defb    %00011100,0             ; BRIGHT INK 4          bright green
        defb    %00011111,1             ; BRIGHT INK 5          bright cyan
        defb    %11111100,0             ; BRIGHT INK 6          bright yellow
        defb    %11111111,1             ; BRIGHT INK 7          bright white
        defb    %00000000,0             ; PAPER 0               black
        defb    %00000010,1             ; PAPER 1               blue
        defb    %10100000,0             ; PAPER 2               red
        defb    %10100010,1             ; PAPER 3               magenta
        defb    %00010100,0             ; PAPER 4               green
        defb    %00010110,1             ; PAPER 5               cyan
        defb    %10110100,0             ; PAPER 6               yellow
        defb    %10110110,1             ; PAPER 7               white
        defb    %00000000,0             ; BRIGHT PAPER 0        black
        defb    %00000011,1             ; BRIGHT PAPER 1        bright blue
        defb    %11100000,0             ; BRIGHT PAPER 2        bright red
        defb    %11100111,1             ; BRIGHT PAPER 3        bright magenta
        defb    %00011100,0             ; BRIGHT PAPER 4        bright green
        defb    %00011111,1             ; BRIGHT PAPER 5        bright cyan
        defb    %11111100,0             ; BRIGHT PAPER 6        bright yellow
        defb    %11111111,1             ; BRIGHT PAPER 7        bright white


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

; NOTE: The ordering of viewflags, sortflags, viewmask, sortmask is
;       important and relied on in the code.
viewflags:
        defb    0

sortflags:
        defb    0

viewmask:
        defb    0

sortmask:
        defb    0

filter_string:
        defs    15,$ff

colour_settings:
        defw    0

save_addr:
        defw    0

saved_sp:
        defw    0

saved_turbo:
        defb    0

fileheader:
        defs    8

command_tail:
        defw    0

        defs    256                     ; space for temporary stack
temp_stack:

saved_ram:
; NOTE: Do not place anything after here
;       defs    ram_buffer_size

if ((saved_ram+ram_buffer_size) > $4000)
.ERROR saved_ram buffer exceeds DivMMC RAM area
endif
