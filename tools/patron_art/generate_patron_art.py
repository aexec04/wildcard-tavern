#!/usr/bin/env python3
"""
Patron art pipeline: prompts -> images -> Roblox assets -> PatronArt.lua (Rojo syncs it into Studio).

Run from the project root on your Mac:
  python3 tools/patron_art/generate_patron_art.py generate --limit 5     # style test first
  python3 tools/patron_art/generate_patron_art.py generate               # the rest (skips existing PNGs)
  python3 tools/patron_art/generate_patron_art.py upload                 # Open Cloud upload, saves ids
  python3 tools/patron_art/generate_patron_art.py lua                    # writes src/Shared/Engine/PatronArt.lua
  python3 tools/patron_art/generate_patron_art.py all                    # generate + upload + lua
  python3 tools/patron_art/generate_patron_art.py status                 # what is missing / stale / uploaded
  python3 tools/patron_art/generate_patron_art.py queue                  # JSON of images awaiting upload (Studio route)
  python3 tools/patron_art/generate_patron_art.py record <id> <assetId>  # store an id uploaded via Studio
  python3 tools/patron_art/generate_patron_art.py import-ids ids.csv     # manual route: lines of "patron_id,assetId"

Options: --only id1,id2   --limit N   --force (regenerate/re-upload)   --stale   --workers N (default 4, parallel)

Keys go in tools/patron_art/.env (gitignored), one per line:
  OPENAI_API_KEY=...
  ROBLOX_API_KEY=...        (Creator Dashboard > Open Cloud > API Keys, Assets: read + write)
  ROBLOX_USER_ID=...        (or ROBLOX_GROUP_ID=... if the game is group-owned)
Optional: IMAGE_MODEL (default gpt-image-1), IMAGE_QUALITY (default medium)
"""
import argparse, base64, hashlib, json, os, pathlib, sys, threading, time
from concurrent.futures import ThreadPoolExecutor, as_completed
import requests

LOCK = threading.RLock()   # guards ids.json / state.json / image-ids.json when workers run in parallel
ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = ROOT / "tools" / "patron_art"
OUT = ROOT / "art-wip" / "patrons"      # gitignored
IDS = OUT / "ids.json"
IMAGE_IDS = OUT / "image-ids.json"   # patron id -> IMAGE asset id (the Decal wraps it; ImageLabel needs this one)
STATE = OUT / "state.json"   # per patron: prompt hash at generation, image hash at upload
LUA = ROOT / "src" / "Shared" / "Engine" / "PatronArt.lua"


def load_env():
    env = HERE / ".env"
    if env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def need(name):
    v = os.environ.get(name)
    if not v:
        sys.exit(f"Missing {name}. Put it in {HERE / '.env'}")
    return v


def load_prompts():
    return json.loads((HERE / "prompts.json").read_text(encoding="utf-8"))


def load_ids():
    return json.loads(IDS.read_text()) if IDS.exists() else {}


def save_ids(ids):
    OUT.mkdir(parents=True, exist_ok=True)
    IDS.write_text(json.dumps(ids, indent=2, sort_keys=True))


def load_state():
    return json.loads(STATE.read_text()) if STATE.exists() else {}


def save_state(state):
    OUT.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2, sort_keys=True))


def sha(b):
    return hashlib.sha1(b).hexdigest()[:12]


def prompt_hash(data, pid):
    return sha((data["style"] + "|" + data["subjects"][pid]).encode("utf-8"))


def image_hash(pid):
    return sha((OUT / f"{pid}.png").read_bytes())


def qa(pid):
    """Cheap sanity checks. Returns a list of problems (empty = ok)."""
    path = OUT / f"{pid}.png"
    if not path.exists():
        return ["missing"]
    b = path.read_bytes()
    problems = []
    if b[:8] != b"\x89PNG\r\n\x1a\n":
        problems.append("not a PNG")
    if len(b) < 30_000:
        problems.append("suspiciously small (blank or failed image?)")
    if len(b) > 15_000_000:
        problems.append("too large for upload")
    return problems


