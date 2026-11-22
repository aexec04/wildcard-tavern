import os, re
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
p = os.path.join(root, "src/Shared/Engine/CosmeticSets.lua")
lines = open(p, encoding="utf-8").read().split("\n")
cur = None
n = 0
for i, l in enumerate(lines):
    m = re.match(r'^\t\tid = "([a-z_]+)",', l)
    if m:
        cur = m.group(1)
    m2 = re.match(r'^(\t\tcardBackId = )"[a-z_]+"(,.*)$', l)
    if m2 and cur and cur != "classic_tavern":
        lines[i] = m2.group(1) + '"back_' + cur + '"' + m2.group(2)
        n += 1
open(p, "w", encoding="utf-8").write("\n".join(lines))
print(n)
