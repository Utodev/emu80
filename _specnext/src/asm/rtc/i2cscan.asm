;
; TBBlue / ZX Spectrum Next project
; Copyright (c) 2010-2018 
;
; RTC I2CSCAN - Victor Trucco and Tim Gilberts
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
; .I2CSCAN for ESXDOS
;
; V1 by Tim Gilberts
; based on I2C code for RTC by Victor Trucco, Fabio Belavenuto and Velesoft (I think)

	org 0x2000

	
	defc PORT = 0x3B
	defc PORT_CLOCK = 0x10 			;0x103b
	defc PORT_DATA = 0x11 			;0x113b

  
MAIN:
	
	ld a,h
	or l
	JP z,READ_I2C_NODEBUG  		;if we dont have parameters it is a read command

	LD A,(HL)

	CP '-'				;options flag missing
	JR NZ,end_error
	
	INC HL
	LD A,(HL)
;	CP 'd'
;	JP Z,DO_OPTION_D

end_error:
	LD HL, MsgUsage
	CALL print	

	ret


;---------------------------------------------------
; This uses the strategy of https://playground.arduino.cc/Main/I2cScanner
; which in turn uses the arduino Wire library to see if a device acknowledges 
; the address... 
; .... this may be useful in the time and date commands as well
; RTC.SYS is tight to do much but, may remove need for Signature system
; and allow faster return if no RTC? 

READ_I2C_NODEBUG:

	LD HL,1			;Device 0 is broadcast so ignore (H=count)
	

SCAN_DEVICE:					
	;---------------------------------------------------
	; Talk to Devices

	PUSH HL
	
	DI

	call START_SEQUENCE	;Get all devices attention
	
	DEFB $CB,$35 ;SLL L 	(faulty instruction places 1 into BIT 0 which means Read for us)
;	SLA L			;Temp do a write as above does not work on Next

	CALL SEND_DATA
	JR C,NO_ACK

	CALL STOP_SEQUENCE	;Release device and bus quickly

	EI

	LD HL,device_found
	CALL print		;Print string we had
	
	POP HL			;Recall device no we were scanning
	PUSH HL

	CALL prt_hex_l
	CALL print_newline
	
	POP HL
	INC H			;No of devices found

	JR NEXT_DEV

NO_ACK:
	
	CALL STOP_SEQUENCE
	
	EI
	
	POP HL

NEXT_DEV:
	INC L
	LD A,L
	CP 128				;120-127 'reserved for expansion' look anyway!
	JR NZ, SCAN_DEVICE

	LD L,H
	LD H,0
	CALL prt_dec
	
	LD HL,countof_found
	CALL print

	RET


;-----------------------------------------------------------------------------------------

SEND_DATA:

	;8 bits
	ld h,8				;7
	
SEND_DATA_LOOP:	
	
	;next bit
	RLC L				;8
		
	ld a,L				;4			;Could use RLA for lower bit set only same speed / size if we knew it was zero
	CALL SDA			;17 + xxx
	
	;This is only just enough at 3.5 MHz and creates a poor if fast clock interval so the 
	;edge detection is probably broken - lengthened to same as data write	
	call PULSE_CLOCK		;17 + xxx	
		
	dec h				;4
	jr nz, SEND_DATA_LOOP		;12 or 7
	
WAIT_ACK:

	;free the line to wait the ACK
	CALL SDA1			;17 + xxx
	
	;but it did not wait for the ack it just pulsed the clock...
;	JR PULSE_CLOCK			;12
	;so we now do the same but, check for an ACK coming back!
	;http://www.gammon.com.au/forum/?id=10896 useful to see the timing diagrams
	CALL SCL1			;17	;17 + 

	LD HL,4				;loop for a short while looking for the ACK
	
WAIT_ACK_LOOP:
	LD B,PORT_DATA			;7
	IN A,(C)			;12
	RRCA
	JR C,LINE_HIGH			
	
	INC H				;Something on the bus pulled SDA low - count how long
	
LINE_HIGH:
	DEC L
	JR NZ,WAIT_ACK_LOOP

;	CALL SCL0
;	SCF				;Flag we did not get an ACK
;	RET

