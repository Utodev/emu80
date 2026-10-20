; TBBlue / ZX Spectrum Next project
; Copyright (c) 2010-2018
;
; MOUSE.DRV Chris Cowley, Garry Lancaster and Tim Gilberts
;
; All rights reserved
;
; Redistribution and use in source and synthezised forms, with or without
; modification, are permitted provided that the following conditions are met:
;
; Redistributions of source code must retain the above copyright notice,
; this list of conditions and the following disclaimer.
;
; Redistributions in synthesized form must reproduce the above copyright
; notice, this list of conditions and the following disclaimer in the
; documentation and/or other materials provided with the distribution.
;
; Neither the name of the author nor the names of other contributors may
; be used to endorse or promote products derived from this software without
; specific prior written permission.
;
; THIS CODE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
; THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
; PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
; POSSIBILITY OF SUCH DAMAGE.
;
; You are responsible for any legal issues arising from your use of this code.
;
;-------------------------------------------------------------------------------
; ***************************************************************************
; * Simple example NextOS driver                                            *
; ***************************************************************************
;
; This file is the 512-byte NextOS driver itself, plus relocation table.
;
; Assemble with: pasmo mouse.asm mouse.bin mouse.sym
;
; After this, mouse_drv.asm needs to be built to generate the actual
; driver file.

; Based on code freely made available with credit for original work:
; mouse.asm v1.0 - Chris Cowley 2003 <ccowley@grok.co.uk>
; modified to use larger XY space / cursor and sprites for ZX Next: Tim Gilberts
; v0p2 to use return values for new DRIVER command in BASIC.
; v0p2b correct bugs in Sprite and Pattern number - forward port to v0p4
; v0p3 abandoned track
; v0p4 experiment with Mouse Acceleration - see www.c64os.com/post?p=62
; v0p5 simple support for Wheel as per TBU 49 - returned as top part of buttons
; so any code needs to mask off bottom three bits for buttons - we had to
; disable detection so may get random effects now if not present.
; v0p6 use nextreg sprite interface to avoid conflicts with NextBASIC programs.


; ***************************************************************************
; * Entry points                                                            *
; ***************************************************************************
; Drivers are a fixed length of 512 bytes (although can have external 8K
; banks allocated to them if required).
;
; They are always assembled at origin $0000 and relocated at installation time.
;
; Your driver always runs with interrupts disabled, and may use any of the
; standard register set (AF,BC,DE,HL). Index registers and alternates must be
; preserved.
;
; No esxDOS hooks or restarts may be used. However, 3 calls are provided
; which drivers may use:
;
;       call    $2000   ; drv_drvswapmmc
;                       ; Used for switching between allocated DivMMC banks
;
;       call    $2003   ; drv_drvrtc
;                       ; Query the RTC. Returns BC=date, DE=time (as M_DATE)
;
;       call    $2006   ; drv_drvapi
;                       ; Access other drivers. Same parameters as M_DRVAPI.
;
; The stack is always located below $4000, so if ZX banks have been allocated
; they may be paged in at any location (MMU2..MMU7). However, when switching
; to other allocated DivMMC banks, the stack cannot be used unless you set
; it up/restore it yourself.


; ***************************************************************************
; * Macros                                                                  *
; ***************************************************************************

macro nxtregn,reg,val
	defb	$ed,$91,reg,val
endm

macro nxtrega,val
	defb	$ed,$92,val
endm


; ***************************************************************************
; * NextReg definitions                                                     *
; ***************************************************************************

nxr_sprite_num		equ	$34
nxr_sprite_attr0	equ	$35
nxr_sprite_attr1	equ	$36
nxr_sprite_attr2	equ	$37
nxr_sprite_attr3	equ	$38
nxr_sprite_attr4	equ	$39
nxr_sprite_attr0_inc	equ	$75
nxr_sprite_attr1_inc	equ	$76
nxr_sprite_attr2_inc	equ	$77
nxr_sprite_attr3_inc	equ	$78
nxr_sprite_attr4_inc	equ	$79


; ***************************************************************************
; * Entry points                                                            *
; ***************************************************************************

        org     $0000


; At $0000 is the entry point for API calls directed to your driver.
; B,DE,HL are available as entry parameters.

; If your driver does not provide any API, just exit with A=0 and carry set.

api_entry:	JR	return_mouse
		NOP
;        xor     a
;        scf
;        ret

; At $0003 is the entry point for the interrupt handler. This will only be
; called if bit 7 of the driver id byte has been set in your .DRV file, so
; need not be implemented otherwise.

