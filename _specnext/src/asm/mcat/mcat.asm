;
; TBBlue / ZX Spectrum Next project
; Copyright (c) 2010-2018 
;
; MCAT - DOTJAM for June 2022
; Reused code from date by Victor Trucco and Tim Gilberts and others...
;
; Version 0.4
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
;
; .MCAT for ESXDOS and eventually NextZXOS
;
; This will eventually catalog a microdrive on the Next
;
; Built using Z80ASM for Z88DK
; See https://github.com/z88dk/z88dk/wiki/Tool---z80asm---directives

	DEFC IDE_BANK = $01bd           ; NextZXOS function to manage memory
	DEFC M_P3DOS = $94  		 ; +3 DOS function call

;	DEFC MAINRAM = 49152		; Where out code can run above CLEAR
	DEFC MAINRAM = 61440

	ORG 0x2000
  
MAIN:
	LD	A,H
	OR	L
	JP	Z,end_error	;if we dont have parameters it is an error

	LD	IX,MCATMAIN	;Included bin of MCATMAIN location
	
	LD	A,(HL)

;***TODO add skip whitespace from later DOTS...

	CP	'-'		;options flag (anything other than -i gives the help)
	JP	NZ,CAT		;Do our main function

	INC	HL
	LD	A,(HL)
	CP	'i'
	JR	Z,init_drives

	CP	'e'
	JP	NZ,end_error
	JP	Z,EXTCAT

init_drives:
;Equivalent to the BASIC:
;OUT 9275,135: OUT 9531,246
;OUT 9275,128: OUT 9531,8
;soft reset (OUT 9275,2:OUT 9531,1)

	LD	BC,9275
	LD	A,135
	OUT	(C),A
;	LD	BC,9531 - 
	INC	B
	LD	A,246
	OUT	(C),A
	
	DEC	B
	LD	A,128
	OUT	(C),A
	INC	B
	LD	A,8
	OUT	(C),A

	DEC	B
	LD	A,2
	OUT	(C),A
	INC	B
	LD	A,1
	OUT	(C),A	
	
	HALT			; This dumps us into the main ROM at ***
;	 

EXTCAT:
;Need whitespace skip
	INC	HL		; Skip the one space
	LD	A,(HL)
	CP	' '
	JR 	NZ,end_error
	INC	HL

;	CALL	0A028h		; Breakpoint to monitor ***

	LD	DE,MsgECat

	LD	A,4
	JR	CAT2

;The actual CAT routine.
	
CAT:	
	LD	DE,MsgCat
	LD	A,3		;Option 4 is extended CAT for supported drivers
CAT2:
	LD	(IX+$16),A
	
	LD	A,(HL)		;Get our drive number
	LD	(DRIVE),A	;Put in here for error message
	LD	(IX+2),A	;Copy drive into that as well.	
	
	SUB	'0'		;Must be 1-8
	JR	Z,err_drive
	CP	9
	JR	NC,err_drive

	EX	DE,HL
	CALL	PrintMsg

;***TODO - allocate a page properly - don't assume Page 0 and a CLEAR before...
	PUSH	IX
	POP	HL
	LD	DE,MAINRAM
	LD	BC,MCATMEND-MCATMAIN
	LDIR				;Copy code into page

;	CALL	0A028h		; Breakpoint to monitor ***

;Transfer ops to main memory

	CALL	MAINRAM
			
;***TODO Deallocate any page we had for our code...

	XOR	A		; Zero is OK error return by convention


	RET

err_drive:
	PUSH	AF
	LD	HL,ErrDrive
	CALL	PrintMsg
	POP	AF

diag_code:
	CALL	prt_hex
	CALL	print_newline
	
end_error:
	LD	HL,MsgUsage
	JP	PrintMsg

;---------------------------------------------	
;emook pointed me to this - not used yet but getting ready
;originally via Matt Davies — 30/03/2021
allocPage:
                push    ix
                push    bc
                push    de
                push    hl

                ; Allocate a page by using the OS function IDE_BANK.
                ld      hl,$0001        ; Select allocate function and allocate from normal memory.
                call    callP3dos
                ccf
                ld      a,e
                pop     hl
                pop     de
                pop     bc
                pop     ix
                ret     nc
                xor     a               ; Out of memory, page # is 0 (i.e. error), CF = 1
                scf
                ret

callP3dos:
                exx                     ; Function parameters are switched to alternative registers.
                ld      de,IDE_BANK     ; Choose the function.
                ld      c,7             ; We want RAM 7 swapped in when we run this function (so that the OS can run).
                rst     8
                DEFB      M_P3DOS         ; Call the function, new page # is in E
                ret

