; xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
	device zxspectrum48
; xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

SPRITE_INFO_PORT = $5b

; ----- Colour palette (ULA)
BLACK 			equ 0
BLUE 			equ 1
RED 			equ 2
MAGENTA 		equ 3
GREEN 			equ 4
CYAN 			equ 5
YELLOW	 		equ 6
WHITE	 		equ 7
P_BLACK			equ 0
P_BLUE			equ 1<<3
P_RED			equ 2<<3
P_MAGENTA		equ 3<<3
P_GREEN			equ 4<<3
P_CYAN			equ 5<<3
P_YELLOW		equ 6<<3
P_WHITE			equ 7<<3
; ----- Attribs
A_FLASH			equ 128
A_BRIGHT 		equ 64
;----------------------------------------------
BIT_UP			equ 4	; 16
BIT_DOWN		equ 5	; 32
BIT_LEFT		equ 6	; 64
BIT_RIGHT		equ 7	; 128

DIR_NONE		equ %00000000
DIR_UP			equ %00010000
DIR_DOWN		equ %00100000
DIR_LEFT		equ %01000000
DIR_RIGHT		equ %10000000

DIR_UP_I		equ %11101111
DIR_DOWN_I		equ %11011111
DIR_LEFT_I		equ %10111111
DIR_RIGHT_I		equ %01111111

