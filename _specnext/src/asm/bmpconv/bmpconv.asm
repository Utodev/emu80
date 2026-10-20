;-------------------------------
	device zxspectrum48
;-------------------------------

;	DEFINE testing

LAYER_2_PAGE	equ	9

M_GETSETDRV		equ	$89
F_OPEN			equ	$9a
F_CLOSE			equ	$9b
F_READ			equ	$9d
F_WRITE			equ	$9e
F_SEEK			equ	$9f
F_GET_DIR		equ	$a8
F_SET_DIR		equ	$a9
FA_READ			equ	$01
FA_APPEND		equ	$06
FA_OVERWRITE	equ	$0E

SPRITE_CONTROL_REGISTER			equ $15		;Enables/disables Sprites and Lores Layer, and chooses priority of sprites and Layer 2.
PALETTE_INDEX_REGISTER			equ $40		;Chooses a ULANext palette number to configure.
PALETTE_VALUE_REGISTER			equ $41		;Used to upload 8-bit colors to the ULANext palette.
PALETTE_FORMAT_REGISTER			equ $42
PALETTE_CONTROL_REGISTER		equ $43		;Enables or disables ULANext interpretation of attribute values and toggles active palette.
PALETTE_VALUE_BIT9_REGISTER		equ $44		;Holds the additional blue color bit for RGB333 color selection.
MMU_REGISTER_6					equ $56		;Set a Spectrum RAM page at position 0xC000 to 0xDFFF
MMU_REGISTER_7					equ $57		;Set a Spectrum RAM page at position 0xE000 to 0xFFFF

GRAPHIC_PRIORITIES_SLU	= %00000000	; sprites over l2 over ula
GRAPHIC_PRIORITIES_LSU	= %00000100
GRAPHIC_PRIORITIES_SUL	= %00001000
GRAPHIC_PRIORITIES_LUS	= %00001100
GRAPHIC_PRIORITIES_USL	= %00010000
GRAPHIC_PRIORITIES_ULS	= %00010100
GRAPHIC_OVER_BORDER	= %00000010
GRAPHIC_SPRITES_VISIBLE	= %00000001
LORES_ENABLE		= %10000000

	MACRO ADD_HL_nnnn data
		dw $34ED
		dw data
	ENDM

	MACRO ADD_HL_A
		dw $31ED
	ENDM

	MACRO BREAK
		dw $01DD
	ENDM

	MACRO MUL_DE
		dw $30ED
	ENDM

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
	jp convbmp
	
	ELSE
	
	org	$2000
start
	ld a,h:or l:jr nz,.gl
	ld hl,emptyline:call print_rst16:jr finish
.gl	ld de,lineName:ld b,255
.bl	ld a,(hl):cp ":":jr z,.dn:or a:jr z,.dn:cp 13:jr z,.dn:bit 7,a:jr nz,.dn
	ld (de),a:inc hl:inc de:djnz .bl
.dn	xor a:ld	(de),a
	jp convbmp
finish		xor a:ret
prt_rst16
	ld	a,(hl):or a:ret z:inc hl:rst 16:jr prt_rst16
	ENDIF

;-------------------------------

stackptr	dw	0
numTiles	dw	0
curTile		dw	0

minusT		db	0	; add to tileset -T tileset.nxb
use8x8s		db	0	; use 8x8s 1=true 0=16x16
saveBitmap	db	0	; 0=save map and tiles, 1=save bitmap
saveBytemap	db	0	; 0=save map as words, 1=save map as bytes
dontMatch	db	0	; 0=remove duplicate, 1=each tile is grabbed even if it repeats.

MAPSTARTBANK	db	12*2
BMPSTARTBANK	db	16*2
TILESTARTBANK	db	32*2

;-------------------------------

IDE_BANK	equ $01bd

NEXTOS_RAM	equ	$0000
MMC_RAM		equ $0100

NEXTOS_BANK_REASON_TOTAL		=	0
NEXTOS_BANK_REASON_ALLOCATE		=	1
NEXTOS_BANK_REASON_RESERVE		=	2
NEXTOS_BANK_REASON_FREE			=	3
NEXTOS_BANK_REASON_AVAILABLE	=	4

; H=banktype (ZX=0, 1=MMC); L=reason (1=allocate)
AllocateBank
	ld a,e:exx:ld hl,NEXTOS_BANK_REASON_ALLOCATE:exx	;If you want a specific bank ID, you can change L to $02 (reserve) and provide the bank number you want in E
	ld c,7:ld de,IDE_BANK:rst $8:defb $94				; M_P3DOS
	ld a,e:ret											;If successful (carry SET), returns 8K bank id in A
