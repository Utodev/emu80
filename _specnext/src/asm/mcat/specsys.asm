;Define spectrum system
;System variables

;Screen attributes at 22528 (5800h)

	DEFC ATTRIB = 22528
	
;Note printer buffer is at 23296 (5B00h)

;Must be shorter on 128K

	DEFC BANKM =	23388	;128 machines only
	DEFC BANK678 =	23399	;+3 only	

;Main vars on 48K start at KSTATE = 23552  (5C00h) - 8 bytes long

	DEFC LASTK =	23560
	DEFC KDATA =	23565
	DEFC TVDATA =	23566
	DEFC TVDATH =	23567
	DEFC STRMS =	23568
	DEFC STRM6 =	23574
	DEFC CHARS =	23606
	DEFC ERRNR =	23610
	DEFC FLAGS =	23611
	DEFC FLAGS_IY = 01h
	DEFC TVFLAG =	23612
	DEFC TVFLAG_IY = 02h
	DEFC ERRSP =	23613
	DEFC NEWPPC =	23618
	DEFC NSPPC =	23620
	DEFC BORDCR =	23624
	DEFC VARS =	23627
	DEFC CHANSA =	23631
	DEFC CURCHL =	23633
	DEFC PROG =	23635
	DEFC ELINE =	23641
	DEFC KCUR =	23643
	DEFC CHADD =	23645
	DEFC XPTR =	23647
	DEFC WORKS =	23649
	DEFC STKBO =	23651
	DEFC STKEND =	23653
	DEFC FLAGS2 =	23611
	DEFC FLAGS2_IY = 30h
	DEFC DFSZ =	23659
	DEFC FLAGX =	23665
	DEFC TADDR =	23668
	DEFC SEED =	23670
	DEFC FRAMES =	23672
	DEFC UDG =	23675
	DEFC COORDS =	23677
	DEFC SPOSN =	23688
	DEFC ATTRT =	23695
	DEFC SCRCT =	23692
	DEFC ATTRP =	23693
	DEFC PFLAG =	23697

	DEFC HD_11 =	$5CED	;23789 for Mdrive only

;ROM Routines
	
	DEFC ROMED =	$0F2C	;Line Editor
	DEFC ROMIN =	$15E6	;Input
	DEFC ROMON =	$1652	;One space
	DEFC ROMMR =	$1655	;Make Room
	DEFC ROMSM =	$16B0	;Set minimum workspace
	DEFC ROMSS =	$16C5	;Clear Calculator stack
	DEFC ROMS1 =	$0734	;S,V or L BASIC program
	DEFC ROMS2 =	$0761	;Main Load/Verify
	DEFC ROMS3 =	$0984	;Part of SAVE
	DEFC ROMS4 =	$0708	;LOAD/SAVE Control Routine
	DEFC ROMS5 =	$075A	;SA-ALL
	DEFC ROMO3 =	$1A2E	;Number out
	DEFC ROMCP =	$0EAC	;Copy to sinclair printer
	DEFC ROMB1 =	$03B5	;BEEPER
	DEFC ROMB2 =	$03F8	;BEEP
	DEFC ROMBO =	$229B	;part of BORDER
	DEFC ROMBR =	$1F54	;BREAK-KEY
	DEFC ROMCH =	$1601	;CHAN-OPEN
	DEFC ROMCL =	$0D6E	;CLS-LOWER
	DEFC ROMCS =	$0D6B	;CLS
	DEFC ROMLD =	$0802	;LD-BLOCK
	DEFC ROMM1 =	$1391	;MESSAGES
	DEFC ROMM2 =	$09A1	;MESSAGES
	DEFC ROMNU =	$2D1B	;NUMERIC
	DEFC ROMO1 =	$1A1B	;OUT-NUM-1
	DEFC ROMO2 =	$1A28	;OUT-NUM-2
	DEFC ROMPE =	$1CAD	;part of PERMS
	DEFC ROMPF =	$2DE3	;PRINT-FP
	DEFC ROMPO =	$0C0A	;PO-MSG
	DEFC ROMPR =	$203C	;PR-STRING
	DEFC ROMSA =	$04C2	;SA-BYTES
	DEFC ROMSB =	$2D2B	;STACK-BC