im1_entry:	JR	update_mouse

; Read the kempston mouse port and update PointerX and PointerY if the pointer
; has moved

; ***************************************************************************
; On entry, use B=call id with HL,DE other parameters.
; (NOTE: HL will contain the value that was either provided in HL (when called
;        from dot commands) or IX (when called from a standard program).
;
; When called from the DRIVER command, DE is the first input and HL is the 2nd.
;
; When returning values, the DRIVER command will place the contents of BC into
; the first return variable, then DE and then HL.
;
; API services we have are:
;
; B=1 Return current XY location of mouse in DE,HL(L only actually) with Button
; status in C.  B WILL BE previous status of buttons - not yet implemented
; - probably better to use mouse event
;
; B=2 enable Sprite mouse
; 1st Param HL = sprite number to use	;Would be IX if from a standard command
; 2nd Param DE = pattern number to use
;
; B=3 disable Sprite mouse
;
; B=4 enable cursor mouse / change attribute used
; 1st Param HL = Attribute to use
; 2nd Param DE = unused as yet
;
; B=5 disable Cursor mouse
;
; Double X resolution (used for Timex mode) obviously sprite pointer snaps
; to center of the two pixels.
;
;
; TODO...
;
; Option to Constrain sprite to within border - does not set clipping, if it is
; outside it snaps to closest edge.
;
; Get next mouse event.
; Returns BC,DE,HL as
;     BC=[event type NONE(0),UP(1), DOWN(2), CLICK(3), DOUBLE CLICK(4)]
;     DE=X, HL=Y
;
; For acceleration experiment horizontal X and vertical Y movement are doubled
; if you exceed speed threshold TODO option to set threshhold.

return_mouse:
		DJNZ    bnot1                   ; On if B<>1
reloc_api_1:
		LD	HL,PointerX+1		; MSB
		LD	D,(HL)
		DEC	HL			; PointerX-LSB
		LD	E,(HL)
		DEC	HL			; Pointer Y
		LD	B,(HL)
		DEC	HL			; Lastbutton
		LD	C,(HL)
		XOR	A			; All is well so Clear Carry
		LD	H,A			; No MSB for Y
		LD	L,B
		LD	B,A			; Make sure MSB Lastbutton is 0
		RET

;2 enable sprite mouse pointer
bnot1		DJNZ	bnot2
		LD	A,E
		AND	%00111111		; 0-63 only valid so force
reloc_api_2:	LD	(SelfMod1+1),A
		LD	A,L
		AND	%00111111		; Same again
reloc_api_3:	LD	(SelfMod2+1),A		; We only use the bottom 4 bits
		LD	A,%00000010		; Set Bit 1 so sprite enabled.

set_flags:
reloc_api_4:	LD	HL,Flags
		OR	(HL)			; Enable sprite cursor
		LD	(HL),A			; (it will appear next IRQ)
		XOR	A
		RET

;3 disable sprite mouse pointer
bnot2:		DJNZ	bnot3

		XOR	A			; Bit 7=0
reloc_api_5:	CALL	sprite_cursor		; Get rid of it !

		LD	A,%11111101		; Make sure no sprite cursor

reset_flags:
reloc_api_6:	LD	HL,Flags
		AND	(HL)
		LD	(HL),A
		XOR	A
		RET

;4 enable cursor mouse
bnot3:		DJNZ	bnot4
		LD	A,E			; Totally zero value not allowed
		OR	A	; i.e. BLACK on BLACK (if wanted set Bright)
		JR	Z,use_last
reloc_api_7:	LD	(Attrib),A
use_last:	LD	A,%00000001		; It will appear on next INT
		JR	set_flags

;5 disable cursor mouse
bnot4:		DJNZ	bnot5

reloc_api_8:	CALL	remove_cursor
		INC	HL			; Old Attrib
		INC	HL			; AttribAddLSB
		INC	HL			; AttribAddMSB
		XOR	A
		LD	(HL),A			; Like never enabled

		LD	A,%11111110
		JR	reset_flags

; 6 set X acceleration threshold
; - setting it to 127 will effectivly shut it off
bnot5:
		LD	A,E
reloc_api_9:	LD	(selfmod_rx_accel+1),A
reloc_api_10:	LD	(selfmod_lx_accel+1),A
		RET

; Unsupported values of B.
; You may wish to return an error code in A.
bnot6:
		SCF                             ; Fc=1, signals error
		RET




; ***************************************************************************
; Main bulk of IM1 routine

update_mouse:

reloc_1:	CALL	remove_cursor	; Leaves HL pointing at Attrib

		DEC	HL		; Point at MouseX
		PUSH	HL

		LD	BC,64479	; Kempston X
		LD	A,(HL)
		LD	E,A
		IN	A,(C)
		LD	(HL),A
		SUB	E
		; Mouse Left/Right
;		LD	E,A		; Do only if needed.
		CP	$80
		JR	NC,moving_left

; Moving Right
reloc_2:	LD	HL,(PointerX)
		LD	E,A		; needed...
		LD	D,0
		ADD	HL,DE
selfmod_rx_accel:
		CP	32
		JR	C,no_rx_accel
		ADD	HL,DE
no_rx_accel:
		EX	DE,HL		; DE is new X pos
		LD	HL,639		; Was 319
		OR	A
		SBC	HL,DE

;		JR	Z,mouse_y	; No change do nothing

		JR	C,right_edge

reloc_4_3:	LD	(PointerX),DE
		JR	mouse_y

right_edge:
		LD	HL,639		; Was 319
reloc_5:	LD	(PointerX),HL
		JR	mouse_y

moving_left:
reloc_6:	LD	HL,(PointerX)
;		LD	A,E		; A is still value...
		NEG
		LD	E,A
		LD	D,0
		OR	A
		SBC	HL,DE
selfmod_lx_accel:
		CP	32		; X accel threshold
		JR	C,no_lx_accel	; < 32 no accel
		SBC	HL,DE		; *2 (C was clear)
no_lx_accel:
		EX	DE,HL		; DE is new X pos
reloc_7:	LD	HL,(PointerX)	; HL is old X pos
		OR	A
		SBC	HL,DE
		JR	C,left_edge

reloc_8_3:	LD	(PointerX),DE
		JR	mouse_y

left_edge:
		XOR	A
		LD	L,A
		LD	H,A
reloc_9:	LD	(PointerX),HL


mouse_y:	POP	HL
		DEC	HL		; Point at Mouse Y

		LD	BC,65503	; Kempston Y
		LD	A,(HL)
		LD	D,A
		IN	A,(C)
		LD	(HL),A
		SUB	D

		CP	$80
		JR	C,going_up

;going_down
		NEG
		LD	B,A
reloc_10:	LD	A,(PointerY)
		ADD	A,B
		JR	C,set_vert_edge

reloc_11:	LD	(PointerY),A
		JR	mouse_display


;Keep the exit code in range of all JR

mouse_btn:
		LD	BC,64223
		IN	A,(C)

;		CP	255
;		JR	NZ,end_pointer

;		SCF			; probably no mouse if port floating
;		RET
;As of V5 cannot use that as wheel at 15 with three buttons and the 1 = 255

end_pointer:
		XOR	%00000111	; Invert bits for simplicity
		AND	%11110111	; Only keep the three buttons & wheel

reloc_12:	LD	(LastButton),A	; Save in LastButton

		AND	%00000111	; Check buttons only

		XOR	255		; This will set the Z flag (if no
		RET			; buttons) and clear the carry


set_vert_edge:
		LD	A,255
		JR	set_vertical
;reloc_14:	LD	(PointerY),A
;		JR	mouse_display

going_up:
		LD	B,A
reloc_13:	LD	A,(PointerY)	; old pos
		SUB	B
		JR	NC,set_vertical
; set_bottom_edge
		XOR	A
set_vertical:
reloc_15:	LD	(PointerY),A
; Display mouse if needed

mouse_display:
		DEC	HL		; Now Flags

		BIT	0,(HL)
		PUSH	HL

reloc_16:	CALL	NZ, mouse_cursor

		POP	HL

		BIT	1,(HL)
		JR	Z,mouse_btn

		LD	A,%10000000		; Make mouse sprite appear
reloc_17:	CALL	sprite_cursor

		JR	mouse_btn

;--------------
;Enter A=128 to make it appear and 0 to dissappear
sprite_cursor:
		PUSH	AF

reloc_18:	LD	HL,PointerY
		LD	E,(HL)
		INC	HL
		LD	D,(HL)
		INC	HL
		LD	H,(HL)
		LD	L,D

		SRL	H		; Divide HL by 2 due to Timex support
		RR	L

SelfMod1:	LD	A,0		; Use sprite zero unless set by API

		nxtrega	nxr_sprite_num

		LD	A,L		; X
		nxtrega	nxr_sprite_attr0
		LD	A,E		; Y
		nxtrega	nxr_sprite_attr1

		XOR	A		; 7-4 Palette, 3-1 Rotation, 0 MSB of X
		SRL	H
		RLA
		nxtrega	nxr_sprite_attr2

		POP	AF

SelfMod2:	OR	0		; Combine in pattern index 0-63

		nxtrega	nxr_sprite_attr3; Display or hide sprite

		RET


;OK now we have a pointer location let's turn it into an Attibute location
mouse_cursor:

reloc_19:	LD	HL,PointerY
		LD	A,(HL)
;Limit Y as it can be higher than bottom of screen
		CP	24*8
		JR	C,lines_ok
		LD	A,24*8-1	; Doesn't matter never lower than ln 23
lines_ok:
		LD	B,%00010110	; Base of attrib at 22528 / 4
		LD	C,A		; So convert 0-175 /8 then *32 = *4
		SLA	C
		RL	B
		SLA	C
		RL	B
		LD	A,C
		AND	%11100000	; Preserve relevant bits
		LD	C,A
		INC	HL		; PointerX LSB

		LD	E,(HL)		; Get X and divide by 16 for timex
		INC	HL
		LD	A,(HL)
		SRL	A
		RR	E
		SRL	A
		RR	E
		SRL	A		; We throw these away if there anyway
		RR	E
		SRL	A
		RR	E
		LD	A,E
		CP	32
		JR	C,cols_ok
		LD	A,31
cols_ok:
		OR	C
		LD	E,A		; DE is now loc in attr screen for X,Y
		LD	D,B

reloc_20:	LD	HL,OldAttrib

		LD	A,(DE)		; Get current attibute from screen
		LD	(HL),A		; Save it
		INC	HL		; OldAttribAdd LSB

		LD	(HL),E
		INC	HL		; OldAttribAdd MSB
		LD	(HL),D
reloc_21:	LD	A,(Attrib)
		LD	(DE),A

		RET

;--------------
remove_cursor:
reloc_22:	LD	HL,OldAttribAdd+1	; On first install there is no
		LD	D,(HL)		; saved attribute so MSB = 0
		DEC	HL
		LD	E,(HL)
; Probably safe to write to address 0 on first load - but better code...
		DEC	HL		; HL = OldAttrib
		DEC	HL		; HL = Attrib
		XOR	A		; =0
		CP	D
		JR	Z,no_old_A

		LD	A,(DE)
		CP	(HL)		; Best to see if attribute is still
					;our ATTRIB (if not do not restore)
		JR	NZ,no_old_A

		INC	HL		; OldAttrib again

;Below can be swapped with LDD damages BC/DE but hell it decs HL for us
;		LD	A,(HL)
;		LD	(DE),A		; Restore Attibute byte on screen
;		DEC	HL		; Keep HL consistent in case reused

		LDD
no_old_A:
		RET			; pointing at Attrib


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************


LastButton:	DEFB	255
PointerY:	DEFB	0
PointerX:	DEFW	0		;Needs two bytes for width

Flags:		DEFB	0		;Flags for Bit management
					;0 - Attribute Cursor pointer enable
					;1 - Sprite pointer enable
					;2 - TODO Constrain sprite to screen

MouseY:		DEFB	0
MouseX:		DEFB	0
Attrib:		DEFB	%11000111	;Bright flashing BLACK and WHITE
OldAttrib:	DEFB	0
OldAttribAdd:	DEFW	0		;Attribute location of mouse at 0,0

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
        defw    reloc_api_1+2
        defw    reloc_api_2+2
        defw    reloc_api_3+2
        defw    reloc_api_4+2
        defw    reloc_api_5+2
        defw    reloc_api_6+2
        defw    reloc_api_7+2
        defw    reloc_api_8+2
        defw    reloc_api_9+2
        defw    reloc_api_10+2
        defw    reloc_1+2
        defw    reloc_2+2
;        defw    reloc_3+2
        defw    reloc_4_3+3		;DE load
        defw    reloc_5+2
        defw    reloc_6+2
        defw    reloc_7+2
        defw    reloc_8_3+3		;DE load
        defw    reloc_9+2
        defw    reloc_10+2
        defw    reloc_11+2
        defw    reloc_12+2
        defw    reloc_13+2
;        defw    reloc_14+2
        defw    reloc_15+2
        defw    reloc_16+2
        defw    reloc_17+2
        defw    reloc_18+2
        defw    reloc_19+2
        defw    reloc_20+2
        defw    reloc_21+2
        defw    reloc_22+2
reloc_end:

