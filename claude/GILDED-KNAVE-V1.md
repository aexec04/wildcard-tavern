# Gilded Knave v1 (archived)

v1 is the full game before the focused remake: Journey map, Tome and Collection, Settings, Volume panel, Poker Hands reference, boards, Counter extras, Season and storefront, on the Concept T painted play screen (`ConceptTPlay`).

## Read the old code
`git tag gilded-knave-v1` and `git branch gilded-knave-v1` both point at 781096f (local only, never pushed). `git show gilded-knave-v1:src/Client/ConceptTPlay.lua`, or `git checkout gilded-knave-v1` in a separate worktree.

## Flags (`src/Shared/Engine/FeatureFlags.lua`)
All default false. `LEGACY_V1 = true` turns every flag on; a single flag turns one feature back on. A false flag means the icon is not created (the hub hands back a detached, invisible button so its opener can never fire).

| Flag | Where it is read |
| --- | --- |
| JOURNEY_MAP | corner Journey icon, `makeCornerButton(..., "journey")` in `Client/init.client.lua`, opener in `Client/Journey.lua` |
| TOME_COLLECTION | corner Collection icon (`"collection"`), opener in `Client/Collection.lua` |
| SETTINGS | corner gear (`"settings"`), opener in `Client/Settings.lua`, gear placement in `Client/ConceptTPlay.lua` |
| VOLUME_PANEL | corner speaker (`"volume"`), `Client/VolumePanel.lua` |
| RECIPES | corner Poker Hands icon (`"handRef"`), `Client/PokerHandsReference.lua` |
| DAILY_BOARD, NOTICE_BOARD, HAGGLE_COUNTER, PACK_ROOM, SEASON, STOREFRONT | reserved names, not wired yet (the menu and Counter keep them) |

The main menu and the Night map are untouched. Settings and Volume stay reachable from the menu, so Calm mode and mute are still available.
`GAMEPLAY_V1` (the old table behind a flag) lands with the Gameplay v2 task; until then `ConceptTPlay` is the only table.

## Worth reusing in the remake
Scoring engine (`Engine/Scoring`, `HandPreview`), Patron effects (`Engine/Patrons`), save data and remotes (server), card faces (`Engine/CardFacePainted`, `ConceptTCardFaces`), sound ids (`Engine/SoundIds`, `SoundFX`), `Client/FxLoop`, `Client/TavernKit`.
