;---------------------------------
;-- BMP2SPR (C) 2022 Jim Bagley --
;---------------------------------
; assemble with SJASMPlus
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
F_FSEEK      equ $9f
F_FGETPOS    equ $a0
F_FSTAT      equ $a1
F_GET_DIR    equ $a8
F_SET_DIR    equ $a9
FA_READ      equ $01
FA_APPEND    equ $06
FA_OVERWRITE equ $0E

IDE_BANK	 equ $01bd
RC_BANKTYPE_ZX	equ 0	; in H
RC_BANKTYPE_MMC	equ 1
RC_BANK_TOTAL	equ 0	; in E ; return total number of 8K banks specified type
RC_BANK_ALLOC	equ 1	; in E ; return alloc next available 8K bank
RC_BANK_RESERVE	equ 2	; in E ; reserve bank specified in E ( 0..total - 1 )
RC_BANK_FREE	equ 3	; in E ; free bank specified in E ( 0..total - 1  )
RC_BANK_AVAILABLE equ 4 ; in E ; return number of currently available 8K banks of specified type
; in E BANK_ID ( 0..total - 1 ) for RC_BANK_RESERVE and RC_BANK_FREE
; on return C = set = success E = BANK_ID for RC_BANK_ALLOC, E = total number of banks for RC_BANK_TOTAL, E = avail num of banks for RC_BANK_AVAILABLE
; on C = clear, A = error type

SPRITE_CONTROL_REGISTER			equ $15		;Enables/disables Sprites and Lores Layer, and chooses priority of sprites and Layer 2.
PALETTE_INDEX_REGISTER			equ $40		;Chooses a ULANext palette number to configure.
PALETTE_VALUE_REGISTER			equ $41		;Used to upload 8-bit colors to the ULANext palette.
PALETTE_FORMAT_REGISTER			equ $42
PALETTE_CONTROL_REGISTER		equ $43		;Enables or disables ULANext interpretation of attribute values and toggles active palette.
PALETTE_VALUE_BIT9_REGISTER		equ $44		;Holds the additional blue color bit for RGB333 color selection.

MMU_REGISTER_0					equ $50		;Set a Spectrum RAM page at position 0x0000 to 0x1FFF
MMU_REGISTER_1					equ $51		;Set a Spectrum RAM page at position 0x2000 to 0x3FFF
MMU_REGISTER_2					equ $52		;Set a Spectrum RAM page at position 0x4000 to 0x5FFF
MMU_REGISTER_3					equ $53		;Set a Spectrum RAM page at position 0x6000 to 0x7FFF
MMU_REGISTER_4					equ $54		;Set a Spectrum RAM page at position 0x8000 to 0x9FFF
MMU_REGISTER_5					equ $55		;Set a Spectrum RAM page at position 0xA000 to 0xBFFF
MMU_REGISTER_6					equ $56		;Set a Spectrum RAM page at position 0xC000 to 0xDFFF
MMU_REGISTER_7					equ $57		;Set a Spectrum RAM page at position 0xE000 to 0xFFFF

CPU_SPEED_REGISTER				equ	$07		;Set to 3 for 28Mhz

GRAPHIC_PRIORITIES_SLU	= %00000000	; sprites over l2 over ula
GRAPHIC_PRIORITIES_LSU	= %00000100
GRAPHIC_PRIORITIES_SUL	= %00001000
GRAPHIC_PRIORITIES_LUS	= %00001100
GRAPHIC_PRIORITIES_USL	= %00010000
GRAPHIC_PRIORITIES_ULS	= %00010100
GRAPHIC_OVER_BORDER	= %00000010
GRAPHIC_SPRITES_VISIBLE	= %00000001
LORES_ENABLE		= %10000000

HEADER_WIDTH        = 18
HEADER_HEIGHT       = 22
HEADER_FLIPPED      = 25

;-------------------------------
;testing
	IFDEF testing
	
	org	$6000
start
	ld hl,testfile:ld de,filename:ld bc,64:ldir
	ld ix,filename
	jp loadbmp

;testfile db "SpyHunterArea01.bmp",0
testfile db "mario.bmp",0
;testfile db "gas.bmp",0
;testfile db "parrots.bmp",0

;-------------------------------
;release
	ELSE
	
	org	$2000
start
	ld a,h:or l:jr nz,.gl	
	ld	hl,emptyline:call print_rst16:xor a:ret
