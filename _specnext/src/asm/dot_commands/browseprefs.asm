; ***************************************************************************
; * Dot command to change the Browser preferences                           *
; ***************************************************************************

include "macros.def"
include "nexthw.def"
include "sysvars.def"
include "esxapi.def"
include "nextzxos.def"


; ***************************************************************************
; * Definitions                                                             *
; ***************************************************************************

; Size of a colour scheme
colour_scheme_size      equ     32+(32*2)       ; 32 attributes, 32 palette entries

; Size of an integer array
int_array_size          equ     64*2

; Use some main RAM below $c000 for buffers to pass to IDE_BROWSER.
; The stack will also be located here
ram_buffer              equ     $6000
; Space for colour scheme or 15-byte filter, integer array plus a 128-byte stack
RAM_BUFFER_SIZE         equ     colour_scheme_size+int_array_size+128


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************

        org     $2000

browseprefs_init:
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
        jr      nc,browseprefs_start    ; okay if none
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

browseprefs_start:
        ; Save data in the main RAM buffer
        ; The stack is also relocated into the main RAM buffer so it is
        ; below $c000 and safe for use with +3DOS calls.
        ld      hl,ram_buffer
        ld      de,saved_ram
        ld      bc,RAM_BUFFER_SIZE
        ldir                            ; save some RAM below $c000
        ld      sp,ram_buffer+RAM_BUFFER_SIZE

        ; Fetch the current filter and settings
        ld      hl,ram_buffer           ; buffer for current filter
        ld      de,0                    ; get/set Browser settings
        ld      a,d                     ; A=0, get current settings
        callp3d ide_browser,7           ; get current Browser filter & settings

        ; Update with specified settings
        ld      hl,filter_string
        ld      a,(hl)
        inc     a
        jr      z,browseprefs_nofilter
        ld      de,ram_buffer
        push    bc
        ld      bc,15
        ldir                            ; copy any specified filter
        pop     bc
browseprefs_nofilter:
        ld      hl,(viewflags)          ; L=viewflags, H=sortflags
        ld      de,(viewmask)           ; E=viewmask, D=sortmask
        ld      a,e
        cpl                             ; A=mask of view flags to retain
        and     c                       ; keep unchanged flags
        or      l                       ; merge in changed flags
        ld      c,a
        ld      a,d
        cpl                             ; A=mask of sort flags to retain
        and     b                       ; keep unchanged flags
        or      h                       ; merge in changed flags
        ld      b,a

        ; Update the Browser settings
        ld      hl,ram_buffer           ; saved filter
        ld      de,0                    ; get/set Browser settings
        ld      a,1                     ; A=1, change current settings
        callp3d ide_browser,7           ; set Browser filter & settings

        ; Set Browser colours
        ld      hl,(colour_settings)
        ld      a,h
        or      l
        jr      z,browseprefs_noset     ; no colour data to set
        ld      de,ram_buffer
        push    de
        ld      bc,colour_scheme_size
        ldir                            ; copy colour scheme
        pop     hl                      ; colour data address
        ld      de,0                    ; get/set Browser settings
        ld      a,3                     ; A=3, change colours
        callp3d ide_browser,7           ; set Browser colours

browseprefs_noset:
        ld      hl,(save_addr)
        ld      a,h
        or      l
        jr      z,browseprefs_end       ; don't want to fetch current scheme
        push    hl
        ld      hl,ram_buffer
        push    hl
        ld      de,0                    ; get/set Browser/Editor settings
        ld      a,2                     ; A=2, get Browser colours
        callp3d ide_browser,7           ; get Browser colours
        pop     hl                      ; HL=ram_buffer
        pop     de                      ; DE=(save_addr)
        ld      a,d
        and     a
        jr      z,browseprefs_setarray  ; on if dest is integer array
        ld      bc,colour_scheme_size
        ldir                            ; else just copy to memory address
        jr      browseprefs_end
browseprefs_setarray:
        ; First the scheme must be converted to 64 x 16-bit values
        ld      de,ram_buffer+colour_scheme_size
        push    de
        ld      b,32                    ; 32 x 8-bit attributes to convert
bsa_convattr_loop:
        ld      a,(hl)
        inc     hl
        ld      (de),a                  ; copy attribute as low byte
        inc     de
        xor     a
        ld      (de),a                  ; set high byte to zero
        inc     de
        djnz    bsa_convattr_loop
        ld      a,32                    ; 32 x 16-bit palette values to convert
