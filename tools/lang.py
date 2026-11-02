#!/usr/bin/env python3
"""Translations of ochenta (see CLAUDE.md).

  tools/lang.py extract   collects the texts of the sources (_('...'), _F('...'), and the
                          constants between "// TR-BEGIN" and "// TR-END") into lang/ochenta.pot
                          and updates lang/{es,fr,pt,de}.po (new texts get an empty translation,
                          texts that are gone are dropped)
  tools/lang.py inc       writes src/LangData.inc (the tables compiled into ochenta) from the .po
                          files and the LCL's ones (lang/lcl/*.po)
  tools/lang.py check     reports missing translations and mistakes (placeholders, & accelerators,
                          terms that are never translated)

The sources have the texts in English; a .po entry is msgid (English) / msgstr (translation).
"""
import os, re, sys, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'src')
LANG = os.path.join(ROOT, 'lang')
LANGS = ['es', 'fr', 'pt', 'de']
# Not translated: the debuggers and their help, and generated files
EXCLUDE = {'DebuggerForm', 'DaadForm', 'DaadExport', 'DaadHelp', 'DaadTemplate', 'Z80Help', 'Z80Opcodes',
           'Disasm', 'BreakExpr', 'AsmExport', 'DebugFiles', 'ZXUnoRegsForm', 'Daad', 'Symbols',
           'LangData', 'Release', 'Lang', 'PawHelp', 'QuillHelp', 'C64Debugger', 'C64Disasm', 'C64Expr', 'C64Help', 'C64Opcodes'}
# Words that are never translated (CLAUDE.md): a translation that has lost one is reported
KEEP = ['Debug', 'NMI', 'SD', 'CR', 'Zoom', 'Turbosound', 'DivMMC', 'Currah', 'ULAPlus', 'Timex',
        'Radastan', 'Joystick', 'Scanlines', 'Breakpoints', 'Watches', 'Process', 'Flags',
        'Adventure debugger', 'Debugger']

ATOM = r"(?:'(?:[^'\n]|'')*'|#\$?[0-9A-Fa-f]+)+"


def blank_comments(t):
    """The text with the comments (and nothing else) replaced by spaces"""
    def sp(m):
        return re.sub(r'[^\n]', ' ', m.group(0))
    pat = re.compile(r"'(?:[^'\n]|'')*'|\{[^}]*\}|//[^\n]*|\(\*.*?\*\)", re.S)
    return pat.sub(lambda m: m.group(0) if m.group(0)[0] == "'" else sp(m), t)


def decode(run):
    out = bytearray()
    for m in re.finditer(r"'((?:[^'\n]|'')*)'|#(\$?)([0-9A-Fa-f]+)", run):
        if m.group(1) is not None:
            out += m.group(1).replace("''", "'").encode('utf-8')
        else:
            out.append(int(m.group(3), 16 if m.group(2) else 10))
    return out.decode('utf-8')


def sources():
    for f in sorted(glob.glob(os.path.join(SRC, '*.pas')) + glob.glob(os.path.join(SRC, '*.inc'))):
        if os.path.splitext(os.path.basename(f))[0] in EXCLUDE:
            continue
        yield f


def collect():
    """{english text: [file:line, ...]} in order of appearance"""
    found = {}

    def add(text, f, line):
        if text.strip() == '':
            return
        found.setdefault(text, []).append('%s:%d' % (os.path.basename(f), line))

    for f in sources():
        raw = open(f, encoding='utf-8').read()
        t = blank_comments(raw)
        # _('...') and _F('...'): the literals up to the closing parenthesis
        for m in re.finditer(r"(?<![A-Za-z0-9_])(_[FB]?)\(\s*(" + ATOM + r"(?:\s*\+\s*" + ATOM + r")*)\s*\)", t):
            text = ''.join(decode(a) for a in re.findall(ATOM, m.group(2)))
            line = t.count('\n', 0, m.start()) + 1
            if m.group(1) == '_F':
                parts = text.split('|')
                for i in range(0, len(parts), 2):
                    add(parts[i], f, line)
            elif m.group(1) == '_B':
                add('btn:' + text, f, line)
            else:
                add(text, f, line)
        # constants between TR-BEGIN and TR-END
        for m in re.finditer(r"//\s*TR-BEGIN.*?\n(.*?)//\s*TR-END", raw, re.S):
            block = blank_comments(m.group(1))
            base = raw.count('\n', 0, m.start(1)) + 1
            for a in re.finditer(ATOM, block):
                txt = decode(a.group(0))
                if re.search(r'[A-Za-z]{2}', txt):
                    add(txt, f, base + block.count('\n', 0, a.start()))
    return found


def po_escape(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t')


def po_unescape(s):
    return re.sub(r'\\(.)', lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), s)


def read_po(path):
    """{msgid: msgstr}"""
    res = {}
    if not os.path.exists(path):
        return res
    cur = None
    mid = mstr = None
    for line in open(path, encoding='utf-8').read().split('\n') + ['']:
        line = line.rstrip()
        if line.startswith('msgid '):
            if mid is not None:
                res[mid] = mstr or ''
            mid = po_unescape(line[7:-1]); mstr = None; cur = 'id'
        elif line.startswith('msgstr '):
            mstr = po_unescape(line[8:-1]); cur = 'str'
        elif line.startswith('"') and cur:
            v = po_unescape(line[1:-1])
            if cur == 'id':
                mid += v
            else:
                mstr += v
    if mid is not None:
        res[mid] = mstr or ''
    res.pop('', None)
    return res


