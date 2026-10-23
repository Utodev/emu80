# Draws the emu80 icon (a rubber-keyed computer's keyboard) and writes emu80.ico.
#   python3 tools/make-icon.py src/emu80.ico preview.png
import struct, zlib, sys
N = 1024                      # supersampled canvas (4x the 256 icon)
S = N / 256.0
img = bytearray(N * N * 4)    # RGBA, transparent

def put(x, y, c):
    i = (y * N + x) * 4
    img[i:i+4] = bytes(c)

def rrect(x1, y1, x2, y2, r, c):
    x1, y1, x2, y2, r = [int(v * S) for v in (x1, y1, x2, y2, r)]
    for y in range(y1, y2):
        for x in range(x1, x2):
            dx = max(x1 + r - x, 0, x - (x2 - 1 - r))
            dy = max(y1 + r - y, 0, y - (y2 - 1 - r))
            if dx * dx + dy * dy <= r * r:
                put(x, y, c)

def poly(pts, c):
    pts = [(px * S, py * S) for px, py in pts]
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    for y in range(int(min(ys)), int(max(ys)) + 1):
        # scanline crossings
        cross = []
        for i in range(len(pts)):
            (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
            if (ay <= y < by) or (by <= y < ay):
                cross.append(ax + (y - ay) * (bx - ax) / (by - ay))
        cross.sort()
        for k in range(0, len(cross) - 1, 2):
            for x in range(max(0, int(cross[k])), min(N, int(cross[k + 1]))):
                put(x, y, c)

BODY = (24, 24, 24, 255)
PLATE = (52, 52, 56, 255)
KEY = (180, 184, 196, 255)
KEYTOP = (214, 218, 228, 255)
# Case: slightly wedge-shaped look with a lighter keyboard plate
rrect(4, 52, 252, 204, 14, BODY)
rrect(14, 62, 242, 166, 6, PLATE)
# Rubber keys: 4 rows of 10, each row shifted like the real keyboard
for row in range(4):
    y = 68 + row * 24
    off = (0, 6, 10, 2)[row]
    for k in range(10):
        x = 20 + off + k * 21.5
        rrect(x, y, x + 17, y + 18, 4, KEY)
        rrect(x + 2, y + 2, x + 15, y + 11, 3, KEYTOP)

def downsample(size):
    f = N // size
    out = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            acc = [0, 0, 0, 0]
            for yy in range(y * f, y * f + f):
                base = (yy * N + x * f) * 4
                row = img[base: base + f * 4]
                for k in range(0, f * 4, 4):
                    a = row[k + 3]
                    acc[0] += row[k] * a; acc[1] += row[k + 1] * a; acc[2] += row[k + 2] * a
                    acc[3] += a
            o = (y * size + x) * 4
            if acc[3]:
                out[o] = acc[0] // acc[3]; out[o + 1] = acc[1] // acc[3]; out[o + 2] = acc[2] // acc[3]
            out[o + 3] = acc[3] // (f * f)
    return out

def png(size, data):
    raw = b''.join(b'\0' + bytes(data[y * size * 4:(y + 1) * size * 4]) for y in range(size))
    def chunk(t, b):
        return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

def dib(size, data):
    # Classic icon entry: BITMAPINFOHEADER (double height), 32-bit BGRA rows
    # bottom-up, then the 1-bit AND mask (all zero: alpha decides)
    head = struct.pack('<IiiHHIIiiII', 40, size, size * 2, 1, 32, 0, 0, 0, 0, 0, 0)
    rows = []
    for y in range(size - 1, -1, -1):
        row = bytearray()
        for x in range(size):
            o = (y * size + x) * 4
            row += bytes((data[o + 2], data[o + 1], data[o], data[o + 3]))
        rows.append(bytes(row))
    mask_row = ((size + 31) // 32) * 4
    return head + b''.join(rows) + bytes(mask_row * size)

# LCL only reads BMP-style entries, so no PNG-compressed ones
sizes = [16, 24, 32, 48, 64, 128, 256]
pics = [downsample(s) for s in sizes]
entries = [dib(s, d) for s, d in zip(sizes, pics)]
out = struct.pack('<HHH', 0, 1, len(sizes))
offset = 6 + 16 * len(sizes)
for s, e in zip(sizes, entries):
    out += struct.pack('<BBBBHHII', s % 256, s % 256, 0, 0, 1, 32, len(e), offset)
    offset += len(e)
out += b''.join(entries)
open(sys.argv[1], 'wb').write(out)
if len(sys.argv) > 2:
    open(sys.argv[2], 'wb').write(png(256, pics[-1]))