bsa_convpal_loop:
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
        jr      nz,bsa_convpal_loop
        pop     hl                      ; HL=address of converted data
        ; Now set the 64 integer array elements
        ld      a,(save_addr)
        dec     a
        ld      c,a                     ; C=array id 0..25
        ld      b,64                    ; 64 elements
bsa_set_loop:
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
        djnz    bsa_set_loop

browseprefs_end:

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
        defopt  "-f",option_filter
        defopt  "--filter",option_filter
        defopt  "--info-none",option_info_none
        defopt  "--info-size",option_info_size
        defopt  "--info-date",option_info_date
        defopt  "--info-attr",option_info_attr
        defopt  "--show-sys",option_show_sys
        defopt  "--hide-sys",option_hide_sys
        defopt  "--show-dots",option_show_dots
        defopt  "--hide-dots",option_hide_dots
        defopt  "--mixed-on",option_mixed_on
        defopt  "--mixed-off",option_mixed_off
        defopt  "--sort-name",option_sort_name
        defopt  "--sort-size",option_sort_size
        defopt  "--sort-date",option_sort_date
        defopt  "--sort-off",option_sort_off
        defopt  "--sort-forwards",option_sort_forwards
        defopt  "--sort-backwards",option_sort_backwards
        defopt  "--scheme",option_scheme
        defopt  "--scheme-file",option_scheme_file
        defopt  "--show-meta",option_show_meta
        defopt  "--hide-meta",option_hide_meta
        defopt  "--get-scheme",option_get_scheme
        endopts()


; ***************************************************************************
; * -f, --filter FILTER                                                     *
; ***************************************************************************

option_filter:
        call    get_sizedarg            ; get filter into temparg
        ld      a,c
        cp      15                      ; max length is 14 (plus $ff terminator)
        ld      hl,msg_badfilter
        jp      nc,err_custom
        ld      hl,msg_nofilter
        and     a
        jp      z,err_custom
        ld      de,filter_string
        ld      hl,temparg
        ldir                            ; copy filter
        ld      a,$ff
        ld      (de),a                  ; append terminator
        ret


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
; * --sort-name                                                             *
; * --sort-size                                                             *
; * --sort-date                                                             *
; * --sort-off                                                              *
; ***************************************************************************

option_sort_name:
        ld      c,0
        jr      option_sort_set

option_sort_off:
        ld      c,1
        jr      option_sort_set

option_sort_date:
        ld      c,2
        jr      option_sort_set

option_sort_size:
        ld      c,3
option_sort_set:
        ld      b,$03
        jr      change_sort_bits


; ***************************************************************************
; * --sort-forwards                                                         *
; * --sort-backwards                                                        *
; ***************************************************************************

option_sort_forwards:
        ld      bc,$0400
        jr      change_sort_bits

option_sort_backwards:
        ld      bc,$0404
        jr      change_sort_bits


; ***************************************************************************
; * --info-none                                                             *
; * --info-size                                                             *
; * --info-date                                                             *
; * --info-attr                                                             *
; ***************************************************************************

option_info_none:
        ld      c,0
        jr      option_info_set

option_info_size:
        ld      c,1
        jr      option_info_set

option_info_date:
        ld      c,2
        jr      option_info_set

option_info_attr:
        ld      c,3
option_info_set:
        ld      b,$03
        jr      change_view_bits


; ***************************************************************************
; * --show-sys                                                              *
; * --hide-sys                                                              *
; * --show-dots                                                             *
; * --hide-dots                                                             *
; * --show-meta                                                             *
; * --hide-meta                                                             *
; * --mixed-on                                                              *
; * --mixed-off                                                             *
; ***************************************************************************

option_show_sys:
        ld      bc,$1010
        jr      change_view_bits

option_hide_sys:
        ld      bc,$1000
        jr      change_view_bits

option_show_dots:
        ld      bc,$2000
        jr      change_view_bits

option_hide_dots:
        ld      bc,$2020
        jr      change_view_bits

option_show_meta:
        ld      bc,$0404
        jr      change_view_bits

option_hide_meta:
        ld      bc,$0400
        jr      change_view_bits

option_mixed_on:
        ld      bc,$4000
        jr      change_view_bits

option_mixed_off:
        ld      bc,$4040
        jr      change_view_bits


; ***************************************************************************
; * Change bits in sortflags and sortmask                                   *
; ***************************************************************************
; Entry: B=mask of bits to change
;        C=value to use

change_sort_bits:
        ld      hl,sortflags
        jr      change_bits


; ***************************************************************************
; * Change bits in viewflags and viewmask                                   *
; ***************************************************************************
; Entry: B=mask of bits to change
;        C=value to use

change_view_bits:
        ld      hl,viewflags
        ; drop through to change_bits

