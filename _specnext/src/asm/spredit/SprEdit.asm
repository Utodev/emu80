;-------------------------------
	device zxspectrumnext
;-------------------------------

;	DEFINE testing

;-------------------------------

SPRITE_STATUS_SLOT_SELECT	equ $303B

SPRITE_INFO_PORT	equ	$5b

KEYAND_CAPS		equ %00000001
KEYAND_Z		equ	%00000010
KEYAND_X		equ	%00000100
KEYAND_C		equ	%00001000
KEYAND_V		equ	%00010000
KEYAND_A		equ %00000001
KEYAND_S		equ	%00000010
KEYAND_D		equ	%00000100
KEYAND_F		equ	%00001000 
KEYAND_G		equ	%00010000
KEYAND_Q		equ %00000001
KEYAND_W		equ	%00000010
KEYAND_E		equ	%00000100
KEYAND_R		equ	%00001000
KEYAND_T		equ	%00010000
KEYAND_1		equ %00000001
KEYAND_2		equ	%00000010
KEYAND_3		equ	%00000100
KEYAND_4		equ	%00001000
KEYAND_5		equ	%00010000
KEYAND_0		equ %00000001
KEYAND_9		equ	%00000010
KEYAND_8		equ	%00000100
KEYAND_7		equ	%00001000
KEYAND_6		equ	%00010000
KEYAND_P		equ %00000001
KEYAND_O		equ	%00000010
KEYAND_I		equ	%00000100
KEYAND_U		equ	%00001000
KEYAND_Y		equ	%00010000
KEYAND_ENTER		equ %00000001
KEYAND_L		equ	%00000010
KEYAND_K		equ	%00000100
KEYAND_J		equ	%00001000
KEYAND_H		equ	%00010000
KEYAND_SPACE		equ %00000001
KEYAND_SYM		equ	%00000010
KEYAND_M		equ	%00000100
KEYAND_N		equ	%00001000
KEYAND_B		equ	%00010000

KEY_CAPS	equ 7
KEY_Z		equ	7
KEY_X		equ	7
KEY_C		equ	7
KEY_V		equ	7
KEY_A		equ 6
KEY_S		equ	6
KEY_D		equ	6
KEY_F		equ	6
KEY_G		equ	6
KEY_Q		equ 5
KEY_W		equ	5
KEY_E		equ	5
KEY_R		equ	5
KEY_T		equ	5
KEY_1		equ 4
KEY_2		equ	4
KEY_3		equ	4
KEY_4		equ	4
KEY_5		equ	4
KEY_0		equ 3
KEY_9		equ	3
KEY_8		equ	3
KEY_7		equ	3
KEY_6		equ	3
KEY_P		equ 2
KEY_O		equ	2
KEY_I		equ	2
KEY_U		equ	2
KEY_Y		equ	2
KEY_ENTER	equ 1
KEY_L		equ	1
KEY_K		equ	1
KEY_J		equ	1
KEY_H		equ	1
KEY_SPACE	equ 0
KEY_SYM		equ	0
KEY_M		equ	0
KEY_N		equ	0
KEY_B		equ	0

;-------------------------------

LAYER_2_PAGE	= 9*2
LAYER_2_PAGE_0	= 9*2
LAYER_2_PAGE_1	= 10*2
LAYER_2_PAGE_2	= 11*2


M_DRV_API	 equ $92
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
FA_OVERWRITE equ $0C

TBBLUE_REGISTER_SELECT			equ $243B
TBBLUE_REGISTER_ACCESS			equ $253B

TURBO_CONTROL_REGISTER			equ $07		;Turbo mode 0=3.5Mhz, 1=7Mhz, 2=14Mhz 3=28Mhz
GLOBAL_TRANSPARENCY_REGISTER		equ $14		;Sets the color treated as transparent when drawing layer 2.
SPRITE_CONTROL_REGISTER			equ $15		;Enables/disables Sprites and Lores Layer, and chooses priority of sprites and Layer 2.
RASTER_LINE_MSB_REGISTER		equ $1E
RASTER_LINE_LSB_REGISTER		equ $1F
SPRITE_SELECT_REGISTER			equ $34
SPRITE_X_VALUE_REGISTER			equ $35
SPRITE_Y_VALUE_REGISTER			equ $36
SPRITE_X_MSB_AND_FLIP_REGISTER		equ $37
SPRITE_PATTERN_ENABLE_REGISTER		equ $38
SPRITE_ATTRIBUTES_REGISTER		equ $39
PALETTE_INDEX_REGISTER			equ $40		;Chooses a ULANext palette number to configure.
PALETTE_VALUE_REGISTER			equ $41		;Used to upload 8-bit colors to the ULANext palette.
PALETTE_FORMAT_REGISTER			equ $42
PALETTE_CONTROL_REGISTER		equ $43		;Enables or disables ULANext interpretation of attribute values and toggles active palette.
PALETTE_VALUE_BIT9_REGISTER		equ $44		;Holds the additional blue color bit for RGB333 color selection.
TRANSPARENCY_INDEX_SPRITES_REGISTER	equ $4b
TRANSPARENCY_INDEX_TILEMAP_REGISTER	equ $4c
MMU_REGISTER_0				equ $50		;Set a Spectrum RAM page at position 0x0000 to 0x1FFF
MMU_REGISTER_1				equ $51		;Set a Spectrum RAM page at position 0x2000 to 0x3FFF
MMU_REGISTER_2				equ $52		;Set a Spectrum RAM page at position 0x4000 to 0x5FFF
MMU_REGISTER_3				equ $53		;Set a Spectrum RAM page at position 0x6000 to 0x7FFF
MMU_REGISTER_4				equ $54		;Set a Spectrum RAM page at position 0x8000 to 0x9FFF
MMU_REGISTER_5				equ $55		;Set a Spectrum RAM page at position 0xA000 to 0xBFFF
MMU_REGISTER_6				equ $56		;Set a Spectrum RAM page at position 0xC000 to 0xDFFF
MMU_REGISTER_7				equ $57		;Set a Spectrum RAM page at position 0xE000 to 0xFFFF
SPRITE_X_VALUE_REGISTER_INC		equ $75
SPRITE_Y_VALUE_REGISTER_INC		equ $76
SPRITE_X_MSB_AND_FLIP_REGISTER_INC	equ $77
SPRITE_PATTERN_ENABLE_REGISTER_INC	equ $78
SPRITE_ATTRIBUTES_REGISTER_INC		equ $79


