#!/usr/bin/env python3
"""dskfiles.py IMAGE: lists the files of a FAT12 disk image (.dsk) in the root directory's order: the name,
the size, the attributes and a checksum (CRC-32) of the bytes the FAT's chain gives (as many as the size
says), and whether the chain is longer than the size needs. Then the free clusters. The dates and times are
left out (they come from the clock). Used by fbasic-difftests.sh to compare the disks the disk ROMs leave."""
import sys, zlib

data = open(sys.argv[1], 'rb').read()
bps = data[11] | data[12] << 8
spc = data[13]
reserved = data[14] | data[15] << 8
fats = data[16]
entries = data[17] | data[18] << 8
total = data[19] | data[20] << 8
fatsize = data[22] | data[23] << 8
fat = data[reserved * bps:(reserved + fatsize) * bps]
rootsec = reserved + fats * fatsize
first = rootsec + (entries * 32 + bps - 1) // bps
clusters = (total - first) // spc

def entry(n):
    v = fat[n * 3 // 2] | fat[n * 3 // 2 + 1] << 8
    return v >> 4 if n & 1 else v & 0xFFF

for i in range(fats):
    if data[(reserved + i * fatsize) * bps:(reserved + (i + 1) * fatsize) * bps] != fat:
        print('the FAT copies differ')
for i in range(entries):
    e = data[rootsec * bps + i * 32:rootsec * bps + i * 32 + 32]
    if e[0] == 0:
        break
    if e[0] == 0xE5:
        continue
    name = e[0:8].decode('latin-1').rstrip() + '.' + e[8:11].decode('latin-1').rstrip()
    size = int.from_bytes(e[28:32], 'little')
    cl = e[26] | e[27] << 8
    body = b''
    chain = 0
    while 2 <= cl < 0xFF8 and chain < 4096:
        start = (first + (cl - 2) * spc) * bps
        body += data[start:start + spc * bps]
        cl = entry(cl)
        chain += 1
    extra = '' if chain == (size + spc * bps - 1) // (spc * bps) else ' (chain of %d clusters)' % chain
    print('%-12s %7d %02X %08X%s' % (name, size, e[11], zlib.crc32(body[:size]), extra))
print('free clusters', sum(1 for n in range(2, clusters + 2) if entry(n) == 0))
