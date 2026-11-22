#!/usr/bin/env python3
"""One-off: Golden Gala palace keeper (behind and wave pieces), edits of the classic Marlo pieces. No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
STYLE = (", blocky painted Roblox tavern style, chunky shapes, painted texture, matte, calm, soft warm light, original art, "
         "no text, no letters, no numbers, no logos, no bottles, no alcohol, no weapons, kid-friendly")
MAG = ", flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges"
KEEP = ("Marlo the friendly shopkeeper, redressed as a palace courtier: same blocky Roblox figure, same size, same crop and same pose as the reference image, "
        "no hood, bare friendly face with a kind smile, neat dark hair, a deep burgundy coat with gold trim and gold buttons, a white cravat, "
        "no lantern and no bundle pack, exactly two hands, shown from the waist up, large, facing the viewer, portrait 3:4 composition, centered, ")
d["shop_scene_subjects"]["shop_marlo_gala_behind"] = KEEP + "one arm extended palm up presenting goods toward the viewer's right" + STYLE + MAG
d["shop_scene_subjects"]["shop_marlo_gala_wave"] = KEEP + "one hand raised in a small friendly wave, the other hand resting at his side" + STYLE + MAG
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok")
