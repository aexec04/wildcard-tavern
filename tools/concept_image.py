#!/usr/bin/env python3
"""
One-off concept image generator (OpenAI, model from .env). Not part of the game build.
Run from the project root on your Mac:
  python3 tools/concept_image.py                 # one image by default (about 0.25 USD at high quality); add --all for every variant
  python3 tools/concept_image.py --quality medium --only A
  python3 tools/concept_image.py --style pixel     # pixel art variants D, E, F
  python3 tools/concept_image.py --style roblox    # bright Roblox look, variants G, H, I
  python3 tools/concept_image.py --ref claude/reference/concepts/rusty_mug_ref.png   # redraw the reference in Roblox style
  python3 tools/concept_image.py --ref <concept_R file> --prompt tweak   # quieter crowd, clearer rarity labels
  python3 tools/concept_image.py --assets      # three asset sheets in the same style (about 0.75 USD)
Reads OPENAI_API_KEY from tools/patron_art/.env. Writes PNGs to claude/reference/concepts/.
"""
import argparse, base64, os, pathlib, sys, time
import requests

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "claude" / "reference" / "concepts"

BASE = (
    "A polished game screenshot mockup of an original Roblox-style fantasy tavern card game, wide landscape. "
    "Warm, inviting, medium brightness: a cozy candlelit tavern with a glowing stone fireplace, soft purple banners, "
    "and softly blurred blocky Roblox-style tavern guests in the background. Exposure is balanced so every card and "
    "every number is clearly visible, not too dark and not oversaturated orange. "
    "The table is a rich dark green felt with a polished wooden rail, seen from a slightly raised 3D camera with soft depth of field. "
    "Center-bottom: a hand of 7 large ivory playing cards with thin gold filigree borders, gently fanned, soft shadows under each, "
    "one card lifted a little with a warm gold glow to show it is selected. "
    "Above the felt, a row of 5 collectible Patron character cards in ONE cohesive painted Roblox-character art style, "
    "all same size and frame shape: a cheerful jester, a bearded king, a purple wizard, a hooded rogue, a friendly green ogre. "
    "Each card has a short name plate and a small rarity gem. Rarity is instantly readable by frame color and glow: "
    "Common is plain wood and brass with no glow, Uncommon is green, Rare is blue with a shimmer, Epic is purple with swirling magic sparkles, "
    "Legendary is gold with radiant rays. Show one of each tier across the five cards. "
    "Two Patron cards have small floating effect pills above them reading +30 and +4 with tiny sparkle bursts. "
    "In the middle of the felt, a soft glowing scoring stage with the words Full House and a large score number. "
    "The interface is minimal and original: a slim carved wooden banner at top center showing Round 3 and a gold progress bar; "
    "two small round icons in the top-left corner for coins and hands left; one large glowing brass Play Hand button at bottom center "
    "and one smaller Discard button next to it; a small card deck pile at bottom right with a count; a tiny settings gear at top right. "
    "Exactly two action buttons plus the gear. No tall side panels, no stat bars, no other buttons. "
    "Do not print the word Joker anywhere. Crisp readable text, clean game UI, no logos, no copyrighted characters."
)

VARIANTS = {
    "A": "Lighting: warm golden-hour tavern, bright and friendly.",
    "B": "Lighting: balanced evening tavern, moderately bright, slightly cooler purple shadows, warm candle highlights.",
    "C": "Lighting: bright cozy tavern, high clarity, the felt table lit by a hanging chandelier, rich saturated colors.",
}


PIXEL_BASE = (
    "A polished 16-bit pixel art game screenshot of an original fantasy tavern card game, wide landscape, crisp chunky pixels, rich warm colors with purple accents. "
    "Warm cozy medium-brightness tavern: wooden beams, a glowing stone fireplace on the right, a candle chandelier, purple banners with a gold crown, "
    "a crowd of tavern regulars with mugs in the background, and a sleepy orange cat curled up on a barrel at the right. "
    "A wooden table with a dark maroon felt mat in the foreground. "
    "Bottom center: a hand of 7 cream playing cards with simple pixel pips, gently fanned, one card lifted with a soft gold outline. "
    "Above the table, a row of 5 collectible Patron cards in ONE cohesive pixel art style, same size and frame shape: a cheerful jester, a bearded king, a purple wizard, a hooded rogue, a friendly green ogre. "
    "Each has a short name plate and a small rarity gem; rarity is readable at a glance by frame color and glow: Common wood and brass, Uncommon green, Rare blue, Epic purple with sparkles, Legendary gold with rays, one of each tier. "
    "Two Patron cards have small floating effect pills above them reading +30 and +4 with tiny pixel sparkles. "
    "In the middle of the felt, a glowing scoring stage with the words Full House and one large score number. "
    "The interface is minimal and original: a slim carved wooden banner at top center showing Round 3 and a gold progress bar; two small round pixel icons in the top-left corner for coins and hands left; "
    "one large glowing brass Play Hand button at bottom center and one smaller Discard button beside it; a small deck pile at bottom right with a count; a tiny settings gear at top right. "
    "Exactly two action buttons plus the gear. Absolutely no tall side panel, no blue and red stat boxes, no Run Info or Options buttons. "
    "Do not print the word Joker anywhere. Crisp readable pixel text, no logos, no copyrighted characters."
)
PIXEL_VARIANTS = {
    "D": "Lighting: warm and cozy, bright fireplace glow.",
    "E": "Lighting: balanced evening, soft purple shadows, warm candle highlights.",
    "F": "Lighting: bright and cheerful, clear colors, strong readability.",
}