GRAPHIC_PRIORITIES_SLU	= %00000000	; sprites over l2 over ula
GRAPHIC_PRIORITIES_LSU	= %00000100
GRAPHIC_PRIORITIES_SUL	= %00001000
GRAPHIC_PRIORITIES_LUS	= %00001100
GRAPHIC_PRIORITIES_USL	= %00010000
GRAPHIC_PRIORITIES_ULS	= %00010100
GRAPHIC_OVER_BORDER		= %00000010
GRAPHIC_SPRITES_VISIBLE	= %00000001
LORES_ENABLE			= %10000000


;-------------------------------

	IFDEF testing

	org	$6000
start
	ld	(stackptr),sp:ld sp,$5fff
	ELSE

	org	$2000
start
	ld	de,filename:ld b,64
	ld	a,h:or l:jp z,noname
.bl	ld	a,(hl):cp '"':jr nz,.nq:inc hl:jr .bl
.nq	cp	":":jr z,.dn:or a:jr z,.dn:cp 13:jr z,.dn:bit 7,a:jr nz,.dn
	ld	(de),a:inc hl:inc de:djnz .bl
.dn	xor a:ld	(de),a
	ld	(stackptr),sp:ld sp,$3fff

	ENDIF

	di
	ld bc,$243b:ld a,MMU_REGISTER_4:out (c),a:inc b:in a,(c):ld (reg4+1),a
	ld bc,$243b:ld a,MMU_REGISTER_5:out (c),a:inc b:in a,(c):ld (reg5+1),a
	ld bc,$243b:ld a,MMU_REGISTER_6:out (c),a:inc b:in a,(c):ld (reg6+1),a
	ld bc,$243b:ld a,MMU_REGISTER_7:out (c),a:inc b:in a,(c):ld (reg7+1),a
	nextreg MMU_REGISTER_4,40
	nextreg MMU_REGISTER_5,41
	nextreg MMU_REGISTER_6,42
	nextreg MMU_REGISTER_7,43
	
	nextreg TRANSPARENCY_INDEX_SPRITES_REGISTER,$e3
	nextreg GLOBAL_TRANSPARENCY_REGISTER,$e3
	nextreg TRANSPARENCY_INDEX_TILEMAP_REGISTER,0

	nextreg TURBO_CONTROL_REGISTER,3
	call DecompressEditorSprites
	ld hl,$8000:ld de,$8001:ld bc,$3fff:ld a,(e3col):ld (hl),a:ldir
	call setdrv:ld ix,filename:ld a,(ix+0):or a:call nz,loadto8000

	ld hl,nextpal:ld c,0
.pp	ld (hl),c:inc hl:ld a,c:rra:and 1:ld (hl),a:inc hl:inc c:jr nz,.pp
	ld hl,filename:ld de,palext:call changeext:jr nz,.sp
	ld ix,filename:ld a,(ix+0):or a:jr z,.sp
	call fopen:jr c,.sp
	ld ix,nextpal:ld bc,$200:call dofread
	call fclose
	ld hl,nextpal:ld c,0:ld b,0
.sc	ld a,(hl):inc hl:inc hl:cp $e3:jr nz,.ne:ld b,c
.ne	inc c:jr nz,.sc
	ld hl,nextpal:ld a,b:ld (e3col),a:add hl,a:ld (hl),$e3
.sp
	nextreg PALETTE_CONTROL_REGISTER,%10000
	nextreg PALETTE_INDEX_REGISTER, 	0
	ld	hl,nextpal:ld b,0
.pl	ld a,(hl):inc hl:nextreg PALETTE_VALUE_BIT9_REGISTER,a
	ld a,(hl):inc hl:nextreg PALETTE_VALUE_BIT9_REGISTER,a
	djnz .pl

	ld	de,$0000
.l	push de:ld bc,$0000:call vramfill:pop de:inc d:ld a,d:cp 192:jr nz,.l
	ld	de,$5080
.l2	push de:ld bc,(e3col):ld b,$80:call vramfill:pop de:inc d:ld a,d:cp $80:jr nz,.l2
	ld	hl,$4000:ld de,$4001:ld bc,$1800:ld (hl),l:ldir:ld (hl),$38:ld bc,$2ff:ldir:ld a,0:out (254),a
	ld hl,$5950:ld b,2
.l3	push hl:push bc:ld e,l:ld d,h:inc e:ld (hl),0*8+4:ld bc,15:ldir:pop bc:pop hl:ld de,32:add hl,de:djnz .l3
	ld b,4
.l4	push hl:push bc:ld e,l:ld d,h:inc e:ld (hl),0*8+5:ld bc,15:ldir:pop bc:pop hl:ld de,32:add hl,de:djnz .l4

	call showhelp

	ld	bc,4667:ld a,2:out (c),a
	call editor

finish
	ld	hl,$4000:ld de,$4001:ld bc,$1800:ld (hl),l:ldir:ld bc,$2ff:ld (hl),$38:ldir
	ld	bc,4667:xor a:out (c),a
	call sproff
	ld a,4:nextreg MMU_REGISTER_4,a
	ld a,5:nextreg MMU_REGISTER_5,a
	ld a,($5b5c):and 7:add a,a:nextreg MMU_REGISTER_6,a:inc a:nextreg MMU_REGISTER_7,a
;	ld a,0:nextreg MMU_REGISTER_6,a
;	ld a,1:nextreg MMU_REGISTER_7,a
	ld sp,(stackptr):ei:xor a:ret
reg4 ld a,0:nextreg MMU_REGISTER_4,a
reg5 ld a,0:nextreg MMU_REGISTER_5,a
reg6 ld a,0:nextreg MMU_REGISTER_6,a
reg7 ld a,0:nextreg MMU_REGISTER_7,a
	ld sp,(stackptr):ei:xor a:ret

noname
	ld hl,$4000:ld de,$4001:ld bc,$1800:ld (hl),l:ldir:ld bc,$2ff:ld (hl),$38:ldir
	call sprint
	db	22,0*8,0*8,"SprEdit"
	db	22,0*8,2*8,"Usage :-"
	db	22,0*8,3*8,"SprEdit filename.spr"
	db	0
	xor a:ret