;	-- port 0x123B = 4667
;	-- bit 7 and 6 = new vram page selection ("00", "01" or "10") 0, 64, 128
;	-- bit 5 and 4 = layers order	"00" - new vram over vram (100% magenta is transparent)
;	--								"01" - vram over new vram (black with bright is transparent) ; out 9275,20:out 9531,colour
;	-- bit 3 = not used
;	-- bit 2 = 	"0" page selected is write only, ZX ROM visible at 0000-3FFF
;	--			"1" page selected is read and write, ZX ROM is disabled
;	-- bit 1 = 	"0" new vram not visible
;	-- bit 0 = 	"0" new vram read and write disabled
LAYER2_ACCESS_PORT			equ $123B
TBBLUE_REGISTER_SELECT			equ $243B
TBBLUE_REGISTER_ACCESS			equ $253B
SPRITE_STATUS_SLOT_SELECT		equ $303B
MEMORY_PAGING_CONTROL			equ $7FFD
SOUND_CHIP_REGISTER_WRITE		equ $BFFD
NEXT_MEMORY_BANK_SELECT			equ $DFFD
NXT_ULA_PLUS				equ $FF3B
TURBO_SOUND_CONTROL			equ $FFFD
Z80_DMA_PORT			equ $6b
;----------------------------------------------
; DMA (Register 6)
DMA_RESET				equ $c3
DMA_RESET_PORT_A_TIMING			equ $c7
DMA_RESET_PORT_B_TIMING			equ $cb
DMA_LOAD				equ $cf			; %11001111
DMA_CONTINUE				equ $d3
DMA_DISABLE_INTERUPTS			equ $af
DMA_ENABLE_INTERUPTS			equ $ab
DMA_RESET_DISABLE_INTERUPTS		equ $a3
DMA_ENABLE_AFTER_RETI			equ $b7
DMA_READ_STATUS_BYTE			equ $bf
DMA_REINIT_STATUS_BYTE			equ $8b
DMA_START_READ_SEQUENCE			equ $a7
DMA_FORCE_READY				equ $b3
DMA_DISABLE				equ $83
DMA_ENABLE				equ $87
DMA_WRITE_REGISTER_COMMAND		equ $bb
DMA_BURST				equ %11001101
DMA_CONTINUOUS				equ %10101101
;----------------------------------------------
; Registers
MACHINE_ID_REGISTER			equ $00
NEXT_VERSION_REGISTER			equ $01		; 7-4 = major, 3-0 = minor, CORE_VERSION_REGISTER = sub minor
NEXT_RESET_REGISTER			equ $02
MACHINE_TYPE_REGISTER			equ $03
ROM_MAPPING_REGISTER			equ $04		;In config mode, allows RAM to be mapped to ROM area.
PERIPHERAL_1_REGISTER			equ $05		;Sets joystick mode, video frequency, Scanlines and Scandoubler.
PERIPHERAL_2_REGISTER			equ $06		;Enables Acceleration, Lightpen, DivMMC, Multiface, Mouse and AY audio.
TURBO_CONTROL_REGISTER			equ $07
PERIPHERAL_3_REGISTER			equ $08		;Enables Stereo, Internal Speaker, SpecDrum, Timex Video Modes, Turbo Sound Next and NTSC/PAL selection.
PERIPHERAL_4_REGISTER			equ $09		;1-0 = scanlines level 00=off. 01=75%,10=50%,11=25%
CORE_VERSION_REGISTER			equ $0E
ANTI_BRICK_REGISTER			equ $10
LAYER2_RAM_PAGE_REGISTER		equ $12		;Sets the bank number where Layer 2 video memory begins.
LAYER2_RAM_PAGE_SHADOW_REGISTER		equ $13		;Sets the bank number where the Layer 2 shadow screen begins.
GLOBAL_TRANSPARENCY_REGISTER		equ $14		;Sets the color treated as transparent when drawing layer 2.
SPRITE_CONTROL_REGISTER			equ $15		;Enables/disables Sprites and Lores Layer, and chooses priority of sprites and Layer 2.
LAYER2_XOFFSET_REGISTER 		equ $16
LAYER2_YOFFSET_REGISTER			equ $17
CLIP_WINDOW_REGISTER			equ $18
CLIP_SPRITE_REGISTER			equ $19
CLIP_LORES_REGISTER			equ $1a
CLIP_WINDOW_CONTROL_REGISTER		equ $1C		;set to 7 to reset all clipping
RASTER_LINE_MSB_REGISTER		equ $1E
RASTER_LINE_LSB_REGISTER		equ $1F
RASTER_INTERUPT_CONTROL_REGISTER	equ $22		;Controls the timing of raster interrupts and the ULA frame interrupt.
RASTER_INTERUPT_VALUE_REGISTER		equ $23
HIGH_ADRESS_KEYMAP_REGISTER		equ $28
LOW_ADRESS_KEYMAP_REGISTER		equ $29
HIGH_DATA_TO_KEYMAP_REGISTER		equ $2A
LOW_DATA_TO_KEYMAP_REGISTER		equ $2B
SOUNDDRIVE_MIRROR_REGISTER		equ $2D		;this port cand be used to send data to the SoundDrive using the Copper co-processor
LORES_XOFFSET_REGISTER			equ $32
LORES_YOFFSET_REGISTER			equ $33
PALETTE_INDEX_REGISTER			equ $40		;Chooses a ULANext palette number to configure.
PALETTE_VALUE_REGISTER			equ $41		;Used to upload 8-bit colors to the ULANext palette.
PALETTE_FORMAT_REGISTER			equ $42
PALETTE_CONTROL_REGISTER		equ $43		;Enables or disables ULANext interpretation of attribute values and toggles active palette.
PALETTE_VALUE_BIT9_REGISTER		equ $44		;Holds the additional blue color bit for RGB333 color selection.
TRANSPARENCY_FALLBACK			equ $4a
TRANSPARENCY_INDEX_SPRITES		equ $4b
MMU_REGISTER_0				equ $50		;Set a Spectrum RAM page at position 0x0000 to 0x1fff
MMU_REGISTER_1				equ $51		;Set a Spectrum RAM page at position 0x2000 to 0x3fff
MMU_REGISTER_2				equ $52		;Set a Spectrum RAM page at position 0x4000 to 0x5fff
MMU_REGISTER_3				equ $53		;Set a Spectrum RAM page at position 0x6000 to 0x7fff
MMU_REGISTER_4				equ $54		;Set a Spectrum RAM page at position 0x8000 to 0x9fff
MMU_REGISTER_5				equ $55		;Set a Spectrum RAM page at position 0xa000 to 0xbfff
MMU_REGISTER_6				equ $56		;Set a Spectrum RAM page at position 0xC000 to 0xDFFF
MMU_REGISTER_7				equ $57		;Set a Spectrum RAM page at position 0xE000 to 0xFFFF
;----------------------------------------------
COPPER_DATA				equ $60
COPPER_CONTROL_LO_BYTE_REGISTER		equ $61
COPPER_CONTROL_HI_BYTE_REGISTER		equ $62
COPPER_WAIT				= %10000000
;----------------------------------------------
DEBUG_LED_CONTROL_REGISTER		equ $FF 	;Turns debug LEDs on and off on TBBlue implementations that have them.
;----------------------------------------------
ZX_SCREEN				= $4000
ZX_ATTRIB				= $5800
LORES_MEM_1				= $4000
LORES_MEM_2				= $6000

