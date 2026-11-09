#!/usr/bin/env python3
"""
Art pipeline: prompts -> images -> Roblox assets -> generated Lua id map (Rojo syncs it into Studio).

Categories (--category / -c, default patrons):
  patrons      prompts.json "subjects"            -> art-wip/patrons/      -> src/Shared/Engine/PatronArt.lua
  bosses       prompts.json "boss_subjects"       -> art-wip/bosses/       -> src/Shared/Engine/BossRoundArt.lua
  recipes      prompts.json "recipe_subjects"     -> art-wip/recipes/      -> src/Shared/Engine/RecipeArt.lua
  housepasses  prompts.json "housepass_subjects"  -> art-wip/housepasses/  -> src/Shared/Engine/HousePassArt.lua
  titles       prompts.json "title_subjects"      -> art-wip/titles/       -> src/Shared/Engine/TitleArt.lua
Each category keeps its own ids.json / image-ids.json / state.json (stale tracking) in its art-wip folder.

Run from the project root on your Mac (add -c <category> to any command):
  python3 tools/patron_art/generate_patron_art.py generate --limit 5     # style test first
  python3 tools/patron_art/generate_patron_art.py generate               # the rest (skips existing PNGs)
  python3 tools/patron_art/generate_patron_art.py upload                 # Open Cloud upload, saves ids
  python3 tools/patron_art/generate_patron_art.py lua                    # writes src/Shared/Engine/PatronArt.lua
  python3 tools/patron_art/generate_patron_art.py all                    # generate + upload + lua
  python3 tools/patron_art/generate_patron_art.py status                 # what is missing / stale / uploaded
  python3 tools/patron_art/generate_patron_art.py estimate               # image counts + cost estimate, every category (no API calls)
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
ENGINE = ROOT / "src" / "Shared" / "Engine"

# name -> (prompts.json key, art-wip folder, generated Lua file, singular label)
CATEGORIES = {
    "patrons":     ("subjects",            "patrons",     "PatronArt.lua",    "Patron"),
    "bosses":      ("boss_subjects",       "bosses",      "BossRoundArt.lua", "Boss Round"),
    "recipes":     ("recipe_subjects",     "recipes",     "RecipeArt.lua",    "Recipe"),
    "housepasses": ("housepass_subjects",  "housepasses", "HousePassArt.lua", "House Pass"),
    "titles":      ("title_subjects",      "titles",      "TitleArt.lua",     "Title"),
    "rooms":       ("room_subjects",       "rooms",       "RoomArt.lua",      "Room"),
    "backgrounds": ("background_subjects", "backgrounds", "BackgroundArt.lua", "Background"),
    "tutorial_icons": ("tutorial_icon_subjects", "tutorial_icons", "TutorialIconArt.lua", "Tutorial Icon"),
    "map_nodes": ("map_node_subjects", "map_nodes", "MapNodeArt.lua", "Map Node"),
    "hud": ("hud_subjects", "hud", "HudArt.lua", "HUD"),
    "menu_icons": ("menu_icon_subjects", "menu_icons", "MenuIconArt.lua", "Menu Icon"),
    "map_regions": ("map_region_subjects", "map_regions", "MapRegionArt.lua", "Map Region"),
    "map_decor": ("map_decor_subjects", "map_decor", "MapDecorArt.lua", "Map Decor"),
    "card_backs": ("card_back_subjects", "card_backs", "CardBackArt.lua", "Card Back"),
    "scenes": ("scene_subjects", "scenes", "SceneArt.lua", "Scene"),
    "packs": ("pack_subjects", "packs", "PackArt.lua", "Pack"),
    "biome_backdrops": ("biome_backdrop_subjects", "biome_backdrops", "BiomeBackdropArt.lua", "Biome Backdrop"),
    "set_backdrops": ("set_backdrop_subjects", "set_backdrops", "SetBackdropArt.lua", "Set Backdrop"),
    "set_skins": ("set_skin_subjects", "set_skins", "SetSkinArt.lua", "Set Skin"),
    "badges": ("badge_subjects", "badges", "BadgeArt.lua", "Badge"),
    "stakes": ("stake_subjects", "stakes", "StakeArt.lua", "Stake"),
    "quests": ("quest_subjects", "quests", "QuestArt.lua", "Quest"),
    "rank_medals": ("rank_medal_subjects", "rank_medals", "RankMedalArt.lua", "Rank Medal"),
    "store_bundles": ("store_subjects", "store_bundles", "StoreBundleArt.lua", "Store Bundle"),
    "events": ("event_subjects", "events", "EventArt.lua", "Event"),
    "discoveries": ("discovery_subjects", "discoveries", "DiscoveryArt.lua", "Discovery"),
    "challenges": ("challenge_subjects", "challenges", "ChallengeArt.lua", "Challenge"),
    "endless_rules": ("endless_rule_subjects", "endless_rules", "EndlessRuleArt.lua", "Endless Rule"),
    "flair": ("flair_subjects", "flair", "FlairArt.lua", "Flair"),
    "seasons": ("season_subjects", "seasons", "SeasonArt.lua", "Season"),
    "legend": ("legend_subjects", "legend", "LegendArt.lua", "Legend"),
    "spectate": ("spectate_subjects", "spectate", "SpectateArt.lua", "Spectate"),
    "shop": ("shop_subjects", "shop", "ShopArt.lua", "Shop"),
    "menu_scene": ("menu_scene_subjects", "menu_scene", "MenuSceneArt.lua", "Menu Scene"),
    "bonds": ("bond_subjects", "bonds", "BondArt.lua", "Bond"),
    "menu_bayou": ("bayou_subjects", "menu_bayou", "BayouArt.lua", "Bayou"),
    # fx = procedural textures (tools/patron_art/make_fog_puff.py); upload/record/lua only, never `generate`.
    "fx": ("fx_subjects", "fx", "FxArt.lua", "FX"),
}
# Per-category overrides: image size, quality, and which prompts.json key holds the style prefix.
CATEGORY_OPTS = {
    "backgrounds": {"size": "1536x1024", "quality": "low", "style_key": "style_background"},
    "tutorial_icons": {"quality": "low", "style_key": "style_icon"},
    "map_nodes": {"quality": "low", "style_key": "style_icon"},
    "menu_icons": {"quality": "low", "style_key": "house_style"},
    # sizes = per-key overrides (sidebar_board is portrait, the divider is wide landscape)
    "hud": {"quality": "low", "style_key": "house_style",
            "sizes": {"sidebar_board": "1024x1536", "flourish_divider": "1536x1024"}},
    "map_regions": {"size": "1536x1024", "quality": "low", "style_key": "style_map_region"},
    "map_decor": {"quality": "low", "style_key": "style_map_decor"},
    "card_backs": {"size": "1024x1536", "quality": "medium", "style_key": "house_style"},
    "scenes": {"size": "1536x1024", "quality": "low", "style_key": "house_style"},
    "packs": {"quality": "low", "style_key": "house_style"},
    "biome_backdrops": {"size": "1536x1024", "quality": "low", "style_key": "house_style"},
    "set_backdrops": {"size": "1536x1024", "quality": "low", "style_key": "house_style"},
    "badges": {"quality": "low", "style_key": "style_icon"},
    "stakes": {"quality": "low", "style_key": "house_style"},
    "quests": {"quality": "low", "style_key": "house_style"},
    "rank_medals": {"quality": "low", "style_key": "house_style"},
    "store_bundles": {"quality": "low", "style_key": "house_style"},
    # event cards and the wide news banners share one category; banners (news_*) are landscape
    "events": {"quality": "low", "style_key": "house_style", "sizes": {
        "news_lantern_weekend": "1536x1024", "news_harvest_week": "1536x1024", "news_feast_week": "1536x1024"}},
    "discoveries": {"quality": "low", "style_key": "house_style"},
    "challenges": {"quality": "low", "style_key": "house_style"},
    "endless_rules": {"quality": "low", "style_key": "house_style"},
    "flair": {"quality": "low", "style_key": "house_style"},
    # season banners are wide; menu_season is a single object icon
    "seasons": {"quality": "low", "style_key": "house_style", "sizes": {
        "season_harvest_moon": "1536x1024", "season_winter_welcome": "1536x1024"}},
    "legend": {"quality": "low", "style_key": "house_style"},
    "spectate": {"quality": "low", "style_key": "house_style"},
    # shop_counter is a wide strip; the rest are single objects or portraits
    "shop": {"quality": "low", "style_key": "house_style", "sizes": {"shop_counter": "1536x1024"}},
    "bonds": {"quality": "low", "style_key": "house_style"},
    # Card Set UI skins: 6 slots per set. face_paper is an opaque tile; the rest are cut out from magenta.
    "set_skins": {"quality": "low", "style_key": "house_style", "transparent": True, "opaque": [], "sizes": {}},  # filled below
    # Bayou tavern menu layers (back to front). Transparent layers are cut out from magenta; sky and water stay opaque.
    "menu_bayou": {"quality": "low", "style_key": "house_style", "transparent": True,
                   "opaque": ["bayou_sky", "bayou_water"],
                   "sizes": {"bayou_sky": "1536x1024", "bayou_far_trees": "1536x1024", "bayou_water": "1536x1024",
                             "bayou_tavern_stilts": "1536x1024", "bayou_mist": "1536x1024",
                             "bayou_cypress_knees": "1536x1024", "bayou_willow_fg": "1024x1536"}},
    # Menu tavern layers and props. `transparent` = generated on flat magenta, then cut out to real alpha (cutout.py, checked in qa());
    # `opaque` lists the ids that stay opaque. The model has no wide strip size, so menu_counter is 1536x1024 with the
    # bar drawn in the lower part of the canvas (the UI crops it).
    "menu_scene": {"quality": "low", "style_key": "house_style", "transparent": True,
                   "opaque": ["menu_wall_far", "menu_parchment"],
                   "sizes": {"menu_wall_far": "1536x1024", "menu_mid_beams": "1536x1024", "menu_counter": "1536x1024",
                             "menu_noticeboard_wall": "1024x1024"}},
}

# set_skins: one id per "<setId>_<slot>"; sizes and opaque ids follow the slot suffix.
_SKIN_SIZES = {"_face_frame": "1024x1536", "_face_paper": "1024x1024", "_face_court": "1024x1024",
               "_panel_frame": "1536x1024", "_button_plate": "1536x1024", "_tab_plate": "1024x1024"}
try:
    for _pid in json.loads((HERE / "prompts.json").read_text(encoding="utf-8")).get("set_skin_subjects", {}):
        for _suffix, _size in _SKIN_SIZES.items():
            if _pid.endswith(_suffix):
                CATEGORY_OPTS["set_skins"]["sizes"][_pid] = _size
                if _suffix == "_face_paper":
                    CATEGORY_OPTS["set_skins"]["opaque"].append(_pid)
except (OSError, ValueError):
    pass


def wants_alpha(pid):
    """True when this category asks for a transparent background for pid."""
    opts = CATEGORY_OPTS.get(CATEGORY, {})
    return bool(opts.get("transparent")) and pid not in opts.get("opaque", [])
# Rough OpenAI gpt-image-1 price per 1024x1024 image (USD). Check platform.openai.com/pricing.
COST_PER_IMAGE = {"low": 0.011, "medium": 0.042, "high": 0.167}

# Rebound by set_category(); every function reads these at call time.
CATEGORY = "patrons"
SUBJECTS_KEY = "subjects"
LABEL = "Patron"
OUT = IDS = IMAGE_IDS = STATE = LUA = None


def set_category(name):
    global CATEGORY, SUBJECTS_KEY, LABEL, OUT, IDS, IMAGE_IDS, STATE, LUA
    if name not in CATEGORIES:
        sys.exit(f"Unknown category {name!r}. Choose from: {', '.join(CATEGORIES)}")
    key, folder, lua_name, label = CATEGORIES[name]
    CATEGORY, SUBJECTS_KEY, LABEL = name, key, label
    OUT = ROOT / "art-wip" / folder          # gitignored
    IDS = OUT / "ids.json"
    IMAGE_IDS = OUT / "image-ids.json"       # id -> IMAGE asset id (the Decal wraps it; ImageLabel needs this one)
    STATE = OUT / "state.json"               # per id: prompt hash at generation, image hash at upload
    LUA = ENGINE / lua_name


set_category("patrons")


def subjects(data):
    return data.get(SUBJECTS_KEY, {})


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
    return sha((data["style"] + "|" + subjects(data)[pid]).encode("utf-8"))


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
    if wants_alpha(pid) and len(b) > 26 and b[25] not in (4, 6):
        problems.append("no alpha channel (expected a transparent background)")
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
            sys.exit(f"Unknown {CATEGORY} ids: {bad}")
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
    opts = CATEGORY_OPTS.get(CATEGORY, {})
    style_key = getattr(args, "style", None) or opts.get("style_key", "style")
    prompt = f"{data[style_key]}. Subject: {subjects(data)[pid]}."
    quality = opts.get("quality", quality)
    ref = getattr(args, "reference", None)
    if ref and not pathlib.Path(ref).exists():
        raise Stop(f"--reference file not found: {ref}")
    for attempt in range(4):
        if ref:
            # Reference image: the edits endpoint takes it as image input and restyles toward it.
            r = requests.post(
                "https://api.openai.com/v1/images/edits",
                headers={"Authorization": f"Bearer {key}"},
                data={"model": model, "prompt": prompt, "size": opts.get("sizes", {}).get(pid, opts.get("size", "1024x1024")), "quality": quality, "n": "1"},
                files={"image[]": (pathlib.Path(ref).name, pathlib.Path(ref).read_bytes(), "image/png")},
                timeout=300,
            )
        else:
            r = requests.post(
                "https://api.openai.com/v1/images/generations",
                headers={"Authorization": f"Bearer {key}"},
                json={"model": model, "prompt": prompt, "size": opts.get("sizes", {}).get(pid, opts.get("size", "1024x1024")), "quality": quality, "n": 1},
                timeout=300,
            )
        if r.status_code == 200:
            path.write_bytes(base64.b64decode(r.json()["data"][0]["b64_json"]))
            if wants_alpha(pid):  # generated on flat magenta; the model has no alpha output, so key it out (tools/patron_art/cutout.py)
                import cutout
                cutout.cutout(str(path))
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
    pids = pick(subjects(data), args)
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
        "displayName": f"{LABEL} {pid}",
        "description": f"Wildcard Tavern {LABEL.lower()} art",
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
    pids = pick(subjects(data), args)
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
    for pid in subjects(data):
        st = status_of(data, pid, ids, state)
        counts[st] = counts.get(st, 0) + 1
        if st != "done":
            todo.append((pid, st))
    print("  ".join(f"{k}: {v}" for k, v in sorted(counts.items())))
    for pid, st in todo:
        print(f"  {st:13} {pid}")
    extra = [p for p in ids if p not in subjects(data)]
    if extra:
        print(f"ids for {CATEGORY} no longer in prompts.json:", extra)


def cmd_queue(_args):
    """JSON list of images that still need uploading (for the Studio upload route)."""
    data = load_prompts()
    ids, state = load_ids(), load_state()
    out = []
    for pid in subjects(data):
        if status_of(data, pid, ids, state) == "needs-upload":
            out.append({"id": pid, "path": str(OUT / f"{pid}.png"), "displayName": f"{LABEL} {pid}"})
    print(json.dumps(out, indent=2))


def cmd_record(args):
    """record <id> <assetId>: store an id uploaded some other way (e.g. via Studio)."""
    pid, aid = args.file, args.extra
    if not pid or not aid:
        sys.exit("usage: record <id> <assetId>")
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
    """record-image <patron_id> <imageId>: the Image asset id inside an entry's Decal."""
    pid, aid = args.file, args.extra
    if not pid or not aid:
        sys.exit("usage: record-image <id> <imageId>")
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
        print(f"WARNING: {len(unresolved)} {CATEGORY} id(s) have a Decal id but no resolved Image id "
              f"(they will NOT load in ImageLabels): {', '.join(unresolved)}")
    ids = {p: imgs[p] for p in ids if p in imgs}
    lines = [
        "--[[",
        f"\tShared/Engine/{LUA.name}",
        f"\tGENERATED by tools/patron_art/generate_patron_art.py (--category {CATEGORY}) -- do not hand-edit.",
        f"\tMaps {LABEL.lower()} id -> rbxassetid. UI should fall back to the entry's emoji icon",
        "\twhen an id is missing from this table.",
        "]]",
        "",
        "return {",
    ]
    for pid in sorted(ids):
        lines.append(f'\t["{pid}"] = "rbxassetid://{ids[pid]}",')
    lines.append("}")
    LUA.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {LUA} with {len(ids)} {CATEGORY}")