ROBLOX_BASE = (
    "A premium, AAA-quality 3D game screenshot of a top-tier Roblox game, with the blocky Roblox art style but very high production value: "
    "richly detailed materials (real wood grain, brushed brass, stitched felt, glossy lacquer, soft fabric), realistic global illumination, soft shadows, ambient occlusion, "
    "gentle bloom, shallow depth of field, crisp high-resolution textures, and carefully designed ornate details everywhere. Blocky, chunky shapes and Roblox avatar proportions are the style, not a shortcut: "
    "every surface is beautifully crafted, nothing looks flat, cheap, or low-poly. Bright, warm, welcoming and colorful. "
    "Wide landscape. The setting is a sunny, welcoming tavern game room built in Roblox: honey-colored wooden beams and planks with visible grain, large arched windows with bright daylight and light rays, "
    "colorful hanging banners and bunting, a stone fireplace with a lively flame, shelves with detailed mugs and bottles, and a few expressive Roblox avatars with custom outfits cheering at tables in the softly blurred background. "
    "Nothing is spooky or dark, no skulls, no hooded figures, no dungeon or roguelike look. "
    "In the foreground, a handsome rounded wooden card table with a rich teal-green stitched felt top and a polished rail, seen from a slightly raised 3D camera. "
    "Bottom center: a hand of 7 large, beautifully designed playing cards with glossy ivory faces, ornate gold corner details, crisp pips, soft contact shadows, gently fanned, one card lifted with a bright golden glow. "
    "Above the table, a row of 5 collectible Patron cards in ONE cohesive style, same size and ornate rounded frames: each shows a highly detailed Roblox avatar character with a custom outfit, expressive face, and a dynamic pose: "
    "a joyful jester, a friendly king with a jeweled crown, a cheerful wizard with a starry hat and glowing staff, a happy chef with a tall hat, and a jolly green troll adventurer. "
    "Each card has an engraved name plate and a faceted gem. Rarity is instantly readable by frame material and effects: Common is carved wood and brass, Uncommon is emerald green with leaf filigree, "
    "Rare is sapphire blue with a shimmering glow, Epic is amethyst purple with swirling magic sparkles, Legendary is shining gold with radiant light rays and a small crown, one of each tier. "
    "Two Patron cards have glowing floating effect pills above them reading +30 and +4 with particle bursts. "
    "In the middle of the felt, a radiant scoring stage with the words Full House and one large score number in bold outlined golden letters with glow. "
    "The interface is minimal but premium: an ornate carved wooden sign at top center showing Round 3 with a glowing yellow progress bar; "
    "two small round glossy brass icons at top-left for coins and hands left; one large glowing green gem-studded Play Hand button at bottom center with a gold rim and one smaller warm orange Discard button beside it; "
    "a small detailed deck pile at bottom right with a count; a tiny brass settings gear at top right. Exactly two action buttons plus the gear. No side panels, no stat boxes, no other buttons. "
    "Do not print the word Joker anywhere. Crisp readable text, no logos, no copyrighted characters."
)
ROBLOX_VARIANTS = {
    "G": "Mood: sunny afternoon, warm daylight through big windows.",
    "H": "Mood: festive party, colorful bunting and confetti, lively and playful.",
    "I": "Mood: bright cozy cafe, soft pastel accents, extra clean and glossy.",
}

