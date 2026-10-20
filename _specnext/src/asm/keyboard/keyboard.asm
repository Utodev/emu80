; ***************************************************************************
; * Example NextZXOS keyboard driver                                        *
; ***************************************************************************
; The keyboard driver used by NextZXOS may be replaced by installing a
; special driver with id 0.

; This file is the 512-byte NextZXOS driver itself, plus relocation table.
;
; Assemble with: pasmo keyboard.asm keyboard.bin keyboard.sym
;
; After this, keyboard_drv.asm needs to be built to generate the actual
; driver file.

; Keyboard drivers are installed using the same .install dot command
; as standard drivers, and immediately replace the existing keyboard
; driver (the keyboard driver does not count towards the total number
; of standard installable NextZXOS drivers).
;
; The main differences between the keyboard driver and standard drivers
; are as follows:
;       1. The keyboard driver always has driver id 0.
;       2. The keyboard driver cannot provide an API.
;       3. The keyboard driver is always called at every IM1 interrupt.
;       4. The keyboard driver has just a single entry point, at $0000,
;          which is called during IM1 interrupts.
;
; Replacement keyboard drivers should perform the same effective
; functionality as the standard KEYBOARD routine at $02bf in the ROM of
; the original 48K Spectrum.
;
; The following driver replicates the code from the original
; ROM (although slightly re-ordered). It additionally reads the Kempston
; joystick port so a joystick may be used for navigation purposes within
; NextZXOS. It may be used as a base for a replacement driver.
;
; Possible uses for replacement keyboard drivers might be:
;       * For use with alternative international keyboard layouts
;       * Adding a multi-byte buffer to allow faster typing
;
; Be aware that the driver is called by all ROMs, so should support
; keyword tokens (unless you don't intend to use 48K BASIC mode, or only
; intend to use 48K BASIC mode using the Gosh Wonderful ROM in standard
; single-letter entry).


; ***************************************************************************
; * System variable definitions                                             *
; ***************************************************************************

KSTATE  equ     $5c00
LAST_K  equ     $5c08
REPDEL  equ     $5c09
REPPER  equ     $5c0a
ERR_NR  equ     $5c3a
FLAGS   equ     $5c3b
MODE    equ     $5c41
FLAGS2  equ     $5c6a

iy_FLAGS        equ     FLAGS-ERR_NR
iy_MODE         equ     MODE-ERR_NR
iy_FLAGS2       equ     FLAGS2-ERR_NR


; ***************************************************************************
; * Next register definitions                                               *
; ***************************************************************************

next_reg_select                         equ     $243b
nxr_core_boot                           equ     $10


; ***************************************************************************
; * Token definitions                                                       *
; ***************************************************************************

udgA                    equ     144
token_sin               equ     $b2
token_to                equ     $cc
token_new               equ     $e6


; ***************************************************************************
; * KEYBOARD routine (at $02bf in original 48K ROM)                         *
; ***************************************************************************

        org     $0000           ; this is the entry point for the driver

keyboard:
reloc_1:
        call    key_scan                ; scan the matrix
        ret     nz                      ; ignore invalid key combinations
        ld      hl,KSTATE               ; start with KSTATE0..3
keyboard_2:
        bit     7,(hl)
        jr      nz,keyboard_3           ; on if the set is free
        inc     hl
        dec     (hl)                    ; otherwise decrease its counter
        dec     hl
        jr      nz,keyboard_3
        ld      (hl),$ff                ; signal set is free after 5 calls
keyboard_3:
        ld      a,l
        ld      hl,KSTATE+$04
        cp      l
        jr      nz,keyboard_2           ; back with 2nd set (KSTATE4..7)
reloc_2:
        call    k_test                  ; check for a valid key

; NOTE: At this point, the driver in the original ZX ROM simply returned
;       if no key is pressed (carry clear). In the NextZXOS driver, we
;       additionally check for the Kempston joystick.

        jr      c,lk_gotkey             ; on if valid key
        in      a,($1f)                 ; else read kempston port
        cp      $ff
        ret     z                       ; exit if $ff (no Kempston port)
        and     a
        ret     z                       ; exit if $00
reloc_13:
        ld      hl,kempston_keys-1
kemp_decode_loop:
        inc     hl                      ; next table address
        srl     a                       ; next port bit to carry
        jr      nc,kemp_decode_loop     ; until found a set bit
        ret     nz                      ; exit if more than one set bit
        ld      a,(hl)                  ; A=code

