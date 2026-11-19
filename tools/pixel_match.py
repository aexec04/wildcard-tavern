"""Compare a 1536x1024 Studio screenshot of the Concept T reference scene with claude/reference/concept_t/full_reference.png.

Usage: python3 tools/pixel_match.py <screenshot.png> [--reference <png>]

Prints the mean absolute difference (0 to 255) per region, PASS or FAIL against its target, and the worst three
regions. Writes art-wip/pixel-match/side_by_side.png and diff_heatmap.png. Needs pillow and numpy only.
"""
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
REFERENCE = ROOT / "claude" / "reference" / "concept_t" / "full_reference.png"
OUT = ROOT / "art-wip" / "pixel-match"
SIZE = (1536, 1024)

# name -> (x0, y0, x1, y1) as fractions of the frame, and the target (most mean difference allowed)
REGIONS = {
    "hud": ((0.0, 0.0, 0.22, 0.10), 8),
    "banner": ((0.375, 0.0, 0.621, 0.09), 8),
    "gear": ((0.915, 0.0, 1.0, 0.11), 8),
    "patrons": ((0.185, 0.16, 0.81, 0.41), 8),
    "labels": ((0.185, 0.405, 0.81, 0.50), 8),
    "stage": ((0.35, 0.53, 0.66, 0.70), 15),
    "hand": ((0.19, 0.68, 0.80, 0.92), 15),
    "buttons": ((0.30, 0.87, 0.69, 0.985), 8),
    "deck": ((0.80, 0.64, 0.98, 0.93), 8),
    "room_left": ((0.0, 0.12, 0.18, 0.68), 15),
    "room_right": ((0.82, 0.12, 1.0, 0.68), 15),
    "room_top": ((0.18, 0.0, 0.82, 0.16), 15),
}


def crop_bars(im, threshold=12, share=0.05):
    """Cut the black bars off a screenshot taken in a window that is not 3:2: keep the rows and columns where at least
    `share` of the pixels are brighter than `threshold`. A frame with no bars comes back unchanged."""
    a = np.asarray(im, dtype=np.uint8).max(axis=2) > threshold
    rows = np.where(a.mean(axis=1) >= share)[0]
    cols = np.where(a.mean(axis=0) >= share)[0]
    if len(rows) == 0 or len(cols) == 0:
        return im
    box = (int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1)
    return im.crop(box) if box != (0, 0, im.size[0], im.size[1]) else im


def load(path, bars=False):
    im = Image.open(path).convert("RGB")
    if bars:
        im = crop_bars(im)
    if im.size != SIZE:
        im = im.resize(SIZE, Image.LANCZOS)
    return im


def box(frac):
    w, h = SIZE
    return (int(round(frac[0] * w)), int(round(frac[1] * h)), int(round(frac[2] * w)), int(round(frac[3] * h)))


def compare(ref_im, shot_im):
    """Returns {region: mean absolute difference}, plus the per-pixel difference array (H, W)."""
    a = np.asarray(ref_im, dtype=np.int16)
    b = np.asarray(shot_im, dtype=np.int16)
    diff = np.abs(a - b).mean(axis=2)
    out = {}
    for name, (frac, _target) in REGIONS.items():
        x0, y0, x1, y1 = box(frac)
        out[name] = float(diff[y0:y1, x0:x1].mean())
    return out, diff


def write_images(ref_im, shot_im, diff):
    OUT.mkdir(parents=True, exist_ok=True)
    side = Image.new("RGB", (SIZE[0] * 2, SIZE[1]))
    side.paste(ref_im, (0, 0))
    side.paste(shot_im, (SIZE[0], 0))
    side.save(OUT / "side_by_side.png")
    t = np.clip(diff / 64.0, 0, 1)  # 0 = identical, 1 = 64 or more apart
    heat = np.zeros(diff.shape + (3,), dtype=np.uint8)
    heat[..., 0] = (255 * t).astype(np.uint8)
    heat[..., 1] = (255 * np.clip(2 * t, 0, 1) * (1 - t)).astype(np.uint8)
    heat[..., 2] = (80 * (1 - t)).astype(np.uint8)
    Image.fromarray(heat).save(OUT / "diff_heatmap.png")


def report(scores):
    worst = sorted(scores, key=lambda n: scores[n] - REGIONS[n][1], reverse=True)[:3]
    lines = []
    for name, (_frac, target) in REGIONS.items():
        ok = scores[name] <= target
        lines.append("%-11s %6.2f  (max %2d)  %s" % (name, scores[name], target, "PASS" if ok else "FAIL"))
    lines.append("worst three: " + ", ".join("%s %.2f" % (n, scores[n]) for n in worst))
    return lines


def main(argv):
    ref_path = REFERENCE
    args = list(argv)
    if "--reference" in args:
        i = args.index("--reference")
        ref_path = pathlib.Path(args[i + 1])
        del args[i:i + 2]
    if len(args) != 1:
        print(__doc__)
        return 2
    ref_im, shot_im = load(ref_path), load(args[0], bars=True)
    scores, diff = compare(ref_im, shot_im)
    write_images(ref_im, shot_im, diff)
    print("\n".join(report(scores)))
    return 0 if all(scores[n] <= REGIONS[n][1] for n in scores) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
