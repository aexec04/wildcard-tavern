import re, subprocess, sys
lines = open('claude/QUEUE.md').read().split('\n')[1939:1976]
pat = re.compile(r'^python3 tools/patron_art/generate_patron_art\.py record-image ([a-z_0-9]+) (\d+) -c (menu_scene|hud_kit)$')
n = 0
for l in lines:
    if 'record-image' not in l:
        continue
    m = pat.match(l.strip())
    if not m:
        print('SKIP unexpected line:', l[:80])
        continue
    r = subprocess.run(['python3', 'tools/patron_art/generate_patron_art.py', 'record-image', m.group(1), m.group(2), '-c', m.group(3)], capture_output=True, text=True)
    n += 1
    if r.returncode != 0:
        print('FAIL', m.group(1), r.stderr[-200:])
print('ran', n)
for c in ('hud_kit', 'menu_scene'):
    r = subprocess.run(['python3', 'tools/patron_art/generate_patron_art.py', '-c', c, 'lua'], capture_output=True, text=True)
    print(c, r.returncode, (r.stdout + r.stderr)[-200:])