PLAYER_UP		= 0
PLAYER_RIGHT		= 1
PLAYER_DOWN		= 2
PLAYER_LEFT		= 3

DIRECTION_UP		= 0
DIRECTION_DOWN		= 1
DIRECTION_LEFT		= 2
DIRECTION_RIGHT		= 4

	MACRO MUL_DE:dw $30ED:ENDM
	MACRO PIXELAD:dw $94ED:ENDM
	MACRO PIXELDN:dw $93ED:ENDM

	MACRO SWAPNIB: dw $23ED: ENDM
	MACRO ADD_HL_A: dw $31ED: ENDM
	MACRO ADD_DE_A: dw $32ED: ENDM
	MACRO ADD_BC_A: dw $33ED: ENDM
	MACRO ADD_HL_nnnn data: dw $34ED: dw data: ENDM
	MACRO ADD_DE_nnnn data: dw $35ED: dw data: ENDM
	MACRO ADD_BC_nnnn data: dw $36ED: dw data: ENDM

	MACRO SetSpriteControlRegister:NEXTREG_A SPRITE_CONTROL_REGISTER:ENDM

	MACRO Set3mhz:NEXTREG_nn TURBO_CONTROL_REGISTER,%00:ENDM
	MACRO Set7mhz:NEXTREG_nn TURBO_CONTROL_REGISTER,%01:ENDM
	MACRO Set14mhz:NEXTREG_nn TURBO_CONTROL_REGISTER,%10:ENDM

	MACRO BREAK:dw $01DD:ENDM

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

;--------------------------
; Key defines
KEYAND_CAPS	equ 	%00000001
KEYAND_Z	equ	%00000010
KEYAND_X	equ	%00000100
KEYAND_C	equ	%00001000
KEYAND_V	equ	%00010000
KEYAND_A	equ	%00000001
KEYAND_S	equ	%00000010
KEYAND_D	equ	%00000100
KEYAND_F	equ	%00001000
KEYAND_G	equ	%00010000
KEYAND_Q	equ 	%00000001
KEYAND_W	equ	%00000010
KEYAND_E	equ	%00000100
KEYAND_R	equ	%00001000
KEYAND_T	equ	%00010000
KEYAND_1	equ 	%00000001
KEYAND_2	equ	%00000010
KEYAND_3	equ	%00000100
KEYAND_4	equ	%00001000
KEYAND_5	equ	%00010000
KEYAND_0	equ 	%00000001
KEYAND_9	equ	%00000010
KEYAND_8	equ	%00000100
KEYAND_7	equ	%00001000
KEYAND_6	equ	%00010000
KEYAND_P	equ 	%00000001
KEYAND_O	equ	%00000010
KEYAND_I	equ	%00000100
KEYAND_U	equ	%00001000
KEYAND_Y	equ	%00010000
KEYAND_ENTER	equ 	%00000001
KEYAND_L	equ	%00000010
KEYAND_K	equ	%00000100
KEYAND_J	equ	%00001000
KEYAND_H	equ	%00010000
KEYAND_SPACE	equ 	%00000001
KEYAND_SYM	equ	%00000010
KEYAND_M	equ	%00000100
KEYAND_N	equ	%00001000
KEYAND_B	equ	%00010000