.gl	ld	de,filename:ld b,255
	ld a,(hl):cp 34:jr nz,.bl:ld (.bl+2),a:inc hl
.bl	ld	a,(hl):cp ":":jr z,.dn:or a:jr z,.dn:cp 13:jr z,.dn:bit 7,a:jr nz,.dn
	ld	(de),a:inc hl:inc de:djnz .bl
.dn	xor a:ld	(de),a
	ld	ix,filename
	jp loadbmp

	ENDIF

;-------------------------------

notenoughmem
    call sprint:db "Not enough memory for image",13,0
    ei:jp exit

invalidMinusCommand
    call sprint:db "Illegal minus command",13,0
    ei:jp exit

;-------------------------------

loadbmp
	ld (stackptr),sp
	di
	ld (iyreg),iy
	exx
	ld (hlreg),hl
	exx

	ld a,CPU_SPEED_REGISTER:call nextrd:ld (cpuspeed),a
	nextreg CPU_SPEED_REGISTER,3	;28Mhz

	IFDEF testing
	ELSE
		ld a,MMU_REGISTER_0:call nextrd:ld (bank0),a
		ld a,MMU_REGISTER_1:call nextrd:ld (bank1),a
		ld a,MMU_REGISTER_2:call nextrd:ld (bank2),a
		ld a,MMU_REGISTER_3:call nextrd:ld (bank3),a
		ld a,MMU_REGISTER_4:call nextrd:ld (bank4),a
		ld a,MMU_REGISTER_5:call nextrd:ld (bank5),a
		ld a,MMU_REGISTER_6:call nextrd:ld (bank6),a
		ld a,MMU_REGISTER_7:call nextrd:ld (bank7),a

		ld a,(NumBanksUsedMap):ld c,a:ld a,(NumBanksUsedBlocks):add a,c:ld (NumBanksUsed),a
		push ix:call HowManyAvailable:pop ix:ld c,a:ld a,(NumBanksUsed):cp c:jp nc,notenoughmem
		push ix:call AllocateBanks:pop ix:jp nc,exit
	ENDIF
	
;-------------------------------

   	di:ld sp,mystack

;-------------------------------
; Sorting filename

.checkforminus
	ld a,(ix+0):cp "-":jr nz,.skpmin
	inc ix:ld a,(ix+0):inc ix

;-p = don't add 16 to palette RGB ( half a Next RGB unit )
	cp "p":jr nz,.nmp
	xor a:ld (.a1+1),a:ld (.a2+1),a:ld (.a3+1),a:inc ix:jr .checkforminus
.nmp

;-m8 = 8bit map -m16 = 16bit map ; 8bit standard
	cp "m":jr nz,.nmm
	ld a,(ix+0):cp "8":jr z,.m8
	cp "1":jp nz,invalidMinusCommand:inc ix:ld a,(ix+0):cp "6":jp nz,invalidMinusCommand
.m16 xor a:ld (Map8Bit),a:inc ix:inc ix:jr .checkforminus
.m8	ld a,1:ld (Map8Bit),a:inc ix:inc ix:jr .checkforminus
.nmm

.skpmin
	push ix:pop hl:ld de,filename:ld bc,256:ldir
	ld ix,filename

	push ix:call setdrv:pop ix
    call fopen:ld a,2:jp c,fileError
	ld	ix,header:ld bc,0x36:call fread:ld a,3:jp c,fileError
	ld hl,(header+10):ld bc,-0x36:add hl,bc:ld c,l:ld b,h:ld ix,palette:call fread:ld a,3:jp c,fileError
	ld	hl,palette:ld de,nextpal:ld b,0
.lp	ld	a,(hl):inc hl
.a1	add a,16:jr nc,.nb:ld a,255
.nb	rlca:rlca:push af:and 3:ld c,a
	ld	a,(hl):inc hl
.a2	add a,16:jr nc,.ng:ld a,255
.ng	rra:rra:rra:and 7<<2:or c:ld c,a
	ld	a,(hl):inc hl
.a3	add a,16:jr nc,.nr:ld a,255
.nr	and 7<<5:or c:ld (de),a:inc de:pop af:rlca:and 1:ld (de),a:inc de:inc hl:djnz .lp
	nextreg PALETTE_CONTROL_REGISTER, %10000
	nextreg PALETTE_INDEX_REGISTER, 0
	ld	hl,nextpal:ld b,0
