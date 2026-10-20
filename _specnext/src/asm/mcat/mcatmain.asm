;LSTON 
;DOTJAM June 2022 Microdrive Memory Resident code
;adapted from ;Professional Adventure Writer 128K
;Microdrive Handler (C) Phil Wade, May 1987
;
;Version 01
;LSTOFF 

		ORG	61440 ;49152		; Now on a page boundary so we can use in DOT
	
;Define Spectrum operating system calls
	
INCLUDE "specsys.asm"

DEFC	CR     =  13

DEFC	PRINT  =  2
DEFC	RECFLG =  67

DEFC	WAIT_K =  15D4h
DEFC	MAKE_S =  1655h

;DEFC	STRMS  =  5C16h
DEFC	ERR_NR =  5C3Ah
DEFC	CHANS  =  5C4Fh
;DEFC	PROG   =  5C53h

DEFC	D_STR1 =  5CD6h
DEFC	S_STR1 =  5CD8h
DEFC	N_STR1 =  5CDAh
DEFC	T_STR1 =  5CDCh
DEFC	HD_00  =  5CE6h
DEFC	HD_0B  =  5CE7h
DEFC	HD_0D  =  5CE9h
DEFC	HD_0F  =  5CEBh
;DEFC	HD_11  =  5CEDh

DEFC	OPEN_M =  22h
DEFC	CLOSE_M =  23h
DEFC	NEWVARS =  31h
DEFC	SHADOW =  32h



;Save/Verify or Load a block - details as tape header at IX.
;Also used as entry point to request a catalogue with TADDR_lo=3

;relocated from the end so the calling code can patch it easily.
		JR	DISCLS
	
DATDEV:	DEFB	'3'
DRIVEN:	DEFW	3
		
HMSAFE:	DEFB	3		;Buffer for Header
		DEFM	"012345678"
SAFENX:	DEFM	'9'
		DEFW	0,0,0

;Function required

DISPATCH:	DEFB	3

;various stores for System Variable and Register values
	
STK_SV:	DEFW	0		;original value of SP
ERR_ST:	DEFW	0		;your value for ERRSP
STK_ST:	DEFW	0		;value of SP after error

;Needed for HiSoft EXT Cat

POINTE: 	DEFS 2


DISCLS:	DI			; This is done in EDSLVH but, just in case

		PUSH	IX
		PUSH	HL
		PUSH	DE
		PUSH	BC
		EXX
		PUSH	HL
		PUSH	DE
		PUSH	BC
		EXX
		
		LD	BC,9275	; Disable all the SD card handling stuff
		LD	A,135
		OUT	(C),A
;		LD BC,9531 - 
		INC	B
		LD	A,246
		OUT	(C),A	
		
		DEC	B		;Enable the BUS
		LD	A,128
		OUT	(C),A 
		INC	B
		LD	A,128
		OUT	(C),A
			
		CALL	INITROM	;Setup to ensure correct ROM points

		LD 	A,4		;Green border as all OK
		OUT 	(254),A

		LD	A,(DATDEV)	;Set current drive
		SUB	'0'		;Convert to real numbers
		LD	(DRIVEN),A
		
;		CALL	MOVHED		;Move header info to 'safe' memory

		LD	IX,HMSAFE	;We are not currently passed anything
		LD	L,(IX+$0B)
		LD	H,(IX+$0C)
		LD	C,(IX+$0D)
;		LD	C,3		;Force a CAT at the moment
		LD	B,(IX+$0E)
		CALL	EDSLVH		;Do function

		LD 	A,5		;Cyan border as we have returned from sub
		OUT 	(254),A

		LD	BC,9275	; Re-enable all the SD card handling stuff
		LD	A,135
		OUT	(C),A
		INC	B
		LD	A,255
		OUT	(C),A	

		DEC	B		;Enable the BUS (caller has handled hardware)
		LD	A,128
		OUT	(C),A
		INC	B
		XOR	A		;Zero to disable bus
		OUT	(C),A
