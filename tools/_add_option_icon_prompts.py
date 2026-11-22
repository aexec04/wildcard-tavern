"""Adds the option_icon_subjects block to prompts.json and registers the option_icons category in the generator."""
import json

p = "tools/patron_art/prompts.json"
s = open(p).read()
if "option_icon_subjects" not in s:
    tail = (", single centered subject filling about 70 percent of the square frame on flat pure magenta #FF00FF with no gradient, "
            "square composition, blocky painted Roblox tavern style, warm lantern light, painterly, readable at 40 pixels, "
            "bold simple shapes, no text, no letters, no numbers, kid-friendly")
    items = {
        "decline": "a friendly open palm held up politely with a small gold check mark of thanks floating beside it",
        "bet": "two wooden dice mid roll with gold pips and a few gold coins beside them",
        "recipe": "a rolled parchment recipe scroll tied with a red ribbon and a small ladle",
        "swap": "two friendly round arrows chasing each other in a circle over a small tavern stool",
        "gain": "a woven basket full of shiny gold coins with a little green sprig on top",
        "hand": "a friendly open hand holding a fan of three playing cards",
        "discard": "a single playing card tossed into the air with small gold motion sparkles",
        "supper": "a steaming wooden bowl of stew with a spoon and a little curl of steam",
    }
    block = '  "option_icon_subjects": {\n' + ",\n".join('    "%s": "%s%s"' % (k, v, tail) for k, v in items.items()) + "\n  },\n"
    i = s.index('  "event_subjects": {')
    s = s[:i] + block + s[i:]
    open(p, "w").write(s)
    json.load(open(p))

g = "tools/patron_art/generate_patron_art.py"
t = open(g).read()
a = '    "events": ("event_subjects", "events", "EventArt.lua", "Event"),\n'
if '"option_icons"' not in t:
    t = t.replace(a, a + '    "option_icons": ("option_icon_subjects", "option_icons", "OptionArt.lua", "Option Icon"),\n', 1)
    b = '    "blessing_icons": {"quality": "low", "style_key": "house_style", "transparent": True},\n'
    t = t.replace(b, b + '    "option_icons": {"quality": "low", "style_key": "house_style", "transparent": True},\n', 1)
    open(g, "w").write(t)
print("ok")
