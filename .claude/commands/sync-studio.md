---
description: Check that the open Studio place matches the files on disk, and fix any drift
model: haiku
---
Studio only shows our code if Rojo is syncing it. Verify, don't assume.

Mapping (default.project.json): `src/Client` -> StarterPlayer.StarterPlayerScripts.Client, `src/Shared` -> ReplicatedStorage.Shared, `src/Server` -> ServerScriptService.Server.

1. Use the Roblox Studio MCP: `list_roblox_studios`, pick the Wildcard Tavern place (confirm if several are open), then `get_studio_state`. Use the Edit datamodel.
2. For every .lua file under src/ (or only the files in `git diff --name-only` plus untracked files, if $ARGUMENTS is "changed"), find the matching script in Studio with `execute_luau` and compare. Compare a hash or length plus a distinctive line, not whole sources, to save tokens. Report: in sync, differs, missing in Studio, extra in Studio.
3. If anything differs, first tell me Rojo is probably not connected: `cd ~/Desktop/wildcard-tavern && rojo serve`, then Connect in the Studio Rojo plugin. Re-check after I say it's connected.
4. Only if I ask, push the differing files into Studio directly by setting `.Source` through `execute_luau` (use a long-bracket string with enough `=` signs that the file can't close it). Never overwrite a Studio script that has changes not on disk: show me the difference and ask first.
5. Finish with a one-line verdict: "Studio matches disk" or the list of drift.