; ***************************************************************************
; * Change bits in flags and mask                                           *
; ***************************************************************************
; Entry: B=mask of bits to change
;        C=value to use
;        HL=address of flags
;        HL+2=address of mask

change_bits:
        ld      a,b
        cpl                             ; A=mask of bits to retain
        and     (hl)                    ; get the bits to retain
        or      c                       ; merge the new bits
        ld      (hl),a
        inc     hl
        inc     hl                      ; address current mask value
        ld      a,(hl)
        or      b                       ; merge the mask of changed bits
        ld      (hl),a
        ret


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

; TAB 32 used within help message so it is formatted wide in 64/85 column mode.
msg_help:
        defm    "BROWSEPREFS v1.3",23,32,0
        defm    "by Garry Lancaster",$0d
        defm    "Sets Browser preferences",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    " .BROWSEPREFS [OPTION]...",$0d
        defm    "OPTIONS:",$0d
        defm    " -h, --help",23,32,0
        defm    "     Display this help",$0d
        defm    " -f, --filter FILTER",23,32,0
        defm    "     Change filter",$0d
        defm    " --info-none",23,32,0
        defm    "     Set info column to none",$0d
        defm    " --info-size",23,32,0
        defm    "     Set info column to size",$0d
        defm    " --info-date",23,32,0
        defm    "     Set info column to date",$0d
        defm    " --info-attr",23,32,0
        defm    "     Set info column to attribs",$0d
        defm    " --show-sys",23,32,0
        defm    "     Show system/hidden files",$0d
        defm    " --hide-sys",23,32,0
        defm    "     Hide system/hidden files",$0d
        defm    " --show-dots",23,32,0
        defm    "     Show . and .. entries",$0d
        defm    " --hide-dots",23,32,0
        defm    "     Hide . and .. entries",$0d
        defm    " --show-meta",23,32,0
        defm    "     Show filename metadata",$0d
        defm    " --hide-meta",23,32,0
        defm    "     Hide filename metadata",$0d
        defm    " --mixed-on",23,32,0
        defm    "     Mix files and directories",$0d
        defm    " --mixed-off",23,32,0
        defm    "     List directories first",$0d
        defm    " --sort-name",23,32,0
        defm    "     Sort file list by name",$0d
        defm    " --sort-size",23,32,0
        defm    "     Sort file list by size",$0d
        defm    " --sort-date",23,32,0
        defm    "     Sort file list by date",$0d
        defm    " --sort-forwards",23,32,0
        defm    "     Sort from small to large",$0d
        defm    " --sort-backwards",23,32,0
        defm    "     Sort from large to small",$0d
        defm    " --sort-off",23,32,0
        defm    "     Don't sort the file list",$0d
        defm    " --scheme NAME",23,32,0
        defm    "     Choose colour scheme",$0d
        defm    "     Available scheme names:",23,32,0
        defm    "      default,dark,grey,rainbow",$0d
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

msg_nofilter:
        defm    "Missing filte",'r'+$80

msg_badfilter:
        defm    "Filter too lon",'g'+$80

msg_bad_dest:
        defm    "Invalid address/arra",'y'+$80

msg_badscheme:
        defm    "Unknown colour schem",'e'+$80


; ***************************************************************************
; * Colour schemes                                                          *
; ***************************************************************************