def cmd_import_ids(args):
    ids = load_ids()
    for line in pathlib.Path(args.file).read_text().splitlines():
        if "," in line:
            pid, aid = [x.strip() for x in line.split(",", 1)]
            ids[pid] = "".join(ch for ch in aid if ch.isdigit())
    save_ids(ids)
    print(f"{len(ids)} ids saved")


def cmd_estimate(_args):
    """Image counts and cost at the current IMAGE_QUALITY. No API calls."""
    data = load_prompts()
    quality = os.environ.get("IMAGE_QUALITY", "medium")
    base_per = COST_PER_IMAGE.get(quality, COST_PER_IMAGE["medium"])
    print(f"IMAGE_QUALITY={quality}  (~${base_per:.3f}/image, rough; categories with their own quality use that; check platform.openai.com/pricing)")
    total_all = todo_all = 0
    cost_all = 0.0
    for name in CATEGORIES:
        set_category(name)
        ids, state = load_ids(), load_state()
        subs = subjects(data)
        per = COST_PER_IMAGE.get(CATEGORY_OPTS.get(name, {}).get("quality", quality), base_per)
        todo = sum(1 for pid in subs if not (OUT / f"{pid}.png").exists())
        stale = sum(1 for pid in subs if (OUT / f"{pid}.png").exists()
                    and state.get(pid, {}).get("prompt") != prompt_hash(data, pid))
        total_all += len(subs)
        todo_all += todo
        cost_all += todo * per
        print(f"  {name:12} {len(subs):3} prompts, {todo:3} to generate (~${todo * per:.2f}), {stale} stale")
    print(f"  {'TOTAL':12} {total_all:3} prompts, {todo_all:3} to generate (~${cost_all:.2f})")
    # store_page is generate-only (its own command, medium quality, never uploaded), so it sits outside CATEGORIES.
    sp = data.get("store_page_subjects", {})
    sp_todo = sum(1 for pid in sp if not (STORE_DIR / f"{pid}.png").exists())
    sp_per = COST_PER_IMAGE["medium"]
    print(f"  {'store_page':12} {len(sp):3} prompts, {sp_todo:3} to generate (~${sp_todo * sp_per:.2f}), separate command, not in TOTAL")


