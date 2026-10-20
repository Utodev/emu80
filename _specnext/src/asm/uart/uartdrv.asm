; TBBlue / ZX Spectrum Next project
; Copyright (c) 2010-2018
;
; UART.DRV Victor Trucco, Garry Lancaster and Tim Gilberts
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
; File version 2.4
;
; This file is the 512-byte NextOS driver itself, plus relocation table.
;
; Assemble with: pasmo uartdrv.asm uartdrv.bin uartdrv.sym
;
; After this, uart_drv.asm needs to be built to generate the actual
; driver file.
;
; At the moment it requires the 16K of bank of memory at C000 to FFFF to be
; available to bank to a known page before calling setup as part of the open
; this will eventually form part of the install process.


; ***************************************************************************
; * Entry points                                                            *
; ***************************************************************************
; Drivers are a fixed length of 512 bytes (although can have external 8K
; banks allocated to them if required).
;
; They are always assembled at origin $0000 and relocated at installation time
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
; If you do switch any banks, don't forget to restore the previous MMU setting
; afterwards.

;
TX_CHKREADY	EQU	4923	;133Bh Write is byte to send, when read status
					;0x01 = RX_AVAIL (1 = data to collect)
					;0x02 - TX_READY (1 = still transmit)
					;0x04 - UART FULL (1 if buffer full)
RX_SETBAUD	EQU	5179	;143Bh Read is byte received, when written set
				;the BAUD rate which is written as two bytes
				;forming a 14bit prescale value
				;First byte Bit 7=0 contains LSBits0-6,
				;2nd BIT7=1 contains MSBits 14-7

; Makes use of the following to save and load MMU registers
; Slot 6 and Slot 7 C000-FFFF

;   nextreg reg,val   ED 91 reg,val   16Ts  Set a NEXT register (like doing out
;   ($243b),reg then out($253b),val )
;   nextreg reg,a     ED 92 reg       12Ts  Set a NEXT register using A (like 
;   doing out($243b),reg then out($253b),A )

; ***************************************************************************
; * Entry points                                                            *
; ***************************************************************************

WRITE_BUFFER	EQU	$C000
	
        org     $0000

; At $0000 is the entry point for API calls directed to your driver.
; B,DE,HL are available as entry parameters.

api_entry:
        jr      uart_api
 
flags:					;Bit 2 = UART FULL error state,
					;Bit 4/3=1 stop speaker clicks
	defb	%10011000		;Bit 1 = 16K buffer full error state, 
					;Bit 7 - we are disabled
 
 ;       nop				;Was a wasted Space - now our flags!

; At $0003 is the entry point for the interrupt handler. This will only be
; called if bit 7 of the driver id byte has been set in your .DRV file, so
; need not be implemented otherwise.

im1_entry:

;IF BYTE(S) AVAILABLE
;    STORE ERROR STATE IF UART FULL FLAG SET
;    SAVE MMU STATE
;    BANK IN BUFFER PAGE
;    DRAIN UART FIFO BUFFER to CURRENT READ BUFFER
;    Timeout if no more data for a short period...
;ELSE RETURN
	
	LD BC,TX_CHKREADY		;133Bh service routine faster if no data
	IN A,(C)
	BIT 0,A				;Check status but don't damage A
	RET Z				;Return from IRQ if no data in fifo

;SAVE UART FULL - Note this flag must stay set until acknowledged from BASIC
im_reloc_0:
	LD HL,flags
	AND %00000100			;UART was full.
	OR (HL)
	LD (HL),A
			
;Check if we are disabled (BIT 7 of flags set) - this is done so we do not 
;write data to Page 0 without Authorisation. OR (HL) will set Sign Flag so M set
	RET M

im_reloc_1:
	CALL PAGES_IN			;Bring in our pages

im_reloc_2:		
	LD HL,(input_add)		;Get current buffer write address

GET_BYTE:
	LD BC,RX_SETBAUD		;143Bh - RX_SETBAUD
	IN A,(C)
	
	LD (HL),A
	INC HL				;If next storage add zero then wrap.
	LD A,H
	OR L
	JR NZ,NO_WRAP
	
	LD H,WRITE_BUFFER>>8			;Wrap around			

NO_WRAP:
;Now see if our next write is to the same as our read address
;(i.e. we have filled our 16K buffer)
im_reloc_3:
	LD DE,(output_add)
	
	LD A,D
	CP H
	JR NZ,GET_BYTE_CHKTIMEOUT
	LD A,E
	CP L
	JR NZ,GET_BYTE_CHKTIMEOUT