changeext
	ld a,(hl):inc hl:or a:jr nz,changeext
	dec	hl
	dec hl:ld a,(hl):cp ".":jr z,.got
	dec hl:ld a,(hl):cp ".":jr z,.got
	dec hl:ld a,(hl):cp ".":jr z,.got
	dec hl:ld a,(hl):cp ".":jr z,.got
	ret
.got inc hl
.gl ld a,(de):ld (hl),a:inc de:inc hl:or a:jr nz,.gl:ret

palext	db 	"pal",0
sprext	db	"spr",0

;-------------------------------

;IDE_BANK	equ $01bd
;
;NEXTOS_RAM	equ	$0000
;MMC_RAM		equ $0100
;
;NEXTOS_BANK_REASON_TOTAL		=	0
;NEXTOS_BANK_REASON_ALLOCATE		=	1
;NEXTOS_BANK_REASON_RESERVE		=	2
;NEXTOS_BANK_REASON_FREE			=	3
;NEXTOS_BANK_REASON_AVAILABLE	=	0
;
;NumBanksUsed	db	4
;AllocatedBank	db	0
;AllocatedBanks	db	0,0,0,0
;
;AllocateBanks
;	ld hl,AllocatedBanks:ld a,(NumBanksUsed):ld b,a
;.lp	push hl:push bc:call AllocateBank:pop bc:pop hl:jp nc,mallocerr:ld (hl),a:inc hl:djnz .lp
;	xor a
;	ret
;
;FreeBanks
;	ld hl,AllocatedBanks:ld a,(NumBanksUsed):ld b,a
;.lp	push hl:push bc:ld a,(hl):inc hl:call FreeBank:pop bc:pop hl:djnz .lp
;	ret
;
; H=banktype (ZX=0, 1=MMC); L=reason (1=allocate)*
;AllocateBank
;	exx:ld hl,NEXTOS_BANK_REASON_ALLOCATE:exx	;If you want a specific bank ID, you can change L to $02 (reserve) and provide the bank number you want in E
;	ld c,7:ld de,IDE_BANK:rst $8:defb $94		; M_P3DOS
;	ld (AllocatedBank),a:ret					;If successful (carry SET), returns 8K bank id in A
;FreeBank
;	exx:ld hl,NEXTOS_BANK_REASON_FREE:exx	;If you want a specific bank ID, you can change L to $02 (reserve) and provide the bank number you want in E
;	ld c,7:ld de,IDE_BANK:rst $8:defb $94		; M_P3DOS
;	ret
;HowManyAvailable
;	exx:ld hl,NEXTOS_BANK_REASON_AVAILABLE:exx	;If you want a specific bank ID, you can change L to $02 (reserve) and provide the bank number you want in E
;	ld c,7:ld de,IDE_BANK:rst $8:defb $94		; M_P3DOS
;	ret
;HowManyTotal
;	exx:ld hl,NEXTOS_BANK_REASON_TOTAL:exx		;If you want a specific bank ID, you can change L to $02 (reserve) and provide the bank number you want in E
;	ld c,7:ld de,IDE_BANK:rst $8:defb $94		; M_P3DOS
;	ret
;
;mallocerr
;	scf
;	ret
;
;-------------------------------

savefile	push hl:push bc:call fcreate:pop bc:pop ix:jr c,failsave:push bc:call fwrite:pop de:ld a,c:cp e:jr nz,failsave:ld a,b:cp d:jr nz,failsave:call fclose:xor a:ret
failsave	scf:ret
loadto8000	call fopen:ld a,(handle):or a:ret z:ld ix,$8000:ld bc,$4000:call dofread:jp fclose

dofread		push bc:push ix:ld bc,128:call fread:pop hl:push hl
			ld b,8:ld de,.plus3
.lp			ld a,(de):cp (hl):jr nz,.skip:inc hl:inc de:djnz .lp
			pop ix:pop bc:jp fread
.skip		pop ix:ld bc,128:add ix,bc:pop bc:add bc,-128:jp fread
.plus3		db "PLUS3DOS"
;--------------------

sprint	pop hl:call prt:jp (hl)
prt		ld a,(hl):inc hl:or a:ret z:cp 32:jr c,.codes
		call prtchr:jp prt
.codes	cp	22:jr nz,.nat:ld e,(hl):inc hl:ld d,(hl):inc hl:jr prt
.nat	jp prt

prthex16	ld a,h:call prthex8:ld a,l
prthex8	push af:rra:rra:rra:rra:call prthex4:pop af
prthex4	push hl:and 15:ld hl,.hex:add hl,a:ld a,(hl):call prtchr:pop hl:ret
.hex	db	"0123456789ABCDEF"

prtchr	push hl:push de:push bc
		push af:PIXELAD:pop af
		sub 32:ld e,a:ld d,8:mul d,e:add de,font:ld b,8
.lp		ld a,(de):inc de:ld (hl),a:pixeldn:djnz .lp
		pop bc:pop de:pop hl:ld a,e:add a,8:ld e,a:ret

WaitVertical192
        ld bc,TBBLUE_REGISTER_SELECT:ld a,RASTER_LINE_MSB_REGISTER:out (c),a:inc b
.w1		in a,(c):and 1:jp nz,.w1
		ld bc,TBBLUE_REGISTER_SELECT:ld a,RASTER_LINE_LSB_REGISTER:out (c),a:inc b
.w2		in a,(c):cp 192:jp nz,.w2
        ret
;--------------------
fileError
	ld a,6:out (254),a
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
	ld (handle),a:jp c, fileError
	ret
;--------------
fread
	push ix:pop hl:db 62
handle	db 1
	rst $08:db F_READ
	ret
;--------------
fwrite
	push ix:pop hl:ld a,(handle)
	rst $08:db F_WRITE
	ret
;-------------
fclose
	ld a,(handle):rst $08:db F_CLOSE
	ret

;-------------

editorSprites	incbin "cursor.cbn"
	INCLUDE "Packer.asm"

DecompressEditorSprites
	ld hl, editorSprites:ld de, $8000:call DEC40
	ld e,0:ld bc,SPRITE_STATUS_SLOT_SELECT:out (c),e		; select sprite 0
	ld c,0:ld b,64							; 64 sprites
	ld hl, $8000							; from $8000
	call TransferDMASprite
	ret
;-------------
TransferDMASprite
	ld (DMAW),hl:ld (DMAW+2),bc
	ld hl,DMA:ld b,DMALen:ld c,$6b
	otir
	ret
DMA
	db $c3,$c7,$cb,%01111101
