#!/usr/bin/env python3
"""Write claude/SAFETY-AUDIT.md from the prompts.json at git HEAD (before rewording) and the art registries.

Usage: python3 -I tools/patron_art/safety_report.py <prompts_before.json> <out.md>
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import safety_scan as S  # noqa: E402

GROUPS = ("/hud_kit_subjects/", "/play_scene_subjects/")


def registry_ids():
    ids = {}
    for f in sorted((ROOT / "src/Shared/Engine").glob("*Art*.lua")):
        for m in re.finditer(r'\["([^"]+)"\]\s*=\s*"rbxassetid://(\d+)"', f.read_text()):
            ids.setdefault(m.group(1), []).append((f.name, m.group(2)))
    return ids


def main(before, out):
    if before == "HEAD":
        import subprocess
        raw = subprocess.run(["git", "show", "HEAD:tools/patron_art/prompts.json"], cwd=ROOT,
                             capture_output=True, text=True, check=True).stdout
    else:
        raw = Path(before).read_text()
    data = json.loads(raw)
    pat = S.pattern(S.BANNED + S.WATCH)
    ids = registry_ids()
    single, groups = [], {}
    for path, text in S.walk(data):
        found = sorted({m.group(1).lower() for m in pat.finditer(text)})
        if not found:
            continue
        key = path.rsplit("/", 1)[1]
        grp = next((g for g in GROUPS if g in path), None)
        if grp:
            groups.setdefault(grp, []).append((key, found))
        else:
            single.append((path, key, found, text))
    lines = ["# Safety audit of art prompts", "",
             "Scope: every string in tools/patron_art/prompts.json against the banned list (beer, ale, wine, whiskey, rum, liquor, cigar, cigarette, tobacco, skull, blood, gun, pipe smoke) and a wider watch list (drinks in mugs or goblets, bottles, kegs and barrels, pipes, smoke, weapons, poker chips and cash).",
             "No prompt depicts alcohol, tobacco, blood, skulls, guns or cash. The risky phrases were drinks in mugs, goblets, bottles, barrels, a toast, poker chips, smoke, brass pipes, a knife, swords, 'wine red', and 'no skulls, no weapons, no blood' style negatives (naming a thing in a negative can make the image model draw it).",
             "All of them were reworded (cups of cocoa, trophy cups, jars, crates, gold coins, sparkles, brass horns, cake server, brass keys, burgundy red, positive wording). Existing images were NOT regenerated except where noted in OUTBOX, so the asset ids below were made from the old wording. A later `--stale` run would redraw them.",
             "", "## Prompts that matched (original wording)", "",
             "| Asset id | Registry | Key | Matched | Original text |", "|---|---|---|---|---|"]
    for path, key, found, text in single:
        hit = ids.get(key) or ids.get(key.replace("ctp_", ""), [])
        aid = ", ".join(i for _, i in hit) or "none"
        reg = ", ".join(sorted({f for f, _ in hit})) or "no registry entry"
        snippet = text.replace("|", "/")
        m = pat.search(snippet)
        a = max(0, m.start() - 70) if m else 0
        lines.append(f"| {aid} | {reg} | {path.lstrip('/')} | {','.join(found)} | ...{snippet[a:a + 190]}... |")
    lines += ["", "## Grouped (shared negative wording only)", ""]
    for grp, rows in groups.items():
        sample = [ids.get(k, [("", "none")])[0][1] for k, _ in rows[:3]]
        lines.append(f"- {grp.strip('/')}: {len(rows)} prompts said 'no barrels, mugs, bottles or drinks anywhere' or 'no chips'. Plain empty trims and frames, nothing depicted. Reworded to positive wording. Sample ids: {', '.join(sample)}.")
    Path(out).write_text("\n".join(lines) + "\n")
    print(len(single), "single prompts,", sum(len(v) for v in groups.values()), "grouped")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
