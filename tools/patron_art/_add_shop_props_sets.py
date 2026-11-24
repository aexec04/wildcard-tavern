#!/usr/bin/env python3
"""One-off: per-Card-Set counter props sheets (edits of shop_counter_props so the crops stay valid). No API calls."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
STYLE = (", keep exactly the same four props in exactly the same positions and sizes as the reference picture (brass service bell, closed ledger book, wooden mug, lit candle in a brass holder), "
         "blocky painted Roblox tavern style, chunky shapes, painted texture, matte, calm, original art, no text, no letters, no numbers, no logos, kid-friendly, "
         "flat solid pure magenta #FF00FF background with no gradient and no shadow on it, clean sharp edges")
LOOK = {
    "winter_evening": "repaint the props as frosted winter versions: the book has an icy pale blue cover with silver corners and a dusting of snow on top, the bell is silvery brass with frost and a tiny icicle, the mug is pale blue ceramic with a snowy rim, the candle has frost on its brass holder",
    "festival_night": "repaint the props for a mountain lantern festival: the book has a deep red cover with gold trim and a paper lantern charm, the bell is bright brass with a red ribbon, the mug is red and gold painted ceramic, the candle sits in a small red paper lantern holder",
    "closing_time": "repaint the props for a quiet late closing time: dim muted tones, the book has a dark navy cover with dull brass corners, the bell is tarnished dark brass, the mug is dark blue ceramic, the candle is a half-burned stub in a dark holder",
    "golden_gala": "repaint the props as palace gala versions: the book has a white and gold cover with ornate gold corners, the bell is polished shining gold, the mug is a white and gold goblet, the candle is a tall ivory candle in a gold candelabra holder",
    "meadow_picnic": "repaint the props as a spring meadow picnic: the book has a soft green cloth cover with a tiny flower, the bell is light brass with a green ribbon, the mug is a cream enamel cup with small flowers, the candle sits in a little glass jar with a daisy",
    "riverside_evening": "repaint the props for a riverside evening: the book has a teal blue cover with wet shine, the bell is brass with a blue-green patina, the mug is blue-grey pottery, the candle sits in a small lantern with a reed",
    "summit_camp": "repaint the props for a high mountain camp: the book has a weathered green canvas cover with a leather strap, the bell is a dented camp bell of grey iron, the mug is a dented tin camp cup with a light dusting of snow, the candle sits in a metal camp lantern",
    "dune_market": "repaint the props for a desert market: the book has a sand-colored cover with a copper clasp and a woven pattern, the bell is hammered copper, the mug is a terracotta cup with an orange pattern, the candle sits in a copper holder with small cut-out stars",
    "marsh_lanterns": "repaint the props for a misty marsh: the book has a mossy dark green cover with a few leaves, the bell is brass with green moss on it, the mug is a green-brown clay cup, the candle glows soft green-yellow in a small glass marsh lantern",
    "snowy_hearth": "repaint the props as cozy snowy hearth versions: the book has a warm cream and red knit cover with a dusting of snow, the bell is brass with a small pine sprig, the mug is a warm cocoa mug with steam and a snowy rim, the candle is a red candle in a brass holder with holly",
    "harbor_lights": "repaint the props for a harbor tavern: the book has a navy blue cover with a rope-bound edge, the bell is a ship's brass bell with a rope, the mug is a blue and white striped pottery tankard, the candle sits in a small ship's lantern",
    "tavern_feast": "repaint the props for a big tavern feast: the book has a rich burgundy cover with gold corners, the bell is shiny brass with a small wheat sprig, the mug is a large golden pewter tankard, the candle is a thick tall candle in a brass holder dripping wax",
    "harvest_table": "repaint the props for an autumn harvest table: the book has an orange-brown leather cover with a dried leaf, the bell is brass with a small corn husk bow, the mug is an orange pumpkin-colored cup, the candle sits in a small gourd holder",
    "winter_table": "repaint the props for a winter welcome table: the book has an evergreen cover with a red ribbon and a dusting of snow, the bell is gold with a holly sprig, the mug is a red and white cup with a snowy rim, the candle is a white candle in a gold holder with pine",
}
subj = d["shop_scene_subjects"]
for k, v in LOOK.items():
    subj["shop_counter_props_" + k] = v + STYLE
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", list(LOOK))
