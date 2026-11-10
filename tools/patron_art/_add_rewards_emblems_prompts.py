#!/usr/bin/env python3
"""One-off: add the rewards_emblem prompts (Collection Rewards) to prompts.json. No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
STYLE = (", blocky painted Roblox tavern style, chunky shapes, painted texture, matte, calm, low contrast, soft warm light, "
         "original art, no text, no letters, no numbers, no logos, kid-friendly, square 1:1 composition")
MAG = ", flat solid pure magenta #FF00FF background filling every empty pixel with no gradient, no shadow and no glow touching the edge, object centred with a margin, clean sharp edges"
M = "a round brass medallion with "
d["rewards_emblem_subjects"] = {
    "rewards_emblem_patrons": M + "a small framed patron portrait silhouette and a tricorn hat" + STYLE + MAG,
    "rewards_emblem_recipes": M + "an open recipe book, a wooden spoon and a small flame" + STYLE + MAG,
    "rewards_emblem_bosses": M + "a horned crown above crossed keys" + STYLE + MAG,
    "rewards_emblem_cardsets": M + "a fan of three playing cards with plain faces" + STYLE + MAG,
    "rewards_emblem_titles": M + "an engraved scroll plaque and a ribbon" + STYLE + MAG,
    "rewards_emblem_bonds": M + "two pins joined by a red string" + STYLE + MAG,
    "rewards_emblem_passes": M + "a ticket and a key crossed" + STYLE + MAG,
    "rewards_pouch_small": "a small leather coin pouch tied with string, a few coins peeking out" + STYLE + MAG,
    "rewards_pouch_full": "a bulging leather coin pouch with a golden clasp and coins spilling" + STYLE + MAG,
}
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", len(d["rewards_emblem_subjects"]))