.pl	ld a,(hl):inc hl:nextreg PALETTE_VALUE_BIT9_REGISTER,a
	ld a,(hl):inc hl:nextreg PALETTE_VALUE_BIT9_REGISTER,a
	djnz .pl

	ld a,(header+HEADER_FLIPPED):bit 7,a:jr z,.norm
	ld hl,(header+HEADER_HEIGHT):ld a,h:cpl:ld h,a:ld a,l:cpl:ld l,a:inc hl:ld (header+HEADER_HEIGHT),hl	; invert Y size
.norm
    ld hl,(header+HEADER_WIDTH):call divhl16:ld (MapWidth),hl
    ld hl,(header+HEADER_HEIGHT):call divhl16:ld (MapHeight),hl

;	ld hl,$4000:ld de,$4001:ld bc,$17ff:ld (hl),l:ldir
;	ld hl,$5800:ld de,$5801:ld bc,$2ff:ld (hl),$47:ldir

;----------------------------
; show layer 2
	ld a,2:ld	bc,4667:out (c),a

;----------------------------
; load BMP into tiles

    ld hl,0:ld (mapaddress),hl
	ld a,0:ld (screeny),a
	ld a,0:ld (screenx),a
	ld hl,0:ld (pixely),hl
.yl	ld hl,0:ld (pixelx),hl
    xor a:ld (screenx),a
.xl
    ld a,(screenx):rra:rra:rra:rra:and 7:out (254),a
;----------------------------
; load 16x16 from BMP into temp tile
    call Load16x16

;----------------------------
; find blockID
    call FindBlock

;----------------------------
; put blockID into MAP
    call MapWrite

;----------------------------
; Point to next tile and loop X
	ld hl,(pixelx):add hl,16:ld (pixelx),hl
 	ld a,(screenx):add a,16:ld (screenx),a
    ld de,(header+HEADER_WIDTH):or a:sbc hl,de:jr c,.xl

;----------------------------
; Point to next tile row and loop Y
	ld hl,(pixely):add hl,16:ld (pixely),hl
	ld a,(screeny):add a,16:ld (screeny),a
    cp 192:jr c,.n1:xor a:ld (screeny),a
.n1 ld de,(header+HEADER_HEIGHT):or a:sbc hl,de:jr c,.yl

;----------------------------
; save map file
	ld hl,filename:ld de,mapext:call changeext:ld a,6:jp c,fileError
    ld ix,filename:call fcreate:ld a,2:jp c,fileError
    ld hl,(mapaddress)
	ld a,(Map8Bit):or a:jr z,.m162:srl h:rr l
.m162
	ld (tempw),hl
    ld hl,AllocatedBanksMap:ld b,8
.l1 ld a,(hl):inc hl:nextreg MMU_REGISTER_6,a
    push hl:push bc
    ld de,(tempw):ld a,d:or e:jr z,.mt
    ld ix,$c000:ld bc,$2000:ld a,d:cp $20:jr nc,.fl:ld b,d:ld c,e
.fl push bc:call fwrite:pop bc:ld a,3:jp c,fileError
.mt ld a,(tempw+1):sub $20:ld (tempw+1),a:jr nc,.n3:ld hl,0:ld (tempw),hl
.n3 pop bc:pop hl:djnz .l1
    call fclose

;----------------------------
; save blk file
	ld de,blkext:call swapext
    ld hl,(numBlocks):ld a,h:or l:jp z,.sb
	ld a,0:ld (blksaved),a:ld a,"0":ld (blkbanks),a

	ld hl,(firstextletterpos):inc hl:inc hl:ld (hl),"0":ld ix,filename:call fcreate:ld a,2:jp c,fileError
	xor a:ld (blksaved),a
    ld hl,(numBlocks):ld (tempw),hl
	ld hl,AllocatedBanksBlocks:ld b,56
.l2 ld a,(hl):inc hl:nextreg MMU_REGISTER_6,a
    push hl:push bc
    ld de,(tempw):ld a,d:or e:jr z,.n4
    ld ix,$c000:ld bc,$2000:ld a,d:or a:jr nz,.f2:ld a,e:cp $20:jr nc,.f2:ld b,e:ld c,0
.f2 push bc:call fwrite:pop bc:ld a,3:jp c,fileError
	ld a,(blksaved):add a,b:ld (blksaved),a:cp 64:jr c,.m2

	call fclose
    ld de,(tempw):ld a,d:or a:jr nz,.c1:ld a,e:cp $20:jr z,.m2