;****Arghhhh		OUT	(128),A
		
		EXX
		POP	BC
		POP	DE
		POP	HL
		EXX		
		POP	BC
		POP	DE
		POP	HL
		POP	IX
	
		EI

		RET			;Our DOT command can be returned to.
		
;		JP	ROMSM		;Set minimum workspace as we return
	
;Phil's bit....
;On entry to this routine, there must be a "Tape Header" in the Workspace,
;to which IX points.  The extra System variables must already exist (BOOT
;should do this). Note that TADDR_lo=3 carries out a CAT
;After succesful Loading/Saving/Verifying, the routine will RETURN to the
;calling routine, ELSE, the appropriate error message will be printed and the
;main PAW error handler joined at a suitable place.
	
EDSLVH:	DI			;Interrupts off
		LD	A,(BANKM)	;Save current page as 128 error system 
		AND	$7		;(Cant use PAGENO as it may not exist!!!)
		PUSH	AF		;Sets Page 0 after an error
		PUSH	IX
		LD	(STK_SV),SP	;save stack pointer
		LD	HL,(ERRSP)	;save ERRSP
		LD	(ERR_ST),HL
	
		LD	HL,_ERROR	;HL=temporary error handler
		PUSH	HL		;put it on the stack
		LD	(ERRSP),SP	;point ERRSP at it
		SET	2,(IY+124)	;signal ERRSP has been changed
	
		LD	B,8		;now make room on the stack
MK_RM:		PUSH	HL		;for an interrupt to occur
		DJNZ	MK_RM		;and still be able to recover ERRNR after error
	
		LD	A,$FF
		LD	(ERRNR),A	;ensure errors cleared from ERRNR
	
		CALL	PAGOUT		;page-out 16K ROM, and use shadow ROM
	
;now set the necessary pointers
	
		LD	A,(IX+0)	;Copy filetype into
		LD	($5CE6),A	;HD_00
		LD	DE,11
		PUSH	IX
		POP	HL
		ADD	HL,DE		;HL is now pointing at length and start
		LD	DE,$5CE7	;DE=HD_0B
		LD	BC,4		;Copy the data
		LDIR
		LD	HL,($5CE7)	;Copy length into program length
		LD	($5CEB),HL
	
		LD	HL,$5CD9	;HL=L_STR1 (channel number)
		LD	(HL),$4D
	
		LD	HL,(DRIVEN)	;drive number
		LD	($5CD6),HL	;put drive no. into D_STR1
	
		LD	HL,$0A		;ten
		LD	($5CDA),HL	;length of name into N_STR1
	
		INC	IX		;IX points to name
		LD	($5CDC),IX	;T_STR1 holds address of name
		DEC	IX		;restore value of IX
	
		SET	7,(IY+$0A)	;NSPPC to flag "no jump"
		LD	HL,NONSNC	;Ensure a Nonsense in BASIC error
		LD	(CHADD),HL
NONSNC:	EI			;interrups back on
	
		LD	A,($5C74)	;get value of T_ADDR_lo
		CP	$00
		JR	Z,DR_SV		;if #00, then save
		CP	$01
		JR	Z,DR_LD		;if #01, then load
		CP	$02
		JR	NZ,DR_CAT	;If not #02 then a catalogue is required
	
		SET	7,(IY+124)	;flag "verify"
	
	DEFC POKE_L =	ASMPC+1		;poke this with address of shadow LOAD
LD_VFY:		CALL	$08B3		;will not come back here...
	
DR_SV:		SET	5,(IY+124)	;flag "save"
	DEFC POKE_S =	ASMPC+1		;poke this with address of shadow SAVE
		CALL	$1AC4		;will not come back here...
	
DR_LD:		SET	4,(IY+124)	;flag "load"
		JR	LD_VFY		;save a byte!
	
