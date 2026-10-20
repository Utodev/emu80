;-------------------------------
	device zxspectrum48
;-------------------------------

;	DEFINE testing

LAYER_2_PAGE	= 9

M_GETSETDRV  equ $89
F_OPEN       equ $9a
F_CLOSE      equ $9b
F_READ       equ $9d
F_WRITE      equ $9e
F_SEEK       equ $9f
F_GET_DIR    equ $a8
F_SET_DIR    equ $a9
FA_READ      equ $01
FA_APPEND    equ $06
FA_OVERWRITE equ $0E

SPRITE_CONTROL_REGISTER			equ $15		;Enables/disables Sprites and Lores Layer, and chooses priority of sprites and Layer 2.
PALETTE_INDEX_REGISTER			equ $40		;Chooses a ULANext palette number to configure.
PALETTE_VALUE_REGISTER			equ $41		;Used to upload 8-bit colors to the ULANext palette.
PALETTE_FORMAT_REGISTER			equ $42
PALETTE_CONTROL_REGISTER		equ $43		;Enables or disables ULANext interpretation of attribute values and toggles active palette.
PALETTE_VALUE_BIT9_REGISTER		equ $44		;Holds the additional blue color bit for RGB333 color selection.
MMU_REGISTER_6				equ $56		;Set a Spectrum RAM page at position 0xC000 to 0xDFFF
MMU_REGISTER_7				equ $57		;Set a Spectrum RAM page at position 0xE000 to 0xFFFF

GRAPHIC_PRIORITIES_SLU	= %00000000	; sprites over l2 over ula
GRAPHIC_PRIORITIES_LSU	= %00000100
GRAPHIC_PRIORITIES_SUL	= %00001000
GRAPHIC_PRIORITIES_LUS	= %00001100
GRAPHIC_PRIORITIES_USL	= %00010000
GRAPHIC_PRIORITIES_ULS	= %00010100
GRAPHIC_OVER_BORDER	= %00000010
GRAPHIC_SPRITES_VISIBLE	= %00000001
LORES_ENABLE		= %10000000


	MACRO SetSpriteControlRegister
		NEXTREG_A SPRITE_CONTROL_REGISTER
	ENDM

; Set Next hardware register using A
	MACRO NEXTREG_A register
	dw $92ED
	db register
	ENDM
; Set Next hardware register using an immediate value
	MACRO NEXTREG_nn register, value
	dw $91ED
	db register
	db value
	ENDM

;-------------------------------

	IFDEF testing
	
	org	$6000
start
	ld ix,testfile
	jp loadbmp

testfile db "bg00_2.bmp",0
	
	ELSE
	
	org	$2000
start
	ld a,h:or l:jr nz,.gl	
	ld	hl,emptyline:call print_rst16:jr finish
.gl	ld	de,filename:ld b,255
.bl	ld	a,(hl):cp ":":jr z,.dn:or a:jr z,.dn:cp 13:jr z,.dn:bit 7,a:jr nz,.dn
	ld	(de),a:inc hl:inc de:djnz .bl
.dn	xor a:ld	(de),a
	ld	ix,filename
	jp loadbmp
finish
	xor	a:ret

	ENDIF

;-------------------------------

loadbmp
	ld (stackptr),sp
	ld sp,mystack
	
	push ix:call setdrv:pop ix:call fopen:ld a,2:jp c,fileError
	ld	ix,header:ld bc,0x36:call fread:ld a,3:jp c,fileError
	ld hl,(header+10):ld bc,-0x36:add hl,bc:ld c,l:ld b,h:ld ix,palette:call fread:ld a,3:jp c,fileError
	ld	hl,palette:ld de,nextpal:ld b,0
.lp	ld	a,(hl):inc hl:add a,16:jr nc,.nb:ld a,255
.nb	rlca:rlca:push af:and 3:ld c,a
	ld	a,(hl):inc hl:add a,16:jr nc,.ng:ld a,255
.ng	rra:rra:rra:and 7<<2:or c:ld c,a
	ld	a,(hl):inc hl:add a,16:jr nc,.nr:ld a,255
