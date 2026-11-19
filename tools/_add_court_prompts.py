"""One-off: add Concept T court card figure prompts (12: K, Q, J in four suits) to prompts.json."""
import json, pathlib

P = pathlib.Path(__file__).parent / "patron_art" / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

d["ctc_style"] = (
    "Edit the reference image: keep EXACTLY the same hand-painted blocky Roblox character style, paint texture, thin dark outline, warm palette and "
    "half-length framing, but draw a NEW friendly character as described. Only the character, no card, no frame, no border, no corner marks, no "
    "letters, no numbers, no text and no suit symbols anywhere, on a flat solid pure magenta #FF00FF background with no gradient and no shadow on "
    "it, clean sharp edges, the figure centred with generous margin. Bright, kind, kid-friendly original art, not dark, no weapons"
)
SUITS = {
    "spades": "midnight blue and silver robes with a deep indigo cape",
    "hearts": "crimson and gold robes with a white fur collar",
    "diamonds": "amber orange and teal robes with golden trim",
    "clubs": "forest green and bronze robes with a leafy trim",
}
WHO = {
    "k": ("a kind king with a gold crown", {
        "spades": "a broad silver bearded man with light skin",
        "hearts": "a jolly man with a thick brown beard and rosy cheeks",
        "diamonds": "a tall man with dark skin and a neat black moustache",
        "clubs": "an older man with a white beard and warm tan skin"}),
    "q": ("a kind queen with a gold crown", {
        "spades": "a poised woman with long silver braids and pale skin",
        "hearts": "a smiling woman with long wavy brown hair",
        "diamonds": "a cheerful woman with dark skin and a high golden bun",
        "clubs": "a gentle woman with red curls and freckles"}),
    "j": ("a young knave in a feathered cap instead of a crown", {
        "spades": "a lanky teenager with short black hair and olive skin",
        "hearts": "a cheeky boy with messy blond hair",
        "diamonds": "a grinning teenager with curly dark hair and brown skin",
        "clubs": "a small keen boy with a green feather in his cap and brown hair"}),
}
subj = {}
for r, (role, looks) in WHO.items():
    for s, robe in SUITS.items():
        subj[f"court_{r}_{s}"] = f"{role}: {looks[s]}, wearing {robe}, friendly smile, half-length figure, hands relaxed in front"
d["ctc_subjects"] = subj
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(len(subj), "court subjects")