def status_of(data, pid, ids, state):
    if not (OUT / f"{pid}.png").exists():
        return "missing"
    if qa(pid):
        return "bad-image"
    st = state.get(pid, {})
    if st.get("prompt") != prompt_hash(data, pid):
        return "stale-prompt"          # subject/style changed since this image was made
    if pid not in ids:
        return "needs-upload"
    if st.get("image") != image_hash(pid):
        return "needs-upload"          # image replaced after upload
    return "done"


def pick(subjects, args):
    keys = list(subjects.keys())
    if args.only:
        wanted = [k.strip() for k in args.only.split(",")]
        bad = [k for k in wanted if k not in subjects]
        if bad:
            sys.exit(f"Unknown patron ids: {bad}")
        keys = wanted
    return keys[: args.limit] if args.limit else keys


class Stop(Exception):
    """A failure that affects every item (bad key, no credits): stop the whole run."""


def _generate_one(pid, data, key, model, quality, args):
    path = OUT / f"{pid}.png"
    with LOCK:
        stale = load_state().get(pid, {}).get("prompt") != prompt_hash(data, pid)
    if path.exists() and not args.force and not (args.stale and stale):
        print(f"skip {pid} (exists{', STALE: rerun with --stale' if stale else ''})")
        return "skipped"
    prompt = f"{data['style']}. Subject: {data['subjects'][pid]}."
    for attempt in range(4):
        r = requests.post(
            "https://api.openai.com/v1/images/generations",
            headers={"Authorization": f"Bearer {key}"},
            json={"model": model, "prompt": prompt, "size": "1024x1024", "quality": quality, "n": 1},
            timeout=300,
        )
        if r.status_code == 200:
            path.write_bytes(base64.b64decode(r.json()["data"][0]["b64_json"]))
            with LOCK:
                state = load_state()
                state[pid] = {"prompt": prompt_hash(data, pid)}
                save_state(state)
            problems = qa(pid)
            print(f"made {pid}" + (f"  QA: {problems}" if problems else ""), flush=True)
            return "made"
        body = r.text[:400]
        low = body.lower()
        if r.status_code in (401, 403) or "credit" in low or "billing" in low or "insufficient_quota" in low:
            raise Stop(f"STOPPED at {pid}: HTTP {r.status_code}: {body}\n"
                       "Check the key and add credits at platform.openai.com/settings/organization/billing")
        if r.status_code in (429, 500, 502, 503) and attempt < 3:
            print(f"  {pid}: HTTP {r.status_code}, retrying in {5 * (attempt + 1)}s", flush=True)
            time.sleep(5 * (attempt + 1))
            continue
        print(f"FAILED {pid}: HTTP {r.status_code} {body}", flush=True)
        return "failed"
    return "failed"


def _run_parallel(fn, pids, workers):
    """Run fn(pid) over pids with a thread pool. Returns (failed_ids, stop_message)."""
    failed, stop = [], None
    with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        futs = {ex.submit(fn, pid): pid for pid in pids}
        for f in as_completed(futs):
            try:
                if f.result() == "failed":
                    failed.append(futs[f])
            except Stop as e:
                stop = str(e)
                for g in futs:
                    g.cancel()
    return failed, stop


def cmd_generate(args):
    key = need("OPENAI_API_KEY")
    data = load_prompts()
    OUT.mkdir(parents=True, exist_ok=True)
    model = os.environ.get("IMAGE_MODEL", "gpt-image-1")
    quality = os.environ.get("IMAGE_QUALITY", "medium")
    pids = pick(data["subjects"], args)
    failed, stop = _run_parallel(lambda pid: _generate_one(pid, data, key, model, quality, args), pids, args.workers)
    if stop:
        sys.exit(stop)
    if failed:
        sys.exit(f"{len(failed)} image(s) failed: {', '.join(failed)}")


