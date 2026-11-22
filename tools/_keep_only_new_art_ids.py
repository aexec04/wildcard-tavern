"""One shot: the art upload rewrote whole art maps from local records, which swapped a few older ids.
Rebuilds PatronArt.lua and ConceptTPatronArt.lua from git HEAD plus only the new ids given on the command line as key=value.
Usage: python3 -I tools/_keep_only_new_art_ids.py <file> key=rbxassetid://123 ..."""
import re
import subprocess
import sys
import os

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rel = sys.argv[1]
adds = dict(a.split("=", 1) for a in sys.argv[2:])
head = subprocess.run(["git", "show", "HEAD:" + rel], cwd=root, capture_output=True, text=True, check=True).stdout
lines = head.split("\n")
entry = re.compile(r'^\t\["([^"]+)"\] = "(.*)",$')
first = next(i for i, l in enumerate(lines) if entry.match(l))
last = max(i for i, l in enumerate(lines) if entry.match(l))
items = {}
for l in lines[first:last + 1]:
    m = entry.match(l)
    items[m.group(1)] = m.group(2)
items.update(adds)
body = ['\t["%s"] = "%s",' % (k, items[k]) for k in sorted(items)]
out = lines[:first] + body + lines[last + 1:]
open(os.path.join(root, rel), "w").write("\n".join(out))
print("wrote", len(items), "entries")
