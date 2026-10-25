# Makes src/KeyboardGuide.inc (the Keyboard guide's picture, a PNG, as a byte array)
# from tools/keyboard-guide.png, scaled to 1400 px wide and reduced to 256 colours.
#   python3 tools/make-keyboard-guide.py
import io, os
from PIL import Image
here = os.path.dirname(os.path.abspath(__file__))
im = Image.open(os.path.join(here, 'keyboard-guide.png')).convert('RGB')
im = im.resize((1400, round(im.height * 1400 / im.width)), Image.LANCZOS)
im = im.quantize(256, method=Image.MEDIANCUT, dither=Image.NONE)
buf = io.BytesIO()
im.save(buf, 'PNG', optimize=True)
data = buf.getvalue()
out = ['{ The Keyboard guide\'s picture (a PNG), made by tools/make-keyboard-guide.py }',
       'const', '  KEYBOARD_GUIDE_SIZE = %d;' % len(data),
       '  KEYBOARD_GUIDE: array[0..%d] of Byte = (' % (len(data) - 1)]
for i in range(0, len(data), 24):
    chunk = ', '.join(str(b) for b in data[i:i + 24])
    out.append('    ' + chunk + (',' if i + 24 < len(data) else ''))
out.append('  );')
open(os.path.join(here, '..', 'src', 'KeyboardGuide.inc'), 'w').write('\n'.join(out) + '\n')
print(len(data), 'bytes')