.c1
	ld a,(blkbanks):inc a:ld (blkbanks),a:push hl:ld hl,(firstextletterpos):inc hl:inc hl:ld (hl),a:pop hl
    push hl:ld ix,filename:call fcreate:ld a,2:pop hl:jp c,fileError
	xor a:ld (blksaved),a
.m2 ld hl,(tempw):or a:ld de,$20:sbc hl,de:ld (tempw),hl:jr nc,.n4:ld hl,0:ld (tempw),hl
.n4 pop bc:pop hl:djnz .l2

.cb call fclose
.sb

;----------------------------
; save pal file
	ld de,palext:call swapext

    ld ix,filename:call fcreate:ld a,2:jp c,fileError
    ld ix,nextpal:ld bc,$200:push ix:pop hl:call fwrite:ld a,3:jp c,fileError
    call fclose

;----------------------------
; done

    jr  exit

.err ld sp,0:jp fileError

exit
	ld a,0:call cleanup
	IFDEF testing
		ELSE
		call FreeBanks
	ENDIF
	xor a:out (254),a
	ld sp,(stackptr)
    ld iy,(iyreg)
    exx
    ld hl,(hlreg)
    exx

	IFDEF testing
		ld a,-1:nextreg MMU_REGISTER_0,a
		ld a,-1:nextreg MMU_REGISTER_1,a
		ld a,0:nextreg MMU_REGISTER_6,a
		ld a,1:nextreg MMU_REGISTER_7,a
	ELSE
		ld a,(bank0):nextreg MMU_REGISTER_0,a
		ld a,(bank1):nextreg MMU_REGISTER_1,a
;		ld a,(bank2):nextreg MMU_REGISTER_2,a
;		ld a,(bank3):nextreg MMU_REGISTER_3,a
;		ld a,(bank4):nextreg MMU_REGISTER_4,a
;		ld a,(bank5):nextreg MMU_REGISTER_5,a
		ld a,(bank6):nextreg MMU_REGISTER_6,a
		ld a,(bank7):nextreg MMU_REGISTER_7,a
	ENDIF

	ld a,(cpuspeed):nextreg CPU_SPEED_REGISTER,a

	ld a,2:call $1601
	call sprint:db "Blocks used = ",0
	ld hl,(numBlocks):call dec5
	call sprint:db 13, "Map size = ",0
	ld hl,(MapWidth):call dec5
	ld a,",":call prtchr
	ld hl,(MapHeight):call dec5
	ld a,13:call prtchr

	ei
	ret

iyreg   dw  0
hlreg   dw  0
tempw   dw  0

divhl16
    srl h:rr l:srl h:rr l:srl h:rr l:srl h:rr l:ret

;----------------------------
; FindBlock
FindBlock
    ld hl,0
.lp ld de,(numBlocks):ld a,h:cp d:jr nz,.no:ld a,l:cp e:jr z,.ye
.no push hl:call BankInBlock
    ld de,tempBlock:ld b,0
.ll ld a,(de):cp (hl):jr nz,.sk:inc hl:inc de:djnz .ll
;found
    pop hl:ld (blockID),hl:ret
.sk pop hl:inc hl:jr .lp
.ye call BankInBlock
    ex de,hl:ld hl,tempBlock:ld bc,256:ldir
    ld hl,(numBlocks):ld (blockID),hl:inc hl:ld (numBlocks),hl
    ret

;----------------------------
; Bank in Block
BankInBlock
    push de:push bc
    ld a,l:push af
    srl h:rr l:srl h:rr l:srl h:rr l:srl h:rr l:srl h:rr l						; divide by 32 ( as 32*256 = 8K )
    ld de,AllocatedBanksBlocks:add hl,de,a:ld a,(hl):nextreg MMU_REGISTER_6,a	; set bank
    pop af:and 31:or $c0:ld h,a:ld l,0											; get location
.ex pop bc:pop de:ret

;----------------------------
; done

Load16x16
; load image from 16x16 part of file
	ld a,16
.al	push af

	call GetXY
	call Read16x1:ld a,3:jp c,fileError

    pop af:push af:ld c,a:ld a,16:sub c:add a,a:add a,a:add a,a:add a,a:ld de,tempBlock:add de,a:ld hl,sixteen_bytes:ld bc,16:ldir

    ld a,(pixelx+1):or a:jr nz,.skip
    ld hl,(pixely):ld a,h:or a:jr nz,.skip
    ld a,l:cp 192:jr nc,.skip
	ld a,(screeny):swapnib:rra:and 7:add a,LAYER_2_PAGE*2:nextreg MMU_REGISTER_6,a
	ld hl,sixteen_bytes
	ld a,(screeny):and 31:or $c0:ld d,a
	ld a,(screenx):ld e,a
	ld bc,16:ldir
