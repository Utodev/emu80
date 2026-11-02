#!/usr/bin/env python3
"""mkc64tap: makes a C64 tape image (.tap) of a program the way the KERNAL's SAVE does (a header block and a data block, each
twice), for testing the datasette.

    mkc64tap.py program.prg out.tap [name]
    mkc64tap.py --demo out.tap          (a BASIC program that prints TAPE OK)"""
import struct
import sys

SHORT, MEDIUM, LONG = 0x30, 0x42, 0x56      # pulse lengths in 8 cycle units


def byte_pulses(b):
    out = [LONG, MEDIUM]                       # new data marker
    ones = 0
    for i in range(8):
        bit = (b >> i) & 1
        ones += bit
        out += [MEDIUM, SHORT] if bit else [SHORT, MEDIUM]
    parity = 0 if (ones & 1) else 1            # odd parity over the nine bits
    out += [MEDIUM, SHORT] if parity else [SHORT, MEDIUM]
    return out


def block(data, first):
    out = []
    count = [0x89 - i for i in range(9)] if first else [0x09 - i for i in range(9)]
    chk = 0
    for b in count:
        out += byte_pulses(b)
    for b in data:
        out += byte_pulses(b)
        chk ^= b
    out += byte_pulses(chk)
    out += [LONG, SHORT]                       # end of data marker
    return out


def make(prg, name):
    start = prg[0] | (prg[1] << 8)
    body = prg[2:]
    end = start + len(body)
    header = bytes([1, start & 255, start >> 8, end & 255, end >> 8]) + name.encode('ascii').ljust(16)[:16]
    header = header.ljust(192, b' ')
    pulses = [SHORT] * 2500                    # the leader
    pulses += block(header, True)
    pulses += [SHORT] * 79
    pulses += block(header, False)
    pulses += [SHORT] * 2500
    pulses += block(body, True)
    pulses += [SHORT] * 79
    pulses += block(body, False)
    pulses += [SHORT] * 200
    return pulses


def demo():
    text = b'TAPE OK'
    line = struct.pack('<HH', 0x0801 + 2 + 2 + 1 + 1 + len(text) + 1 + 1, 10) + bytes([0x99, 0x22]) + text + bytes([0x22, 0])
    return struct.pack('<H', 0x0801) + line + b'\x00\x00'


if __name__ == '__main__':
    if sys.argv[1] == '--demo':
        prg, out, name = demo(), sys.argv[2], 'DEMO'
    else:
        prg, out = open(sys.argv[1], 'rb').read(), sys.argv[2]
        name = sys.argv[3] if len(sys.argv) > 3 else 'PROGRAM'
    pulses = make(prg, name)
    with open(out, 'wb') as f:
        f.write(b'C64-TAPE-RAW' + bytes([1, 0, 0, 0]) + struct.pack('<I', len(pulses)))
        f.write(bytes(pulses))
