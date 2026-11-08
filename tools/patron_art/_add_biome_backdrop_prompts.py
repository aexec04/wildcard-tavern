#!/usr/bin/env python3
"""One-off: add the 8 biome table backdrops (category `biome_backdrops`) to prompts.json.

They sit behind the card table (Engine/BiomeBackdrops.Images), so: wide empty scenery, calm center,
darker lower third, no people or props where the cards go, same size and composition as the default.
Generation costs credits: run `generate_patron_art.py generate -c biome_backdrops` only for a queue task
marked ALLOWED: generate.
"""
import json
import pathlib

P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

COMP = ("Composition: calm darker center and lower third (soft shadow, ground, no busy detail), interest in the "
        "upper half and the edges, strong dark vignette, clear horizontal light-to-dark flow, wide empty scenery, "
        "no people, no characters, no props where cards would sit, no text, no letters, no logos, kid-friendly")

backdrops = {
    "meadow": "wide landscape backdrop, a quiet wildflower meadow at golden evening with rolling green-gold hills, soft grass and a warm sky",
    "river": "wide landscape backdrop, a calm willow river at dusk with cool blue water, reeds and drifting mist",
    "peaks": "wide landscape backdrop, grey-blue mountain peaks and pine slopes at sunset with a rocky ledge in the foreground",
    "desert": "wide landscape backdrop, amber sand dunes at sunset with long soft shadows and a pale warm sky",
    "swamp": "wide landscape backdrop, a murky green marsh at twilight with reeds, lily pads and fireflies",
    "snow": "wide landscape backdrop, a snowy pine trail at blue dusk with soft drifts and a pale glowing sky",
    "coast": "wide landscape backdrop, a teal sea cove at sunset with smooth rocks, gentle waves and a faint far lighthouse glow",
    "tavern": "wide landscape backdrop, a warm lantern-lit tavern courtyard at dusk with cobblestones, dark timber and golden window light",
}
d["biome_backdrop_subjects"] = {k: f"{v}. {COMP}" for k, v in backdrops.items()}
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("added", len(backdrops), "biome backdrop prompts")
