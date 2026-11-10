#!/usr/bin/env python3
"""One-off: add logo_subjects and logo_style (The Gilded Knave wordmark and emblem) to prompts.json. No API calls.
The logo style differs from house_style on purpose: the wordmark must contain lettering."""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))
d["logo_style"] = (
    "Calm, refined, premium game logo art in a blocky painted Roblox tavern style, matte warm gold on a flat solid pure magenta "
    "#FF00FF background with no gradient and no shadow on it, clean sharp edges, subtle carved character, restrained, "
    "no heavy ornament, no glow, not chunky or noisy, kid-friendly, no alcohol, not a copy of any existing game logo or font"
)
WORD = ("the exact words The Gilded Knave in one line of gilded serif lettering, carved matte gold with a thin dark outline, "
        "letters spelled exactly T h e G i l d e d K n a v e, centered, wide and short, nothing else in the picture, only this one line of text")
d["logo_subjects"] = {
    "logo_wordmark_v1": WORD,
    "logo_wordmark_v2": WORD + ", slightly more rounded letterforms",
    "logo_wordmark_v3": WORD + ", slightly sharper letterforms with tiny serifs",
    "logo_wordmark_v4": WORD + ", a thin gold underline beneath the words",
    "logo_emblem": ("a gilded jack-of-cards knave face wearing a floppy tavern hat and holding a small lantern, inside a round brass coin frame, "
                    "centered, square, no text, no letters, no numbers"),
}
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", len(d["logo_subjects"]))