;flag to driver that we are now dropping characters and it isn't the UART's 
;fault. Bit 1 is set in flags.

im_reloc_4:
	LD HL,flags
	LD A,(HL)
	OR  %00000010			;Make sure SW buffer full bit is set
	LD (HL),A
	
	JR PAGES_OUT			;Just keep overwrting the last byte
					;But stop draining the UART
					;so software gets time to run
	
GET_BYTE_CHKTIMEOUT:	
	LD DE,256			;Allow setting of Receive timeout,
timeout_receive equ $-2

	LD BC,TX_CHKREADY
GET_BYTE_CTLOOP:
	IN A,(C)
	BIT 0,A
	JR NZ,GET_BYTE

	DEC DE
	LD A,E
	OR D
	JR NZ,GET_BYTE_CTLOOP		;Timout not error, just stop looking.

im_reloc_5:
	LD (input_add),HL

PAGES_OUT:
	DEFB $ED,$91,$56,$00		;NEXTREG r,n ED 91 reg,val
;(By default pages back in Zero, old one saved here)
saved_mmu6 equ $-1
	DEFB $ED,$91,$57,$01		
saved_mmu7 equ $-1
	OR A				;No errors - needed when used from API
	RET



	
; ***************************************************************************
; * API for UART                                                            *
; ***************************************************************************
; On entry, use B=call id with HL,DE other parameters.
; (NOTE: HL will contain the value that was either provided in HL (when called
;        from dot commands) or IX (when called from a standard program).
;
; When called from the DRIVER command, DE is the first input and HL is the 
; second.
;
; When returning values, the DRIVER command will place the contents of BC into
; the first return variable, then DE and then HL.

; Note this is a hybrid driver that supports the standard DRIVER command and use
; through streams API (see later) - the difference is these direct calls return
; actual Memory addresses and clear error status flags, wheras the stream
; returns offsets and does not affect error flags.

uart_api:
        bit     7,b                     ; check if B>=$80
reloc_1: 
        jp      nz,channel_api          ; on if so, for standard channel API

;-----
; B=1: Set Baud rate / prescaler DE {HL}, returns used prescaler value in BC, 
; If DE is <15 then set prescaler to that - if 255 then use second value.
; Actually uses it if it is not a valid one...

        djnz    bnot1                   ; On if B<>1

	ld	a,d			; DE must be a low value
	or	a
	jr	nz,exit_invalid_io

	ld	a,e
	cp	4
	jr	nc,Use_HL_prescale
	
	SLA A		; *2		; D must already be 0
	SLA A		; *4		; SWAPNIB would be better here?
	SLA A		; *8
	SLA A		; *16
	LD E,A
reloc_1a:		
	LD HL,BaudPrescale	; HL now points at the BAUD to use.
	ADD HL,DE

	LD BC,9275	;$243B Now adjust for the set Video timing.
;	IN A,(C)			;Save current registry state
;reloc_1b:
;	LD (saved_reg),A	;Probably not needed here but just in case
	LD A,17		
	OUT (C),A
	INC B		;$253B
	IN A,(C)	;get timing adjustment
	LD E,A
;	DEC B		;Saves space not saving registry on this call
;reloc_1c:
;	CALL reset_registry
	RLC E		;*2 guaranteed as <127
;	LD D,0		;D still zero from earler.
	ADD HL,DE

	LD E,(HL)
	INC HL
	LD D,(HL)
	EX DE,HL

Use_HL_prescale:
	PUSH HL		; This is prescaler
	PUSH AF		; and value
				
	LD BC,RX_SETBAUD
	LD A,L
	AND %01111111	; Res BIT 7 to request write to lower 7 bits
	OUT (C),A
	LD A,H
	RL L		; Bit 7 in Carry
	RLA		; Now in Bit 0
	OR %10000000	; Set MSB to request write to upper 7 bits
	OUT (C),A

	POP AF		; Recall timing adjustment used
	POP BC		; and calculated prescaler.

	LD E,A		; Second return is timing value.
	LD D,0

	OR A
	RET


;-----
; B=2: get values including flags C=Flag status
; (BIT 2 = UART was filled. BIT 1 = BUFFER was filled)
; DE and HL are input and output positions on the UART read buffer.

bnot1:
        djnz    bnot2                   ; On if B<>2

reloc_2:
        ld      a,(flags)		; C only really needed
        and	%00000111		; Ignore all other flags just return
        ld 	c,a
        ld	b,0
reloc_3:
        ld      de,(input_add)
reloc_4:
        ld      hl,(output_add)
        jr	back_to_black

;-----
; B=3: set values of input and output buffer directly (also resets the flags)

bnot2:
	djnz	bnot3

reloc_5:
        ld      (input_add),de
reloc_6:
        ld      (output_add),hl

back_to_black:
        xor     a                       ; clear carry to indicate success

reloc_7:
	ld	(flags),a		; and reset flags.
	ret
	
;-----	
;4 set RX/TX timeout - allow people to wait for variable periods for send.

bnot3:
	djnz	bnot4

reloc_7a:
        ld      (timeout_receive),de
reloc_7b:
        ld      (timeout_send),hl
        or	a
        ret

;------
;5 set available memory pages to use - ignores upper values of MSB
;Now converts a 16K BASIC BANK to 8K pages 

bnot4:
	djnz	bnot5
	
	ld	a,e
	rlca
reloc_7c:
	ld	(new_mmu6),A
	inc	a
reloc_7d:
	ld	(new_mmu7),A
		
	or	a
	ret


exit_invalid_io:
	ld	a,$fe			; Invalid I/O device	
	jr 	exit_error

; ***************************************************************************
; * Validate handle for our simple channel                                  *
; ***************************************************************************

validate_handle:
        dec     d                       ; D should have been 1
        ret     z                       ; return if so
        pop     af                      ; otherwise discard return address

bnot5:	
api_error:
        xor     a                       ; A=0, unsupported call id
exit_error:
        scf                             ; Fc=1, signals error
        ret

; ***************************************************************************
; * Standard channel API                                                    *
; ***************************************************************************
; If you want your device driver to support standard channels for i/o, you
; can do so using the following API calls.
; Each call is optional - just return with carry set and A=0
; for any calls that you don't want to provide.
;
; B=$f9: open channel
; B=$fa: close channel
; B=$fb: output character		; Only one char at a time at the moment 
;***TODO small letterbox transmit
; B=$fc: input character
; B=$fd: get current stream pointer	; This affects the input buffer readout
; B=$fe: set current stream pointer	; so can be used for block transfer out
; ***TODO NB if attempt to SET to zero then it causes a transmit buffer flush.
; B=$ff: get stream size/extent

channel_api:
        ld      a,b
        sub     $f9                     ; set zero flag if call $f9 (open)
        jr      c,api_error             ; exit if invalid ($80..$f8)
        ld      b,a                     ; B=0..6
        jr      nz,bnotf9               ; on if not $f9 (open)


; B=$f9: open channel
; In the documentation for your driver you should describe how it should be
; opened. The command used will determine the input parameters provided to
; this call (this example assumes your driver id is ASCII 'X', ie $58):
; OPEN #n,"D>X"         ; simple open: HL=DE=0
; OPEN #n,"D>X>string"  ; open with string: HL=address, DE=length
;                       ; NOTE: be sure to check for zero-length strings
; OPEN #n,"D>X,p1,p2"   ; open with numbers: DE=p1, HL=p2 (zeros if notprovided)
;
; In this case for the UART:
;
; OPEN #n,"D>U"

; This call returns a unique channel handle in A. This allows a driver
; to support multiple different concurrent channels if desired although that
; is not relevant with the UART as there is only one.
; The ESP will support several streams
;
; If you return with any error (carry set), "Invalid filename" will be reported
; and no stream will be opened.
;
; For this example, we will simply check that no other channels have yet been
; opened:

reloc_8:
        ld      a,(chanopen_flag)
        and     a
        jr      nz,api_error            ; exit with error if already open
        ld      a,1
reloc_9:
        ld      (chanopen_flag),a       ; signal "channel open"

	or	a			; Clear carry
        ret                             ; exit with carry reset (from AND above)
                                        ; and A=handle=1


; B=$fa: close channel
; This call is entered with D=handle, and should close the channel
; If it cannot be closed for some reason, exit with an error (this will be
; reported as "In use").

bnotf9:
        djnz    bnotfa                  ; on if not call $fa
reloc_10:
        call    validate_handle         ; check D is our handle (does not return
                                        ; if invalid)
        xor     a
reloc_11:
        ld      (chanopen_flag),a       ; signal "channel closed"
        ret                             ; exit with carry reset (from XOR)


; B=$fb: output character
; This call is entered with D=handle and E=character.
; If you return with carry set and A=$fe, the error "End of file" will be
; reported. If you return with carry set and A<$fe, the error
; "Invalid I/O device" will be reported.
; Do not return with A=$ff and carry set; this will be treated as a successful
; call.
;
; **TODO we can add a small output buffer to prevent any blocking then
; use the End of file error return if it is filled before transmission.
; This will have to be added to the IRQ routine for transmission 

bnotfa:
        djnz    bnotfb                  ; on if not call $fb
reloc_12:
        call    validate_handle         ; check D is our handle (does not return
                                        ; if invalid)       
reloc_13:
        call	tx_char			; Send character in E
        ret 	nc
       	ld	a,1			; Trigger an Invalid I/O dev on timeouts
        
        ret                             ; exit with carry set (return from call)


; B=$fc: input character
; This call is entered with D=handle.
; You should return the character in A (with carry reset).
; If no character is currently available, return with A=$ff and carry set.
; This will cause INPUT # or NEXT # to continue calling until a character
; is available.
; If you return with carry set and A=$fe, the error "End of file" will be
; reported. If you return with carry set and any other value of A, the error
; "Invalid I/O device" will be reported.

bnotfb:
        djnz    bnotfc                  ; on if not call $fc
reloc_14:
        call    validate_handle         ; check D is our handle (does not return
                                        ; if invalid)

reloc_15:
	call	PAGES_IN	

reloc_17:
        ld      hl,(output_add)
reloc_18:
        ld	de,(input_add)
	ld	a,h
	cp	d
	jr	nz,notsame
	ld	a,l
	cp	e
	jr	nz,notsame

	ld	a,255
	scf
	ret

notsame:
	ld	e,(hl)
	inc	hl
	ld	a,h
	or	l
	jr	nz,no_wrap_out

	ld	h,WRITE_BUFFER>>8	; Reset to start of buffer

no_wrap_out:
reloc_19:
        ld      (output_add),hl          ; update pointer

        ld      a,e                     ; A=character

reloc_20:
	jp	PAGES_OUT

; B=$fd: get current stream pointer
; This call is entered with D=handle.
; You should return the pointer in DEHL (with carry reset).
; This can be used with RETURN #n TO var I assume... 
; This will always return 0/Carry set as we are always at the start

bnotfc:
        djnz    bnotfd                  ; on if not call $fd

        xor	a
	scf
        ret


; B=$fe: set current stream pointer
; This call is entered with D=handle and IXHL=pointer.
; Exit with A=$fe and carry set if the pointer is invalid (will result in
; an "end of file" error).
; NOTE: Normally you should not use IX as an input parameter, as it cannot
;       be set differently to HL if calling via the esxDOS-compatible API.
;       This call is a special case that is only made by NextOS.
; This can be used with "GOTO #n,m" I assume.
; This can be used to ADD x bytes to the stream to bulk skip over incoming
; data - it cannot be used to rewind the stream, error if x is > extent

bnotfd:
        djnz    bnotfe                  ; on if not call $fe


reloc_21:
        call    validate_handle         ; check D is our handle (does not return
                                        ; if invalid)
	xor	a
        or      ixl			; Discard any obviously too big
        or      ixh
        scf
        ret	nz
        ld	c,l
        ld	b,h
        
reloc_22:
	call	output_size		; Get the current absolute size	
        or	a                       ; check if pointer > extent
	sbc	hl,bc			; Carry will be set if so
	ld      a,$fe
        ret     c                       ; exit with A=$fe and carry set if so

reloc_23:
        ld      hl,(output_add)		; OK so lets adjust the pointer
	add	hl,bc
	jr	nc,all_done

	ld	bc,WRITE_BUFFER		; If we wrapped around
	add	hl,bc			; then set base address again

all_done:
reloc_24:
        ld      (output_add),hl         ; set the pointer
        and     a                       ; reset carry (successful call)
        ret


;------
; B=$ff: get stream size/extent
; This call is entered with D=handle
; You should return the size/extent in DEHL (with carry reset).
; This can be used with "DIM #n TO var" I assume.

bnotfe:
reloc_25:
        call    validate_handle         ; check D is our handle (does not return
                                        ; if invalid)

output_size:				; Used as a subroutine to get abs buffer size in HL
reloc_26:
        ld      hl,(output_add)
reloc_27:
        ld	de,(input_add)       
        or	a			; Clear carry
        sbc	hl,de
    	xor	a			; Clear Carry and flags
    	ld	e,a			; Never extend >65535 anyway.
    	ld	d,a
    	bit	7,h			; Trick for ABS HL from http://z80-heaven.wikidot.com/math
    	ret	z			; Carry clear
	sub	l			; A was zero from xor above
	ld	l,a
	sbc	a,a
	sub	h
	ld	h,a	
        and     a                       ; reset carry (successful call)
        ret


;-------------------------------
;Send character in E to UART
;Returns with C set if timeout

tx_char:
	LD HL,1024		;Delay timeout
timeout_send equ $-2
									
	LD BC,TX_CHKREADY
char_out_wait:
	IN A,(C)

	BIT 1,A
	JR Z,char_out_ready
							
	DEC HL
	LD A,H
	OR L
	JR NZ,char_out_wait
	
	SCF			;Return an error.
	RET
			
char_out_ready:
	LD A,E
	OUT (C),A
			
	XOR A			;Zero flag set and Carry reset
	RET

;-------------------------------
PAGES_IN:
;PAGE IN Correct Buffer page....
	LD BC,9275			;$243B Need to Save MMU registers
	IN A,(C)			;Save current registry state
sub_reloc_1:
	LD (saved_reg),A
	LD A,$56
	OUT (C),A
	INC B
;	LD BC,9531			;$253B
	IN A,(C)	
sub_reloc_2:
	LD (saved_mmu6),A
	LD A,0		
new_mmu6 equ $-1
	OUT (C),A			;New 8K bank					
	DEC B				;$243B
	LD A,$57
	OUT (C),A
	INC B				;$253B
	IN A,(C)
sub_reloc_3:
	LD (saved_mmu7),A			
	LD A,1
new_mmu7 equ $-1
	OUT (C),A
	DEC B				;$243B Need to Save MMU registers		
;reset_registry:
	LD A,2
saved_reg equ $-1	
	OUT (C),A		;just in case IRQ was in between registry work 
	RET

; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

chanopen_flag:
        defb    0
     
input_add:
	defw	WRITE_BUFFER
;Note we could house a small output buffer at bottom if needed.
	
output_add:
	defw	WRITE_BUFFER			;Nothing in buffer as yet


; Due to space limitations only the most common values are included
; built in which work with the ESP.
BaudPrescale:
	DEFW 2917,2976,3069,3125,3229,3333,3438,2813 	; 9600 (0)
;WAS	DEFW 1458,1488,1535,1563,1615,1667,1719,1406 	; 19200 (1)
	DEFW 14,14,15,15,16,16,17,14			; 2000000 (1)
	DEFW 243,248,256,260,269,278,286,234 		; 115200 (2)

		
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
	defw	im_reloc_0+2
        defw    im_reloc_1+2
        defw	im_reloc_2+2
        defw	im_reloc_3+3
        defw	im_reloc_4+2
        defw	im_reloc_5+2

        
	defw	reloc_1+2
	defw	reloc_1a+2	
        defw    reloc_2+2
        defw    reloc_3+3
        defw    reloc_4+2
        defw    reloc_5+3
        defw    reloc_6+2
        defw    reloc_7+2
        defw    reloc_7a+3
        defw    reloc_7b+2
        defw    reloc_7c+2
        defw    reloc_7d+2
        defw    reloc_8+2
        defw    reloc_9+2
        defw    reloc_10+2
        defw    reloc_11+2
        defw    reloc_12+2
        defw    reloc_13+2
        defw    reloc_14+2
        defw    reloc_15+2
;        defw    reloc_16+2
        defw    reloc_17+2
        defw    reloc_18+3        
        defw    reloc_19+2
        defw    reloc_20+2
        defw    reloc_21+2
        defw	reloc_22+2
        defw    reloc_23+2
        defw    reloc_24+2
        defw    reloc_25+2
        defw    reloc_26+2
        defw    reloc_27+3

        defw	sub_reloc_1+2
        defw	sub_reloc_2+2
        defw	sub_reloc_3+2

reloc_end:

;01234567890123456789012345678901
;abcdefghijklmnopqrstuvwxyzABCDEF
;FEDCBAzyxwvutsrqponmlkjihgfedcba