FreeBank
	ld e,a:exx:ld hl,NEXTOS_BANK_REASON_FREE:exx		;If you want a specific bank ID, you can change L to $02 (reserve) and provide the bank number you want in E
	ld c,7:ld de,IDE_BANK:rst $8:defb $94				; M_P3DOS
	ret
HowManyAvailable
	exx:ld hl,NEXTOS_BANK_REASON_AVAILABLE:exx			;If you want a specific bank ID, you can change L to $02 (reserve) and provide the bank number you want in E
	ld c,7:ld de,IDE_BANK:rst $8:defb $94				; M_P3DOS
	ret
HowManyTotal
	exx:ld hl,NEXTOS_BANK_REASON_TOTAL:exx				;If you want a specific bank ID, you can change L to $02 (reserve) and provide the bank number you want in E
	ld c,7:ld de,IDE_BANK:rst $8:defb $94				; M_P3DOS
	ret

;-------------------------------

skipspace
	ld a,(ix+0):cp " ":ret nz:inc ix:jr skipspace

getstring
	ld a,(ix+0):cp 34:ld c,32:jr nz,.l1:inc ix:ld c,34
.l1	ld a,(ix+0):ld (de),a:or a:ret z:cp 13:jr z,.end:cp c:jr z,.end
.ne	inc ix:inc de:cp c:jr nz,.l1:dec de:xor a:ld (de),a:ret
.end xor a:ld (de),a:ret


convbmp
	NEXTREG_nn 7,%10
	ld (stackptr),sp
	ld sp,mystack

	ld hl,lineName:ld de,filename:ld bc,256:ldir
	ld ix,lineName
.getinfo
	call skipspace
	ld a,(ix+0):or a:jr z,.gotinfo
	ld a,(ix+0):cp "-":jr nz,.noMinus
	inc ix:ld a,(ix+0)
	cp	"i":jr nz,.noMinusI							;-i = save bitmap instead of tiles and map
	inc ix:ld a,1:ld (saveBitmap),a:jr .getinfo
.noMinusI
	cp	"2":jr nz,.noMinus2							;-2 = use 2MB version ie change max buffers
	inc ix:ld a,64*2:ld (TILESTARTBANK),a:jr .getinfo
.noMinus2
	cp	"r":jr nz,.noMinusR							;-r = don't remove repeats ( can be used to grab sprite sets from 256x64 keeping ordering )
	inc ix:ld a,1:ld (dontMatch),a:jr .getinfo
.noMinusR
	cp	"b":jr nz,.noMinusB							;-b = save map as bytes
	inc ix:ld a,1:ld (saveBytemap),a:jr .getinfo
.noMinusB
	cp	"8":jr nz,.noMinus8							;-8 = use 8x8 tiles instead of 16x16
	inc ix:ld a,1:ld (use8x8s),a:jr .getinfo
.noMinus8
	cp	"t":jr nz,.noMinusT							;-t = load in some tiles ( 8x8s or 16x16s and use these as the base predefined set of tiles eg to add new map to an existing set )
	inc ix:ld a,1:ld (minusT),a:ld	de,tilename:call getstring:jr .getinfo
.noMinusT
	jr .getinfo
.noMinus
	ld de,filename:call getstring

.gotinfo
	call setdrv
	ld ix,tilename:ld a,(ix+0):or a:jr z,.skiptileload
	call fopen:jp c,filenotfound
	ld hl,0
.loadtileloop
	ld (curTile),hl:push hl:call bankInTile
	push hl:pop ix:ld bc,64:call fread:pop hl:jr c,.done
	inc hl:jr .loadtileloop
.done
	ld a,(use8x8s):or a:jr z,.uu:srl h:rr l:srl h:rr l
.uu	ld (numTiles),hl
	call fclose

.skiptileload
	ld ix,filename:call fopen:jp c,filenotfound
	ld	ix,header:ld bc,0x36:call fread:ld a,1:jp c,fileError

	ld a,(header+28):cp 8:jr z,.is8bit:ld hl,emptyline:jp print_rst16
.is8bit
	ld a,(header+25):bit 7,a:jr z,.norm
	ld hl,(header+22):ld a,h:cpl:ld h,a:ld a,l:cpl:ld l,a:inc hl:ld (header+22),hl	; invert Y
.norm
	ld hl,(header+18):ld (scrWidth),hl:srl h:rr l:srl h:rr l:srl h:rr l:ld a,(use8x8s):or a:jr nz,.w1:srl h:rr l
