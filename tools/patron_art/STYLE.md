# Wildcard Tavern house art style

The reference look is the Journey map background (`journey_map`, category `backgrounds`).
The reference image is `art-wip/backgrounds/journey_map.png` (gitignored with the rest of `art-wip/`, keep it on disk).

## Exact settings used for `journey_map`
- Model: `gpt-image-1` (`IMAGE_MODEL` default), endpoint `images/generations`
- Size `1536x1024`, quality `low` (category `backgrounds` in `CATEGORY_OPTS`)
- Prompt = `<style>. Subject: <subject>.` where `<style>` is `style_background` in `prompts.json`:

> Painterly digital illustration in the style of a cozy medieval tavern scene: warm amber candlelight, rich wood tones, soft painterly brushwork, kid-friendly, no alcohol, no text, no letters, no logos, no frame or border

- Subject (`background_subjects.journey_map`):

> Aged parchment map on a dark wooden table seen from above, curled edges, subtle faded ink textures, faint stains, warm candlelight at the corners, large empty center, painterly, same style as the other tavern art. No characters, no text, no writing.

## What makes it work
- Warm candlelight: amber light, glowing corners, rich wood and parchment tones.
- Painterly: soft brushwork, no hard outlines or glossy 3D look.
- A clear, empty center so UI can sit on top of it.
- Dark vignette edges that frame the scene and keep the middle readable.
- No characters, no text or letters, no logos, no frame or border; kid-friendly, no alcohol.

## Using it for a new category
- `house_style` in `prompts.json` holds the style text above. Opt in with `--style house_style`,
  or set `"style_key": "house_style"` for the category in `CATEGORY_OPTS`.
- To match the reference image itself, add `--reference` (defaults to `art-wip/backgrounds/journey_map.png`,
  or pass another path). This switches to the `images/edits` endpoint with the image as input; the
  prompt still applies. Example:
  `python3 tools/patron_art/generate_patron_art.py -c map_decor generate --style house_style --reference --force`
- Changing the style text marks images stale (`--stale` regenerates them).