DR_CAT:
;***TODO We need to do the extended CAT stuff here...
		LD	A,(DISPATCH)
		CP	$04
		JP	Z,EXT_CAT
	
	DEFC POKE_C =	ASMPC+1	;Poked with address of shadow CATALOGUE
		CALL	$1C5E		;little way into the Shadow ROM cat
		
		CALL	$0700
			
		LD	HL,(ERR_ST)	;Back here so reset error system
		LD	(ERRSP),HL
		JR	NO_ERR		;Exit back to caller
	
;now the "error" handler, which is ALWAYS used
;Even a successful load/save/verify will come here.
	
_ERROR:	DI			;interrupts OFF

		LD 	A,1		;If we get back here then Blue...
		OUT 	(254),A

		LD	(IY+124),0	;clear FLAGS3
		LD	(STK_ST),SP	;store SP (to be picked up in HL)
		LD	A,(ERRNR)	;inspect "old" error number
		CP	$FF		;is it still #FF?
		JR	Z,NEW_ER	;if so, suspect a new error
	
OLD_ER:	LD	HL,(ERR_ST)	;restore PAW error handler
		LD	(ERRSP),HL
		EI			;interrupts ON
		CP	$14		;Break?
		JR	Z,BRK_ER
		CP	$0C		;Break?
		JR	Z,BRK_ER
		CP	$0B		;if 'Nonsense in Basic', all was OK!
		JR	NZ,SH_UNK	;if not, error unknown
	
;To get here, we must have been successful in our Save/Load/Vfy
;We now set the Zero flag to signify this success to the caller
	
NO_ERR:	XOR	A		;Set the Zero flag
		LD	SP,(STK_SV)	;original stack pointer from caller
		LD	(IY+0),$FF	;clear error
		POP	IX		;Recall IX
;		INC	(IX+10)	;Left over from PAW to make 9th char inc
		POP	AF		;Restore correct RAM page
		
		LD	A,6		;Set yellow
		OUT	(254),A

		RET
	
SH_UNK:	CALL	M_OFF		;turn off motors etc.,
		LD	L,22		;'Statement Lost' (too true!)
ERR_2:		JP	$55		;jump to PAW error handler via ROM
	
BRK_ER:	CALL	M_OFF		;turn off motors etc.,
		LD	L,12		;'BREAK'
		JR	ERR_2		;save one byte...
	
	DEFC PK_RCL =	ASMPC+1		;POKE THIS FROM BOOT (reclaim/motors)
M_OFF:		LD	HL,$17B7	;address of routine in shadow ROM
		LD	(HD_11),HL
		RST	$08
		DEFB	$32		;Call the shadow routine
		RET
	
;"New" errors (interface one) are tested here
	
NEW_ER:	LD	DE,$0081	;Test HL against #81
		AND	A
		SBC	HL,DE
		JR	NZ,SH_UNK	;if not, we appear to be lost...
		LD	DE,$003D	;use DE to compare, find this on stack
		LD	HL,(STK_ST)	;this is SP value after error
		LD	BC,(STKEND)	;we don't want to go this far down...
		JR	_LOOK2		;we start at the Hi-Byte
	
_LOOK:		DEC	HL		;move down old stack, one "pair"
_LOOK2:	DEC	HL		;come here to move down one more byte
		LD	A,B		;compare address/Hi with Stackend/Hi
		CP	H
		JR	NC,SH_UNK	;we've failed if this far down
		LD	A,(HL)		;A = Hi-byte of stack contents
		CP	D		;is it a #00 ?
		JR	NZ,_LOOK		;if not, inspect next "pair"
		DEC	HL
		LD	A,(HL)		;A = Lo-byte of stack contents
		CP	E		;is it #3D ?
		JR	NZ,_LOOK2	;if not, try next pair (one byte down)
		INC	HL		;we've found #003D
		INC	HL		;address is two bytes back up
		LD	E,(HL)		;transfer 8K ROM address to DE
		INC	HL
		LD	D,(HL)		;DE now equals 8K ROM address
		PUSH	DE		;save it
		CALL	PAGOUT		;page-out old ROM, 8K ROM in
		POP	DE		;get back the address
		LD	A,(DE)		;A = ERROR CODE from 8K ROM
		INC	A		;A = true error number
		CALL	$0700		;page-in old ROM

		CP	$18		;if bigger than #17 it's garbage
		JR	NC,SH_UNK	;we've failed...
	
		PUSH	AF		;stack the true error code
	