colour_scheme_names:
        defm    "default",0
        defm    "dark",0
        defm    "grey",0
        defm    "rainbow",0
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
        defb    6<<3+0                  ; hl unknown:           black on yellow
        defb    5<<3+0                  ; hl links:             black on cyan
        defb    5<<3+0                  ; hl exec:              black on cyan
        defb    5<<3+0                  ; hl run:               black on cyan
        defb    5<<3+0                  ; hl dir:               black on cyan
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    7<<3+0                  ; bg unknown:           black on white
        defb    7<<3+0                  ; bg links:             black on white
        defb    7<<3+0                  ; bg exec:              black on white
        defb    7<<3+0                  ; bg run:               black on white
        defb    7<<3+0                  ; bg dir:               black on white
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
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
        defb    7<<3+1+64               ; hl bar:       BRIGHT  blue on white
        defb    7<<3+0+64               ; bg bar:       BRIGHT  black on white
        defb    2<<3+0                  ; hl unknown:           black on red
        defb    6<<3+0                  ; hl links:             black on yellow
        defb    5<<3+0                  ; hl exec:              black on cyan
        defb    5<<3+0+64               ; hl run:       BRIGHT  black on cyan
        defb    4<<3+0                  ; hl dir:               black on green
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0<<3+2                  ; bg unknown:           blue on red
        defb    0<<3+6                  ; bg links:             yellow on black
        defb    0<<3+5                  ; bg exec:              cyan on black
        defb    0<<3+5+64               ; bg run:       BRIGHT  cyan on black
        defb    0<<3+4                  ; bg dir:               green on black
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
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
        defb    3<<3+0                  ; hl unknown:           black on light grey
        defb    2<<3+0                  ; hl links:             black on mid grey
        defb    2<<3+0                  ; hl exec:              black on mid grey
        defb    1<<3+6                  ; hl run:               mid white on dark grey
        defb    1<<3+6                  ; hl dir:               mid white on dark grey
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    6<<3+3                  ; bg unknown:           light grey on mid white
        defb    6<<3+1                  ; bg links:             dark grey on mid white
        defb    6<<3+1                  ; bg exec:              dark grey on mid white
        defb    6<<3+2                  ; bg run:               mid grey on mid white
        defb    6<<3+2                  ; bg dir:               mid grey on mid white
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        ; palette for grey
        defb    %00000000,0             ; INK 0                 black
        defb    %00100100,1             ; INK 1                 dark grey
        defb    %01001001,0             ; INK 2                 mid grey
        defb    %01101101,1             ; INK 3                 light grey
        defb    %10010010,1             ; INK 4                 very light grey
        defb    %10110110,1             ; INK 5                 dull white
        defb    %11011011,0             ; INK 6                 mid white
        defb    %11111111,1             ; INK 7                 bright white
        defb    0,0                     ; BRIGHT INK 0          UNUSED
        defb    0,0                     ; BRIGHT INK 1          UNUSED
        defb    0,0                     ; BRIGHT INK 2          UNUSED
        defb    0,0                     ; BRIGHT INK 3          UNUSED
        defb    0,0                     ; BRIGHT INK 4          UNUSED
        defb    0,0                     ; BRIGHT INK 5          UNUSED
        defb    0,0                     ; BRIGHT INK 6          UNUSED
        defb    0,0                     ; BRIGHT INK 7          UNUSED
        defb    %00000000,0             ; PAPER 0               black
        defb    %00100100,1             ; PAPER 1               dark grey
        defb    %01001001,0             ; PAPER 2               mid grey
        defb    %01101101,1             ; PAPER 3               light grey
        defb    %10010010,1             ; PAPER 4               very light grey
        defb    %10110110,1             ; PAPER 5               dull white
        defb    %11011011,0             ; PAPER 6               mid white
        defb    %11111111,1             ; PAPER 7               bright white
        defb    0,0                     ; BRIGHT PAPER 0        UNUSED
        defb    0,0                     ; BRIGHT PAPER 1        UNUSED
        defb    0,0                     ; BRIGHT PAPER 2        UNUSED
        defb    0,0                     ; BRIGHT PAPER 3        UNUSED
        defb    0,0                     ; BRIGHT PAPER 4        UNUSED
        defb    0,0                     ; BRIGHT PAPER 5        UNUSED
        defb    0,0                     ; BRIGHT PAPER 6        UNUSED
        defb    0,0                     ; BRIGHT PAPER 7        UNUSED

        ; rainbow
colour_scheme_rainbow:
        defb    7<<3+0                  ; base:                 black on white
        defb    2<<3+0+64               ; stripe 0:     BRIGHT  black on red
        defb    2<<3+6+64               ; stripe 1:     BRIGHT  yellow on red
        defb    4<<3+6+64               ; stripe 2:     BRIGHT  yellow on green
        defb    4<<3+5+64               ; stripe 3:     BRIGHT  cyan on green
        defb    0<<3+5+64               ; stripe 4:     BRIGHT  cyan on black
        defb    0<<3+6+64               ; hl bar:       BRIGHT  yellow on black
        defb    0<<3+6                  ; bg bar:               yellow on black
        defb    2<<3+7                  ; hl unknown:           white on red
        defb    4<<3+0                  ; hl links:             black on green
        defb    5<<3+0                  ; hl exec:              black on cyan
        defb    3<<3+7                  ; hl run:               white on magenta
        defb    1<<3+7                  ; hl dir:               white on blue
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    7<<3+2                  ; bg unknown:           red on white
        defb    7<<3+4                  ; bg links:             green on white
        defb    7<<3+5                  ; bg exec:              cyan on white
        defb    7<<3+3                  ; bg run:               magenta on white
        defb    7<<3+1                  ; bg dir:               blue on white
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        defb    0                       ; rsvd:                 must be 0
        ; palette for rainbow (standard)
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