;GOT_ACK:;
	CALL SCL0			;If stitched back into RTC etc could be a JP to save a byte this will CCF due to XOR A

	LD A,H
	SUB 2				;Carry will be set if we did not receive at least duration 2 of pulse.

	RET
;

;This reads a byte from the bus, it does not send an ACK or NACK calling code must do that.
;It is dumped directly into the memory pointed at by HL

READ:

;	free the data line
	CALL SDA1			;17 + xxx
	
; lets read 8 bits
	ld D,8				;7
			
READ_LOOP:
	
	;clock is high
	CALL SCL1			;17 + xxx

;*** TODO consider delay here before clock transition to allow data to settle
;
	
	;read the bit
	ld b,PORT_DATA			;7
	in a,(c)			;12

	RRCA				;4
	RL (HL)				;15

;*** TODO consider delay here before clock transition
	
	;clock is low
	CALL SCL0			;17 + xxx
	
	dec d				;4
	
	;go to next bit
	jr nz, READ_LOOP		;12 or 7
	
	;finish the byte read
	ret				;10
	
;Pretty self explanitary pair - note that A must be set to 1 before jump to SEND_ACK_NACK
SEND_ACK:
	
	xor a  				;4
	
SEND_ACK_NACK:

	CALL SDA			;17 + xxx
	
	call PULSE_CLOCK		;17 + xxx
	
;	free the data line
	JR SDA1				;12

;--This is main entrance to become BUS master...

START_SEQUENCE:	

;high in both i2c, before begin - i.e. ensures a stop state is present on the bus.  Sets C to IO PORT as well
	
	ld a,1				;7	;Could save this by calling SCL1 not SCL...
	ld c, PORT			;7
	CALL SCL 			;17 + xxx
	CALL SDA			;17 + xxx  The data line should transition as soon as poss after clock 

;*** POSS at >3.5Mhz this delay is not long enough...?

	;high to low when clock is high
	CALL SDA0			;17 + 29 = 46 which is 13.2 uSec + the 4.6/5.7 after 

	JR SCL				;12

;-- Basic bit manipulation A=0 or 1 then call SDA for data and SCL for clock state.
;
;Timings based on 1 T State = 1 uSec @ 1Mhz for a Z80 so 1 T State = 0.285714286 uSec at 3.5Mhz (0.286)
;Assumption is transition happens half way through 12 T States of OUT...  Rise and Fall times will be hardware specific.
;this assumption implied state held or present for 1.714 uSec in the OUT command alone.
;It is more likely as OUT is a 2 byte instruction that the transition occurs at T state 8 onwards...  
;if we change to that view then the state change has not been present very long on exit. (more research)
;Help from https://calcium3000.wordpress.com/2016/08/19/i2c-bit-banging-tutorial-part-i/

SDA0:						;Total = 4+25 = 29 = 8.3uSec
	xor a 				;4
	jr SDA				;12
SDA1: 						;Total = 7+25 = 32 = 9.2uSec
	ld a,1				;7
SDA: 						;Total = 7+12+6(?) = 25 = 7.15uSec to transition then 4.6/5.7 after 
	ld b,PORT_DATA			;7
	
;Note for space in RTC.SYS this jump to SCL0 is used but that means all data transitions have same delay as Clock
;***TODO allow varying of this somehow.  Maybe better to have clock delay transition by jumping here as a faster
;data transition is desirable after a clock change for stability
	JR SCLO				;12

PULSE_CLOCK:
	CALL SCL1			;17	;17 + 
	CALL SCL1				;Keep clock up for a while (1 less byte than 4 nops)

SCL0:						;Total = 4+12+7+6(?) to half way of OUT = 29 Tstates = 8.3uSec at 3.5Mhz - V 5.7uSec on way out V
	xor a 				;4
	jr SCL				;12
SCL1:						;Total = 7+7+6(?) to half way of OUT = 20 Tstates = 5.7uSec at 3.5Mhz, then 5.7uSec after
	ld a,1				;7
SCL:						;Total = 7+6(?) = 13 Tstates = 3.72uSec only 0.93 at 14Mhz then 5.7uSec after
	ld b,PORT_CLOCK			;7
