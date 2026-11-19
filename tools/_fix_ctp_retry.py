"""One-off: reword the two Patron card prompts that failed the check (gray interior, tankard-like mugs)."""
import json, pathlib

P = pathlib.Path(__file__).parent / "patron_art" / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
s = d["ctp_subjects"]
s["ctp_efficient_service"] = (
    "the same common card, same frame and gem and the same warm parchment paper background inside the frame (no gray, no white), with the character replaced by "
    "a speedy young server with a ponytail and dark skin in a mint green uniform, balancing three plates on one arm and a stopwatch in the other hand. "
    "The wooden name plate at the bottom reads exactly \"Efficient Service\" and nothing else is written anywhere"
)
s["ctp_regulars_round"] = (
    "the same common card, same frame and gem and the same warm parchment paper background inside the frame (no gray), with the character replaced by "
    "a jolly host with a bald head and a ginger beard and pale skin in a green vest, carrying a round tray of three small white ceramic cups of steaming cocoa with marshmallows (cups with a saucer, no handles like tankards), no table. "
    "The wooden name plate at the bottom reads exactly \"Regulars' Round\" and nothing else is written anywhere"
)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok")