DMAW	dw 0,0
	db %01010100, %00000010, %01101000,%00000010,%10101101,$5b,%10000010,$cf,$87
DMALen	equ $-DMA
;-------------
filename	db	"cursor.spr"
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

nextpal	db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

emptyline	db		".SPREDIT <filename> to load     sprite images to sprite VRAM andedit them",13,0

font	incbin	"specfont.chr"

;-------------------------------

oldkeys	db	0,0,0,0,0,0,0,0	; 0 0 1 1
newkeys	db	0,0,0,0,0,0,0,0 ; 0 1 0 1
debkeys	db	0,0,0,0,0,0,0,0 ; 0 1 0 0

scankeys	ld	a,%01111111:ld hl,oldkeys:ld de,newkeys:ld bc,debkeys
.lp	push af:ld a,(de):ld (hl),a:pop af
	push af:in a,(254):cpl:ld (de),a:and (hl):ex de,hl:xor (hl):ex de,hl:ld (bc),a:pop af
	inc	 hl:inc de:inc bc:rrca:jr c,.lp:ret

;-------------------------------

stackptr	dw	0
gameframe	db	0
sprnumber	db	0
sprn		db	0
spri		db	$00
sprb		db	$00
paper		db	$e3
ink			db	$ff
cursorx		db	0
cursory		db	0
mousex		db	0
mousey		db	0
omousex		db	0
omousey		db	0
nmousex		db	0
nmousey		db	0
mouseb		db	0
omouseb		db	0
mouseon		db	0
rmousex		dw	0
rmousey		dw	0
dmousex		db	0
dmousey		db	0

e3col		db	$e3

animframe	db	0
animtable	db	0,1,2,3,4,5,6,7
animcount	db	0
animtick	db	0
animspd		db	4

copyID		db	0

rangehl
	bit 7,h:jr nz,.mi
	or a:push hl:sbc hl,bc:pop hl:ret c
	ld	h,b:ld l,c:dec hl:ret
.mi ld hl,0:ret

editor
	nextreg SPRITE_CONTROL_REGISTER,3	;Sprites Enabled and over border.

	ld	de,$8000:xor a
.l	push af:push de:call draw16x16:pop de:ld a,e:add a,16:ld e,a:jr nc,.s:ld a,d:add a,16:ld d,a
.s	pop af:inc a:cp 64:jr nz,.l

	call getmouse
	
editorlp
	ld	a,(sprnumber):call dumpsprite

editlp
	call scankeys
	ld	hl,gameframe:inc (hl)
	call WaitVertical192
	nextreg SPRITE_SELECT_REGISTER,0
	ld	a,(gameframe):rra:rra:and 1:ld (spri),a
	
	ld c,0
.cl	push bc:ld a,c:and 15:add a,a:add a,a:add a,192:ld e,a:ld a,c:rra:rra:and 15*4:ld d,a:ld a,c:call plot4x4:pop bc:inc c:jr nz,.cl
	
;	ld de,$00c0+32:ld l,32:ld bc,$008c:call SetSprite4x4
	ld	a,(sprnumber):ld l,a:add a,a:add a,a:add a,a:add a,a:add a,$20-2:ld e,a:adc a,0:sub e:ld d,a:ld a,l:and $30:add a,$80+$20-2:ld l,a:ld b,0:ld c,$8a:call SetSprite2x2

	ld a,(cursorx):and $0f:add a,a:add a,a:add a,a:add a,$20-1:ld e,a:ld d,0:ld a,(cursory):and $0f:add a,a:add a,a:add a,a:add a,$20-1:ld l,a:ld bc,(spri):set 7,c:call SetSprite

	ld	a,(paper):ld l,a:and $0f:add a,a:add a,a:add a,$e0:ld e,a:adc a,0:sub e:ld d,a:ld a,l:and $f0:rra:rra:add a,$20:ld l,a:ld b,0:ld a,(spri):add a,$82:ld c,a:call SetSprite
	ld	a,(ink):ld l,a:and $0f:add a,a:add a,a:add a,$e0:ld e,a:adc a,0:sub e:ld d,a:ld a,l:and $f0:rra:rra:add a,$20:ld l,a:ld b,0:ld a,(spri):add a,$84:ld c,a:call SetSprite

	ld	de,(nmousex):ld (omousex),de
	ld	a,(mouseb):ld (omouseb),a
	
	call getmouse:ld (mouseb),a:ld (nmousex),hl

	ld a,l:sub e:ld e,a:ld a,h:sub d:ld d,a:ld (dmousex),de	;delta mouse
	
	ld d,0:bit 7,e:jr z,.bl:dec d
.bl ld hl,(rmousex):add hl,de:ld bc,4*256:call rangehl:ld (rmousex),hl:sra  h:rr l:sra h:rr l:ld a,l:ld (mousex),a
	ld de,(dmousey):ld d,0:bit 7,e:jr z,.bd:dec d
.bd ld hl,(rmousey):add hl,de:ld bc,4*192:call rangehl:ld (rmousey),hl:sra  h:rr l:sra h:rr l:ld a,l:ld (mousey),a

	ld a,(mousex):add a,$20:ld e,a:adc a,0:sub e:ld d,a:ld a,(mousey):add a,$20:ld l,a:ld bc,$0006:ld a,(mouseon):or c:ld c,a:call SetSprite
	ld	de,(mousex):ld a,d:or e:jr z,.nms:ld a,$80:ld (mouseon),a
.nms

	ld a,(mouseb):bit 0,a:jp nz,.nlm
	ld	a,(mousex):cp 128:jr nc,.nlgrd:rrca:rrca:rrca:and 15:ld e,a
	ld	a,(mousey):cp 128:jr nc,.nlgrd:rrca:rrca:rrca:and 15:ld d,a
	ld a,(sprnumber):add a,$80:ld h,a:ld a,d:add a,a:add a,a:add a,a:add a,a:add a,e:ld l,a:ld a,(hl):ld (ink),a:jp .nlm
.nlgrd
	ld	a,(mousex):sub 192:jr c,.nlpal:rrca:rrca:and 15:ld e,a
	ld	a,(mousey):cp 64:jr nc,.nlpal:rrca:rrca:and 15:ld d,a
	ld a,d:add a,a:add a,a:add a,a:add a,a:add a,e:ld (ink),a:jr .nlm
