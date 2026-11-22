#!/usr/bin/env python3
"""One-off helper: run the hud_kit pipeline for whole sets. Usage: python3 -I tools/_hud_kit_batch.py <step> <setid> [<setid> ...]
step = ids (print the piece ids) | generate | frames (panel_frame at high) | crop | upload
Never prints keys. Keep local, do not commit."""
import json, os, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
GEN = str(ROOT / "tools" / "patron_art" / "generate_patron_art.py")
subj = json.loads((ROOT / "tools" / "patron_art" / "prompts.json").read_text(encoding="utf-8"))["hud_kit_subjects"]
step, sets = sys.argv[1], sys.argv[2:]
ids = [k for k in subj if k.split("__")[0] in sets]
frames = [k for k in ids if k.endswith("__panel_frame")]
rest = [k for k in ids if k not in frames]
def run(*args):
    return subprocess.call(["python3", GEN, *args], cwd=ROOT)
if step == "ids":
    print(",".join(ids))
elif step == "generate":
    sys.exit(run("generate", "-c", "hud_kit", "--workers", "4", "--only", ",".join(rest)))
elif step == "frames":
    sys.exit(run("generate", "-c", "hud_kit", "--workers", "2", "--quality", "high", "--only", ",".join(frames)))
elif step == "crop":
    sys.exit(subprocess.call(["python3", "-I", str(ROOT / "tools" / "patron_art" / "_crop_hud_kit.py")], cwd=ROOT))
elif step == "upload":
    sys.exit(run("upload", "-c", "hud_kit", "--workers", "2", "--only", ",".join(ids)))
