#!/usr/bin/env python3
"""Variety check for Patron portraits. Exit 1 on failure.
Rules: no expression on more than 15 percent of Patrons, smiling expressions on at most 25 percent,
no two Patrons of one rarity share both expression and prop, every Patron in ctp_rarity has an entry,
and every ctp_subjects prompt states its expression, pose and prop. Run: python3 tools/patron_art/check_variety.py"""
import collections, json, pathlib, sys
HERE = pathlib.Path(__file__).resolve().parent
SMILING = {"smiling", "laughing", "delighted", "sly grin"}
MAX_ONE, MAX_SMILE = 0.15, 0.25


def check(variety, rarity, subjects):
    errs = []
    n = len(variety)
    for pid in rarity:
        if pid not in variety:
            errs.append("missing variety entry: " + pid)
    ex = collections.Counter(v["expression"] for v in variety.values())
    for e, c in ex.items():
        if c > MAX_ONE * n:
            errs.append("expression %r on %d of %d Patrons (max %.0f percent)" % (e, c, n, MAX_ONE * 100))
    smiling = sum(c for e, c in ex.items() if e in SMILING)
    if smiling > MAX_SMILE * n:
        errs.append("smiling on %d of %d Patrons (max %.0f percent)" % (smiling, n, MAX_SMILE * 100))
    seen = {}
    for pid, v in variety.items():
        key = (v["rarity"], v["expression"], v["prop"])
        if key in seen:
            errs.append("%s and %s share rarity, expression and prop" % (seen[key], pid))
        seen[key] = pid
    for pid, v in variety.items():
        s = subjects.get("ctp_" + pid, "")
        for field in ("expression", "pose", "prop"):
            if v[field] not in s:
                errs.append("ctp_%s prompt does not state its %s" % (pid, field))
    return errs, ex, smiling


def main():
    variety = json.loads((HERE / "patron_variety.json").read_text(encoding="utf-8"))
    prompts = json.loads((HERE / "prompts.json").read_text(encoding="utf-8"))
    errs, ex, smiling = check(variety, prompts["ctp_rarity"], prompts["ctp_subjects"])
    print("%d Patrons, %d expressions, smiling %d" % (len(variety), len(ex), smiling))
    for e, c in ex.most_common():
        print("  %-12s %d" % (e, c))
    for e in errs:
        print("FAIL", e)
    print("FAIL" if errs else "PASS")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
