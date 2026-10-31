#!/usr/bin/env python3
"""mkcas.py <out.cas>: the tape of the free ROMs' file tests (tests/fbasic-difftests.sh): ASCII files
(a header block of 10 x EAh and the 6-character name, then blocks of 256 bytes of text ended by 1Ah) for
OPEN "CAS:name" FOR INPUT, INPUT #, LINE INPUT #, EOF and INPUT$(n, #)."""
import sys

BLOCK_HEADER = bytes([0x1F, 0xA6, 0xDE, 0xBA, 0xCC, 0x13, 0x7D, 0x74])


def block(tape, data):
    while len(tape) % 8:
        tape.append(0)
    tape += BLOCK_HEADER
    tape += data


def ascii_file(tape, name, text):
    block(tape, bytes([0xEA] * 10) + name.ljust(6).encode())
    data = text.encode() + b'\x1a'
    while len(data) % 256:
        data += b'\x1a'
    for i in range(0, len(data), 256):
        block(tape, data[i:i + 256])


tape = bytearray()
ascii_file(tape, 'OTHER', '1,2,3\r\n')
ascii_file(tape, 'FIELDS',
           '10,20,"Hello, world",abc def ,-3.5E2\r\n'
           'second line\r\n'
           '  42  , 7\r\n'
           '"quoted" tail,x\r\n'
           '&H1F,1.5D3\r\n'
           '1 2,3\r\n'
           '\n  lf first\r\n'
           'abcdefghij\r\n'
           '"open quote\r\n'
           '"a,b"  ,  c  \r\n'
           'last')
ascii_file(tape, 'LINES', ''.join('line %d of the long file, padded to cross the blocks\r\n' % i
                                  for i in range(1, 13)))
with open(sys.argv[1], 'wb') as f:
    f.write(tape)
