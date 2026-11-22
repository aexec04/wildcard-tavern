import json

p = "tools/patron_art/prompts.json"
raw = open(p, encoding="utf-8").read()
d = json.loads(raw)
d["store_page_style"] = (
    "Stylized 3D render in a Roblox blocky-avatar look, warm candlelit cozy tavern, golden light, rich painterly lighting, "
    "strong contrast, big readable composition with one clear focal point, readable at thumbnail size, "
    "wide cinematic framing with the subject in the middle third and empty dark space near the edges for a title to be added later, "
    "no text, no letters, no numbers, no logos, no watermark, kid-friendly, nothing resembling another game's art"
)
tail = ", playing cards around a wooden tavern table"
d["store_page_subjects"] = {
    "thumb_hero": "close up of a cheerful blocky avatar hero holding up a glowing hand of five playing cards, golden light spilling from the cards, tavern behind softly blurred",
    "thumb_patrons": "a long candlelit tavern table full of friendly blocky avatar patrons laughing and playing cards, warm lanterns overhead, a big pile of golden chips in the middle",
    "thumb_boss": "a blocky hero avatar facing a huge dramatic shadowy boss silhouette across a card table, glowing cards between them, golden light against deep blue shadow",
    "thumb_map": "a blocky hero avatar walking a winding lantern-lit road toward a glowing tavern on a hill at dusk, a treasure map and playing cards floating in the sky",
    "thumb_treasure": "a blocky avatar opening a glowing card pack that bursts with golden light, treasure chest and gold coins and floating playing cards around, amazed face",
    "thumb_cozy": "a cozy tavern at night, a warm fireplace, a table with a single glowing hand of cards, candles and a sleeping cat, a blocky avatar smiling by the window",
    "icon_cards": "centered close up of a fan of five glowing playing cards with a golden crown above them, simple bold shapes, dark warm background" + tail,
    "icon_lantern": "centered glowing golden lantern with a playing card hanging from it, simple bold shapes, dark warm background",
    "icon_hero": "centered smiling blocky avatar face with a tiny tavern hat holding one glowing playing card, simple bold shapes, dark warm background",
}
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
print(len(d["store_page_subjects"]))
