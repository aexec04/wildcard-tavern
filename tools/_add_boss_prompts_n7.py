"""One shot: adds boss_subjects (and boss_rounds names if that map is keyed by id) for Frozen Hand, Quiet Tavern and Short Table."""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(ROOT, "tools", "patron_art", "prompts.json")
d = json.load(open(path, encoding="utf-8"))
new = {
    "frozen_hand": "an avatar dealer in a pale blue coat holding a frosty playing card with ice crystals on their gloved hand, a cold glow, a cozy tavern behind, no text",
    "quiet_tavern": "an avatar innkeeper in a purple robe holding a finger to their lips beside a tavern full of sleepy guests with a small candle, hush mood, no text",
    "short_table": "an avatar waiter in a chef hat carrying one wooden chair toward a small crowded tavern table with an empty gap at the end, friendly, no text",
}
print("boss_rounds type", type(d.get("boss_rounds")).__name__)
for key, text in new.items():
    d["boss_subjects"][key] = text
with open(path, "w", encoding="utf-8") as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("ok", len(d["boss_subjects"]))
