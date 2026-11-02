#!/usr/bin/env python3
"""Makes roms/c64.sym, the labels of the Commodore 64's ROMs and system variables, from Michael Steil's C64 reference
(github.com/mist64/c64ref, src/c64disasm and src/c64mem): the labels of the original sources (c64disasm_ms.txt for BASIC,
c64disasm_cbm.txt for the KERNAL, c64mem_src.txt for the RAM) with Lee Davison's headings (c64disasm_en.txt) as their
descriptions. Download those files into a folder as ms.txt, cbm.txt, en.txt and mem_src.txt, then:
    python3 tools/make-c64-symbols.py FOLDER roms/c64.sym
A third argument lists the headings left without a name."""
import re, sys
src = sys.argv[1]
MN = set("ADC AND ASL BCC BCS BEQ BIT BMI BNE BPL BRK BVC BVS CLC CLD CLI CLV CMP CPX CPY DEC DEX DEY EOR INC INX INY JMP JSR LDA LDX LDY LSR NOP ORA PHA PHP PLA PLP ROL ROR RTI RTS SBC SEC SED SEI STA STX STY TAX TAY TSX TXA TXS TYA".split())
IDENT = re.compile(r'^[A-Za-z][A-Za-z0-9_]*$')

def labels(path, lo, hi):
    out = {}
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if not (line.startswith('.,') or line.startswith('.:')): continue
        a = int(line[2:6], 16)
        if not (lo <= a <= hi): continue
        s = line[32:].split(';')[0].strip()
        if not s: continue
        t = s.split()
        tok = t[0]
        if tok.endswith(':'):
            name = tok[:-1]
        elif len(t) > 1 and (t[1].upper() in MN or t[1].startswith('.') or t[1] == '='):
            name = tok
        else:
            continue
        if tok.upper() in MN or tok.startswith('.'): continue
        name = name.rstrip('>')
        if IDENT.match(name) and a not in out: out[a] = name.upper()
    return out

def headings(path):
    out = {}; pend = None
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if line.startswith(' ' * 32) and line[32:].startswith('***'):
            pend = line[32:].lstrip('* ').strip(); continue
        if line.startswith('.,') or line.startswith('.:'):
            if pend:
                out.setdefault(int(line[2:6], 16), pend)
            pend = None
    return out

ram = {}
for line in open(src + '/mem_src.txt', encoding='utf-8'):
    if not line.startswith('$'): continue
    a = int(line[1:5], 16); name = line[13:21].strip(); desc = line[21:].strip()
    if name and IDENT.match(name) and a not in ram: ram[a] = (name.upper(), desc)

basic = labels(src + '/ms.txt', 0xA000, 0xBFFF); basic.update({k: v for k, v in labels(src + '/ms.txt', 0xE000, 0xE4FF).items()})
kern = labels(src + '/cbm.txt', 0xE500, 0xFFFF)
head = headings(src + '/en.txt')
print(len(ram), len(basic), len(kern), len(head), file=sys.stderr)

allsyms = {}
for a, (n, d) in ram.items(): allsyms[a] = (n, d)
for d_ in (basic, kern):
    for a, n in d_.items(): allsyms[a] = (n, head.get(a, ''))
