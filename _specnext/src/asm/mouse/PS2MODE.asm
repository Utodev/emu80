;
; TBBlue / ZX Spectrum Next project
; Copyright (c) 2010-2018
;
; PS2MODE - Tim Gilberts and Victor Trucco
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
;This program PS2MODE to allow you to switch bewteen Keyboard and Mouse on
;ZX Next is by Tim Gilberts after an idea by Rob Uttley, uses code from other
;dot commands on the project so above copyright message stands.
;
;If you are using a splitter you do not need to do this - just using a mouse
;on the PS2 port with a cased Next or Board using a membrane you will!
;
;V1.0 17/12/2017
;V1.1 30/07/2018 

	ORG 2000h

	ld a,h
	or l
	JP z,PRINT_STATUS  ;if we dont have parameters it is a read command

	LD A,(HL)

	CP '-'		;if not options flag then error message
	JR NZ,end_error
	
	INC HL

	LD A,(HL)

;	CP 'h'
;	JR Z,end_error	;asked for help

	CP 'm'
	JR Z,SET_MOUSE
	
	CP 'k'
	JR Z,SET_KEYBOARD
		
	JP end_error		;anything else is help
	

SET_MOUSE:

	DI
	LD A,6 			; select reg 6
	LD BC,9275
	OUT (C), A


	LD BC, 9531
	IN a,(C)
	OR @00000100		;Toggle Mouse keyboard Bit to Mouse mode

	OUT (C), A

	JR PRINT_STATUS

SET_KEYBOARD:
	DI
	LD A,6 			;select reg 6
	LD BC,9275
	OUT (C), A

	NOP
	NOP
	NOP


	LD BC, 9531
	IN A,(C)
	AND @11111011		;Toggle Mouse keyboard Bit to KB mode

	OUT (C), A


PRINT_STATUS:
	LD A,6 			;select reg 6
	LD BC,9275
	OUT (C), A

	NOP
	NOP
	NOP

	LD BC, 9531
	IN A,(C)
	EI

	RRA
	RRA
	RRA			; bit 2 = PS/2 mode (0 = keyboard, 1 = mouse)(Reset to 0 after a PoR or Hard-reset)
	LD HL,Keyboard
	JR NC,Keyboard_mode
	LD HL,Mouse	

Keyboard_mode:
	PUSH HL
	LD HL,Current
	CALL PrintMsg
	POP HL
	JR end_message

	;return to basic with an error message
end_error:
	LD HL, MsgUsage

end_message:
	CALL PrintMsg	
	ret
		
	
;----------------------------- 
print_regs:

			push BC
			push DE
		
			ld HL, str_DE
			call print
			pop hl
			call prt_hex_16
			call print_newline
			
			ld HL, str_BC
			call print
			pop hl
			call prt_hex_16
			
			call print_newline
			
			ret

			
;---------------------------------------------		

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


str_DE:		DEFM "DE  : "
		DEFB 0
str_BC:		DEFM "BC  : "
		DEFB 0
str_REG:	DEFM "RTC : "
		DEFB 0

newline:	DEFB 13,0	
	


PrintMsg:        
	ld a,(hl)
	or a
	ret z
	rst 10h
	inc hl
	jr PrintMsg
	
Current: defm "The mode is "
	 defb 0

Keyboard: defm "Keyboard."
	defb 13,13,0
	  
Mouse:	defm "Mouse."
	defb 13,13,0


MsgUsage: defm "PS2MODE V1.0 usage: ",13
	  defm "ps2mode<ENTER>"
	  defb 13
	  defm "show current mode"
	  defb 13,13
	  defm "ps2mode -m <ENTER>"
	  defb 13
	  defm "set the PS2 port to MOUSE"
	  defb 13,13
	  defm "ps2mode -k <ENTER>"
	  defb 13
	  defm "set the PS2 port to KEYBOARD"
	  defb 13,13
	  defb 0
