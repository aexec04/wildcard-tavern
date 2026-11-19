#!/usr/bin/env python3
"""One-off: add the table_scene prompts (candlelit gameplay table, boss variant, counter, run over) to prompts.json. No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
STYLE = (", blocky painted Roblox tavern style, hand painted texture, matte, same warm lantern and candle light as the reference tavern, "
         "dark brown wood, aged paper, deep soft shadows, painted not photographic, original art, wide 3:2 composition, "
         "no text, no letters, no numbers, no logos, no user interface, no cards, no characters, kid-friendly")
d["table_scene_subjects"] = {
    "table_play": "a round dark muted deep green felt card table seen from slightly above with a worn wood rim, a few candles and a small stack of coins at the far edges, tavern wall and a window blurred and dark behind, the felt centre large, calm, low contrast and completely empty so cards will stand out" + STYLE,
    "table_boss": "the same round muted green felt card table seen from slightly above with a worn wood rim, but darker with a vignette and redder candle light, a few candles at the edges, blurred dark tavern behind, the felt centre large, calm, low contrast and completely empty" + STYLE,
    "table_counter": "a wooden shop counter seen from the front with shelves of jars and crates behind it, hanging lanterns, warm candle light, blurred and soft, the wide centre area empty and calm so cards will stand out" + STYLE,
    "table_runover": "a quiet empty tavern table at closing time, ember light from a dying fire, a single candle, chairs pushed in, blurred dark room behind, the wide centre of the table empty and calm" + STYLE,
}
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", len(d["table_scene_subjects"]))