.w1	ld (mapWidth),hl
	ld hl,(header+22):ld (scrHeight),hl:srl h:rr l:srl h:rr l:srl h:rr l:ld a,(use8x8s):or a:jr nz,.h1:srl h:rr l
.h1	ld (mapHeight),hl
	ld	hl,(header+10):ld bc,-0x36:add hl,bc:ld c,l:ld b,h:ld ix,palette:call fread:ld a,2:jp c,fileError
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

	ld hl,(scrHeight):dec hl
	ld a,(header+25):bit 7,a:jr z,.loadscrlp
	ld hl,0
.loadscrlp
	push hl:call bankInLine:push hl:pop ix:ld bc,(scrWidth):call fread:pop hl:ld a,3:jp c,fileError
	ld a,(header+25):bit 7,a:jr z,.n1
.i1	inc hl:ld a,(scrHeight):cp l:jr nz,.loadscrlp:ld a,(scrHeight+1):cp h:jr nz,.loadscrlp:jr .i2
.n1	dec hl:ld a,h:cp 255:jr nz,.loadscrlp:ld a,l:cp 255:jr nz,.loadscrlp
.i2	call fclose

	ld bc,4667:ld a,2:out (c),a

	ld bc,(mapHeight)
	ld	hl,0
	ld (mapY),hl
.yy	ld (tmpY),hl
	push bc
	ld bc,(mapWidth)
	ld hl,0
	ld (mapX),hl
.xx	ld (tmpX),hl
	push bc
	call getTileAtXY
	call getTileNum
	call putTileInMap
	call putTileAtXY
	ld hl,(mapX):inc hl:ld (mapX),hl
	ld de,16:ld a,(use8x8s):or a:jr z,.n8:ld de,8
.n8	ld hl,(tmpX):add hl,de:pop bc:dec bc:ld a,b:or c:jr nz,.xx
	ld hl,(mapY):inc hl:ld (mapY),hl
	ld hl,(tmpY):add hl,de:pop bc:dec bc:ld a,b:or c:jr nz,.yy
	
;.st jp .st
	
	ld de,palext:call setfilename:call setdrv:ld ix,filename:call fcreate
	ld ix,nextpal:ld bc,512:call fwrite
	call fclose

	ld a,(saveBitmap):or a:jr nz,.sb
	ld de,mapext:call setfilename:call setdrv:ld ix,filename:call fcreate
	ld hl,0
.y1	ld (mapY),hl:call getLineFromMap
	ld ix,mapBuffer:ld bc,(mapWidth):ld a,(saveBytemap):or a:jr nz,.nd:sla B:rl c
.nd	call fwrite
	ld hl,(mapY):inc hl:ld de,(mapHeight):ld a,h:cp d:jr nz,.y1:ld a,l:cp e:jr nz,.y1
	call fclose

	ld de,tileext:call setfilename:call setdrv:ld ix,filename:call fcreate
	ld hl,0
.y2	ld (curTile),hl:call bankInTile:push hl:pop ix:ld bc,256:call fwrite
	ld hl,(curTile):inc hl:ld de,(numTiles):ld a,h:cp d:jr nz,.y2:ld a,l:cp e:jr nz,.y2
	call fclose
	jr .nobitmap
.sb	
	ld de,imgext:call setfilename:call setdrv:ld ix,filename:call fcreate
	ld hl,0
.l2	push hl:call bankInLine:push hl:pop ix:ld bc,(scrWidth):call fwrite:pop hl
	inc hl:ld de,(scrHeight):ld a,d:cp h:jr nz,.l2:ld a,e:cp l:jr nz,.l2
	call fclose
.nobitmap

backtoCMD
	call fclose
	ld a,($5b5c):and 7:add a,a:NEXTREG_A MMU_REGISTER_6:inc a:NEXTREG_A MMU_REGISTER_7
	ld	bc,4667:xor a:out (c),a
	ld a, GRAPHIC_PRIORITIES_SUL + GRAPHIC_SPRITES_VISIBLE:SetSpriteControlRegister		; set image priorities
	; set transparency on ULA
	NEXTREG_nn PALETTE_CONTROL_REGISTER, 0
	NEXTREG_nn PALETTE_CONTROL_REGISTER, 0
	NEXTREG_nn PALETTE_INDEX_REGISTER, 	$18
	NEXTREG_nn PALETTE_VALUE_REGISTER, 	$e3
	ld hl,$5800:ld de,$5801:ld bc,$2ff:ld (hl),$47:ldir
	xor a:out (254),a
	ld sp,(stackptr)
	ret