STORE_DIR = ROOT / "art-wip" / "store_page"


def _fit_image(src, dst, width, height, crop_ratio=None):
    """Center-crop src to `crop_ratio` (w/h) then resize to width x height. Pillow if installed, else macOS sips."""
    try:
        from PIL import Image
        im = Image.open(src).convert("RGB")
        w, h = im.size
        if crop_ratio:
            want_w = min(w, int(h * crop_ratio))
            want_h = int(want_w / crop_ratio)
            left, top = (w - want_w) // 2, (h - want_h) // 2
            im = im.crop((left, top, left + want_w, top + want_h))
        im.resize((width, height), Image.LANCZOS).save(dst)
        return
    except ImportError:
        pass
    import shutil, subprocess
    if not shutil.which("sips"):
        sys.exit("Need Pillow (pip install Pillow) or macOS sips to crop and resize.")
    tmp = str(dst) + ".tmp.png"
    shutil.copyfile(src, tmp)
    if crop_ratio:
        out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", tmp], capture_output=True, text=True).stdout
        w = int(out.split("pixelWidth:")[1].split()[0])
        h = int(out.split("pixelHeight:")[1].split()[0])
        want_w = min(w, int(h * crop_ratio))
        want_h = int(want_w / crop_ratio)
        subprocess.run(["sips", "-c", str(want_h), str(want_w), tmp], capture_output=True, check=True)
    subprocess.run(["sips", "-z", str(height), str(width), tmp, "--out", str(dst)], capture_output=True, check=True)
    os.remove(tmp)


