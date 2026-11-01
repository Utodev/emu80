#!/usr/bin/env python3
"""mkdsk.py: makes a 720K test disk image (FAT12, media F9h, raw sectors) that does not boot: its boot
sector has the volume's parameters but no code (it starts with 00h), so a disk ROM reads it and goes on to
BASIC. Used by tests/fbasic-difftests.sh for the disk ROM tests.

    mkdsk.py OUT.dsk [NAME.EXT=SIZE ...]

each file is SIZE bytes of a pattern of its own (byte i = (i * 7 + i // 256 + n * 31) & 255, n its number),
written in contiguous clusters in the given order. NAME.EXT:TEXT instead: the file holds TEXT (\n a line's end,
written CR LF; for a BASIC program in ASCII)."""
import re, sys

SECTOR, SPC, SECTORS, FATS, FATSIZE, ENTRIES = 512, 2, 1440, 2, 3, 112
FIRST_DIR = 1 + FATS * FATSIZE
FIRST_DATA = FIRST_DIR + ENTRIES * 32 // SECTOR

def pattern(n, size):
    return bytes(((i * 7 + i // 256 + n * 31) & 255) for i in range(size))

def main():
    out = sys.argv[1]
    disk = bytearray(SECTOR * SECTORS)
    boot = bytearray(SECTOR)
    boot[3:11] = b'TESTDISK'
    boot[11:13] = SECTOR.to_bytes(2, 'little')
    boot[13] = SPC
    boot[14:16] = (1).to_bytes(2, 'little')
    boot[16] = FATS
    boot[17:19] = ENTRIES.to_bytes(2, 'little')
    boot[19:21] = SECTORS.to_bytes(2, 'little')
    boot[21] = 0xF9
    boot[22:24] = FATSIZE.to_bytes(2, 'little')
    boot[24:26] = (9).to_bytes(2, 'little')
    boot[26:28] = (2).to_bytes(2, 'little')
    disk[0:SECTOR] = boot
    fat = [0xFF9, 0xFFF]
    entries = []
    cluster = 2
    for n, spec in enumerate(sys.argv[2:]):
        if re.match(r'[^:=]+=\d+$', spec):
            name, size = spec.split('=')
            size = int(size)
            data = pattern(n, size)
        else:
            name, text = spec.split(':', 1)
            data = text.replace('\\n', '\n').replace('\n', '\r\n').encode('latin1')
            size = len(data)
        base, _, ext = name.upper().partition('.')
        count = max(1, -(-size // (SECTOR * SPC)))
        first = cluster if size else 0
        if size:
            for c in range(cluster, cluster + count):
                fat.append(c + 1 if c < cluster + count - 1 else 0xFFF)
            start = (FIRST_DATA + (cluster - 2) * SPC) * SECTOR
            disk[start:start + size] = data
            cluster += count
        entry = bytearray(32)
        entry[0:8] = base.ljust(8).encode()
        entry[8:11] = ext.ljust(3).encode()
        entry[11] = 0x20
        entry[22:24] = (0x6000).to_bytes(2, 'little')      # 12:00
        entry[24:26] = (((2026 - 1980) << 9) | (10 << 5) | 31).to_bytes(2, 'little')
        entry[26:28] = first.to_bytes(2, 'little')
        entry[28:32] = size.to_bytes(4, 'little')
        entries.append(entry)
    packed = bytearray(FATSIZE * SECTOR)
    for i in range(0, len(fat), 2):
        a = fat[i]
        b = fat[i + 1] if i + 1 < len(fat) else 0
        o = i * 3 // 2
        packed[o] = a & 0xFF
        packed[o + 1] = (a >> 8) | ((b & 0x0F) << 4)
        packed[o + 2] = b >> 4
    for f in range(FATS):
        o = (1 + f * FATSIZE) * SECTOR
        disk[o:o + len(packed)] = packed
    for i, e in enumerate(entries):
        o = FIRST_DIR * SECTOR + i * 32
        disk[o:o + 32] = e
    open(out, 'wb').write(disk)

main()