KEY_CAPS	equ 	7
KEY_Z		equ	7
KEY_X		equ	7
KEY_C		equ	7
KEY_V		equ	7
KEY_A		equ	6
KEY_S		equ	6
KEY_D		equ	6
KEY_F		equ	6
KEY_G		equ	6
KEY_Q		equ 	5
KEY_W		equ	5
KEY_E		equ	5
KEY_R		equ	5
KEY_T		equ	5
KEY_1		equ 	4
KEY_2		equ	4
KEY_3		equ	4
KEY_4		equ	4
KEY_5		equ	4
KEY_0		equ 	3
KEY_9		equ	3
KEY_8		equ	3
KEY_7		equ	3
KEY_6		equ	3
KEY_P		equ 	2
KEY_O		equ	2
KEY_I		equ	2
KEY_U		equ	2
KEY_Y		equ	2
KEY_ENTER	equ 	1
KEY_L		equ	1
KEY_K		equ	1
KEY_J		equ	1
KEY_H		equ	1
KEY_SPACE	equ 	0
KEY_SYM		equ	0
KEY_M		equ	0
KEY_N		equ	0
KEY_B		equ	0

KEMPSTON_PORT	equ 	$1f
KEMPSTON_START	equ 	%10000000
KEMPSTON_FIRE3	equ 	%01000000
KEMPSTON_FIRE2	equ 	%00100000
KEMPSTON_FIRE	equ 	%00010000
KEMPSTON_UP		equ 	%00001000
KEMPSTON_DOWN	equ 	%00000100
KEMPSTON_LEFT	equ 	%00000010
KEMPSTON_RIGHT	equ 	%00000001

; xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

TRIES = 5

	org $8000
start
	ld	sp,$6000
	Set3mhz
restart
	ld ix,keystopress
clear
	ld hl,$4000:ld de,$4001:ld bc,$17ff:ld (hl),0:ldir
	call sprint
	db	22,0,0,16,7*8+1,"Keyboard Tester",13,13
	db	16,7*8+0,"Press",9,9,16,7*8+4,"TRY ",16,7*8+4,"OK ",16,7*8+2,"BAD ",16,7*8+2,"WO ",16,7*8+4,"MS",13
	db	0
lp	ld a,(ix+00):or a:jr nz,.nores
	call sprint
	db 13,13,16,7*8+4,"Keyboard Test Complete",0
	ld b,250
.d	ei:halt:di:djnz .d:jp restart
.nores
	ld a,(ix+0):cp 12:jr nz,.nc
	call sprint
	db 13,13,16,7*8+4,"Keyboard Page Complete",13,"press any key to continue",0
	call WaitNoKey:call WaitKey:call WaitNoKey
	inc ix:jp clear
.nc	push ix:pop hl:call print:push hl:pop ix
	push de
	ld hl,0:call prtdec2:ld a," ":call prtcell:ld a," ":call prtcell
	ld hl,0:call prtdec2:ld a," ":call prtcell
	ld hl,0:call prtdec2:ld a," ":call prtcell:ld a," ":call prtcell
	ld hl,0:call prtdec2:ld a," ":call prtcell
	ld hl,0:call prtdec3:ld a,".":call prtcell:ld a,"0":call prtcell
	pop de
	exx
	ld b,TRIES
	ld c,0	; hits OK
	ld d,0	; Bad
	ld e,0	; Wrong Order
	exx

loop
	call WaitNoKey

	ld	hl,0:ld (bothtime),hl
	ei:halt:di