freePage:
                push    af
                push    ix
                push    bc
                push    de
                push    hl

                ld      e,a             ; E = page #
                ld      hl,$0003        ; Deallocate function from normal memory
                call    callP3dos

                pop     hl
                pop     de
                pop     bc
                pop     ix
                pop     af
                ret
                			
;---------------------------------------------	
;Useful subroutines for DOT commands
;*** maybe not needed in here - will be removed if too big	

NUMBER_TO_ASC:
	LD a,(HL)
	
	; get just the upper bits
	SRL A
	SRL A
	SRL A
	SRL A 
	add 48 ;convert number to ASCII
	LD b,a
	
	;now the lower bits
	LD a,(HL)
	and 0x0f ;just the lower bits
	add 48 ;convert number to ASCII
	LD c,a
	
	ret
	
LOAD_PREPARE_AND_MULT:
	ld a,(HL)
;	and 0x7F ; clear the bit 7 
PREPARE_AND_MULT:
	SRL a
	SRL a
	SRL a
	SRL a
	CALL X10
	ld b,a
	ld a,(HL)
	and 0x0F
	add a,b
	
	ret
	
CONVERT_DIGITS:
	LD a,(HL)
	;test ascii for 0 to 9
	CP 48
	jr C,CHAR_ERROR 
	
	CP 58
	jr NC,CHAR_ERROR
	
	or a; clear the carry
	
	sub 48 ; convert asc to number
	
	;first digit in upper bits
	SLA A
	SLA A
	SLA A
	SLA A

	LD b,a ; store in b
	
	; next digit or seperator for 0-9 case.
	inc HL
	LD a,(HL)
	
	CP '/'
	JR Z,SINGLE_DIGIT
	
	;test ascii for 0 to 9
	CP 48
	jr C,CHAR_ERROR 
	
	CP 58
	jr NC,CHAR_ERROR
	
	OR A
	sub 48 ; convert asc to number

	and 0x0f ; get just the lower bits
	or b ;combine with first digit

	
	or a; clear the carry
	ret
	
SINGLE_DIGIT:

	DEC HL
	LD A,(HL)
	OR A		;Clear Carry
	SUB 48		;There should be no carry after this.
	OR A
	RET
	
	
CHAR_ERROR:
	
	scf ; set the carry
	ret
	
; input A, output A = A * 10
X10:
	ld b,a
	add a,a
	add a,a
	add a,a
	add a,b
	add a,b
	ret

PrintMsg:         
	ld a,(hl)
	or a
	ret z
	rst 10h
	inc hl
	jr PrintMsg

openscreen:		ld a,2
			jp $1601
			
sprint:			pop	hl
			call print
			jp (hl)

print:			ld	a,(hl)
			inc hl
			or a
			ret z
			bit 7,a
			ret nz
			rst 16
			jr print

print_newline:		ld hl,newline
			call print
			ret

hextab:			DEFM	"0123456789ABCDEF"

space:			ld	a,' '
			jp 16

prt_hex_16:		ld	a,h
			call prt_hex
			ld a,l
			
prt_hex:		push af
			rra
			rra
			rra
			rra
			call prt_hex_4
			pop af

prt_hex_4:		push hl
			and	15
			add a,hextab&255
			ld l,a
			adc a,hextab/256
			sub l
			ld h,a
			ld a,(hl)
			pop hl
			jp 16

prt_dec:		ld bc,10000
			call dl
			ld bc,1000
			call dl
			ld bc,100
			call dl
			ld bc,10
			call dl
			ld a,l
			add a,'0'
			jp 16
			
dl:			ld a,'0'-1

lp2:			inc a
			or a
			sbc hl,bc
			jr nc,lp2
			add hl,bc
			jp 16


str_DE:	DEFM "DE  : "
		DEFB 0
str_BC:	DEFM "BC  : "
		DEFB 0


newline:	DEFB 13,0	
	

MsgUsage:	DEFM "MCAT V0.5 usage: ",13
	 	DEFB "mcat {-i}",13
	 	DEFB "mcat {-e} drive<ENTER>",13
		DEFB "Functions need CLEAR 61439",13
	 	DEFB 0

MsgECat:	DEFM "Extended "
MsgCat:	DEFM "CAT on Microdrive "
DRIVE:		DEFB '3',':',13
		DEFB 0

ErrDrive:	DEFM "ERROR: Drive No out of range:"
		DEFB 0
	
	
;Now we include the code that runs in main memory after being copied there.	
MCATMAIN:
	BINARY	"mcatmain.bin"
MCATMEND:

