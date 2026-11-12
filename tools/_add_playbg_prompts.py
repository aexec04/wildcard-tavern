import json

p = 'tools/patron_art/prompts.json'
s = open(p).read()
base = ("The inside of a cozy tavern seen from the player seat, painted in a warm painterly candlelit style. "
        "A big %s card table with a deep green felt top and a thick wood rim all the way round, warm lantern "
        "light on the felt, dark vignette corners, a dim tavern wall and window glow behind. The felt centre is "
        "empty and the lower third of the frame is clear for a hand tray. No text, no characters, no cards, no UI.")
v = {"play_table_bg_a": base % "round", "play_table_bg_b": base % "oval"}
marker = '"play_scene_subjects": {'
i = s.index(marker) + len(marker)
ins = "\n    " + ",\n    ".join(json.dumps(k) + ": " + json.dumps(t) for k, t in v.items()) + ","
s = s[:i] + ins + s[i:]
json.loads(s)
open(p, 'w').write(s)