.keyloop

	xor a:in a,(254):and 31:ld (.tb+1),a

	ld c,0
	ld a,(ix+2):ld hl,bitstable:ADD_HL_A:ld a,(hl):in a,(254):and (ix+3):jr nz,.n2:set 1,c
.n2	
	ld a,(ix+0):ld hl,bitstable:ADD_HL_A:ld a,(hl):in a,(254):and (ix+1):jr nz,.n3:set 0,c
.n3
	ld a,c:cp 3:jr z,.ok

	or a:jr z,.tb
	ld a,(ix+0):cp (ix+2):jr nz,.n1
.tb	ld a,0:cp 31:jr nz,.fail
.n1

	ld hl,(bothtime):ld a,h:or l:jr nz,.inc
	ld a,c:or a:jp z,.keyloop
	
	cp 2:jr nz,.inc
	exx:inc e:exx	; wrong order

.inc
	inc hl:ld a,h:or l:jr z,.fail
	ld a,c:or a:jr z,.fail
	ld (bothtime),hl:jp .keyloop

.fail	exx:inc d:dec b:exx:jr .overhere
.ok		exx:inc c:dec b:exx

.overhere
	push de
	exx:ld a,TRIES:sub b:exx:ld l,a:ld h,0:call prtdec2:ld a," ":call prtcell:ld a," ":call prtcell
	exx:ld a,c:exx:ld l,a:ld h,0:call prtdec2:ld a," ":call prtcell
	exx:ld a,d:exx:ld l,a:ld h,0:call prtdec2:ld a," ":call prtcell:ld a," ":call prtcell
	exx:ld a,e:exx:ld l,a:ld h,0:call prtdec2:ld a," ":call prtcell
	ld hl,(bothtime):srl h:rr l:srl h:rr l:srl h:rr l
	push de:ld a,h:or l:jr z,.l1:ld de,999:or a:sbc hl,de:push af:add hl,de:pop af:jr c,.l1:ld hl,999
.l1	pop de:call prtdec3
	ld a,".":call prtcell
	ld a,(bothtime):and 7:add a,"0":call prtcell
	pop de

	call WaitNoKey

	exx:ld a,b:exx:or a:jp nz,loop

	ld bc,4:add ix,bc

	jp lp

bitstable	db	%01111111,%10111111,%11011111,%11101111,%11110111,%11111011,%11111101,%11111110

