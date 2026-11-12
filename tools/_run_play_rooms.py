"""One-off runner: generate, alpha-check, upload play_room_<set>_bg/_front one set at a time. Stops on the first hard error."""
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GEN = [sys.executable, str(ROOT / "tools/patron_art/generate_patron_art.py")]
SETS = ["festival_night", "closing_time", "golden_gala", "meadow_picnic", "riverside_evening", "summit_camp", "dune_market",
        "marsh_lanterns", "snowy_hearth", "harbor_lights", "tavern_feast", "harvest_table", "winter_table"]
gens = 0


def run(args):
    r = subprocess.run(GEN + args, cwd=ROOT, capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip()
    print(out[-400:], flush=True)
    return r.returncode, out


def front_ok(sid):
    im = Image.open(ROOT / ("art-wip/play_scene/play_room_%s_front.png" % sid)).convert("RGBA")
    w, h = im.size
    a = im.split()[3]
    top = a.crop((0, 0, w, int(h * 0.6))).getextrema()[1]
    corners = [a.getpixel(p) for p in [(0, 0), (w - 1, 0), (w // 2, int(h * 0.3))]]
    bottom = a.getpixel((w // 2, int(h * 0.9)))
    return top == 0 and max(corners) == 0 and bottom == 255


for sid in SETS:
    ids = "play_room_%s_bg,play_room_%s_front" % (sid, sid)
    code, out = run(["generate", "-c", "play_scene", "--force", "--only", "play_room_%s_front" % sid] if sid == "festival_night"
                    else ["generate", "-c", "play_scene", "--only", ids])
    gens += 1 if sid == "festival_night" else 2
    if code != 0 or "made" not in out:
        print("STOP generate failed for", sid, flush=True)
        sys.exit(1)
    if not front_ok(sid):
        print("BAD ALPHA, regenerating front once:", sid, flush=True)
        code, out = run(["generate", "-c", "play_scene", "--force", "--only", "play_room_%s_front" % sid])
        gens += 1
        if code != 0 or not front_ok(sid):
            print("STOP front alpha still bad for", sid, flush=True)
            sys.exit(2)
    code, out = run(["upload", "-c", "play_scene", "--decal", "--only", ids])
    if code != 0 or "uploaded" not in out:
        print("STOP upload failed for", sid, flush=True)
        sys.exit(3)
    print("DONE", sid, "generations so far (plus 2 for winter_evening):", gens, flush=True)