MULHLBC
	ld e,l:ld d,c:MUL_DE:ld (result),de
	ld e,h:ld d,b:MUL_DE:ld (result+2),de
	ld e,l:ld d,b:MUL_DE:push hl:ld hl,(result+1):add hl,de:ld (result+1),hl:pop hl:ld a,(result+3):adc a,0:ld (result+3),a
	ld e,c:ld d,h:MUL_DE:push hl:ld hl,(result+1):add hl,de:ld (result+1),hl:pop hl:ld a,(result+3):adc a,0:ld (result+3),a
	ld hl,(result+2):ld bc,(result)
	ret
result dw	0,0

bankInScr
	ld a,l:rlca:rlca:rlca:and 7:add a,LAYER_2_PAGE*2:NEXTREG_A MMU_REGISTER_6:inc a:NEXTREG_A MMU_REGISTER_7
	ld a,l:and 31:or $c0:ld h,a:ld l,0
	ret

putTileInMap
	push hl:call bankInMap:pop de:ld (hl),e:inc hl:ld (hl),d:ex de,hl
	ret
	
bankInLine
	ld bc,(scrWidth):call MULHLBC
	push bc:ld a,b:add a,a:adc hl,hl:add a,a:adc hl,hl:add a,a:adc hl,hl
	ld a,(BMPSTARTBANK):add a,l:NEXTREG_A MMU_REGISTER_6:inc a:NEXTREG_A MMU_REGISTER_7
	pop hl:ld a,h:and 31:or $c0:ld h,a
	ret

getLineFromMap
	ld (mapY),hl:ld hl,0:ld (mapX),hl:call bankInMap
	ld de,mapBuffer:ld bc,(mapWidth)
.lp	ld a,(hl):inc hl:ld (de),a:inc de:ld a,(saveBytemap):or a:jr nz,.b8:ld a,(hl):ld (de),a:inc de
.b8	inc hl:dec bc:ld a,b:or c:jr nz,.lp
	ret

bankInTile
	ld a,(use8x8s):or a:jr z,.use16
.use8
	push hl
	sla l:rl h	;/128 = 8K
	ld a,(TILESTARTBANK):add a,h:NEXTREG_A MMU_REGISTER_6:inc a:NEXTREG_A MMU_REGISTER_7
	pop hl:ld a,l:rra:rra:and 31:or $c0:ld h,a:ld a,l:rrca:rrca:and $c0:ld l,a
	ret