keystopress
	db	13,16,7*8+0,"TRUE VIDEO",9,0,KEY_CAPS,KEYAND_CAPS,KEY_3,KEYAND_3
	db	13,16,7*8+0,"INV VIDEO",9,0,KEY_CAPS,KEYAND_CAPS,KEY_4,KEYAND_4
	db	13,16,7*8+0,"BREAK",9,9,0,KEY_CAPS,KEYAND_CAPS,KEY_SPACE,KEYAND_SPACE
	db	13,16,7*8+0,"DELETE",9,9,0,KEY_CAPS,KEYAND_CAPS,KEY_0,KEYAND_0
	db	13,16,7*8+0,"GRAPH",9,9,0,KEY_CAPS,KEYAND_CAPS,KEY_9,KEYAND_9
	db	13,16,7*8+0,"EXTENDED",9,0,KEY_CAPS,KEYAND_CAPS,KEY_SYM,KEYAND_SYM
	db	13,16,7*8+0,"EDIT",9,9,0,KEY_CAPS,KEYAND_CAPS,KEY_1,KEYAND_1
	db	13,16,7*8+0,"CAPS LOCK",9,0,KEY_CAPS,KEYAND_CAPS,KEY_2,KEYAND_2
	db	13,16,7*8+0,";",9,9,9,0,KEY_SYM,KEYAND_SYM,KEY_O,KEYAND_O
	db	13,16,7*8+0,34,9,9,9,0,KEY_SYM,KEYAND_SYM,KEY_P,KEYAND_P
	db	13,16,7*8+0,"LEFT",9,9,0,KEY_CAPS,KEYAND_CAPS,KEY_5,KEYAND_5
	db	13,16,7*8+0,"RIGHT",9,9,0,KEY_CAPS,KEYAND_CAPS,KEY_8,KEYAND_8
	db	13,16,7*8+0,"UP",9,9,9,0,KEY_CAPS,KEYAND_CAPS,KEY_7,KEYAND_7
	db	13,16,7*8+0,"DOWN",9,9,0,KEY_CAPS,KEYAND_CAPS,KEY_6,KEYAND_6
	db	13,16,7*8+0,",",9,9,9,0,KEY_SYM,KEYAND_SYM,KEY_N,KEYAND_N
	db	13,16,7*8+0,".",9,9,9,0,KEY_SYM,KEYAND_SYM,KEY_M,KEYAND_M

	db	12

	db	13,16,7*8+0,"1",9,9,9,0,KEY_1,KEYAND_1,KEY_1,KEYAND_1
	db	13,16,7*8+0,"2",9,9,9,0,KEY_2,KEYAND_2,KEY_2,KEYAND_2
	db	13,16,7*8+0,"3",9,9,9,0,KEY_3,KEYAND_3,KEY_3,KEYAND_3
	db	13,16,7*8+0,"4",9,9,9,0,KEY_4,KEYAND_4,KEY_4,KEYAND_4
	db	13,16,7*8+0,"5",9,9,9,0,KEY_5,KEYAND_5,KEY_5,KEYAND_5
	db	13,16,7*8+0,"6",9,9,9,0,KEY_6,KEYAND_6,KEY_6,KEYAND_6
	db	13,16,7*8+0,"7",9,9,9,0,KEY_7,KEYAND_7,KEY_7,KEYAND_7
	db	13,16,7*8+0,"8",9,9,9,0,KEY_8,KEYAND_8,KEY_8,KEYAND_8
	db	13,16,7*8+0,"9",9,9,9,0,KEY_9,KEYAND_9,KEY_9,KEYAND_9
	db	13,16,7*8+0,"0",9,9,9,0,KEY_0,KEYAND_0,KEY_0,KEYAND_0

	db	12

	db	13,16,7*8+0,"Q",9,9,9,0,KEY_Q,KEYAND_Q,KEY_Q,KEYAND_Q
	db	13,16,7*8+0,"W",9,9,9,0,KEY_W,KEYAND_W,KEY_W,KEYAND_W
	db	13,16,7*8+0,"E",9,9,9,0,KEY_E,KEYAND_E,KEY_E,KEYAND_E
	db	13,16,7*8+0,"R",9,9,9,0,KEY_R,KEYAND_R,KEY_R,KEYAND_R
	db	13,16,7*8+0,"T",9,9,9,0,KEY_T,KEYAND_T,KEY_T,KEYAND_T
	db	13,16,7*8+0,"Y",9,9,9,0,KEY_Y,KEYAND_Y,KEY_Y,KEYAND_Y
	db	13,16,7*8+0,"U",9,9,9,0,KEY_U,KEYAND_U,KEY_U,KEYAND_U
	db	13,16,7*8+0,"I",9,9,9,0,KEY_I,KEYAND_I,KEY_I,KEYAND_I
	db	13,16,7*8+0,"O",9,9,9,0,KEY_O,KEYAND_O,KEY_O,KEYAND_O
	db	13,16,7*8+0,"P",9,9,9,0,KEY_P,KEYAND_P,KEY_P,KEYAND_P

	db	12

	db	13,16,7*8+0,"A",9,9,9,0,KEY_A,KEYAND_A,KEY_A,KEYAND_A
	db	13,16,7*8+0,"S",9,9,9,0,KEY_S,KEYAND_S,KEY_S,KEYAND_S
	db	13,16,7*8+0,"D",9,9,9,0,KEY_D,KEYAND_D,KEY_D,KEYAND_D
	db	13,16,7*8+0,"F",9,9,9,0,KEY_F,KEYAND_F,KEY_F,KEYAND_F
	db	13,16,7*8+0,"G",9,9,9,0,KEY_G,KEYAND_G,KEY_G,KEYAND_G
	db	13,16,7*8+0,"H",9,9,9,0,KEY_H,KEYAND_H,KEY_H,KEYAND_H
	db	13,16,7*8+0,"J",9,9,9,0,KEY_J,KEYAND_J,KEY_J,KEYAND_J
	db	13,16,7*8+0,"K",9,9,9,0,KEY_K,KEYAND_K,KEY_K,KEYAND_K
	db	13,16,7*8+0,"L",9,9,9,0,KEY_L,KEYAND_L,KEY_L,KEYAND_L
	db	13,16,7*8+0,"ENTER",9,9,0,KEY_ENTER,KEYAND_ENTER,KEY_ENTER,KEYAND_ENTER

	db	12

	db	13,16,7*8+0,"CAPS",9,9,0,KEY_CAPS,KEYAND_CAPS,KEY_CAPS,KEYAND_CAPS
	db	13,16,7*8+0,"Z",9,9,9,0,KEY_Z,KEYAND_Z,KEY_Z,KEYAND_Z
	db	13,16,7*8+0,"X",9,9,9,0,KEY_X,KEYAND_X,KEY_X,KEYAND_X
	db	13,16,7*8+0,"C",9,9,9,0,KEY_C,KEYAND_C,KEY_C,KEYAND_C
	db	13,16,7*8+0,"V",9,9,9,0,KEY_V,KEYAND_V,KEY_V,KEYAND_V
	db	13,16,7*8+0,"B",9,9,9,0,KEY_B,KEYAND_B,KEY_B,KEYAND_B
	db	13,16,7*8+0,"N",9,9,9,0,KEY_N,KEYAND_N,KEY_N,KEYAND_N
	db	13,16,7*8+0,"M",9,9,9,0,KEY_M,KEYAND_M,KEY_M,KEYAND_M
	db	13,16,7*8+0,"SYMBOL",9,9,0,KEY_SYM,KEYAND_SYM,KEY_SYM,KEYAND_SYM
	db	13,16,7*8+0,"SPACE",9,9,0,KEY_SPACE,KEYAND_SPACE,KEY_SPACE,KEYAND_SPACE

	db	0