.nlpal
	ld	a,(omouseb):bit 0,a:jp z,.nlanm
	ld	a,(mousex):sub 128:jr c,.nlanm
	ld	a,(mousey):cp 64:jr c,.nlanm:cp 80:jr nc,.nlanm
	ld	a,(animcount):or a:jr z,.nlm:dec a:ld (animcount),a:jr .nlm
.nlanm
	ld	a,(omouseb):bit 0,a:jp z,.nlspr
	ld	a,(mousex):rra:rra:rra:rra:and 15:ld e,a
	ld	a,(mousey):cp 128:jr c,.nlspr:cp 192:jr nc,.nlspr:rra:rra:rra:rra:and 15:ld d,a
	ld a,d:add a,a:add a,a:add a,a:add a,a:add a,e:and 63:ld (sprnumber),a:jp editorlp
.nlspr
.nlm
	ld a,(mouseb):bit 1,a:jp nz,.nrm
	ld	a,(mousex):cp 128:jr nc,.nrgrd:rrca:rrca:rrca:and 15:ld e,a
	ld	a,(mousey):cp 128:jr nc,.nrgrd:rrca:rrca:rrca:and 15:ld d,a
	ld a,(ink):call setbyte:jp .nrm
.nrgrd
	ld	a,(mousex):sub 192:jr c,.nrpal:rrca:rrca:and 15:ld e,a
	ld	a,(mousey):cp 64:jr nc,.nrpal:rrca:rrca:and 15:ld d,a
	ld a,d:add a,a:add a,a:add a,a:add a,a:add a,e:ld (paper),a:jr .nrm
.nrpal
	ld	a,(omouseb):bit 1,a:jp z,.nranm
	ld	a,(mousex):sub 128:jr c,.nranm
	ld	a,(mousey):cp 64:jr c,.nranm:cp 80:jr nc,.nranm
	ld	a,(animcount):cp 8:jr z,.nranm:ld hl,animtable:add a,l:ld l,a:adc a,h:sub l:ld h,a:ld a,(sprnumber):ld (hl),a:ld a,(animcount):inc a:ld (animcount),a:jr .nrm
.nranm
	ld	a,(omouseb):bit 0,a:jp z,.nrspr
	ld	a,(mousex):rra:rra:rra:rra:and 15:ld e,a
	ld	a,(mousey):cp 128:jr c,.nrspr:cp 192:jr nc,.nrspr:rra:rra:rra:rra:and 15:ld d,a
	ld a,d:add a,a:add a,a:add a,a:add a,a:add a,e:and 63:ld (sprnumber),a:jp editorlp
.nrspr
.nrm
	ld a,(mouseb):bit 2,a:jp nz,.nmm
	ld	a,(mousex):cp 128:jr nc,.nmgrd:rrca:rrca:rrca:and 15:ld e,a
	ld	a,(mousey):cp 128:jr nc,.nmgrd:rrca:rrca:rrca:and 15:ld d,a
	ld a,$e3:call setbyte:jr .nmm
.nmgrd
.nmm

	ld	a,(mousex):cp $98:jr c,.nm1:cp $a8:jr nc,.nm1
	ld	a,(mousey):cp $18:jr c,.nm1:cp $28:jr nc,.nm1
	ld a,(mouseb):bit 0,a:jp nz,.nm0
	ld a,(omouseb):bit 0,a:jp z,.nm0
	ld	a,(animspd):cp 31:jr z,.nm0:inc a:ld (animspd),a
.nm0
	ld a,(mouseb):bit 1,a:jp nz,.nm1
	ld a,(omouseb):bit 1,a:jp z,.nm1
	ld	a,(animspd):or a:jr z,.nm1:dec a:ld (animspd),a
.nm1

	ld	a,(animspd):ld e,a:ld a,(animtick):inc a:ld (animtick),a:cp e:jr c,.a
	xor a:ld (animtick),a:ld a,(animcount):ld e,a:ld a,(animframe):inc a:cp e:jr c,.b:xor a
.b	ld	(animframe),a
.a	ld	a,(animcount):or a:ld a,(sprnumber):jr z,.drawit:ld	a,(animframe):ld hl,animtable:add a,l:ld l,a:adc a,h:sub l:ld h,a:ld a,(hl)
.drawit	ld	de,$1898:call draw16x16

	ld	a,(gameframe):and 7:ld c,a:ld e,a:ld d,0:ld hl,animtable:add hl,de:ld a,e:add a,a:add a,a:add a,a:add a,a:add a,$80:ld e,a:ld d,$40
	ld	a,(animcount):ld b,a:ld a,c:cp b:jr nc,.zz
	ld	a,(hl):call draw16x16:jr .xx
.zz	push af:ld a,(e3col):ld c,a:pop af:call fill16x16 ;ld c,$e3:call fill16x16
.xx

	ld	a,(debkeys+KEY_G):and KEYAND_G:jr z,.ng
	ld	a,(animcount):or a:jr z,.ng:dec a:ld (animcount),a
.ng
	ld	a,(debkeys+KEY_H):and KEYAND_H:jr z,.nh
	ld	a,(animcount):cp 8:jr z,.nh:ld hl,animtable:add hl,a:ld a,(sprnumber):ld (hl),a:ld a,(animcount):inc a:ld (animcount),a
.nh

	ld	a,(debkeys+KEY_Y):and KEYAND_Y:jr z,.ny
	ld	a,(animspd):or a:jr z,.ny:dec a:ld (animspd),a
.ny
	ld	a,(debkeys+KEY_T):and KEYAND_T:jr z,.nt
	ld	a,(animspd):cp 31:jr z,.nt:inc a:ld (animspd),a
.nt

	ld	a,(newkeys+KEY_SYM):and KEYAND_SYM:jr z,.nsym
	ld	a,(debkeys+KEY_C):and KEYAND_C:jr z,.ncopy
	ld	a,(sprnumber):ld (copyID),a
.ncopy
	ld	a,(debkeys+KEY_V):and KEYAND_V:jr z,.npaste
	ld	a,(copyID):and 63:or $80:ld h,a:ld l,0
	ld	a,(sprnumber):and 63:or $80:ld d,a:ld e,0:ld bc,256:ldir:jp editor
.npaste
	ld	a,(debkeys+KEY_W):and KEYAND_W:jr z,.nwipe
	ld	a,(sprnumber):and 63:or $80:ld h,a:ld l,0:ld d,a:ld e,1:ld bc,255:ld a,(e3col):ld (hl),a:ldir:jp editor
.nwipe
	jp	.symskip