.use16
	push hl
	srl h:rr l:srl h:rr l:srl h:rr l:srl h:rr l:srl h:rr l	;/32 ( 8K
	ld a,(TILESTARTBANK):add a,l:NEXTREG_A MMU_REGISTER_6:inc a:NEXTREG_A MMU_REGISTER_7
	pop hl:ld a,l:and 31:or $c0:ld h,a:ld l,0
	ret

bankInMap
	ld hl,(mapY):ld bc,(mapWidth):SLA C:RL B:call MULHLBC
	ld e,c:ld d,b:ld bc,(mapX):SLA C:RL B:ex de,hl:add hl,bc:ex de,hl:ld bc,0:adc hl,bc
	push de:ld a,d:add a,a:adc hl,hl:add a,a:adc hl,hl:add a,a:adc hl,hl
	ld a,(MAPSTARTBANK):add a,l:NEXTREG_A MMU_REGISTER_6:inc a:NEXTREG_A MMU_REGISTER_7
	pop hl:ld a,h:and 31:or $c0:ld h,a
	ret

getTileAtXY
	ld de,tileBuffer
	ld a,(use8x8s):or a:jr nz,.u8
.u16
	ld b,16
.lp	push bc
	ld a,16:sub b
	push de:ld hl,(tmpY):ADD_HL_A:call bankInLine:pop de
	ld bc,(tmpX):add hl,bc:ld bc,16:ldir
	pop bc:djnz .lp
	ret
.u8	ld b,8
.l8	push bc
	ld a,8:sub b
	push de:ld hl,(tmpY):ADD_HL_A:call bankInLine:pop de
	ld bc,(tmpX):add hl,bc:ld bc,8:ldir
	pop bc:djnz .l8
	ret

putTileAtXY
	ld a,(use8x8s):or a:jr nz,.u8
.u16
	ld a,(tmpX+1):or a:ret nz
	ld a,(tmpY+1):or a:ret nz:ld a,(tmpY):cp 192:ret nc
	call bankInTile:ld de,tileBuffer:ld bc,256:ldir
	ld hl,tileBuffer:ld b,16
.lp	push bc:push hl:ld a,16:sub b:ld hl,(tmpY):ADD_HL_A:call bankInScr:ld bc,(tmpX):add hl,bc:ex de,hl:pop hl:ld bc,16:ldir
	pop bc:djnz .lp
	ret
	
.u8	ld a,(tmpX+1):or a:ret nz
	ld a,(tmpY+1):or a:ret nz:ld a,(tmpY):cp 192:ret nc
	call bankInTile:ld de,tileBuffer:ld bc,64:ldir
	ld hl,tileBuffer:ld b,8
.l8	push bc:push hl:ld a,8:sub b:ld hl,(tmpY):ADD_HL_A:call bankInScr:ld bc,(tmpX):add hl,bc:ex de,hl:pop hl:ld bc,8:ldir
	pop bc:djnz .l8
	ret

getTileNum
	ld hl,0
.lp	ld de,(numTiles)
	ld a,(dontMatch):or a:jr z,.dd:ld h,d:ld l,e:jr .dm
.dd	ld a,h:cp d:jr nz,.nN
	ld a,l:cp e:jr nz,.nN
.dm	push hl:inc de:ld (numTiles),de
	call bankInTile:ex de,hl:ld hl,tileBuffer:ld bc,256:ld a,(use8x8s):or a:jr z,.us:ld bc,64
.us	ldir:pop hl:ret
.nN	push hl
	call bankInTile:ld de,tileBuffer:ld b,0:ld a,(use8x8s):or a:jr z,.tl:ld b,64
.tl	ld a,(de):cp (hl):jr nz,.sk
	inc hl:inc de:djnz .tl:pop hl:ret
.sk	pop hl:inc hl:jr .lp

;--------------------
palext	db	"nxp"
imgext	db	"nxi"
tileext	db	"nxt"
mapext	db	"nxm"
scrWidth	dw	0
scrHeight	dw	0
mapWidth	dw	0
mapHeight	dw	0
mapX		dw	0
mapY		dw	0
tmpX		dw	0
tmpY		dw	0

setfilename
	ld hl,filename
.l1	ld a,(hl):or a:jr z,.l2:inc hl:jr .l1
.l2	dec hl:dec hl:dec hl:ld a,(de):ld (hl),a:inc hl:inc de:ld a,(de):ld (hl),a:inc hl:inc de:ld a,(de):ld (hl),a:ret

;--------------------
fileError
	out (254),a
returnBack
	call fclose
	ld	bc,4667:xor a:out (c),a
	ld a,($5b5c):and 7:add a,a:NEXTREG_A MMU_REGISTER_6:inc a:NEXTREG_A MMU_REGISTER_7
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
	ld (handle),a:ret
;--------------
fread
	push ix:pop hl:db 62
handle	db 1
	rst $08:db F_READ
	ret
;--------------
fwrite
	push ix:pop hl:ld a,(handle):rst $08:db F_WRITE
	ret
;-------------
fclose
	ld a,(handle):rst $08:db F_CLOSE
	ret

;-------------

filenotfound
	ld a,34:rst 16:ld hl,filename:call print_rst16:ld a,34:rst 16
	ld hl,fnftext:call print_rst16
	jp returnBack
fnftext
	db " file not found.",13,0

header		db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db	0,0,0,0,0,0

print_rst16	ld a,(hl):inc hl:or a:ret z:rst 16:jr print_rst16

tilename	db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

filename	db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

nextpal		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

tileBuffer	db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

lineName	db		"bg00_2.bmp" ;if testing put your command line in here without the bmpconv eg "-8 -b test.bmp"
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

emptyline	db		".bmpconv <-options> <filename>",13
			db		"to convert image to Next format.",13
			db		"tiles or bitmap.",13
			db		"options :-",13
			db		"-i = save image, default tilemap",13
			db		"-b = map is saved in bytes",13
			db		"-8 = block size 8x8, norm 16x16",13
			db		"-t = include tileset base",13
			db		"-2 = save 2MB layout",13
			db		"-r = don't remove repeat tiles",13
			db		0
not8bitline	db		"file is not an 8bit bmp file.",13,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
mystack

palette		db	0

mapBuffer	equ	palette+$400

	IFDEF testing

	savesna "bmpconv.sna",start

	ELSE

last
	savebin "BMPCONV",start,last-start

	ENDIF

;-------------------------------
