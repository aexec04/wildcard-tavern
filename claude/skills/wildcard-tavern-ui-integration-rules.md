# UI integration rules

Short list for any UI or scene task (tabs, shop, menu, HUD, popups).

## Layers
- Every ZIndex of 100 or more comes from `Shared/Engine/Layers.lua` as a band plus an offset: `Layers.effect + 10`, `Layers.popup + 2`, `Layers.confirm`, `Layers.toast`. No bare number of 100 or more anywhere in `src/Client` (a test fails with file and line).
- Bands: table 1 to 99, table effects and banners 100 to 999, gear and quick icons 1000, screens and pages 2000 to 2999, popups 5000, confirms 6000, toasts 7000.
- A new `...Backdrop` must be listed in `Engine/PopupLayers.lua`: `FULL_SCREEN` (hides the whole table) or `PARTIAL` (table stays). A test fails until it is.
- Confirm plates ("Are you sure?") use `Layers.confirm` so they are always above every HUD and menu layer and always clickable.

## Overlay audit (end every UI task with this)
In Studio Play, run `tools/overlay_audit.luau` with `execute_luau`. It opens menu, map, Tome pages, news, haggle, round1 and boss1 for three Card Sets (and the store, season, daily rewards and quests when present) through DebugGoto, and for each open page or popup prints `PASS <screen>` or `FAIL <screen>` with the paths of every visible object that would draw above it.
- Fix a FAIL by moving the offender to the right band or hiding it through PopupLayers, never by raising the page by a bare number.
- Report the final line `[overlay_audit] N PASS, M FAIL over K screens` in the OUTBOX.

## Look 1 to 1
Furniture, hotspots and per-set art are built to match the reference (`claude/reference`); a "looks the same" report means the per-set art or layout was not wired. Check the equipped path and a previewed set (`round1:<setId>`).