; The standard ZX ROM keyboard routines now continue.

lk_gotkey:
        ld      hl,KSTATE               ; start with KSTATE0..3
        cp      (hl)
        jr      z,k_repeat              ; on for repeat if matching key
        ex      de,hl
        ld      hl,KSTATE+$04           ; again with KSTATE4..7
        cp      (hl)
        jr      z,k_repeat              ; on for repeat of 2nd set's key
        bit     7,(hl)
        jr      nz,keyboard_4           ; on with new key if 2nd set is free
        ex      de,hl
        bit     7,(hl)
        ret     z                       ; exit if neither set is free
keyboard_4:
        ld      e,a
        ld      (hl),a                  ; store "main" key in KSTATE0/4
        inc     hl
        ld      (hl),$05                ; initialise counter in KSTATE1/5
        inc     hl
        ld      a,(REPDEL)
        ld      (hl),a                  ; initialise repeat delay in KSTATE2/6
        inc     hl
        ld      c,(iy+iy_MODE)          ; C=(MODE) system variable
        ld      d,(iy+iy_FLAGS)         ; D=(FLAGS) system variable
        push    hl
reloc_3:
        call    k_decode                ; fully decode key with current shifts
        pop     hl
        ld      (hl),a                  ; store decoded key in KSTATE 3/7
keyboard_5:
        ld      (LAST_K),a              ; update last key
        set     5,(iy+iy_FLAGS)         ; and signal a new key is available
        ret


; ***************************************************************************
; * Kempston key translation table                                          *
; ***************************************************************************

kempston_keys:
        defb    9                       ; cursor right
        defb    8                       ; cursor left
        defb    10                      ; cursor down
        defb    11                      ; cursor up
        defb    13                      ; fire (ENTER)
        defb    32                      ; button 2 (SPACE)
        defb    7                       ; button 3 (EDIT)
        defb    7                       ; button 4 (EDIT)


; ***************************************************************************
; * K-REPEAT routine (at $0310 in original 48K ROM)                         *
; ***************************************************************************
; Enters with HL pointing to the repeating set (KSTATE0 or KSTATE4)

k_repeat:
        inc     hl
        ld      (hl),$05                ; reset the set's 5-call counter
        inc     hl
        dec     (hl)                    ; decrement the repeat delay
        ret     nz                      ; exit if too early to repeat
        ld      a,(REPPER)
        ld      (hl),a                  ; set delay for further repeats
        inc     hl
        ld      a,(hl)                  ; fetch the fully-decoded key
        jr      keyboard_5              ; and register it as a new press


; ***************************************************************************
; * Keytables                                                               *
; ***************************************************************************
; These are copies of the key tables from original 48K ROM

; The L-mode keytable with CAPS-SHIFT

keytable_l:
        defm    "BHY65TGV"
        defm    "NJU74RFC"
        defm    "MKI83EDX"
        defm    $0e,"LO92WSZ"
        defm    " ",$0d,"P01QA"

; The extended-mode keytable (unshifted letters)

keytable_e:
        defb    $e3,$c4,$e0,$e4
        defb    $b4,$bc,$bd,$bb
        defb    $af,$b0,$b1,$c0
        defb    $a7,$a6,$be,$ad
        defb    $b2,$ba,$e5,$a5
        defb    $c2,$e1,$b3,$b9
        defb    $c1,$b8

; The extended mode keytable (shifted letters)

keytable_e_s:
        defb    $7e,$dc,$da,$5c
        defb    $b7,$7b,$7d,$d8
        defb    $bf,$ae,$aa,$ab
        defb    $dd,$de,$df,$7f
        defb    $b5,$d6,$7c,$d5
        defb    $5d,$db,$b6,$d9
        defb    $5b,$d7

; The control code keytable (CAPS-SHIFTed digits)

keytable_cc:
        defb    $0c,$07,$06,$04
        defb    $05,$08,$0a,$0b
        defb    $09,$0f

; The symbol code keytable (letters with symbol shift)

keytable_sym:
        defb    $e2,$2a,$3f,$cd
        defb    $c8,$cc,$cb,$5e
        defb    $ac,$2d,$2b,$3d
        defb    $2e,$2c,$3b,$22
        defb    $c7,$3c,$c3,$3e
        defb    $c5,$2f,$c9,$60
        defb    $c6,$3a

; The extended mode keytable (SYM-SHIFTed digits)