;We can now print the error message from the 8K ROM
	
		EI			;interrupts ON
		HALT			;accept one interrupt
		CALL	M_OFF		;reclaim channels, motors off
	
		CALL	ERRSUB
	
		CALL	PAGOUT		;page-out old ROM, 8K ROM in
		POP	AF		;get the error code
	
	DEFC MES_PK =	ASMPC+1		;POKE this from Boot (messages addr.)
		LD	HL,$02BF	;base address of error messages
	
		LD	B,4
		CPIR			;search for correct message
P_R_L:		LD	A,(HL)		;fetch character of message
		CP	$20		;is it a "marker"?
		JR	C,E_P_M		;if it is, finished
		PUSH	HL		;save pointer
		RST	$10		;call old ROM routine
		DEFW	$0010		;and print the character
		POP	HL		;restore the pointer
		INC	HL		;advance to next character
		JR	P_R_L		;go back and get next character
E_P_M:		CALL	$0700		;finished with 8K ROM

;*** TODO this is the bit that will help us recover after an error?	
		LD	HL,(ERR_ST)	;get PAW error pointer
		LD	(ERRSP),HL
	
		LD 	A,2		;Red border as we have come error route
		OUT 	(254),A

;		CALL	0A028h		; Breakpoint to monitor ***
ERR_LOOP:	JP	ERR_LOOP	; *** TEMP Hold at Red as it causes havok
	
		RET
	
;Subroutine to page-out old ROM and page-in 8K ROM
	
PAGOUT:		LD	HL,_BACK	;prepare to page-out old rom
		LD	(HD_11),HL	;we'll return to "BACK"
		RST	$08
		DEFB	$32
_BACK:		POP	HL		;drop the two unwanted addresses
		POP	HL		;from the stack
		RET			;and return to calling routine
	
;Copy header at IX to safe area as WSPACE seems to be destroyed
	

MOVHED:	LD	DE,HMSAFE	;Address of new header area
		PUSH	DE		;On stack
		EX	(SP),IX		;Into IX and old onto stack
		POP	HL		;Into HL for Source
		LD	BC,17
		LDIR
		RET

;This section converted to a subroutine from Version A07 to allow the Microdrive
;handler to recover correctly
	
ERRSUB:		
		LD	HL,0
		LD	(FLAGX),HL	;FLAGX=XPTRhi=0
		INC	HL
		LD	(STRMS+6),HL	;Reset stream
;		CALL	SELGLB
;		CALL	COL
		CALL	ROMSM
		CALL	USECLL		;Clear lower screen and reset wrap buffer
	
;***TODO Need to do this in a better way
CHKSP2:	
		RET

	
USECLL:	CALL	ROMCL		;Clear lower screen (disables print trap)
;		CALL	CLRWRB		;Clear any wordwrap
CHANK:		LD	A,253		;Select lower screen
		JR	OPEN
	

USECLS:	CALL	ROMCS		;Clear all screen (disables print trap)
;		LD	HL,(SPOSN)	;Do a SAVEAT
;		LD	(SSPOSN),HL
;		CALL	CLRWRB
		LD	A,2
OPEN:
;		CALL	FLUSH		;Flush any characters in wrap buffer
		CALL	ROMCH		;Open channel
OPEN2:
;		CALL	TEMPC		;Was not done by ROM TEMPS
		RET

;We must now set up the extra variables for the microdrive, and work out
;the address of the various routines
;TODO - Check this works with all ROM versions - we may not have known that BITD 
	
INITROM:	
		RST	$08	     ;Create new system vars
		DEFB	$31

		LD	HL,BACK2     ;Page out 16K ROM, 8K ROM in leaving it
		LD	(HD_11),HL
		RST	$08
		DEFB	$32
BACK2:		POP	HL
		POP	HL
	