def cmd_store_page(args):
    """Generate-only: 6 thumbnail candidates (1920x1080) and 3 icon candidates (512x512) into art-wip/store_page/.
    Never uploads. The title is added by hand in an editor."""
    key = need("OPENAI_API_KEY")
    data = load_prompts()
    subs = data["store_page_subjects"]
    style = data["store_page_style"]
    model = os.environ.get("IMAGE_MODEL", "gpt-image-1")
    quality = "medium"
    raw_dir = STORE_DIR / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)
    only = set(args.only.split(",")) if args.only else None
    for pid, subject in subs.items():
        if only and pid not in only:
            continue
        final = STORE_DIR / (pid + ".png")
        if final.exists() and not args.force:
            print(f"skip {pid} (exists)")
            continue
        is_icon = pid.startswith("icon_")
        size = "1024x1024" if is_icon else "1536x1024"
        r = requests.post(
            "https://api.openai.com/v1/images/generations",
            headers={"Authorization": f"Bearer {key}"},
            json={"model": model, "prompt": f"{style}. Subject: {subject}.", "size": size, "quality": quality, "n": 1},
            timeout=300,
        )
        if r.status_code != 200:
            body = r.text[:400]
            sys.exit(f"STOPPED at {pid}: HTTP {r.status_code}: {body}")
        raw_path = raw_dir / (pid + ".png")
        raw_path.write_bytes(base64.b64decode(r.json()["data"][0]["b64_json"]))
        if is_icon:
            _fit_image(raw_path, final, 512, 512)
        else:
            _fit_image(raw_path, final, 1920, 1080, crop_ratio=16 / 9)
        print(f"made {pid}", flush=True)