def _upload_one(pid, data, headers, creator, args):
    png = OUT / f"{pid}.png"
    if not png.exists():
        print(f"no image yet: {pid}")
        return "skipped"
    with LOCK:
        st = status_of(data, pid, load_ids(), load_state())
    if st == "done" and not args.force:
        print(f"skip {pid} (already uploaded)")
        return "skipped"
    if qa(pid):
        print(f"skip {pid}: QA failed {qa(pid)}")
        return "skipped"
    req = {
        "assetType": "Decal",
        "displayName": f"Patron {pid}",
        "description": "Wildcard Tavern patron art",
        "creationContext": {"creator": creator},
    }
    for attempt in range(4):
        r = requests.post(
            "https://apis.roblox.com/assets/v1/assets",
            headers=headers,
            files={"request": (None, json.dumps(req), "application/json"),
                   "fileContent": (png.name, png.read_bytes(), "image/png")},
            timeout=120,
        )
        if r.status_code == 200:
            break
        if r.status_code in (401, 403):
            raise Stop(f"STOPPED at {pid}: HTTP {r.status_code}: {r.text[:300]}")
        if r.status_code in (429, 500, 502, 503) and attempt < 3:
            time.sleep(5 * (attempt + 1))
            continue
        print(f"UPLOAD FAILED {pid}: {r.status_code} {r.text[:300]}", flush=True)
        return "failed"
    op = r.json()
    path = op.get("path")
    for _ in range(90):
        if op.get("done"):
            break
        time.sleep(2)
        op = requests.get(f"https://apis.roblox.com/assets/v1/{path}", headers=headers, timeout=60).json()
    if op.get("done") and "response" in op:
        with LOCK:
            ids = load_ids()
            ids[pid] = str(op["response"]["assetId"])
            save_ids(ids)
            _record_hash(pid)
            _drop_image_id(pid)
        print(f"uploaded {pid} -> {ids[pid]}", flush=True)
        return "made"
    print(f"NOT FINISHED/REJECTED {pid}: {json.dumps(op)[:300]}", flush=True)
    return "failed"


def cmd_upload(args):
    key = need("ROBLOX_API_KEY")
    if os.environ.get("ROBLOX_GROUP_ID"):
        creator = {"creator": {"groupId": os.environ["ROBLOX_GROUP_ID"]}}
    else:
        creator = {"creator": {"userId": need("ROBLOX_USER_ID")}}
    data = load_prompts()
    headers = {"x-api-key": key}
    pids = pick(data["subjects"], args)
    failed, stop = _run_parallel(lambda pid: _upload_one(pid, data, headers, creator["creator"], args), pids, args.workers)
    if stop:
        sys.exit(stop)
    if failed:
        sys.exit(f"{len(failed)} upload(s) failed or unfinished: {', '.join(failed)}")


def _drop_image_id(pid):
    """A new upload is a new Decal, so any previously resolved Image id is stale."""
    if IMAGE_IDS.exists():
        m = json.loads(IMAGE_IDS.read_text())
        if m.pop(pid, None) is not None:
            IMAGE_IDS.write_text(json.dumps(m, indent=2, sort_keys=True))


def _record_hash(pid):
    state = load_state()
    state.setdefault(pid, {})["image"] = image_hash(pid)
    save_state(state)


def cmd_status(_args):
    data = load_prompts()
    ids, state = load_ids(), load_state()
    counts, todo = {}, []
    for pid in data["subjects"]:
        st = status_of(data, pid, ids, state)
        counts[st] = counts.get(st, 0) + 1
        if st != "done":
            todo.append((pid, st))
    print("  ".join(f"{k}: {v}" for k, v in sorted(counts.items())))
    for pid, st in todo:
        print(f"  {st:13} {pid}")
    extra = [p for p in ids if p not in data["subjects"]]
    if extra:
        print("ids for patrons no longer in prompts.json:", extra)