keytable_e_d:
        defb    $d0,$ce,$a8,$ca
        defb    $d3,$d4,$d1,$d2
        defb    $a9,$cf


; ***************************************************************************
; * KEY-SCAN routine (at $028e in original 48K ROM)                         *
; ***************************************************************************
; Scans the keyboard matrix and returns with:
;       E=1st keycode ($ff=none)
;       D=2nd (shift) keycode ($ff=none)
;       zero flag set if invalid (3+ keys pressed, or 2 non-shifts pressed)
; If both shift keys are pressed, D contains CAPS ($27) and E contains SYM ($18)

key_scan:
        ld      l,$2f                   ; initial value for each row: $2f..$28
        ld      de,$ffff                ; D=E=no key
        ld      bc,$fefe                ; C=port, B=row
key_scan_2:
        in      a,(c)                   ; read row
        cpl
        and     $1f
        jr      z,key_scan_5            ; on if no keys pressed in row
        ld      h,a                     ; H=row bits
        ld      a,l                     ; A=initial key value
key_scan_3:
        inc     d                       ; exit with zero reset if this is the
        ret     nz                      ; third key to be detected
key_scan_4:
        sub     $08                     ; find keycode value for each bit
        srl     h                       ; in turn
        jr      nc,key_scan_4
        ld      d,e                     ; copy any previous keycode to D
        ld      e,a                     ; E=keycode
        jr      nz,key_scan_3           ; back if further keys in this row
key_scan_5:
        dec     l                       ; next row's initial keycode
        rlc     b                       ; next row port value
        jr      c,key_scan_2            ; back until all rows scanned
        ld      a,d
        inc     a
        ret     z                       ; exit with zero set if 0 or 1 keys
        cp      $28
        ret     z                       ; or if 2nd key of pair is CAPS SHIFT
        cp      $19
        ret     z                       ; or if 2nd key of pair is SYM SHIFT
        ld      a,e                     ; SYM SHIFT could be 1st key of a pair
        ld      e,d                     ; so swap them
        ld      d,a
        cp      $18                     ; and exit with zero set if so
        ret                             ; or zero reset for an invalid pair


; ***************************************************************************
; * K-TEST routine (at $031e in original 48K ROM)                           *
; ***************************************************************************
; Given a pair of keycodes in D and E, returns with carry set and
; A containing the decoded L-mode key and B containing the shift keycode.
; Returns with carry reset if no key or only a single shift is pressed
; (if both shifts are pressed, the decoded value in A is $0e, EXTEND).

k_test:
        ld      b,d                     ; B=shift keycode ($ff/$27/$18)
        ld      d,$00
        ld      a,e
        cp      $27                     ; return with carry reset if the
        ret     nc                      ; 1st key was CAPS or "no key"
        cp      $18
        jr      nz,k_test_2
        bit     7,b                     ; return with carry reset if
        ret     nz                      ; only SYM shift pressed
k_test_2:
reloc_4:
        ld      hl,keytable_l   ; the main keytable
        add     hl,de
        ld      a,(hl)                  ; A=decoded L-mode key
        scf                             ; carry set, valid key
        ret


; ***************************************************************************
; * K-DECODE routine (at $0333 in original 48K ROM)                         *
; ***************************************************************************
; Enters with:
;       C=contents of MODE system variable
;       D=contents of FLAGS system variable
;       E="main" key code (assuming L mode and no shifts)
;       B=shift key code ($ff/$27/$18)

k_decode:
        ld      a,e
        cp      '9'+1
        jr      c,k_decode_6            ; on for digits, SPACE, ENTER, EXTEND
        dec     c
reloc_5:
        jp      m,k_decode_4            ; on for letters in K/L/C modes
        jr      z,k_decode_2            ; on for letters in E mode

        ; Letters in G mode
        ld      d,b                     ; D=shift key
        ld      bc,next_reg_select
        ld      e,nxr_core_boot
        out     (c),e
        inc     b
        in      e,(c)
        add     a,token_to-'A'          ; DRIVE+letters to TO..RESTORE
        bit     1,e
        ret     nz
        add     a,udgA-token_to         ; unshifted letters to UDGs
        inc     d
        ret     z
        add     a,token_new-udgA        ; CAPS-shifted letters to NEW..COPY
        bit     0,d
        ret     z
        add     a,token_sin-token_new   ; SYM-shifted letters to SIN..THEN
        ret

        ; Letters in E mode