.skip
	ld hl,(pixely):inc hl:ld (pixely),hl
	ld a,(screeny):inc a:ld (screeny),a
	pop af:dec a:jr nz,.al
	ld a,(screeny):sub 16:ld (screeny),a
	ld hl,(pixely):ld de,0-16:add hl,de:ld (pixely),hl
	ret
.popret
    pop af:ret

;mapaddress is the address to be written to, ( then pages from AllocatedBanksMap )
;contents of blockID to be written.
MapWrite
    push hl:push de
    ld hl,(mapaddress)
	ld a,(Map8Bit):or a:jr z,.m16:srl h:rr l
.m16
	ld de,AllocatedBanksMap:ld a,h:srl a:srl a:srl a:srl a:srl a:and 7:add de,a
    ld a,(de):nextreg MMU_REGISTER_6,a
    ld a,h:and 31:or $c0:ld h,a
    ld de,(blockID):ld (hl),e:inc hl:ld (hl),d
    ld hl,(mapaddress):inc hl:inc hl:ld (mapaddress),hl
    pop de:pop hl:ret

GetXY
	ld hl,$436:ld (seekLow),hl:ld hl,0:ld (seekHigh),hl

	ld a,(screeny):dec a:and $e0:rlca:rlca:rlca:add a,LAYER_2_PAGE*2:nextreg MMU_REGISTER_6,a   ;sort screen bank.

	ld de,(pixely)
	ld a,(header+HEADER_FLIPPED):bit 7,a:jr nz,.nm
	ld hl,(header+HEADER_HEIGHT):dec hl:or a:sbc hl,de:ex de,hl
.nm

	ld bc,(header+HEADER_WIDTH):call mult_de_bc
	ld (seekLow),hl:ld (seekHigh),de
	ld hl,$436:call addSeek
	ld hl,(pixelx) ;:jp addSeek fall into addSeek

;add HL to seek32bit
addSeek
	push hl:push de:ld de,(seekLow):add hl,de:ld (seekLow),hl:ld hl,(seekHigh):ld de,0:adc hl,de:ld (seekHigh),hl:pop de:pop hl:ret

mult_de_bc
	ld hl,0:sla e:rl d:jr nc,.s1:ld h,b:ld l,c
.s1	ld a,15
.lp	add	hl,hl:rl e:rl d:jr nc,.s2:add hl,bc:jr nc,.s2:inc de
.s2	dec a:jr nz,.lp:ret

;BCDE = byte address of image line in file
Read16x1
	ld bc,(seekHigh):ld de,(seekLow):call fseek:ld a,3:jp c,fileError
	ld hl,sixteen_bytes:push hl:pop ix:ld bc,16:call fread:ld a,3:jp c,fileError
	ret

display16
	ld hl,sixteen_bytes:ld bc,16:ldir:ret

bank0		db  0
bank1		db  0
bank2		db  0
bank3		db  0
bank4		db  0
bank5		db  0
bank6		db  0
bank7		db  0
cpuspeed	db	0	

sixteen_bytes
	db	0,0,0,0,0,0,0,0 ,0,0,0,0,0,0,0,0

seekHigh	dw 0
seekLow		dw $436

pixelx	dw	0
pixely	dw	0
screenx	dw	0
screeny	dw	0
mapaddress  dw  0
blockID dw  0
numBlocks   dw  0

cleanup
	ld	bc,4667:out (c),a
	call fclose
;	nextreg SPRITE_CONTROL_REGISTER, GRAPHIC_PRIORITIES_SUL + GRAPHIC_SPRITES_VISIBLE		; set image priorities
	; set transparency on ULA
	nextreg PALETTE_CONTROL_REGISTER, 0
	nextreg PALETTE_CONTROL_REGISTER, 0
	nextreg PALETTE_INDEX_REGISTER, $18
	nextreg PALETTE_VALUE_REGISTER, $e3
	ret

;--------------------
changeext
.lp	ld a,(hl):inc hl:or a:jr nz,.lp
	dec hl:dec hl:dec hl:dec hl:dec hl:ld a,(hl):cp ".":jr z,.got
