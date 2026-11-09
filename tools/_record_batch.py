import re, subprocess, sys
lines = [l for l in open("claude/QUEUE.md").read().splitlines() if l.startswith("  record-image ")][-67:]
cats = set()
for l in lines:
    m = re.match(r"\s+record-image (\S+) (\d+) -c (\S+)", l)
    key, iid, cat = m.groups()
    cats.add(cat)
    subprocess.run([sys.executable, "tools/patron_art/generate_patron_art.py", "record-image", key, iid, "-c", cat], check=True, stdout=subprocess.DEVNULL)
print(len(lines), sorted(cats))
for c in sorted(cats):
    subprocess.run([sys.executable, "tools/patron_art/generate_patron_art.py", "lua", "-c", c], check=True)