SCLO:	OUT (c), a			;12	; After transition is 6+DELAY(4)+10 = 20 = 5.7uSec was 16= 4.6uSec without NOP

;***TODO Self modify code for delay after clock state change?  Could use upto 4 NOPS replaced with RET?
;This would be used to add wait states for slower data at 7Mhz and 14Mhz?  It maybe the PULSE CLOCK that needs to be lengthened

	NOP				;Wait 4 t states
	ret				;10


;---------------------------------------------------
; Write data to Device 

WRITE_VALUES:

	call START_SEQUENCE
	
	ld l,0xD0 		;Address of device required
	call SEND_DATA
	
	ld l,0x3E  		;Bytes to send in this case a register number for RTC
	call SEND_DATA
	
	ld hl,(VALUE1)
	call SEND_DATA
	
	ld hl,(VALUE2)
	call SEND_DATA

	ld hl,(VALUE3)
	call SEND_DATA

STOP_SEQUENCE:
	CALL SDA0
	CALL SCL1
	CALL SDA1
	
	RET
	

;------------------------------------------------------------------------------------
;Routines for number handling
	

CONVERT_HEX_DEC_DIGIT:
	LD a,(HL)
	;test ascii for 0 to 9
	CP 48
	JR C,CHAR_ERROR 
	
	CP 58				;This is a colon - why we need a string but in this case is just first char above 9...
	JR C,ONLY_0TO9
	
	CP 'A'
	JR C,CHAR_ERROR
	
	CP 'G'
	JR NC,CHAR_ERROR
	
	OR A
	SUB 'A'-10			;Offset for A 
	
ONLY_0TO9:	
	or a; clear the carry
	
	sub 48 ; convert asc to number
	
	OR A
	RET
	
DIGIT_ERROR:

	SCF
	RET


CONVERT_HEX_DEC:

	CALL CONVERT_HEX_DEC_DIGIT
	JR C,CHAR_ERROR

	LD b,a 		; store first digit in b
	add a,a
	add a,a
	add a,a
	add a,b
	add a,b		;*10

	; next parameter
	inc HL

	CALL CONVERT_HEX_DEC_DIGIT
	JR C,CHAR_ERROR
		
	or a; clear the carry
	ret	
	
	
	
CONVERT_DIGITS:
	LD a,(HL)
	;test ascii for 0 to 9
	CP 48
	jr C,CHAR_ERROR 
	
	CP 58				;This is a colon - why we need a string but in this case is just first char above 9...
	jr NC,CHAR_ERROR
	
	or a; clear the carry
	
	sub 48 ; convert asc to number

	;first digit in upper bits
	SLA A
	SLA A
	SLA A
	SLA A

	LD b,a ; store in b
	
	; next parameter
	inc HL
	LD a,(HL)
	
	;test ascii for 0 to 9
	CP 48
	jr C,CHAR_ERROR 
	
	CP 58
	jr NC,CHAR_ERROR
	
	sub 48 ; convert asc to number

	and 0x0f ; get just the lower bits
	or b ;combine with first digit
	
	or a; clear the carry
	ret
	
	
CHAR_ERROR:
	
	scf ; set the carry
	ret


	


NUMBER_TO_ASC:
	LD a,(HL)
	
	; get just the upper bits
	SRA A
	SRA A
	SRA A
	SRA A 
	add 48 ;convert number to ASCII
	LD b,a
	
	;now the lower bits
	LD a,(HL)
	and 0x0f ;just the lower bits
	add 48 ;convert number to ASCII
	LD c,a
	
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

prt_hex_l:
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


;End of test harness	
	

device_found: 	defm "I2C device found at address 0x"
		defb 0

countof_found:	defm " device(s) found on I2C bus"
		defb 13,13,0
	
MsgUsage: 	defm "USAGE: i2cscan v0.1: ",13
	  	defm "i2cscan <ENTER>"
	  	defb 13
	  	defm "Show devices on bus."
endmsg:		defb 13
newline:	defb 13,0


VALUE1:		defb 0		
VALUE2:		defb 0	
VALUE3:		defb 0	