.nsym
	ld a,(debkeys+KEY_7):and KEYAND_7:jr nz,.iup
	ld a,(debkeys+KEY_Q):and KEYAND_Q+KEYAND_W+KEYAND_E:jr nz,.iup
	ld	a,(gameframe):and 7:jr nz,.nup
	ld a,(newkeys+KEY_Q):and KEYAND_Q+KEYAND_W+KEYAND_E:jr z,.nup
.iup
	ld a,1:ld (zapgameframe),a
	ld a,(cursory):dec a:and 15:ld (cursory),a
.nup
	ld a,(debkeys+KEY_6):and KEYAND_6:jr nz,.idn
	ld a,(debkeys+KEY_Z):and KEYAND_Z+KEYAND_X+KEYAND_C:jr nz,.idn
	ld	a,(gameframe):and 7:jr nz,.ndn
	ld a,(newkeys+KEY_Z):and KEYAND_Z+KEYAND_X+KEYAND_C:jr z,.ndn
.idn
	ld a,1:ld (zapgameframe),a
	ld a,(cursory):inc a:and 15:ld (cursory),a
.ndn
	ld a,(debkeys+KEY_5):and KEYAND_5:jr nz,.gol
	ld a,(debkeys+KEY_Q):and KEYAND_Q:jr nz,.gol:ld a,(debkeys+KEY_A):and KEYAND_A:jr nz,.gol:ld a,(debkeys+KEY_Z):and KEYAND_Z:jr nz,.gol
	ld	a,(gameframe):and 7:jr nz,.nlt
	ld a,(newkeys+KEY_Q):and KEYAND_Q:jr nz,.gol:ld a,(newkeys+KEY_A):and KEYAND_A:jr nz,.gol:ld a,(newkeys+KEY_Z):and KEYAND_Z:jr z,.nlt
.gol
	ld a,1:ld (zapgameframe),a
	ld a,(cursorx):dec a:and 15:ld (cursorx),a
.nlt
	ld a,(debkeys+KEY_8):and KEYAND_8:jr nz,.gor
	ld a,(debkeys+KEY_E):and KEYAND_E:jr nz,.gor:ld a,(debkeys+KEY_D):and KEYAND_D:jr nz,.gor:ld a,(debkeys+KEY_C):and KEYAND_C:jr nz,.gor
	ld	a,(gameframe):and 7:jr nz,.nrt
	ld a,(newkeys+KEY_E):and KEYAND_E:jr nz,.gor:ld a,(newkeys+KEY_D):and KEYAND_D:jr nz,.gor:ld a,(newkeys+KEY_C):and KEYAND_C:jr z,.nrt
.gor
	ld a,1:ld (zapgameframe),a
	ld a,(cursorx):inc a:and 15:ld (cursorx),a
.nrt

	ld	a,(newkeys+KEY_M):and KEYAND_M:jr z,.nm
	ld	de,(cursorx):ld a,(ink):call setbyte
.nm
	ld	a,(newkeys+KEY_N):and KEYAND_N:jr z,.nn
	ld	de,(cursorx):ld a,(paper):call setbyte
.nn
	ld	a,(debkeys+KEY_V):and KEYAND_V:jr z,.nv
	ld de,(cursorx):ld a,(sprnumber):add a,$80:ld h,a:ld a,d:add a,a:add a,a:add a,a:add a,a:add a,e:ld l,a:ld a,(hl):ld (ink),a
.nv
	ld	a,(debkeys+KEY_B):and KEYAND_B:jr z,.nb
	ld de,(cursorx):ld a,$e3:call setbyte
.nb

.symskip


	ld	e,1
	ld	a,(newkeys+KEY_CAPS):and KEYAND_CAPS:jr z,.nC
	ld	e,16
.nC
	ld	a,(debkeys+KEY_U):and KEYAND_U:jr nz,.iu
	ld	a,(gameframe):and 7:jr nz,.nu
	ld	a,(newkeys+KEY_U):and KEYAND_U:jr z,.nu
.iu
	ld a,1:ld (zapgameframe),a
	ld hl,ink:ld a,(hl):sub e:ld (hl),a
.nu
	ld	a,(debkeys+KEY_I):and KEYAND_I:jr nz,.ii
	ld	a,(gameframe):and 7:jr nz,.ni
	ld	a,(newkeys+KEY_I):and KEYAND_I:jr z,.ni
.ii
	ld	a,1:ld (zapgameframe),a
	ld	hl,ink:ld a,(hl):add a,e:ld (hl),a
.ni
	ld	a,(debkeys+KEY_O):and KEYAND_O:jr nz,.io
	ld	a,(gameframe):and 7:jr nz,.no
	ld	a,(newkeys+KEY_O):and KEYAND_O:jr z,.no
.io
	ld	a,1:ld (zapgameframe),a
	ld	hl,paper:ld a,(hl):sub e:ld (hl),a
.no
	ld	a,(debkeys+KEY_P):and KEYAND_P:jr nz,.ip
	ld	a,(gameframe):and 7:jr nz,.np
	ld	a,(newkeys+KEY_P):and KEYAND_P:jr z,.np
.ip
	ld	a,1:ld (zapgameframe),a
	ld	hl,paper:ld a,(hl):add a,e:ld (hl),a
.np

	ld	a,(debkeys+KEY_K):and KEYAND_K:jr nz,.ik
	ld	a,(gameframe):and 7:jr nz,.nk
	ld	a,(newkeys+KEY_K):and KEYAND_K:jr z,.nk
.ik
	ld	a,1:ld (zapgameframe),a
	ld	a,(sprnumber):sub e:and 63:ld (sprnumber),a:jp editorlp
.nk
	ld	a,(debkeys+KEY_L):and KEYAND_L:jr nz,.il
	ld	a,(gameframe):and 7:jr nz,.nl
	ld	a,(newkeys+KEY_L):and KEYAND_L:jr z,.nl
.il
	ld	a,1:ld (zapgameframe),a
	ld	a,(sprnumber):add a,e:and 63:ld (sprnumber),a:jp editorlp
.nl
	ld	a,(debkeys+KEY_J):and KEYAND_J:jr z,.nj
	ld 	a,(newkeys+KEY_CAPS):and KEYAND_CAPS:ld e,1:jr z,.ij:ld e,-1