;--------------------------
sprint	pop hl:call print:jp (hl)
print	ld a,(hl):inc hl:cp 32:jr nc,.ncode
		or a:ret z
		cp 22:jr nz,.nprtat:ld e,(hl):inc hl:ld d,(hl):inc hl:jr print
.nprtat	cp 13:jr nz,.nprent:ld e,0:ld a,d:add a,8:ld d,a:jr print
.nprent	cp 9:jr nz,.nprtab:call prtab:jr print
.nprtab	cp 16:jr nz,.nprcol:ld a,(hl):inc hl:ld (attribute),a:jr print
.nprcol
		jr print
.ncode	call prtcell:jr print

prtab	ld a,e:or 31:inc a:ld e,a:ret

prtdot5	ld bc,10000:call prtdec
prtdot4 ld bc,1000:call prtdec
prtdot3	ld bc,100:call prtdec
prtdot2	ld bc,10:call prtdec
		ld a,".":call prtcell
		ld bc,1:jp prtdec

prtdec5	ld bc,10000:call prtdec
prtdec4 ld bc,1000:call prtdec
prtdec3	ld bc,100:call prtdec
prtdec2	ld bc,10:call prtdec
prtdec1	ld bc,1
prtdec	ld a,"0"-1
.lp		inc a:sbc hl,bc:jr nc,.lp:add hl,bc

