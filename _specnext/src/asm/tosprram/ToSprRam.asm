	device zxspectrum48

;	DEFINE testing

SPRITE_STATUS_SLOT_SELECT	equ $303B

SPRITE_INFO_PORT			equ	$5b

MMU_REGISTER_6				equ $56		;Set a Spectrum RAM page at position 0xC000 to 0xDFFF

M_DRV_API	 				equ $92
M_GETSETDRV  				equ $89
F_OPEN       				equ $9a
F_CLOSE      				equ $9b
F_READ       				equ $9d
F_WRITE      				equ $9e
F_SEEK       				equ $9f
F_GET_DIR    				equ $a8
F_SET_DIR    				equ $a9
FA_READ      				equ $01
FA_APPEND    				equ $06
FA_OVERWRITE				equ $0E

	MACRO Set14mhz:NEXTREG_nn TURBO_CONTROL_REGISTER,%10:ENDM

	MACRO BREAK:dw $01DD:ENDM

;-------------------------------

			IFDEF testing

			org	$6000
start		di:ld (stackptr),sp:ld sp,$5fff
			BREAK
			ELSE

			org	$2000
start		di:ld (stackptr),sp:ld sp,$3fff
			ld de,filename:ld b,255
			ld a,h:or l:jp z,noname
.bl			ld	a,(hl):cp ":":jr z,.dn:or a:jr z,.dn:cp 13:jr z,.dn:bit 7,a:jr nz,.dn
			ld	(de),a:inc hl:inc de:djnz .bl
.dn			xor a:ld	(de),a
			ENDIF

			nextreg MMU_REGISTER_6,42
			
			call setdrv
			
			ld ix,filename:ld e,$00:ld b,64:call loadspr

finish		ld a,($5b5c):and 7:add a,a:nextreg MMU_REGISTER_6,a
			ld sp,(stackptr):ei:xor a:ret
noname		ld	hl,emptyline:call print_rst16:jr finish
;-------------
print_rst16	ld a,(hl):inc hl:or a:ret z:rst 16:jr print_rst16
;-------------
loadspr		push bc:push de:call fopen:pop de:pop bc:ld a,(handle):or a:ret z
			push bc:ld bc,SPRITE_STATUS_SLOT_SELECT:out (c),e:pop bc
.lp			push bc:push de:ld ix,$c000:ld bc,$100:call fread:pop de:ld a,b:or c:pop bc:jp z,fclose
			push bc:ld hl,$c000:call CopySpriteToVram:pop bc
			inc e:ld a,e:cp 64:jp nc,fclose:djnz .lp:jp fclose
;-------------
CopySpriteToVram
			ld bc,$100
;-------------
TransferDMASprite
			ld (DMAW),hl:ld (DMAW+2),bc
			ld hl,DMA:ld b,DMALen:ld c,$6b:otir
			ret
DMA			db $c3,$c7,$cb,%01111101
DMAW		dw 0,0
			db %01010100, %00000010, %01101000,%00000010,%10101101,$5b,%10000010,$cf,$87
DMALen		equ $-DMA
;--------------------
fileError	ld a,6:out (254),a
			ret
;-------------
setdrv		xor a:rst $08:db M_GETSETDRV
			ld (drive),a:ret
;-------------
fopen		ld b,FA_READ:db $21
fcreate		ld b,FA_OVERWRITE:db 62
drive		db 0
			push ix:pop hl:rst $08:db F_OPEN
			ld (handle),a:jp c, fileError
			ret
;--------------
fread		push ix:pop hl:db 62
handle		db 1
			rst $08:db F_READ
			ret
;--------------
fwrite		push ix:pop hl:ld a,(handle)
			rst $08:db F_WRITE
			ret
;-------------
fclose		ld a,(handle):rst $08:db F_CLOSE
			ret
;-------------
emptyline	db	".TOSPRRAM <filename> to load sprite images to sprite VRAM",13,0

stackptr	dw	0

filename	db	"test.spr"
			dw	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			dw	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			dw	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			dw	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

buf			= $c000

	IFDEF testing
	savesna "tosprram.sna",start
	ELSE
.last
	savebin "TOSPRRAM",start,.last-start
	ENDIF
	
;-------------------------------
