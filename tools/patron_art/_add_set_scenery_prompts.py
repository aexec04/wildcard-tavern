#!/usr/bin/env python3
"""One-off: add prompts for the Card Set gameplay scenery (category `set_scenery`), one wide scene per set
except classic_tavern (which keeps the default sunset road). Generating costs credits: run
`generate_patron_art.py generate -c set_scenery` only for a queue task marked ALLOWED: generate."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

TAIL = (". Same painted style as a soft golden-hour road scene: readable shapes, gentle light. Composition: wide open "
        "scene, interest in the upper half and the edges, calm lower-middle area with plain ground and no busy detail "
        "so playing cards stay legible, darker toward the bottom, no people, no characters, no props where cards would "
        "sit, no text, no letters, no logos, kid-friendly")

SCENES = {
    "winter_evening": "wide scene, a snowy garden path at dusk with glowing lanterns on posts, frosted hedges and soft falling snow",
    "festival_night": "wide scene, a lantern-lit mountain festival field with colorful bunting strung between poles and paper lanterns",
    "closing_time": "wide scene, a quiet tavern yard at the end of the evening with a few dim lamps, stacked barrels of apples and a starry sky",
    "golden_gala": "wide scene, a grand garden terrace dressed in gold for an evening party, gold lanterns, ribbons and fountains",
    "meadow_picnic": "wide scene, a sunny wildflower meadow with a checkered picnic cloth far in the background, butterflies and soft golden light",
    "riverside_evening": "wide scene, a quiet riverbank at evening with a wooden footbridge, glowing lanterns on posts and cool blue water",
    "summit_camp": "wide scene, a cozy mountain summit camp with striped tents, a small campfire glow and far snowy peaks at sunset",
    "dune_market": "wide scene, a golden desert market at sunset with striped awnings, hanging lamps and soft rolling dunes",
    "marsh_lanterns": "wide scene, a misty marsh boardwalk with floating lanterns, reeds and fireflies over calm water",
    "snowy_hearth": "wide scene, a snowy hillside lodge yard with warm glowing windows, snow-laden pines and drifting flakes",
    "harbor_lights": "wide scene, a lantern-lit harbor boardwalk at dusk with small boats, rope-wrapped posts and a teal evening sky",
    "tavern_feast": "wide scene, a tavern courtyard set for a feast with long wooden tables far back, garlands, warm lamps and a golden sunset",
    "harvest_table": "wide scene, an autumn orchard under a harvest moon with pumpkins, hay bales and glowing lanterns",
    "winter_table": "wide scene, a cozy winter courtyard with fairy lights, snow-dusted wreaths and a soft blue-gold twilight",
}

d["set_scenery_subjects"] = {k: v + TAIL for k, v in SCENES.items()}
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("added", len(SCENES), "set_scenery prompts")
