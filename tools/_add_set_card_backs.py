import os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
p = os.path.join(root, "src/Shared/Engine/CardBacks.lua")
t = open(p, encoding="utf-8").read()
S = [("winter_evening", "Winter Evening", "❄", (70, 110, 170), (235, 244, 255), "Frost crystals gather on the glass."),
     ("festival_night", "Festival Night", "🎏", (190, 90, 40), (255, 225, 150), "Bunting sways over the festival square."),
     ("closing_time", "Closing Time", "🌙", (70, 40, 100), (255, 200, 120), "One candle left burning for the last guests."),
     ("golden_gala", "Golden Gala", "👑", (90, 40, 120), (255, 215, 120), "A crown for the grandest table."),
     ("meadow_picnic", "Meadow Picnic", "🌼", (100, 150, 80), (255, 235, 140), "Daisies around a blanket in the sun."),
     ("riverside_evening", "Riverside Evening", "✨", (40, 110, 120), (200, 170, 240), "Fireflies drift above the reeds."),
     ("summit_camp", "Summit Camp", "⛰", (110, 115, 125), (255, 170, 90), "First light on the peaks."),
     ("dune_market", "Dune Market", "🏜", (196, 130, 70), (255, 226, 150), "A warm sun over rippled sand."),
     ("marsh_lanterns", "Marsh Lanterns", "🏮", (45, 90, 60), (250, 230, 130), "Paper lanterns glow along the boardwalk."),
     ("snowy_hearth", "Snowy Hearth", "🔥", (170, 50, 50), (255, 240, 215), "A cabin fire against the snow."),
     ("harbor_lights", "Harbor Lights", "⚓", (25, 45, 90), (220, 185, 110), "An anchor and a lantern at the dock."),
     ("tavern_feast", "Tavern Feast", "🍽", (120, 30, 40), (255, 215, 120), "A long table laid for everyone."),
     ("harvest_table", "Harvest Table", "🌾", (190, 110, 40), (245, 215, 130), "Wheat and leaves from the barn."),
     ("winter_table", "Winter Table", "❄", (100, 140, 190), (245, 248, 255), "One snowflake for every seat.")]
ent = "\t-- one painted back per Card Set (CosmeticSets cardBackId), set only\n"
for i, n, ic, b, tr, f in S:
    ent += "\t{\n\t\tid = \"back_%s\",\n\t\tname = \"%s\",\n\t\ticon = \"%s\",\n" % (i, n, ic)
    ent += "\t\tcolors = { base = { %d, %d, %d }, trim = { %d, %d, %d } },\n" % (b + tr)
    ent += "\t\tdescription = \"The card back of the %s Card Set.\",\n\t\tflavorText = \"%s\",\n\t\tsetOnly = true,\n\t},\n" % (n, f)
marker = "}\n\nfunction CardBacks.getById"
assert marker in t
t = t.replace(marker, ent + marker, 1)
open(p, "w", encoding="utf-8").write(t)
print("ok")