REF_PROMPT = (
    "Use the reference image as the art direction and composition guide. Keep its warm, lived-in, hand-crafted indie game charm: a busy tavern full of different characters, "
    "a sleepy orange cat curled up on a barrel at the right, a stone fireplace, hanging purple banners with a gold crown, a candle chandelier, wooden beams, cozy warm lighting, "
    "a row of five collectible cards at the top, a fanned hand of cards on a table at the bottom, and a deck pile at the bottom right. "
    "Redraw the whole scene as a stylized Roblox game screen: blocky Roblox avatars and a 3D Roblox look, but hand-painted and charming, not glossy. "
    "Limited warm color palette, soft stylized lighting, gentle imperfections, clear silhouettes, no bloom, no over-rendering, no stock-ad look, no AAA gloss. "
    "Every character must look different: varied face shapes, hair, skin tones, ages, hats and outfits, with real personality, nobody alike. "
    "Make it brighter and friendlier than the reference, cozy and cheerful, not dark and not roguelike: no skulls, no hooded figures. "
    "Change the interface completely. Remove the whole left panel, the Run Info and Options buttons, the blue and red score boxes, the Score at least box and the Round score box. "
    "New minimal HUD only: a slim carved wooden banner at top center showing Round 3 with a gold progress bar; two small round icons top-left for coins and hands left; "
    "one large Play Hand button at bottom center and one smaller Discard button beside it, in the same hand-painted style as the cards; the deck pile with a count at bottom right; a small settings gear top right. "
    "In the middle of the table, a glowing scoring stage with the words Full House and one large score number. "
    "The five top cards are Patron cards: a jester, a friendly king with a crown, a wizard with a starry hat, an alchemist holding a green potion, and a tavern cat, each a different Roblox-style character or creature with its own personality. "
    "Show rarity by frame color and a small gem, one of each tier: Common wood and brass, Uncommon green, Rare blue, Epic purple with sparkles, Legendary gold with rays. "
    "Two Patron cards show small floating effect pills reading +30 and +4. "
    "Do not print the word Joker anywhere. Crisp readable text, no logos, no copyrighted characters."
)

STYLE_LOCK = (
    "Hand-painted, stylized Roblox 3D game art in the exact same art style, palette, materials and level of detail as the reference image: "
    "blocky Roblox avatars, warm limited palette, soft stylized lighting, gentle imperfections, no bloom, no glossy over-rendering. "
)

REF_PROMPTS = {
    "redraw": REF_PROMPT,
    "tweak": (
        "Keep the reference image almost exactly: the same characters, the sleeping cat, the five Patron cards, the hand of cards, the layout, the palette and the hand-painted Roblox style. "
        "Make only these changes. 1) The big foreground crowd avatars become smaller, lower contrast and softly blurred with depth of field, and sit lower and further back, "
        "so they no longer crowd the scoring stage or sit right behind the Patron row; the middle of the table around the score stays clear. "
        "2) Every Patron card gets an engraved name plate under its portrait and a small tier label (Common, Uncommon, Rare, Epic, Legendary), "
        "and all five cards use the same effect pill style, with +30 and +4 on two of them. "
        "3) The deck count sits on a small plate attached to the deck pile. 4) Slightly brighter, warmer lighting overall. "
        "Everything else stays unchanged. Do not print the word Joker anywhere."
    ),
    "sheet_patrons": (
        STYLE_LOCK +
        "Asset sheet on a plain flat light gray background, assets well separated, nothing overlapping. "
        "Top row: five finished collectible Patron cards, same size and shape, one per rarity: Common (carved wood and brass frame, a jester), Uncommon (emerald green frame with leaf filigree, a friendly king), "
        "Rare (sapphire blue frame with a soft shimmer, a wizard), Epic (amethyst purple frame with sparkles, an alchemist with a green potion), Legendary (shining gold frame with light rays and a tiny crown, an orange cat on a cushion). "
        "Each has a faceted gem at the top, an engraved name plate and a tier label. "
        "Bottom row: the same five frames completely empty, with a blank dark portrait window, no name text, for reuse. No other text. Do not print the word Joker."
    ),
    "sheet_ui": (
        STYLE_LOCK +
        "UI kit sheet on a plain flat light gray background, every element well separated, nothing overlapping. "
        "Include: a large green Play Hand button with the words Play Hand; a smaller red Discard button with the word Discard; "
        "a wide carved wooden round banner with an empty progress bar and below it the same banner with the bar half filled with gold; "
        "a round coin counter pill and a round hand-icon counter pill; a round settings gear button; "
        "a card deck pile seen at an angle with a small count plate attached; "
        "three small floating effect pills (blue Chips pill +30, red Mult pill +4, gold coin pill +5); "
        "a soft golden glowing ring for the scoring stage; and five faceted rarity gems in a row (gray, green, blue, purple, gold). No other text."
    ),
    "sheet_cards": (
        STYLE_LOCK +
        "Playing card sheet on a plain flat light gray background, cards well separated, same size, nothing overlapping. "
        "Ivory cards with thick rounded corners and thin gold corner details. Row one: Ace of spades, King of hearts, Queen of clubs, Jack of diamonds, "
        "each court card showing a different friendly Roblox-style character in painted style. Row two: 10 of hearts, 7 of clubs, 2 of diamonds with clear pip layouts, "
        "and a card back in deep purple with a gold crown. Crisp, readable numbers and suit symbols. No other text. Do not print the word Joker."
    ),
}
ASSET_KEYS = ["sheet_patrons", "sheet_ui", "sheet_cards"]