.er	scf	; carry = failed
	ret
.got inc hl
	ld (firstextletterpos),hl
;.gl ld a,(de):ld (hl),a:inc hl:inc de:or a:jr nz,.gl:ret

swapext
	push hl:ld hl,(firstextletterpos)
.lp	ld a,(de):ld (hl),a:inc hl:inc de:or a:jr nz,.lp:pop hl:ret

firstextletterpos	dw	0
palext	db "pal",0
blkext	db "blk",0
mapext	db "map",0
blksaved	db	0
blkbanks	db	0
;--------------------
fileError
	out (254),a
	xor a:call cleanup
	ld sp,(stackptr)
    ei
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
FSEEK_SET = 0
FSEEK_FWD = 1
FSEEK_BWD = 2
fseek
	ld hl,FSEEK_SET:push hl:pop ix:ld a,(handle):rst $08:db F_FSEEK
	ret
;--------------
fstatBuf  
fstatStar   db  "*"
fstat81     db  $81
fstatattr   db  0
ftimestamp  dw  0
fdatestamp  dw  0
ffilesize   dw  0,0

fstat
    ld  hl,fstatBuf:push hl:pop ix:ld a,(handle):rst $08:db F_FSTAT
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
;--------------
getfilepos
	ld a,(handle)
	rst $08:db F_FGETPOS
	ret
;-------------
fclose
	ld a,(handle):or a:ret z:rst $08:db F_CLOSE
	xor a:ld (handle),a
	ret
;-------------
prthex16
	ld a,h:call prthex8:ld a,l
prthex8
	push af:swapnib:call prthex4:pop af
prthex4
	and 15:push hl:ld hl,hextab:add hl,a:ld a,(hl):pop hl
prtchr
	push hl:push de:push bc:push af:exx:push hl:push de:push bc:exx:push ix:push iy
	rst $10
	pop iy:pop ix:exx:pop bc:pop de:pop hl:exx:pop af:pop bc:pop de:pop hl
	ret
sprint pop hl:call print:jp (hl)
print ld a,(hl):inc hl:or a:ret z:call prtchr:jr print

dec5	ld	bc,10000:call dec0
dec4	ld	bc,1000:call dec0
dec3	ld	bc,100:call dec0
dec2	ld	bc,10:call dec0
dec1	ld	bc,1
dec0	ld	a,"0"-1
.lp		inc a:or a:sbc hl,bc:jr nc,.lp
		add hl,bc:jp prtchr
	
hextab	db "0123456789ABCDEF"
;-------------
showregs
;	push af
;	push hl:push de:push bc:push af:exx:push hl:push de:push bc:exx:push ix:push iy
;	ld a,2:call $1601
;	pop iy:pop ix:exx:pop bc:pop de:pop hl:exx:pop af:pop bc:pop de:pop hl
;	
;	call prthex8:ld a," ":call prtchr
;	ld a,b:call prthex8:ld a,c:call prthex8:ld a," ":call prtchr
;	ld a,d:call prthex8:ld a,e:call prthex8:ld a," ":call prtchr
;	ld a,h:call prthex8:ld a,l:call prthex8:ld a," ":call prtchr
;	exx:ld a,b:exx:call prthex8:exx:ld a,c:exx:call prthex8:ld a," ":call prtchr
;	exx:ld a,d:exx:call prthex8:exx:ld a,e:exx:call prthex8:ld a," ":call prtchr
;	exx:ld a,h:exx:call prthex8:exx:ld a,l:exx:call prthex8
;	ld a,13:call prtchr
;	pop af
	ret
;-------------
NEXTOS_RAM	equ	$0000
MMC_RAM		equ $0100

M_P3DOS		equ $94

NEXTOS_BANK_REASON_TOTAL		=	0
NEXTOS_BANK_REASON_ALLOCATE		=	1
NEXTOS_BANK_REASON_RESERVE		=	2
NEXTOS_BANK_REASON_FREE			=	3
NEXTOS_BANK_REASON_AVAILABLE	=	4

NumBanksUsed		db	0 ; 8 + 48
NumBanksUsedMap		db	8
NumBanksUsedBlocks	db	48
AllocatedBank		db	0

AllocatedBanksMap
				db	 32, 33, 34, 35, 36, 37, 38, 39 ;map 64K
