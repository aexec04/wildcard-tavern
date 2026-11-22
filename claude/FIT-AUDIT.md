# Screen fit audit

Run with `lua tools/fit_audit.lua write`. Sizes: 800x450, 1024x768, 1366x768, 1920x1080. Rules: on screen, text 11 px (14 px body), touch 44 px, no unlisted sibling overlap.

Covered (layout modules in Engine/): Menu, Loading, Settings panel, Store, Table (Gameplay2Layout and PlayBoardLayout), Counter shop, Draft, Collection grid, Daily Rewards row, Run Over.
Not covered: Quests, Season, Victory, Tome tabs, Tavern Map and Round Select have no pure rect layout to read (they size in Client code), and no layout module publishes text sizes, so text size is held by `tools/lint_text_size.lua` (14 px minimum in src). Rects of art layers (Counter shop scene) overlap by design and are listed as intended in `src/Shared/Tests/FitScreens.lua`.
Result: every shared screen fits at all four sizes (tested in EngineTests, `FitAudit`). Nothing needed a code fix in shared files.

## Failures in shared screens
None.

## for the other lane: menu
- Store at 800x450, touch: closeButton is 141x39 (needs 44)

## for the other lane: table
- Table (play board) at 800x450, overlap: discards and ringRow overlap by about 61 px
- Table (play board) at 800x450, overlap: hands and ringRow overlap by about 61 px
- Table (play board) at 800x450, overlap: handsDiscards and ringRow overlap by about 89 px
- Table (play board) at 1024x768, overlap: discards and ringRow overlap by about 56 px
- Table (play board) at 1024x768, overlap: hands and ringRow overlap by about 56 px
- Table (play board) at 1024x768, overlap: handsDiscards and ringRow overlap by about 82 px
- Table (play board) at 1366x768, overlap: discards and ringRow overlap by about 103 px
- Table (play board) at 1366x768, overlap: hands and ringRow overlap by about 103 px
- Table (play board) at 1366x768, overlap: handsDiscards and ringRow overlap by about 150 px
- Table (play board) at 1920x1080, overlap: discards and ringRow overlap by about 148 px
- Table (play board) at 1920x1080, overlap: hands and ringRow overlap by about 148 px
- Table (play board) at 1920x1080, overlap: handsDiscards and ringRow overlap by about 215 px
