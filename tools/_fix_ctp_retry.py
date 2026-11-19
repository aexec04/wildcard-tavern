"""One-off: reword the Patron card prompt that failed the check (a stemmed glass reads as a wine glass)."""
import json, pathlib

P = pathlib.Path(__file__).parent / "patron_art" / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
d["ctp_subjects"]["ctp_sparkling_service"] = (
    "the same common card, same frame and gem and the same warm parchment paper background inside the frame, with the character replaced by "
    "a glittering waitress with short pink hair and dark skin in a silver vest, polishing a shiny silver teapot with a white cloth until it shines, tiny stars around. "
    "The wooden name plate at the bottom reads exactly \"Sparkling Service\" and nothing else is written anywhere"
)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok")