AllocatedBanksBlocks
				db	 40, 41, 42, 43, 44, 45, 46, 47 ;blocks 384K
				db	 48, 49, 50, 51, 52, 53, 54, 55
				db	 56, 57, 58, 59, 60, 61, 62, 63
				db	 64, 65, 66, 67, 68, 69, 70, 71
				db	 72, 73, 74, 75, 76, 77, 78, 79
				db	 80, 81, 82, 83, 84, 85, 86, 87
                                           

MapWidth        dw  0
MapHeight       dw  0
Map8Bit			db	1	;1 = 8bit, 0 = 16bit

AllocateBanks
	ld hl,AllocatedBanksMap:ld a,(NumBanksUsedMap):ld b,a:call .lp:ret nc
	ld hl,AllocatedBanksBlocks:ld a,(NumBanksUsedBlocks):ld b,a
.lp	call AllocateBank:ret nc:ld (hl),a:inc hl:djnz .lp
    scf
	ret

FreeBanks
	ld hl,AllocatedBanksMap:ld a,(NumBanksUsedMap):ld b,a:call .lp
	ld hl,AllocatedBanksBlocks:ld a,(NumBanksUsedBlocks):ld b,a
.lp	ld a,(hl):inc hl:push hl:push bc:or a:call nz,FreeBank:pop bc:pop hl:djnz .lp
	ret

; H=banktype (ZX=0, 1=MMC); L=reason (1=allocate)*
AllocateBank
	push hl:push de:push bc:push ix:push iy:exx:push hl:push de:push bc:ld hl,NEXTOS_BANK_REASON_ALLOCATE:exx	;If you want to allocate a bank, you can change L to $01 (allocate)
	ld c,7:ld de,IDE_BANK:rst $8:defb M_P3DOS
	ld a,e:ld (AllocatedBank),a
	exx:pop bc:pop de:pop hl:pop iy:pop ix:exx:pop bc:pop de:pop hl:ret
ReserveBank
	push hl:push de:push bc:push ix:push iy:exx:push hl:push de:push bc:ld hl,NEXTOS_BANK_REASON_RESERVE:ld e,a:exx	;If you want a specific bank ID, you can change L to $02 (reserve) and provide the bank number you want in E
	ld c,7:ld de,IDE_BANK:rst $8:defb M_P3DOS
	ld a,e:ld (AllocatedBank),a
	exx:pop bc:pop de:pop hl:pop iy:pop ix:exx:pop bc:pop de:pop hl:ret
FreeBank
	push hl:push de:push bc:push ix:push iy:exx:push hl:push de:push bc:ld hl,NEXTOS_BANK_REASON_FREE:ld e,a:exx	;If you want to free bank ID, you can change L to $03 (free) and provide the bank number you want in E
	ld c,7:ld de,IDE_BANK:rst $8:defb M_P3DOS
	exx:pop bc:pop de:pop hl:pop iy:pop ix:exx:pop bc:pop de:pop hl:ret
HowManyAvailable
	push hl:push de:push bc:push ix:push iy:exx:push hl:push de:push bc:ld hl,NEXTOS_BANK_REASON_AVAILABLE:exx
	ld c,7:ld de,IDE_BANK:rst $8:defb M_P3DOS:ld a,e
	exx:pop bc:pop de:pop hl:pop iy:pop ix:exx:pop bc:pop de:pop hl:ret
HowManyTotal
	push hl:push de:push bc:push ix:push iy:exx:push hl:push de:push bc:ld hl,NEXTOS_BANK_REASON_TOTAL:exx
	ld c,7:ld de,IDE_BANK:rst $8:defb M_P3DOS:ld a,e
	exx:pop bc:pop de:pop hl:pop iy:pop ix:exx:pop bc:pop de:pop hl:ret

mallocerr
	ld a,2:out (254),a
	di:halt
	scf
	ret

nextrd
	push bc:ld bc,$243b:out (c),a:inc b:in a,(c):pop bc:ret

;-------------

stackptr dw	0

header	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db	0,0,0,0,0,0

print_rst16	ld a,(hl):inc hl:or a:ret z:rst 16:jr print_rst16

tempBlock
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
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

filename	db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
			db		0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
mystack
emptyline	db		".bmp2spr <filename> to convert a BMP to sprites.",13,"V1.0",13,0

palette		db	0

	IFDEF testing
		savesna "bmp2spr.sna",start
	ELSE
last	savebin "BMP2SPR",start,last-start
	ENDIF

;-------------------------------