.nr	and 7<<5:or c:ld (de),a:inc de:pop af:rlca:and 1:ld (de),a:inc de:inc hl:djnz .lp
	NEXTREG_nn PALETTE_CONTROL_REGISTER,%10000
	NEXTREG_nn PALETTE_INDEX_REGISTER, 	0
	ld	hl,nextpal:ld b,0
.pl	ld a,(hl):inc hl:NEXTREG_A PALETTE_VALUE_BIT9_REGISTER
	ld a,(hl):inc hl:NEXTREG_A PALETTE_VALUE_BIT9_REGISTER
	djnz .pl

	ld a,(header+25):bit 7,a:jr z,.norm
	ld hl,(header+22):ld a,h:cpl:ld h,a:ld a,l:cpl:ld l,a:inc hl:ld (header+22),hl	; invert Y size
.norm

	ld	a,(header+22):ld b,a
.bl	push bc
	ld a,(header+25):bit 7,a:jr z,.nm
	ld a,(header+22):dec a:sub b:ld b,a
.nm	ld a,b:dec a:and $e0:rlca:rlca:rlca:add a,LAYER_2_PAGE*2:NEXTREG_A MMU_REGISTER_6
	ld a,b:dec a:and $1f:or $c0:ld h,a:ld l,0:push hl:pop ix:ld bc,(header+18):call fread:pop bc:ld a,3:jp c,fileError
	djnz .bl

	call fclose
	ld a,($5b5c):and 7:add a,a:NEXTREG_A MMU_REGISTER_6
	ld	bc,4667:ld a,2:out (c),a
	ld a, GRAPHIC_PRIORITIES_SUL + GRAPHIC_SPRITES_VISIBLE:SetSpriteControlRegister		; set image priorities
	; set transparency on ULA
	NEXTREG_nn PALETTE_CONTROL_REGISTER, 0
	NEXTREG_nn PALETTE_CONTROL_REGISTER, 0
	NEXTREG_nn PALETTE_INDEX_REGISTER, 	$18
	NEXTREG_nn PALETTE_VALUE_REGISTER, 	$e3
	ld hl,$4000:ld de,$4001:ld bc,$17ff:ld (hl),l:ldir
	ld hl,$5800:ld de,$5801:ld bc,$2ff:ld (hl),$47:ldir
	xor a:out (254),a
	ld sp,(stackptr)
	ret

;--------------------
fileError
	out (254),a
	call fclose
	ld a,($5b5c):and 7:add a,a:NEXTREG_A MMU_REGISTER_6
	ld	bc,4667:xor a:out (c),a
	ld a, GRAPHIC_PRIORITIES_SUL + GRAPHIC_SPRITES_VISIBLE:SetSpriteControlRegister		; set image priorities
	; set transparency on ULA
	NEXTREG_nn PALETTE_CONTROL_REGISTER, 0
	NEXTREG_nn PALETTE_CONTROL_REGISTER, 0
	NEXTREG_nn PALETTE_INDEX_REGISTER, 	$18
	NEXTREG_nn PALETTE_VALUE_REGISTER, 	$e3
	ld sp,(stackptr)
	ret
;-------------
setdrv
	xor a:rst $08:db M_GETSETDRV
	ld (drive),a:ret
;-------------
fopen
	ld b,FA_READ:db $21
fcreate
	ld b,FA_OVERWRITE:db 62
drive	db 0
	push ix:pop hl:rst $08:db F_OPEN
	ld (handle),a
	ret
;--------------
fread
	push ix:pop hl:db 62
handle	db 1
	rst $08:db F_READ
	ret
;-------------
fclose
	ld a,(handle):rst $08:db F_CLOSE
	ret

;-------------

stackptr dw	0

header	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db	0,0,0,0,0,0

print_rst16	ld a,(hl):inc hl:or a:ret z:rst 16:jr print_rst16

nextpal	db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

filename	db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
mystack
emptyline	db		".bmpload <filename> to load image to background",13,0

palette		db	0

	IFDEF testing

	savesna "bmpload.sna",start

	ELSE

last
	savebin "BMPLOAD",start,last-start

	ENDIF

;-------------------------------
