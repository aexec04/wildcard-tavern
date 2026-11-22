import json

p = "tools/patron_art/prompts.json"
raw = open(p, encoding="utf-8").read()
d = json.loads(raw)
tail = ", single centered subject with generous margin on a plain dark brown background, square composition, painterly, no text, no letters, no numbers, kid-friendly"
spectate = {
    "eye": "a friendly golden eye icon with long lashes inside a round wooden badge",
    "cheer": "a colorful party popper bursting with confetti and ribbons",
    "gasp": "a round surprised face with wide eyes and a small open mouth, golden glow",
    "clap": "two hands clapping with golden sparkles around them",
    "fire": "a cheerful orange flame with a yellow center and small sparks",
    "heart": "a bright red heart with a golden shine and tiny sparkles",
    "laugh": "a round laughing face with a big smile and happy tears, golden glow",
}
d.setdefault("spectate_subjects", {})
for k, v in spectate.items():
    d["spectate_subjects"].setdefault(k, v + tail)
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
print(len(d["spectate_subjects"]))