k_decode_2:
reloc_6:
        ld      hl,keytable_e-'A'       ; unshifted E-mode table
        inc     b
        jr      z,k_decode_3            ; on if neither shift pressed
reloc_7:
        ld      hl,keytable_e_s-'A'     ; shifted E-mode table

        ; Enter here with:
        ;       E="main" key
        ;       HL=keytable offset by minimum value of E
k_decode_3:
        ld      d,$00
        add     hl,de                   ; index into table
        ld      a,(hl)                  ; A=fully-decoded key
        ret

        ; Letters in K/L/C modes
k_decode_4:
reloc_8:
        ld      hl,keytable_sym-'A'     ; symbol code table
        bit     0,b
        jr      z,k_decode_3            ; back for SYM-SHIFTed letters
        bit     3,d
        jr      z,k_decode_5            ; on for K mode
        bit     3,(iy+iy_FLAGS2)
        ret     nz                      ; exit with upper-case letter in C mode
        inc     b
        ret     nz                      ; or if CAPS SHIFT held
        add     a,'a'-'A'               ; otherwise convert to lower-case
        ret

        ; Letters in K mode
k_decode_5:
        add     a,token_new-'A'         ; convert letter to keyword tokens
        ret

        ; Digits, SPACE, ENTER, EXTEND
k_decode_6:
        cp      '0'
        ret     c                       ; no conversion for SPACE/ENTER/EXTEND
        dec     c
reloc_9:
        jp      m,k_decode_9            ; on for K/L/C modes
        jr      nz,k_decode_8           ; on for G mode
reloc_10:
        ld      hl,keytable_e_d-'0'     ; extended mode table for digits
        bit     5,b
        jr      z,k_decode_3            ; use table if SYM SHIFT held
        cp      '8'
        jr      nc,k_decode_7           ; on for '8' or '9'
        sub     $20                     ; convert to "paper colour" $10..$17
        inc     b                       ; if no shift held
        ret     z
        add     a,$08                   ; convert to "ink colour" $18..$1f
        ret                             ; if CAPS SHIFT held

        ; '8' or '9' in E mode with CAPS SHIFT or no shift
k_decode_7:
        sub     '6'                     ; convert to "bright code" $02..$03
        inc     b                       ; if no shift held
        ret     z
        add     a,$fe                   ; convert to "flash code" $00..$01
        ret                             ; if CAPS SHIFT held

        ; Digits in G mode
k_decode_8:
reloc_11:
        ld      hl,keytable_cc-'0'      ; control code keytable
        cp      $39
        jr      z,k_decode_3            ; special case 9 (GRAPHICS mode)
        cp      $30
        jr      z,k_decode_3            ; special case 0 (DELETE)
        add     a,170-'1'               ; SYM-shifted digits to 170..177
        bit     0,b
        ret     z
        dec     a                       ; unshifted digits to 128..135
        and     $07
        or      $80
        inc     b
        ret     z
        xor     $0f                     ; CAPS-shifted digits to 136..143
        ret

        ; Digits in K/L/C modes
k_decode_9:
        inc     b                       ; use digits if unshifted
        ret     z
        bit     5,b
reloc_12:
        ld      hl,keytable_cc-'0'      ; use control code table if CAPS SHIFTed
        jr      nz,k_decode_3
        ; Symbol-shifted digits
        sub     $10                     ; convert to: SPACE,!,",#,$,%,&,',(,)
        cp      '"'                     ; " needs to be replaced with @
        jr      z,k_decode_10
        cp      ' '                     ; SPACE needs to be replaced with _
        ret     nz
        ld      a,'_'                   ; SYM SHIFT+0 is _
        ret
k_decode_10:
        ld      a,'@'                   ; SYM SHIFT+2 is @
        ret


; ***************************************************************************
; * Relocation table                                                        *
; ***************************************************************************
; This follows directly after the full 512 bytes of the driver.


if ($ > 512)
.ERROR Driver code exceeds 512 bytes
else
        defs    512-$
endif

; Each relocation is the offset of the high byte of an address to be relocated.

reloc_start:
        defw    reloc_1+2
        defw    reloc_2+2
        defw    reloc_3+2
        defw    reloc_4+2
        defw    reloc_5+2
        defw    reloc_6+2
        defw    reloc_7+2
        defw    reloc_8+2
        defw    reloc_9+2
        defw    reloc_10+2
        defw    reloc_11+2
        defw    reloc_12+2
        defw    reloc_13+2
reloc_end:

