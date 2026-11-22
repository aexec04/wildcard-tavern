import sys, glob
apply = sys.argv[1] == "apply"
OVR = [('" -- " .. tostring(result.dateKey)','": " .. tostring(result.dateKey)'), ("JUMBO -- ", "JUMBO: "), ("MEGA -- ", "MEGA: "), ("Daily Challenge -- ", "Daily Challenge: "),
       ("%s -- %d", "%s: %d"), ("%s -- %s", "%s: %s"), ("Cleared -- Endless", "Cleared: Endless"),
       (" -- full! Sell", " is full! Sell"), ("   --   ", "   |   ")]


def split_line(line):
    out = []
    i = 0
    n = len(line)
    cur = ""
    while i < n:
        c = line[i]
        if c in "\"'":
            j = i + 1
            while j < n and line[j] != c:
                if line[j] == "\\":
                    j += 1
                j += 1
            out.append((False, cur))
            cur = ""
            out.append((True, line[i:j + 1]))
            i = j + 1
            continue
        if line.startswith("--", i):
            out.append((False, cur + line[i:]))
            return out
        cur += c
        i += 1
    out.append((False, cur))
    return out


def fix(s):
    for a, b in OVR:
        s = s.replace(a, b)
    s = s.replace(" -- ", ", ").replace("—", ",").replace("–", "-")
    if s in ('"---"', "'---'"):
        s = s[0] + "-" + s[0]
    return s


changed = 0
for f in glob.glob("src/**/*.lua", recursive=True):
    if "/Tests/" in f:
        continue
    L = open(f, encoding="utf-8").read().split("\n")
    dirty = False
    inblock = False
    for k, line in enumerate(L):
        if inblock:
            if "]]" in line:
                inblock = False
            continue
        if "--[[" in line and "]]" not in line.split("--[[", 1)[1]:
            inblock = True
            continue
        if line.lstrip().startswith("--"):
            continue
        new = "".join(
            fix(t) if isS and (" -- " in t or "—" in t or "–" in t or t in ('"---"', "'---'")) else t
            for isS, t in split_line(line))
        if new != line:
            print("%s:%d: %s" % (f, k + 1, new.strip()[:150]))
            L[k] = new
            dirty = True
            changed += 1
    if dirty and apply:
        open(f, "w", encoding="utf-8").write("\n".join(L))
print(changed)