def cmd_queue(_args):
    """JSON list of images that still need uploading (for the Studio upload route)."""
    data = load_prompts()
    ids, state = load_ids(), load_state()
    out = []
    for pid in data["subjects"]:
        if status_of(data, pid, ids, state) == "needs-upload":
            out.append({"id": pid, "path": str(OUT / f"{pid}.png"), "displayName": f"Patron {pid}"})
    print(json.dumps(out, indent=2))


def cmd_record(args):
    """record <patron_id> <assetId>: store an id uploaded some other way (e.g. via Studio)."""
    pid, aid = args.file, args.extra
    if not pid or not aid:
        sys.exit("usage: record <patron_id> <assetId>")
    ids = load_ids()
    ids[pid] = "".join(ch for ch in aid if ch.isdigit())
    save_ids(ids)
    _drop_image_id(pid)
    if (OUT / f"{pid}.png").exists():
        _record_hash(pid)
    print(f"recorded {pid} -> {ids[pid]}")


def load_image_ids():
    return json.loads(IMAGE_IDS.read_text()) if IMAGE_IDS.exists() else {}


def cmd_record_image(args):
    """record-image <patron_id> <imageId>: the Image asset id inside a patron's Decal."""
    pid, aid = args.file, args.extra
    if not pid or not aid:
        sys.exit("usage: record-image <patron_id> <imageId>")
    m = load_image_ids()
    m[pid] = "".join(ch for ch in aid if ch.isdigit())
    OUT.mkdir(parents=True, exist_ok=True)
    IMAGE_IDS.write_text(json.dumps(m, indent=2, sort_keys=True))
    print(f"recorded image {pid} -> {m[pid]}")


def cmd_lua(_args):
    ids = load_ids()
    imgs = load_image_ids()
    unresolved = [p for p in ids if p not in imgs]
    if unresolved:
        print(f"WARNING: {len(unresolved)} patron(s) have a Decal id but no resolved Image id "
              f"(they will NOT load in ImageLabels): {', '.join(unresolved)}")
    ids = {p: imgs[p] for p in ids if p in imgs}
    lines = [
        "--[[",
        "\tShared/Engine/PatronArt.lua",
        "\tGENERATED by tools/patron_art/generate_patron_art.py -- do not hand-edit.",
        "\tMaps patron id -> rbxassetid. UI should fall back to the patron's emoji icon",
        "\twhen an id is missing from this table.",
        "]]",
        "",
        "return {",
    ]
    for pid in sorted(ids):
        lines.append(f'\t["{pid}"] = "rbxassetid://{ids[pid]}",')
    lines.append("}")
    LUA.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {LUA} with {len(ids)} patrons")


def cmd_import_ids(args):
    ids = load_ids()
    for line in pathlib.Path(args.file).read_text().splitlines():
        if "," in line:
            pid, aid = [x.strip() for x in line.split(",", 1)]
            ids[pid] = "".join(ch for ch in aid if ch.isdigit())
    save_ids(ids)
    print(f"{len(ids)} ids saved")


def main():
    load_env()
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["generate", "upload", "lua", "all", "import-ids", "status", "queue", "record", "record-image"])
    ap.add_argument("file", nargs="?")
    ap.add_argument("extra", nargs="?")
    ap.add_argument("--workers", type=int, default=4, help="parallel requests for generate/upload (default 4)")
    ap.add_argument("--stale", action="store_true", help="also regenerate images whose prompt changed")
    ap.add_argument("--only")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    if a.cmd == "generate":
        cmd_generate(a)
    elif a.cmd == "upload":
        cmd_upload(a)
    elif a.cmd == "lua":
        cmd_lua(a)
    elif a.cmd == "status":
        cmd_status(a)
    elif a.cmd == "queue":
        cmd_queue(a)
    elif a.cmd == "record":
        cmd_record(a)
    elif a.cmd == "record-image":
        cmd_record_image(a)
    elif a.cmd == "import-ids":
        cmd_import_ids(a)
    else:
        cmd_generate(a); cmd_upload(a); cmd_lua(a)


if __name__ == "__main__":
    main()
