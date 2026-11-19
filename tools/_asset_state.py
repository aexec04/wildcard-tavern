#!/usr/bin/env python3
"""Print the Roblox moderation state and type of asset ids (read only). Usage: python3 tools/_asset_state.py <id> [<id> ...]
Reads ROBLOX_API_KEY from tools/patron_art/.env and never prints it."""
import os, pathlib, sys
import requests

env = pathlib.Path(__file__).resolve().parent / "patron_art" / ".env"
for line in env.read_text().splitlines():
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
key = os.environ.get("ROBLOX_API_KEY", "")
print("roblox key present:", bool(key))
for i in sys.argv[1:]:
    try:
        r = requests.get("https://apis.roblox.com/assets/v1/assets/" + i, headers={"x-api-key": key}, timeout=20)
        j = r.json() if "json" in r.headers.get("content-type", "") else {}
        print(i, r.status_code, j.get("assetType"), (j.get("moderationResult") or {}).get("moderationState"), j.get("displayName"), j.get("code") or "")
    except Exception as e:
        print(i, "error", type(e).__name__)