;Find the address of the "Motors Off" routine
	
		LD	HL,$0047     ;There is a call to RCL_T_CH @ #0046
		LD	E,(HL)       ;Put the address into DE
		INC	HL
		LD	D,(HL)
		LD	(PK_RCL),DE  ;POKE it in.
	
;Find the address of the LOAD routine
	
		LD	HL,$01D6     ;There is a JP to LOAD here
		LD	E,(HL)       ;put JP address into DE
		INC	HL
		LD	D,(HL)
		LD	HL,$0008     ;Add 8 to this address
		ADD	HL,DE
		LD	E,(HL)       ;Get the jump into DE
		INC	HL
		LD	D,(HL)
		LD	(POKE_L),DE  ;POKE it in
	
;Find the address of the SAVE routine
	
		LD	HL,$01D1     ;There is a jump to SAVE here
		LD	E,(HL)
		INC	HL           ;Put address into DE
		LD	D,(HL)
		LD	HL,$001E     ;Add #1E to this address
		ADD	HL,DE
		LD	E,(HL)
		INC	HL           ;Put the jump into DE
		LD	D,(HL)
		LD	(POKE_S),DE  ;POKE it in
	
;Find the address of the CAT routine
	
		LD	HL,($01B8)
		LD	DE,$002A
		ADD	HL,DE
		LD	E,(HL)
		INC	HL
		LD	D,(HL)
		EX	DE,HL
		INC	HL
		LD	E,(HL)
		INC	HL
		LD	D,(HL)
		LD	HL,$0006
		ADD	HL,DE
		LD	(POKE_C),HL
		LD	(POKE_C2),HL
	
;Find the address of the Error Messages
	
		LD	IX,$0100     ;The start of the search.
		LD	DE,$0050     ; = 0,P
		LD	BC,$726F     ; = r,o
	
TRY2:		INC	IX           ;Step on one byte
		LD	A,(IX+0)     ;Get the first address
		CP	D            ;is it a #00 ?
		JR	NZ,TRY2      ;if not, try again with next byte.
	
		LD	A,(IX+1)     ;get next byte if first is OK
		CP	E            ;is it "P" ?
		JR	NZ,TRY2      ;if not, start again (etc.)
		LD	A,(IX+2)
		CP	B
		JR	NZ,TRY2
		LD	A,(IX+3)
		CP	C
		JR	NZ,TRY2
	
;IX contains start of Messages
	
		LD	(MES_PK),IX  ;POKE it in
		JP	$0700        ;page out 8K ROM, return to 16K ROM and then code
		
;Hisoft Extended CAT

EXT_CAT:
	LD	HL,SPACE
	LD	(POINTE),HL
;	LD	IY,5C3Ah

;Set upnew channel and attach to Stream 14

	LD	HL,(PROG)
	DEC	HL
	PUSH	HL
	LD	BC,11
	
	RST	10h
	DEFW	MAKE_S

	LD	HL,CH14out
	POP	DE
	PUSH	DE
	EX	DE,HL
	LD	(HL),E
	INC	HL
	LD	(HL),D
	INC	HL
	EX	DE,HL
	LD	HL,C14INF
	LD	BC,11-2
	LDIR
	POP	HL
	INC	HL
	LD	BC,(CHANS)
	OR	A
	SBC	HL,BC
	LD	(STRM6+28),HL

;Now read in bare catalogue

;	EXX
;	PUSH	HL
;	EXX

;	RST	8
;	DEFB	NEWVARS
	
	LD	A,14
	LD	(S_STR1),A
	LD	HL,(DRIVEN)
	LD	(D_STR1),HL

	RST	$10
	DEFW	$1601

	DEFC POKE_C2 =	ASMPC+1	;Poked with address of shadow CATALOGUE
	CALL	$1C5E		;little way into the Shadow ROM cat

	CALL	$700
;	LD	HL,(POKE_C)
;	LD	(HD_11),HL
;	EI
;	RST	8
;	DEFB	SHADOW
	