def load_env():
    env = ROOT / "tools" / "patron_art" / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"'))

def load_key():
    load_env()
    k = os.environ.get("OPENAI_API_KEY")
    if not k:
        sys.exit("No OPENAI_API_KEY in the environment or tools/patron_art/.env")
    return k

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quality", default="high", choices=["low", "medium", "high"])
    ap.add_argument("--style", default="painted", choices=["painted", "pixel", "roblox"])
    ap.add_argument("--ref", default="", help="path to a reference image: redraws it using REF_PROMPT (edit mode), e.g. claude/reference/concepts/rusty_mug_ref.png")
    ap.add_argument("--prompt", default="redraw", choices=["redraw", "tweak"], help="with --ref: which redraw prompt to use")
    ap.add_argument("--assets", action="store_true", help="make the three asset sheets (Patron cards, UI kit, card faces) from the newest concept_R or concept_T image")
    ap.add_argument("--all", action="store_true", help="make every variant instead of just the first")
    ap.add_argument("--only", default="", help="comma list of variants, e.g. A,C")
    ap.add_argument("--model", default=None, help="default: IMAGE_MODEL from tools/patron_art/.env, else gpt-image-2")
    args = ap.parse_args()
    key_api = key = load_key()
    model = args.model or os.environ.get("IMAGE_MODEL", "gpt-image-2")
    print("model:", model)
    OUT.mkdir(parents=True, exist_ok=True)
    if args.ref or args.assets:
        ref_path = pathlib.Path(args.ref) if args.ref else None
        if ref_path is None:
            found = sorted(OUT.glob("concept_R_*.png")) + sorted(OUT.glob("concept_T_*.png"))
            if not found:
                sys.exit("No reference image. Run --ref <image> first, or pass --ref <path>.")
            ref_path = max(found, key=lambda f: f.stat().st_mtime)
        if not ref_path.is_absolute():
            ref_path = ROOT / ref_path
        if not ref_path.exists():
            sys.exit(f"reference image not found: {ref_path}")
        keys = ASSET_KEYS if args.assets else [args.prompt]
        if args.assets and args.only:
            keys = [k for k in ASSET_KEYS if k in args.only.split(",")]
        for key in keys:
            print(f"{key}: redrawing from reference {ref_path.name} ...", flush=True)
            data = {"model": model, "prompt": REF_PROMPTS[key], "size": "1536x1024", "quality": args.quality, "n": "1"}
            r = None
            for attempt in (0, 1):
                if key.startswith("sheet_") and attempt == 0:
                    data["background"] = "transparent"
                else:
                    data.pop("background", None)
                r = requests.post(
                    "https://api.openai.com/v1/images/edits",
                    headers={"Authorization": f"Bearer {key_api}"},
                    data=data,
                    files=[("image[]", (ref_path.name, ref_path.read_bytes(), "image/png"))],
                    timeout=400,
                )
                if r.status_code == 200 or not key.startswith("sheet_"):
                    break
            if r.status_code != 200:
                print(f"  failed {r.status_code}: {r.text[:300]}")
                continue
            tag = {"redraw": "R", "tweak": "T"}.get(key, key)
            path = OUT / f"concept_{tag}_{int(time.time())}.png"
            path.write_bytes(base64.b64decode(r.json()["data"][0]["b64_json"]))
            print("  saved", path.relative_to(ROOT))
        return
    base, variants = {"pixel": (PIXEL_BASE, PIXEL_VARIANTS), "roblox": (ROBLOX_BASE, ROBLOX_VARIANTS)}.get(args.style, (BASE, VARIANTS))
    names = [n for n in variants if not args.only or n in args.only.split(",")]
    if not args.only and not args.all:
        names = names[:1]  # one image by default, faster and cheaper; use --all for every variant
    for n in names:
        print(f"generating {n} ...", flush=True)
        r = requests.post(
            "https://api.openai.com/v1/images/generations",
            headers={"Authorization": f"Bearer {key}"},
            json={"model": model, "prompt": base + " " + variants[n], "size": "1536x1024",
                  "quality": args.quality, "n": 1},
            timeout=300,
        )
        if r.status_code != 200:
            print(f"  failed {r.status_code}: {r.text[:300]}")
            continue
        png = base64.b64decode(r.json()["data"][0]["b64_json"])
        path = OUT / f"concept_{n}_{int(time.time())}.png"
        path.write_bytes(png)
        print(f"  saved {path.relative_to(ROOT)}")

if __name__ == "__main__":
    main()