.ij	ld	a,(helppage):add a,e:cp 9:jr nz,.n9:ld a,0
.n9	cp	-1:jr nz,.m1:ld a,8
.m1	ld	(helppage),a:call showhelp
.nj

	ld	a,(newkeys+KEY_CAPS):and KEYAND_CAPS:jr z,.ns
	ld	a,(debkeys+KEY_S):and KEYAND_S:jr z,.ns
	ld	hl,savetext:call prt
	ld	a,20:ld bc,$303b:out (c),a:ld a,(cursorx):and $0f:add a,a:add a,a:add a,a:add a,$20-2:ld e,a:ld d,0:ld a,(cursory):and $0f:add a,a:add a,a:add a,a:add a,$20-1:ld l,a:ld bc,$0087:call SetSprite
	ld	hl,filename:ld de,sprext:call changeext
	ld	ix,filename:ld hl,$8000:ld bc,$4000:call savefile:ld hl,saveFailtext:jr c,.ds
	ld	hl,filename:ld de,palext:call changeext:ld hl,saveOktext:jr nz,.ds
	ld	ix,filename:ld hl,nextpal:ld bc,$200:call savefile:ld hl,saveFailtext:jr c,.ds:ld hl,saveOktext
.ds	call prt:call pausekey:call showhelp:call sproff
.ns

	db	62
zapgameframe db	0:or a:jr z,.nz
	xor	a:ld (zapgameframe),a:ld (gameframe),a
.nz

	ld	a,(newkeys+KEY_CAPS):and KEYAND_CAPS:jr z,.ns0
	ld	a,(newkeys+KEY_0):and KEYAND_0:jr z,.ns0
	ld	a,(sprnumber):or $80:ld h,a:ld a,$e3:ld l,0
.s0 ld (hl),a:inc l:jr nz,.s0:jp editor
.ns0

	ld	a,(newkeys+KEY_SYM):and KEYAND_SYM:jp z,editlp
	ld	a,(debkeys+KEY_SPACE):and KEYAND_SPACE:jp z,editlp

	ret

showhelp
	db	62
helppage	db	0
	add a,a:ld hl,helptexts:add hl,a:ld a,(hl):inc hl:ld h,(hl):ld l,a:jp prt
	
helptexts
	dw	helptext0,helptext1,helptext2,helptext3,helptext4,helptext5,helptext6,helptext7,helptext8

helptext0
	db	22,16*8,10*8,"Sprite Editor   "
	db	22,16*8,11*8,"----------------"
	db	22,16*8,12*8,"Press J to cycle"
	db	22,16*8,13*8,"through help    "
	db	22,16*8,14*8,"pages, or Caps J"
	db	22,16*8,15*8,"to cycles back. "
	db	0

helptext1
	db	22,16*8,10*8,"Help : Movement "
	db	22,16*8,11*8,"----------------"
	db	22,16*8,12*8,"     Q/W/E      "
	db	22,16*8,13*8,"     A/ /D      "
	db	22,16*8,14*8,"     Z/X/C      "
	db	22,16*8,15*8,"                "
	db	0

helptext2
	db	22,16*8,10*8,"Help : Plotting "
	db	22,16*8,11*8,"----------------"
	db	22,16*8,12*8,"U previous ink  "
	db	22,16*8,13*8,"I next ink      "
	db	22,16*8,14*8,"O previous paper"
	db	22,16*8,15*8,"P next paper    "
	db	0

helptext3
	db	22,16*8,10*8,"Help : Plotting "
	db	22,16*8,11*8,"----------------"
	db	22,16*8,12*8,"M plot ink      "
	db	22,16*8,13*8,"N plot paper    "
	db	22,16*8,14*8,"B plot clear    "
	db	22,16*8,15*8,"V get ink at cur"
	db	0

helptext4
	db	22,16*8,10*8,"Help : Animation"
	db	22,16*8,11*8,"----------------"
	db	22,16*8,12*8,"K prev sprite   "
	db	22,16*8,13*8,"L next sprite   "
	db	22,16*8,14*8,"                "
	db	22,16*8,15*8,"                "
	db	0

helptext5
	db	22,16*8,10*8,"Help : Anim cont"
	db	22,16*8,11*8,"----------------"
	db	22,16*8,12*8,"H Add spr to ani"
	db	22,16*8,13*8,"G remove sprite "
	db	22,16*8,14*8,"T slow anim down"
	db	22,16*8,15*8,"Y speed up anim "
	db	0

helptext6
	db	22,16*8,10*8,"Help : Saving   "
	db	22,16*8,11*8,"----------------"
	db	22,16*8,12*8,"Shift S to save "
	db	22,16*8,13*8,"Do not turn off "
	db	22,16*8,14*8,"or remove SD    "
	db	22,16*8,15*8,"when saving!    "
	db	0

helptext7
	db	22,16*8,10*8,"Help : Exit     "
	db	22,16*8,11*8,"----------------"
	db	22,16*8,12*8,"Symbol Shift and"
	db	22,16*8,13*8,"Space will exit "
	db	22,16*8,14*8,"the sprite      "
	db	22,16*8,15*8,"editor.         "
	db	0

helptext8
	db	22,16*8,10*8,"Help : Cpy+Paste "
	db	22,16*8,11*8,"----------------"
	db	22,16*8,12*8,"Symbol Shift    "
	db	22,16*8,13*8,"+ C to copy spr "
	db	22,16*8,14*8,"+ V to paste spr"
	db	22,16*8,15*8,"+ W to wipe spr "
	db	0

savetext
	db	22,16*8,10*8,"Saving          "
	db	22,16*8,11*8,"----------------"
	db	22,16*8,12*8,"Please wait     "
	db	22,16*8,13*8,"do not reset or "
	db	22,16*8,14*8,"power off your  "
	db	22,16*8,15*8,"ZX Spectrum Next"
	db	0

saveOktext
	db	22,16*8,10*8,"Save complete!  "
	db	22,16*8,11*8,"----------------"
	db	22,16*8,12*8,"All good        "
	db	22,16*8,13*8,"                "
	db	22,16*8,14*8,"Press any key to"
	db	22,16*8,15*8,"continue        "
	db	0

saveFailtext
	db	22,16*8,10*8,"Save complete!  "
	db	22,16*8,11*8,"----------------"
	db	22,16*8,12*8,"Save failed :(  "
	db	22,16*8,13*8,"                "
	db	22,16*8,14*8,"Press any key to"
	db	22,16*8,15*8,"continue        "
	db	0

;-------------------------------

