; UnpackPanel:
;         ld   hl,panel1lz
;         ld   de,20480
;         call DEC40
;         ret

;Z80 depacker for megalz V4 packed files   (C) fyrex^mhm

; DESCRIPTION:
;
; Depacker is fully relocatable, not self-modifying,
;it's length is 110 bytes starting from DEC40.
;Register usage: AF,AF',BC,DE,HL. Must be CALL'ed, return is done by RET.
;Provide extra stack location for store 2 bytes (1 word). Depacker does not
;disable or enable interrupts, as well as could be interrupted at any time
;(no f*cking wicked stack usage :).

; USAGE:
;
; - put depacker anywhere you want,
; - put starting address of packed block in HL,
; - put location where you want data to be depacked in DE,
;   (much like LDIR command, but without BC)
; - make CALL to depacker (DEC40).
; - enjoy! ;)

; PRECAUTIONS:
;
; Be very careful if packed and depacked blocks coincide somewhere in memory.
;Here are some advices:
;
; 1. put packed block to the highest addresses possible.
;     Best if last byte of packed block has address #FFFF.
;
; 2. Leave some gap between ends of packed and depacked block.
;     For example, last byte of depacked block at #FF00,
;     last byte of packed block at #FFFF.
;
; 3. Place nonpackable data to the end of block.
;
; 4. Always check whether depacking occurs OK and neither corrupts depacked data
;     nor hangs computer.
;

DEC40
        LD      A,$80           ; a starts at 128? (is this the max value of an rle length?)
        EX      AF,AF'
PackS   LDI                     ; copy hl to de
Pack0   LD      BC,$2FF         ; 767 ?
Pack1      EX      AF,AF'
Pack1X     ADD     A,A
        JR      NZ,Pack2
        LD      A,(HL)          ; hl = source, a = amount?
        INC     HL
        RLA
Pack2      RL      C
        JR      NC,Pack1X

        EX      AF,AF'
        DJNZ    PackX2
        LD      A,2
        SRA     C
        JR      C,PackN1
        INC     A
        INC     C
        JR      Z,PackN2
        LD      BC,#33F         ; 831 why?
        JR      Pack1

PackX2      DJNZ    PackX3
        SRL     C
        JR      C,PackS            ; get next?
        INC     B
        JR      Pack1
PackX6
        ADD     A,C
PackN2
        LD      BC,#4FF         ; 1279?
        JR      Pack1
PackN1
        INC     C
        JR      NZ,PackM4
        EX      AF,AF'
        INC     B
PackN5      RR      C
        RET     C
        RL      B
        ADD     A,A
        JR      NZ,PackN6
        LD      A,(HL)
        INC     HL
        RLA
PackN6      JR      NC,PackN5
        EX      AF,AF'
        ADD     A,B
        LD      B,6
        JR      Pack1
PackX3
        DJNZ    PackX4
        LD      A,1
        JR      PackM3
PackX4      DJNZ    PackX5
        INC     C
        JR      NZ,PackM4
        LD      BC,#51F         ; 1311
        JR      Pack1
PackX5
        DJNZ    PackX6
        LD      B,C
PackM4      LD      C,(HL)
        INC     HL
PackM3      DEC     B
        PUSH    HL
        LD      L,C
        LD      H,B
        ADD     HL,DE
        LD      C,A             ; amount to add
        LD      B,0
        LDIR
        POP     HL
        JR      Pack0