;Now process bare catalogue

	LD	HL,SPACE
	LD	B,11
	CALL	WRstring
CatL1:	LD	B,15
CatLoo: PUSH	BC	
	INC	HL
	LD	A,(HL)
	CP	CR	;finished?
	JR	Z,CatEnd
	DEC	HL
	LD	B,11
	PUSH	HL
	CALL	WRstring
	EX	(SP),HL
	INC	HL
	EX	DE,HL
	LD	HL,T_STR1
	LD	(HL),E
	INC	HL
	LD	(HL),D
	LD	HL,(DRIVEN)
	LD	(D_STR1),HL
	LD	HL,10
	LD	(N_STR1),HL
	EI
	RST	8
	DEFB 	OPEN_M
	CALL 	Space
	BIT	PRINT,(IX+RECFLG)
	JR	NZ,NotPri
	LD	A,'D'
	CALL 	CONOUT
	JR	CatBack
NotPri: PUSH 	IX
	
	POP	DE
	LD	HL,82
	ADD	HL,DE
	EX	DE,HL
	LD	A,(DE)
	INC	DE
	LD	HL,TYPETAB
	LD	C,A
	LD	B,0
	ADD	HL,BC
	LD	A,(HL)
	CALL	CONOUT
	CALL	Space
	EX	DE,HL
	LD	A,C
	OR	A
	JR	NZ,NotPro
	INC	HL
	INC	HL
	INC	HL
	INC	HL
	LD	E,(HL)
	INC	HL
	LD	D,(HL)
	INC	HL
	CALL	DEOUTS
	LD	E,(HL)
	INC	HL
	LD	D,(HL)
	CALL	DEOUTS
	JR	CatBack

NotPro: CP	3
	JR	NZ,CatBack
	LD	E,(HL)
	INC	HL
	LD	D,(HL)
	INC	HL
	CALL	DEOUTS
	LD	E,(HL)
	INC	HL
	LD	D,(HL)
	CALL	DEOUTS
	
CatBack: RST	8
	DEFB	CLOSE_M
	POP	HL
	POP	BC
	DJNZ	CatLoo
	JP 	CatL1

CatEnd: POP	BC
	DEC	HL
	LD	B,5
	CALL	WRstring

;	EXX	
;	POP	HL
;	EXX

	LD	BC,0
	
		LD	HL,(ERR_ST)	;Back here so reset error system
		LD	(ERRSP),HL
		JP	NO_ERR		;Exit back to caller

;Subroutines...

;Output DE in decimal
DEOUTS:	PUSH HL
	PUSH IX
        EX   DE,HL
        LD   B,5
        LD   IX,TENTAB
DEloop: LD   E,(IX)
        LD   D,(IX+1)
       LD   A,-1
TenLoop: INC  A
       OR   A
       SBC  HL,DE
       JR   NC,TenLoop
       ADD  HL,DE
       OR   30h
       CALL CONOUT
       INC  IX
       INC  IX
       DJNZ DEloop
       CALL Space
       POP  IX
       POP  HL
       RET

;Outputfor Stream14

CH14out: LD   HL,(POINTE)
       LD   (HL),A
       INC  HL
       LD   (POINTE),HL
       RET

;Writea string oflength B from (HL)

WRstring: LD   A,(HL)
       CALL CONOUT
       INC  HL
       DJNZ WRstring
       RET

;Open a stream

ChOpen: PUSH HL
       PUSH DE
       PUSH BC
       CALL 1601h
       POP  BC
       POP  DE
       POP  HL
       RET

;Output a space to stream 2

Space:  LD   A,' '
;Output to stream 2

CONOUT: PUSH AF
       LD   A,2
       CALL ChOpen
       POP  AF
       RST  10h
       RET


;Stuff needed for EXTCAT

SPACE:  DEFS 512

TENTAB: DEFW 10000,1000,100,10,1
	
TYPETAB: DEFM "PNSB"

C14INF: DEFW 15C4h
       DEFB "Z"
       DEFW 28h,28h,11

	RET
	
