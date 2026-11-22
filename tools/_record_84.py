import re
import subprocess
import sys

CATS = {"patrons", "housepasses", "titles", "quests", "endless_rules"}
text = open("claude/QUEUE.md", encoding="utf-8").read()
start = text.index("Record the 84 new art Image ids")
end = text.index("Tavern Season: a 30 day season track", start)
lines = []
for l in text[start:end].splitlines():
    m = re.match(r"^\s+(patrons|housepasses|titles|quests|endless_rules) (\S+) (\d+)\s*$", l)
    if m:
        lines.append(m.groups())
print("lines", len(lines))
if len(lines) != 84:
    sys.exit("expected 84 lines")
for cat, key, iid in lines:
    subprocess.run([sys.executable, "-I", "tools/patron_art/generate_patron_art.py", "record-image", key, iid, "-c", cat],
                   check=True, stdout=subprocess.DEVNULL)
for cat in sorted({c for c, _, _ in lines}):
    r = subprocess.run([sys.executable, "-I", "tools/patron_art/generate_patron_art.py", "lua", "-c", cat], capture_output=True, text=True)
    print(cat, (r.stdout.strip().splitlines() or [""])[-1], r.stderr.strip()[-200:])