getmouse
	ld	bc,64479:in a,(c):ld l,a
	ld	bc,65503:in a,(c):cpl:ld h,a:ld (nmousex),hl
	ld	bc,64223:in a,(c):ld (mouseb),a
	ret

;-------------------------------

pausekey call waitnokey
waitkey xor a:in a,(254):cpl:and $1f:jr z,waitkey:ret
waitnokey xor a:in a,(254):cpl:and $1f:jr nz,waitnokey:ret

setbyte
	push de:push af:ex de,hl:add hl,hl:add hl,hl:add hl,hl:ex de,hl:call plot8x8:pop af:pop de
	push de:push af:ld a,(sprnumber):add a,a:add a,a:add a,a:add a,a:add a,e:ld e,a:ld a,(sprnumber):and $30:add a,$80:add a,d:ld d,a:pop af:push af:call plot:pop af:pop de
	push de:push af:ld a,(sprnumber):add a,$80:ld h,a:ld a,d:add a,a:add a,a:add a,a:add a,a:add a,e:ld l,a:pop af:ld (hl),a:pop de
	ret

;-------------------------------
;DE = Xpos    L = Ypos     B = sprite bits    C = Sprite image      sprite number already out to $303b
SetSprite
	xor a:nextreg SPRITE_PATTERN_ENABLE_REGISTER,a
	ld a,e:nextreg SPRITE_X_VALUE_REGISTER,a
	ld a,l:nextreg SPRITE_Y_VALUE_REGISTER,a
	ld a,d:and 1:or h:nextreg SPRITE_X_MSB_AND_FLIP_REGISTER,a
	ld a,c:or 128:nextreg SPRITE_PATTERN_ENABLE_REGISTER_INC,a
	ret

SetSprite4x4
	ld a,4
.cl	push af
	ld a,4
.bl	push af
	call SetSprite:ld a,e:add a,16:ld e,a:adc a,d:sub e:ld d,a:inc c:pop af:dec a:jr nz,.bl
	ld a,c:add a,16-4:ld c,a:ld a,l:add a,16:ld l,a:ld a,e:sub 64:ld e,a:jr nc,.skp:dec d
.skp
	pop af:dec a:jr nz,.cl	
	ret

SetSprite2x2
	ld a,2
.cl	push af
	ld a,2
.bl	push af
	call SetSprite:ld a,e:add a,16:ld e,a:adc a,d:sub e:ld d,a:inc c:pop af:dec a:jr nz,.bl
	ld a,c:add a,16-2:ld c,a:ld a,l:add a,16:ld l,a:ld a,e:sub 32:ld e,a:jr nc,.skp:dec d
.skp
	pop af:dec a:jr nz,.cl
	ret

sproff
	nextreg SPRITE_SELECT_REGISTER,0
	ld b,128
.l	nextreg SPRITE_PATTERN_ENABLE_REGISTER_INC,0
	djnz .l
	nextreg SPRITE_SELECT_REGISTER,0
	ret

sendsprs
	ld bc,$303b:xor a:out (c),a:ld hl,$8000:ld bc,SPRITE_INFO_PORT
.lp2	ld	a,(hl):inc l:out (c),a:jr nz,.lp2:inc h:ld a,h:cp $c0:jr nz,.lp2
	ret

tovram
	push bc:ld a,d:rlca:rlca:rlca:and 7:add a,LAYER_2_PAGE:nextreg MMU_REGISTER_6,a:ld a,d:and 31:or $c0:ld d,a:pop bc:ldir
	ret

vramfill
	push bc:ld a,d:rlca:rlca:rlca:and 7:add a,LAYER_2_PAGE:nextreg MMU_REGISTER_6,a:ld a,d:and 31:or $c0:ld d,a:pop bc:ld a,c
.l	ld (de),a:inc e:djnz .l
	ret

plot
	push af:ld a,d:rlca:rlca:rlca:and 7:add a,LAYER_2_PAGE:nextreg MMU_REGISTER_6,a:ld a,d:and 31:or $c0:ld h,a:ld l,e:pop af:ld (hl),a
	ret

plot8x8
	push af:ld a,d:rlca:rlca:rlca:and 7:add a,LAYER_2_PAGE:nextreg MMU_REGISTER_6,a:ld a,d:and 31:or $c0:ld h,a:ld l,e:xor a:ld b,8
.l	ld	(hl),a:inc hl:djnz .l
	ld	de,256-8:add hl,de:pop af:ld c,7
.c	ld	(hl),0:inc l:ld b,7
.b	ld	(hl),a:inc hl:djnz .b
	add	hl,de:dec c:jr nz,.c
	ret

plot4x4
	push af:ld a,d:rlca:rlca:rlca:and 7:add a,LAYER_2_PAGE:nextreg MMU_REGISTER_6,a:ld a,d:and 31:or $c0:ld h,a:ld l,e:xor a:ld b,4
.l	ld	(hl),a:inc hl:djnz .l
	ld	de,256-4:add hl,de:pop af:ld c,3
.c	ld	(hl),0:inc l:ld b,3
.b	ld	(hl),a:inc hl:djnz .b
	add	hl,de:dec c:jr nz,.c
	ret

dumpsprite
	and 63:add a,$80:ld h,a:ld l,0:ld de,$0000
.l	ld a,(hl):inc hl:push hl:push de:call plot8x8:pop de:pop hl:ld a,e:add a,8:ld e,a:cp $80:jr c,.l:ld e,0:ld a,d:add a,8:ld d,a:cp $80:jr c,.l:ret

draw16x16
	and 63:add a,$80:ld h,a:ld l,0:ld b,16
.l	push bc:push de:ld bc,16:call tovram:pop de:inc d:pop bc:djnz .l:ret

fill16x16
	and 63:add a,$80:ld h,a:ld l,0:ld b,16
.l	push bc:push de:ld b,16:call vramfill:pop de:inc d:pop bc:djnz .l:ret

	IFDEF testing
	SAVENEX OPEN "spredit.nex", start, $5fff, 0
	SAVENEX CORE 3, 0, 4       		; Next core 3.0.4 required as minimum
	SAVENEX CFG 0, 0, 0, 0            	; black border, close file ( not handle in BC )
	SAVENEX AUTO			    	; store the 16k banks
	SAVENEX CLOSE				; close the next file
;	savesna "spredit.sna",start
	ELSE
last
	savebin "SPREDIT",start,last-start
	ENDIF

;-------------------------------