def main():
    load_env()
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["generate", "upload", "lua", "all", "import-ids", "status", "queue", "record", "record-image", "estimate", "store_page"])
    ap.add_argument("file", nargs="?")
    ap.add_argument("extra", nargs="?")
    ap.add_argument("--category", "-c", default="patrons", choices=list(CATEGORIES),
                    help="patrons (default), bosses, recipes, housepasses or titles")
    ap.add_argument("--workers", type=int, default=4, help="parallel requests for generate/upload (default 4)")
    ap.add_argument("--stale", action="store_true", help="also regenerate images whose prompt changed")
    ap.add_argument("--only")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--style", help="prompts.json style key to use instead of the category's (e.g. house_style)")
    ap.add_argument("--reference", nargs="?", const="art-wip/backgrounds/journey_map.png",
                    help="reference image sent to the images edit endpoint (default: art-wip/backgrounds/journey_map.png)")
    a = ap.parse_args()
    if a.style and a.style not in load_prompts():
        sys.exit(f"Unknown style key {a.style!r} in prompts.json")
    set_category(a.category)
    if a.cmd == "generate":
        cmd_generate(a)
    elif a.cmd == "upload":
        cmd_upload(a)
    elif a.cmd == "lua":
        cmd_lua(a)
    elif a.cmd == "estimate":
        cmd_estimate(a)
    elif a.cmd == "store_page":
        cmd_store_page(a)
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
