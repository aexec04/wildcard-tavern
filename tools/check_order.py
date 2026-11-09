#!/usr/bin/env python3
"""Flags a top-level `local X` that is read earlier in the same file than its declaration
(the earlier use compiles as a nil global). Usage: python3 -I tools/check_order.py
Heuristic: strips comments and strings; a name that is shadowed (local, parameter or for
variable) on or before the use line is skipped, so hits are real or rare false positives."""
import re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent


def strip(line):
    line = re.sub(r'"(\\.|[^"\\])*"|\'(\\.|[^\'\\])*\'', '""', line)
    return re.sub(r'--.*', '', line)


def check(path):
    text = re.sub(r'--\[(=*)\[.*?\]\1\]', lambda m: "\n" * m.group(0).count("\n"), path.read_text(encoding="utf8"), flags=re.S)
    text = re.sub(r'\[(=*)\[.*?\]\1\]', lambda m: '""' + "\n" * m.group(0).count("\n"), text, flags=re.S)
    lines = [strip(l) for l in text.split("\n")]
    top = {}
    for i, l in enumerate(lines):
        if l[:1] in (" ", "\t"):
            continue
        m = re.match(r'local\s+function\s+([A-Za-z_]\w*)', l) or re.match(r'local\s+([A-Za-z_][\w, ]*?)\s*(=|$)', l)
        if m:
            for name in re.split(r'\s*,\s*', m.group(1)):
                if re.fullmatch(r'[A-Za-z_]\w*', name) and name not in top:
                    top[name] = i
    hits = []
    for name, decl in top.items():
        n = re.escape(name)
        pat = re.compile(r'(?<![\w.:])' + n + r'(?!\w)')
        shadow = re.compile(r'(local\s+[^=]*(?<![\w.])' + n + r'(?!\w)|function[^(]*\([^)]*(?<!\w)' + n + r'(?!\w)|for\s+[^=]*(?<!\w)' + n + r'(?!\w))')
        for j in range(decl):
            if pat.search(lines[j]):
                if any(shadow.search(lines[k]) for k in range(0, j + 1)):
                    break
                hits.append((str(path.relative_to(root)), j + 1, name, decl + 1))
                break
    return hits


def main():
    bad = []
    for sub in ("src/Server", "src/Client", "src/Shared"):
        for p in sorted((root / sub).rglob("*.lua")):
            bad += check(p)
    for f, ln, name, decl in bad:
        print(f"[order] {f}:{ln} uses '{name}' before its declaration at line {decl}")
    if not bad:
        print("[order] no top-level local is used before its declaration")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