;	DEFC ROMSE =	$16B0	;SET-MIN - removed was a duplicate
	DEFC ROMST =	$2D28	;STACK-A
	DEFC ROMLO =	$0708	;LOAD ROUTINE
	DEFC ROMTE =	$0D4D	;TEMPS
	DEFC ROMWA =	$15D4	;WAIT-KEY
	DEFC ROMPC =	$09F4	;Main Print routine
	DEFC ROMPOA =	$0AD9	;PO-ANY all normal chars
	DEFC ROMPOC =	$0A5F	;Print comma expansion
	DEFC ROMPOF =	$0AC3	;PO-FILL spaces to end of line
	DEFC ROMADC =	$0F81	;Add character
	DEFC ROMPFT =	$0B03	;PO-FETCH
	DEFC ROMTV1 =	$0A7D	;Part of CTRL chars routine
	DEFC ROMPCZ =	$0A80	;PO-CHANGE
	DEFC ROMPC2 =	$0A90	;PO-CONT-2, note this is later than versions < A03!
	DEFC ROMCST =	$0DD9	;CL-SET
	DEFC ROMCSR =	$0E00	;Physical Scroll routine
	DEFC ROMPS3 =	$0CD2	;No prompt on scroll
	DEFC ROMPSX =	ROMPS3+3;ditto, but partial scroll
	DEFC ROMPSB =	$0CB7	;allow BRK on more key
	DEFC ROMAL =	$0C72	;Auto list routine
	DEFC ROMPSK =	$0D34	;last bit of chan K scroll routine
	DEFC ROMPCB =	$0ECD	;Printer buffer flush
	DEFC ROMPCC =	$0EDF	;   "       "   clear
	DEFC ROMSR =	$1B76	;STMT-RET
	DEFC ROMISD =	$15C6	;Initial Stream data
	DEFC ROMR1 =	$19E5	;Reclaim area
	DEFC ROMPOS =	$0C3B	;Recursive print routine
	DEFC ROMCHR =	$3D00	;ROM char set 
	DEFC ROMERJ =	$15C4	;Cause error J - Invalid I/O device
	DEFC ROMER5 =	$0C86	;Cause error 5 - Out of screen
	DEFC ROMER4 =	$1F15	;Cause error 4 - Out of memory
	DEFC ROMCAL =	$15FA	;part of CALL-SUB (Credit P.A.!)
	DEFC ROMDL =	$24B7	;Draw line
	DEFC ROMPL =	$22E5	;Plot point
	DEFC ROMPA =	$0BDB	;PO-ATTR
	DEFC ROMPI =	$22AA	;Pixel address
	DEFC ROMCLN =	$0E44	;Clear lines
	DEFC ROMKI =	$10A8	;Key input
	DEFC ROMEDC =	$111D	;Copy edit line
	DEFC ROMKCH =	$1113	;Set key input address
	DEFC ROMKI2 =	$10BC	;Part of Key input
	DEFC ROMPA2 =	$15F2	;Main print routine
	DEFC ROMAT =	$0A9B	;AT control in print routine
	DEFC ROMCLA =	$0E9E	;Address of print line calculator

	DEFC ROM2SP =	$5B00	;Swap ROMS (+2 ONLY)
	DEFC ROM2CP =	$012A	;Copy to Epson printer (+2 ONLY)
	
;DOS routines on the +3
	
	DEFC DOS_SP =	$013F	;Set config for pages 1,3,4 & 6.
	DEFC DOS_AB =	$010C	;Abandon file
	DEFC DOS_RD =	$0112	;Read data
	DEFC DOS_OP =	$0106	;Open file
	DEFC DOS_RH =	$010F	;Reference header
	DEFC DOS_WR =	$0115	;Write data
	DEFC DOS_CL =	$0109	;Close file
	DEFC DOS_CT =	$011E	;Catalogue
	DEFC DOS_FS =	$0121	;Free space on drive
	DEFC DOS_SD =	$012D	;DOS SET DRIVE FF=get default drive or A-P set it C=1 if OK otherwise A is error code

;Proper full lenth use of the names for +3e and NextOS extended calls.

	DEFC NEXTOS_IDE_BANK =	$01BD	;Allocate or free 8K banks in main ZX memory or DivMMC memory
	DEFC NEXTOS_IDE_BASIC =	$01C0	;Run a tokenised BASIC command line at HL terminated in $0d
	DEFC NEXTOS_IDE_BROWSER = $01BA ;Launch built in file browser
	
;Some definitions for them

	DEFC NOS_BROWSERCAPS_ALL = $1F		;All below
	DEFC NOS_BROWSERCAPS_NONE = $00		;None of the below
        DEFC NOS_BROWSERCAPS_COPY= $01		;files may be copied
        DEFC NOS_BROWSERCAPS_RENAME = $02	;files/dirs may be renamed
        DEFC NOS_BROWSERCAPS_MKDIR = $04	;directories may be created
        DEFC NOS_BROWSERCAPS_ERASE = $08	;files/dirs may be erased
        DEFC NOS_BROWSERCAPS_REMOUNT = $10	;SD card may be remounted
	DEFC NOS_BROWSERCAPS_SYSCFG = $80	;system use only - use browser.cfg


