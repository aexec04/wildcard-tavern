import json

p = "tools/patron_art/prompts.json"
raw = open(p, encoding="utf-8").read()
d = json.loads(raw)
print({k: (list(v)[:3] if isinstance(v, dict) else type(v).__name__) for k, v in d["house_passes"].items()})
moved = 0
for k, v in d["house_passes"].items():
    if isinstance(v, dict) and "pantry_shelf" in v:
        for pid, text in list(v.items()):
            if pid not in d["housepass_subjects"]:
                d["housepass_subjects"][pid] = text
                moved += 1
print("moved", moved, "now", len(d["housepass_subjects"]))
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