def write_po(path, entries, refs, lang):
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('msgid ""\nmsgstr ""\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Language: %s\\n"\n' % lang)
        for k, v in entries:
            f.write('\n#: %s\n' % ' '.join(refs.get(k, [])[:3]))
            f.write('msgid "%s"\nmsgstr "%s"\n' % (po_escape(k), po_escape(v)))


def cmd_extract():
    os.makedirs(LANG, exist_ok=True)
    found = collect()
    keys = list(found)
    write_po(os.path.join(LANG, 'ochenta.pot'), [(k, '') for k in keys], found, '')
    for l in LANGS:
        p = os.path.join(LANG, l + '.po')
        old = read_po(p)
        write_po(p, [(k, old.get(k, '')) for k in keys], found, l)
        missing = sum(1 for k in keys if not old.get(k))
        print('%s: %d texts, %d without translation' % (l, len(keys), missing))


def pas_string(s):
    """A Pascal expression for the text (non-ASCII bytes as #$XX, split in lines of reasonable size)"""
    b = s.encode('utf-8')
    parts = []
    cur = ''
    for ch in b:
        c = chr(ch)
        if ch == 39:
            cur += "''"
        elif 32 <= ch < 127:
            cur += c
        else:
            if cur:
                parts.append("'" + cur + "'")
                cur = ''
            parts.append('#$%02X' % ch)
    if cur:
        parts.append("'" + cur + "'")
    if not parts:
        return "''"
    # chunks of at most ~100 characters, joined with +, never splitting a #$ sequence
    out = []
    line = ''
    for p in parts:
        if len(line) + len(p) > 100 and line:
            out.append(line)
            line = ''
        line += p
    out.append(line)
    # adjacent pieces in a line must not have a quote next to a quote (that would be an escaped quote)
    fixed = []
    for l in out:
        fixed.append(re.sub(r"'(?=')", "' + ", l) if False else l)
    res = ' +\n      '.join(fixed)
    # 'a''b' is right; 'a'#$C3 is right; #$C3'a' is right; but 'a' 'b' never appears
    return res


def table(name, pairs):
    pairs = sorted(pairs, key=lambda kv: kv[0].encode('utf-8'))
    lines = ['  %s: array[0..%d] of string = (' % (name, max(len(pairs) * 2 - 1, 1))]
    if not pairs:
        lines[0] += "'', '');"
        return lines
    for i, (k, v) in enumerate(pairs):
        end = ');' if i == len(pairs) - 1 else ','
        lines.append('    %s,' % pas_string(k).replace('\n', '\n  '))
        lines.append('    %s%s' % (pas_string(v).replace('\n', '\n  '), end))
    return lines


def cmd_inc():
    out = ['{ Generated by tools/lang.py inc from lang/*.po and lang/lcl/*.po: do not edit }', 'const']
    lcl_names = {'es': 'es', 'fr': 'fr', 'pt': 'pt_BR', 'de': 'de'}
    for l in LANGS:
        po = read_po(os.path.join(LANG, l + '.po'))
        pairs = [(k, v) for k, v in po.items() if v and v != k]
        out += table('LANG_' + l.upper(), pairs)
        lcl = read_lcl(lcl_names[l])
        out += table('LCL_' + l.upper(), list(lcl.items()))
    open(os.path.join(SRC, 'LangData.inc'), 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
    print('src/LangData.inc written')


def read_lcl(name):
    """The LCL's own texts: its .po file's msgid/msgstr, only the ones with a translation"""
    path = os.path.join(LANG, 'lcl', 'lclstrconsts.%s.po' % name)
    return {k: v for k, v in read_po(path).items() if v and v != k}


def placeholders(s):
    return sorted(re.findall(r'%[-+0-9.]*[dsxXu]|%%', s))


def accel(s):
    return re.findall(r'&\w', s.replace('&&', ''))


def cmd_check():
    found = collect()
    bad = 0
    for l in LANGS:
        po = read_po(os.path.join(LANG, l + '.po'))
        for k in found:
            v = po.get(k, '')
            if not v:
                print('%s: missing: %r' % (l, k))
                bad += 1
                continue
            if placeholders(k) != placeholders(v):
                print('%s: placeholders differ: %r -> %r' % (l, k, v)); bad += 1
            if len(accel(k)) != len(accel(v)):
                print('%s: accelerator differs: %r -> %r' % (l, k, v)); bad += 1
            if k != ' button.' and (k.endswith(' ') != v.endswith(' ') or k.startswith(' ') != v.startswith(' ')):
                print('%s: spaces at the ends differ: %r -> %r' % (l, k, v)); bad += 1
            for w in KEEP:
                if re.search(r'\b' + re.escape(w) + r'\b', k) and w not in v:
                    print('%s: "%s" must stay: %r -> %r' % (l, w, k, v)); bad += 1
    print('%d problems' % bad)
    return bad


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else ''
    {'extract': cmd_extract, 'inc': cmd_inc, 'check': cmd_check}.get(cmd, lambda: print(__doc__))()
