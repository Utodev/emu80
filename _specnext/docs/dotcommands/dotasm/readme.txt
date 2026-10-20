ASM - ZX Spectrum Next Inline Assembler
---------------------------------------

For the latest version visit https://taylorza.itch.io/nextbasic-inline-assembler

Installation
------------
Copy 'asm' to the dot folder in the root of your ZX Spectrum Next SD Card

Usage
-----
The following example should get you started

 10 CLEAR $bff0 : REM Reserve memory for our machine code
 20 .asm
 30 ;  org $c000
 40 ;  ld a, 2
 50 ;  call $1601 ;Open chan 2
 60 ;  ld hl, msg
 70 ;nxtch
 80 ;  ld a, (hl)
 90 ;  or a
100 ;  ret z
110 ;  rst 16
120 ;  inc hl
130 ;  jr nxtch
140 ;msg db "Hello world",0
150 RANDOMIZE USR ($c000) : REM Execute the machine code routine

Version History
---------------
v0.6 - 2024/5/31
- improved parsing of DB/DW pseudo ops
- support for generating NEX files
- BANK accepts an additional argument to indicate if the bank should be cleared before assembling into it
- Added left shift '<<' and right shift '>>' operators

v0.5g - 2024/05/10
- Added support for anonymous labels 
- Added support for multiple instructions per line using ':' separator

v0.5f - 2024/04/21
- Added support for label offsets to make self modifying code easier
- Code optimization
- Moved expression evaluator out of the DOT Command address space

v0.5e - 2024/03/24
- FIXED: Assembler does not error on loading registers other than 'A' with the content of a register pair (Simon N. Goodwin)
- Labels maxlength increased from 11 to 15
- Support scoped labels using '.' prefix to define a scoped label. Total length of scope and local name including the '.' must not exceed 15

v0.5d - 2024/02/25
- Fixed a bug with the support for integer variables (https://gitlab.com/thesmog358/tbblue/-/issues/112)

v0.5c - 2024/02/11
- Added not-equal '<>' operator (Simon N. Goodwin)
- FIXED: Labels not excluded from conditional assembly (Simon N. Goodwin)
- FIXED: ALIGN error if the adjustment is only 1 byte
- Report error when a symbol value changes between passes (Simon N. Goodwin)
- Improved error reporting

v0.5b - Not released
- FIXED: Pseudo-ops not excluded from conditional assembly (Simon N. Goodwin)

v0.5a - 2024/01/28
- Fixed error reporting with nested IF

v0.5 - 2024/01/28
- New pseudo-ops to support generating relocations for drivers
-- RELOC_START/RELOC_END mark the start and end of a relocatable code section
-- RELOC_TABLE emits the relocation table
-- RELOC_COUNT returns the number of relocations that have been generated
- Conditional assembly
-- IF/ELSE/ENDIF nested up to seven levels deep
- Plenty of little bug fixes

v0.4d - 2024/01/21
- New pseudo-ops
-- NBRK trigger hardware breakpoint, short for nextreg 2,8
-- ALIGN align code/data to the specified byte boundary
- New bitwise operators
-- & bitwise AND
-- | bitwise OR
- Optimizations 
-- 16 bit multiplier using hardware optimizations from Ped7g

v0.4c - 2024/01/14 
- Fixed issue with LD (lbl), r/rp that was introduced with v0.4

v0.4b - 2024/01/14
- Fixed issue with z80n instructions not expecting a comment on the line

v0.4 - 2024/01/14
NOTE: This release contains a breaking change regarding hex and binary numbers
- Dropped the suffix notation for hex and binary numbers
-- $ prefix for hex
-- % or @ prefix for binary
- Added support for getting and setting BASIC integer variable during assembly
--   LD b, %a        ; Get the value of the BASIC integer variable at time of assembly
--   LET %a = sym    ; Assign the value of 'sym' to the BASIC integer variable %a
- Moved symbols to dedicated banks so now you can have many more symbols in your code
- Refactored parser to reduce size and improve error handling
- Fixed many bugs :)

v0.3b - 2024/01/06
- Relaxed the requirement to have a space after an OP-code when the next character is clearly not part of the name
- Improved DS, now fills memory/file with 0s
- https://github.com/taylorza/zxn-inlineasm-doc/issues/3
-- Fixed parsing of IN A, (C) 
-- Fixed expression error message for operators other than +/- prefixing the expression

v0.3a - 2023/12/31
- Fixed expressions for LD r, nn class ops

v0.3 - 2023/12/31
- Code size optimizations
- Added support for 'OUTPUT' directive/psuedo-op which allows the assembled code to be directed to
  a file rather than directly to memory

v0.2 - 2023/12/27
- Fixed parsing issue that allowed spaces between the characters of HL, IX, IY 
  registers
- Support specifying the target bank for the generated code
  BANK n[,o] where 'n' is the target bank number and 'o' an optional offset into
  the bank. When a bank is specified the ORG address is used for address 
  calculations. Typicall this should remain at the default of $c000
- Support assembling code that has been banked using 'BANK... LINE...'

v0.1 - 12/25/2023 Christmas Edition
- Initial public release