EXTRA = {
 0xA000:'BASIC_VECTORS', 0xA19E:'ERROR_MESSAGES', 0xA328:'ERROR_VECTORS', 0xA43A:'ERROR_WARM', 0xA474:'READY',
 0xA579:'CRUNCH_VECTOR', 0xA7AE:'NEWSTT_LOOP', 0xA82C:'CHECK_STOP', 0xA871:'RUN', 0xAB3B:'PRINT_SPACE',
 0xABBF:'INPUT', 0xABF9:'PROMPT_INPUT', 0xAE83:'GET_VALUE', 0xAF14:'CHECK_ROM_ADDR', 0xB1AA:'FLOAT_TO_FIXED',
 0xB449:'RESTORE_FN', 0xB526:'GARBAGE_COLLECT', 0xBF3A:'JIFFY_COUNTS', 0xBFED:'EXP', 0xE1D4:'LOAD_SAVE_PARAMS',
 0xE37B:'WARM_START', 0xE394:'COLD_START', 0xE3BF:'INIT_BASIC', 0xE422:'INIT_MESSAGE', 0xE447:'BASIC_VECTOR_TABLE',
 0xE45F:'STARTUP_MESSAGES', 0xE4AD:'BASIC_CKOUT', 0xE4D3:'RS232_START_BIT', 0xE4DA:'SAVE_COLOUR', 0xE4E0:'WAIT_KEY_TAPE',
 0xE4EC:'BAUD_TABLE_PAL', 0xE518:'INIT_SCREEN', 0xE56C:'SET_SCREEN_PTRS', 0xE5CD:'WAIT_KEY', 0xE6B6:'ADVANCE_CURSOR',
 0xE891:'OUTPUT_CR', 0xE8CB:'SET_COLOUR', 0xE8DA:'COLOUR_TABLE', 0xE965:'OPEN_SCREEN_LINE', 0xE9C8:'MOVE_SCREEN_LINE',
 0xE9E0:'COLOUR_LINE_PTRS', 0xEB48:'SHIFT_KEYS', 0xEB79:'KEY_TABLES', 0xEB81:'KEYS_UNSHIFTED', 0xEBC2:'KEYS_SHIFTED',
 0xEC03:'KEYS_COMMODORE', 0xEC44:'SPECIAL_CHARS', 0xEC78:'KEYS_CONTROL', 0xECB9:'VIC_INIT_TABLE', 0xECF0:'SCREEN_LINES_LO',
 0xED21:'DEFER_COMMAND', 0xEDCC:'SERIAL_END_WAIT', 0xEE13:'SERIAL_IN', 0xEE85:'CLOCK_HIGH', 0xEE8E:'CLOCK_LOW',
 0xEE97:'DATA_HIGH', 0xEEA0:'DATA_LOW', 0xEEB3:'DELAY_1MS', 0xF0BD:'KERNAL_MESSAGES', 0xFD30:'KERNAL_VECTORS',
 0xFF5B:'PCINT', 0xFFFA:'HARDWARE_VECTORS'}
JT = ['CINT','IOINIT','RAMTAS','RESTOR','VECTOR','SETMSG','SECOND','TKSA','MEMTOP','MEMBOT','SCNKEY','SETTMO','ACPTR',
 'CIOUT','UNTLK','UNLSN','LISTEN','TALK','READST','SETLFS','SETNAM','OPEN','CLOSE','CHKIN','CHKOUT','CLRCHN','CHRIN',
 'CHROUT','LOAD','SAVE','SETTIM','RDTIM','STOP','GETIN','CLALL','UDTIM','SCREEN','PLOT','IOBASE']
for i, n in enumerate(JT):
    EXTRA.setdefault(0xFF81 + i * 3, n)
used = {n for n, d in allsyms.values()}
for a, n in sorted(EXTRA.items()):
    if a not in allsyms and n not in used:
        allsyms[a] = (n, head.get(a, '')); used.add(n)
# Headings with no label in the source: still worth a name? no, keep only real labels
seen = {}
dups = [n for a, (n, d) in allsyms.items() if seen.setdefault(n, a) != a]
print('dups', dups, file=sys.stderr)
o = open(sys.argv[2], 'w', encoding='utf-8', newline='\n')
o.write("""; Labels of the Commodore 64 ROMs (BASIC at A000-BFFF and E000-E4FF, KERNAL at E500-FFFF) and of its system
; variables (RAM). The names are the ones of the original sources: Microsoft's BASIC for the 6502 and Commodore's
; C64 KERNAL (901227-03). The description after each label is the heading of the routine in Lee Davison's
; "almost completely commented C64 ROM disassembly" (or, for the variables, the one of the original source).
; Taken from Michael Steil's C64 reference, https://www.pagetable.com/c64ref/c64disasm/ (github.com/mist64/c64ref).
; ochenta loads this file by itself for the Commodore 64: the ROM labels apply only while that ROM is paged in.
; Same format as the symbol files exported by SjASM/SjASMPlus; the text after ";" is shown as the label's hint.
""")
for a in sorted(allsyms):
    n, d = allsyms[a]
    d = d.replace(';', ',')
    o.write(f"{n}: EQU 0x{a:08X}" + (f" ; {d}" if d else '') + "\n")
if len(sys.argv) > 3:
    for a in sorted(head):
        if (0xA000 <= a <= 0xBFFF or a >= 0xE000) and a not in allsyms:
            print(f"{a:04X} {head[a]}")
