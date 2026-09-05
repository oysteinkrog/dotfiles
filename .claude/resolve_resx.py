"""Resolve resx conflicts where both sides only ADD <data> blocks.

The conflict shape git produces here: each side is a run of complete
<data>...</data> blocks followed by ONE block whose closing </data> sits in the
shared trailing context after the >>>>>>> marker. So the resolution is
ours + an explicit close + theirs, leaving theirs' final block open for the
shared close to terminate.

Anything that is not that shape is REFUSED rather than guessed at, so a
conflict where a side edits or replaces a value can never be concatenated into
a duplicate. Every written file is then re-parsed as XML and checked for
duplicate keys.
"""
import re, sys, pathlib, subprocess, xml.etree.ElementTree as ET

KEY = re.compile(r'<data\s+name="([^"]+)"')
CLOSE = "  </data>\n"

def shape_ok(text):
    """True when text is complete <data> blocks plus exactly one dangling opener."""
    rest = re.sub(r'<data\b.*?</data>', '', text, flags=re.S)
    # what remains must be one unclosed opener and whitespace, no stray closer
    if '</data>' in rest:
        return False
    openers = re.findall(r'<data\b', rest)
    if len(openers) != 1:
        return False
    return True

def resolve(path):
    src = pathlib.Path(path).read_text(encoding='utf-8')
    pat = re.compile(r'^<<<<<<< [^\n]*\n(.*?)^=======\n(.*?)^>>>>>>> [^\n]*\n', re.S | re.M)
    out, pos, hunks = [], 0, 0
    for m in pat.finditer(src):
        ours, theirs = m.group(1), m.group(2)
        if not (shape_ok(ours) and shape_ok(theirs)):
            return None, "hunk is not the additive dangling-block shape"
        ok, tk = set(KEY.findall(ours)), set(KEY.findall(theirs))
        both = ok & tk
        if both:
            return None, f"key(s) on BOTH sides: {sorted(both)}"
        out.append(src[pos:m.start()]); out.append(ours); out.append(CLOSE); out.append(theirs)
        pos = m.end(); hunks += 1
    if hunks == 0:
        return None, "no conflict hunks found"
    out.append(src[pos:])
    text = ''.join(out)
    for marker in ('<<<<<<<', '>>>>>>>', '\n=======\n'):
        if marker in text:
            return None, "markers remain after resolution"
    keys = KEY.findall(text)
    dupes = {k for k in keys if keys.count(k) > 1}
    # These satellites already ship duplicate <data> keys (18 per file), present
    # identically in base, ours and theirs. Refuse only duplicates this
    # resolution INTRODUCES; pre-existing ones are a separate defect and would
    # otherwise make every file unresolvable.
    inherited = set()
    for stage in ("1", "2", "3"):
        blob = subprocess.run(["git", "show", f":{stage}:{path}"],
                              capture_output=True, text=True)
        if blob.returncode:
            continue
        ks = KEY.findall(blob.stdout)
        inherited |= {k for k in ks if ks.count(k) > 1}
    introduced = sorted(dupes - inherited)
    if introduced:
        return None, f"resolution INTRODUCED duplicate keys: {introduced[:5]}"
    try:
        ET.fromstring(text)
    except ET.ParseError as e:
        return None, f"XML does not parse: {e}"
    return text, f"{hunks} hunk(s), {len(keys)} keys, XML parses, {len(dupes & inherited)} pre-existing dupes carried, 0 introduced"

failed = 0
for p in sys.argv[1:]:
    text, msg = resolve(p)
    name = p.rsplit('/', 1)[-1]
    if text is None:
        failed += 1; print(f"REFUSED {name}: {msg}")
    else:
        pathlib.Path(p).write_text(text, encoding='utf-8')
        print(f"ok      {name}: {msg}")
print(f"\nrefused: {failed} / {len(sys.argv)-1}")
sys.exit(1 if failed else 0)