prtcell
	push hl:push de:PIXELAD:sub 32:ld e,a:ld d,8:MUL_DE:ADD_DE_nnnn font
	ld a,(de):ld (hl),a:inc h:inc de
	ld a,(de):ld (hl),a:inc h:inc de
	ld a,(de):ld (hl),a:inc h:inc de
	ld a,(de):ld (hl),a:inc h:inc de
	ld a,(de):ld (hl),a:inc h:inc de
	ld a,(de):ld (hl),a:inc h:inc de
	ld a,(de):ld (hl),a:inc h:inc de
	ld a,(de):ld (hl),a
	ld a,h:rra:rra:rra:and 3:or $58:ld h,a:db $36 ;$36=ld (hl),n
attribute db $38
	pop de:pop hl:ld a,e:add a,8:ld e,a
	ret

;--------------------------
WaitNoKey
	xor a:in a,(254):and 31:cp 31:jr nz,WaitNoKey
	ret
WaitKey
	xor a:in a,(254):and 31:cp 31:jr z,WaitKey
	ret
;--------------------------
GetInput
	push de
.getk	ld a,%01111111
	ld hl,oldkeys:ld de,newkeys:ld bc,debkeys
.lp	push af:ld a,(de):ld (hl),a:pop af
	push af:in a,(254):cpl:ld (de),a:and (hl):ex de,hl:xor (hl):ex de,hl:ld (bc),a:pop af
	inc  hl:inc de:inc bc:rrca
	jp c,.lp
	pop de
	ret
;--------------------------
GetAscii
	push de:push ix
	xor a:ld (debAscii),a
	ld hl,(debkeys+0):ld (.debkeyscopy+0),hl:ld hl,(debkeys+2):ld (.debkeyscopy+2),hl
	ld hl,(debkeys+4):ld (.debkeyscopy+4),hl:ld hl,(debkeys+6):ld (.debkeyscopy+6),hl
	ld hl,.keytab
	ld a,$fe:in a,(254):rra:jr c,.ncap:ld hl,.captab
.ncap	ld a,$7f:in a,(254):and 2:jr nz,.nsym:ld hl,.symtab
.nsym	ld ix,.debkeyscopy
	res 1,(ix+0):res 0,(ix+7)	; clear caps and symbol bits.
	ld e,$7f
.lp	ld a,(ix+0):inc ix
	ld b,5
.blp	rra:jr c,.got
.skp	inc hl:djnz .blp:rrc e:jr c,.lp
	pop ix:pop de:ret
.got	ld a,(hl):cp 1:jr z,.skp
	ld (debAscii),a
	pop ix:pop de:ret

.debkeyscopy	db	0,0,0,0,0,0,0,0
.keytab	db	" ",  1,"m","n","b"	, 13,"l","k","j","h"
	db	"p","o","i","u","y"	,"0","9","8","7","6"
	db	"1","2","3","4","5"	,"q","w","e","r","t"
	db	"a","s","d","f","g"	,  1,"z","x","c","v"

.captab	db	" ",  1,"M","N","B"	, 13,"L","K","J","H"
	db	"P","O","I","U","Y"	, -1,"9",  8,  7,  6
	db	"1","2","3","4",  5	,"Q","W","E","R","T"
	db	"A","S","D","F","G"	,  1,"Z","X","C","V"

.symtab	db	" ",  1,".",",","*"	, 13,"=","+","-","^"
	db	 34,";","I","U","Y"	,"_",")","(","'","&"
	db	"!","@","#","$","%"	,"Q","W","E","<",">"
	db	"A","S","D","F","G"	,  1,":",$60,$3f,"/"

bothtime	dw 0

debAscii		db	0
oldkeys			db	0,0,0,0,0,0,0,0
oldKempstonValue 	db	0
newkeys			db	0,0,0,0,0,0,0,0
kempstonValue		db	0
debkeys			db	0,0,0,0,0,0,0,0
debKempstonValue	db 	0

font incbin "specfont.chr"

;--------------------------

;--------------------------
	savesna "KeyboardTester.sna",start
;--------------------------
