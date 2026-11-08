# Art TODO

Images to generate. Each is a placeholder `rbxassetid://0` until replaced; the game falls back to the default art meanwhile.

## Cosmetic Set backdrops (`src/Shared/Engine/CosmeticSets.lua`, `backdropImage`)
Same tavern interior and camera as the default gameplay backdrop (`ArtAssets.gameplayBackground`), different mood. Match the default's size and composition so UI sits the same.

| Set id | Mood | Notes |
|---|---|---|
| `winter_evening` | Winter | Snow outside the windows, warm fire, cool-blue window light |
| `festival_night` | Festival | Paper lanterns, ribbons, bunting, warm celebratory light |
| `closing_time` | Closing Time | Few lamps lit, chairs up, quiet and dim |
| `golden_gala` | Gala (Game Pass) | Gold drapes and trim, polished and bright |

When an image is ready, paste its id into that set's `backdropImage`.

## Optional: card back art
New card backs (`winter_frost`, `festival_ribbon`, `closing_lantern`) currently reuse the classic back art, tinted with the card back's `colors.base`. Real art would need a `cardBackImage` field and a small change in `Client/CosmeticSetsView.lua`.

## Journey map (all optional, emoji and UI shapes are used now)
- 8 location icons, one per Night: Front Porch, Warm Kitchen, Snug Booth, Cozy Loft, Garden Terrace, Grand Hall, Rooftop View, Keeper's Table (replace `icon` in `Engine/JourneyMap.lua` with image ids if wanted).
- An Endless Nights node icon.
- Painted map background for the Tavern Map tab: paste the id into `JourneyMap.Config.journeyMapImage` (`Engine/JourneyMap.lua`). Make it about 2.8:1 wide (`Config.mapAspect`); node positions are the normalized `x`/`y` on each node in the same file, tune them to match the painting. 0 or a failed load keeps the UI-built look.
- Optional art for the Night 8 "Tavern Champion" panel (`Client/NightVictory.lua`) and icons for the 3 Endless milestone nodes (`EndlessMilestones[].icon`).
- Backdrops for the winter, festival and closing sets are listed above; they are also Journey rewards.
- Card back art for `kitchen_checks` and `hall_banner` (tinted classic back for now).
- Card back art for `ember_hours` (Endless Night 15 reward, tinted classic back for now).
- Biome reward art (emoji fallback today; prompts already in `tools/patron_art/prompts.json`): patrons `meadow_bee`, `ferry_captain`, `summit_guide`, `sand_merchant`, `marsh_gardener`, `lantern_lighter`, `lighthouse_keeper` (category `patrons`); recipes `honey_drizzle`, `riverside_chowder`, `summit_stew`, `date_cake`, `bog_stew`, `frost_pudding`, `sea_biscuit` (category `recipes`).
- Biome completion rewards (emoji or flat-color fallbacks today): 8 Cosmetic Set backdrops (`meadow_picnic`, `riverside_evening`, `summit_camp`, `dune_market`, `marsh_lanterns`, `snowy_hearth`, `harbor_lights`, `tavern_feast`; `backdropImage` is `rbxassetid://0`, the set's `backdropStyle` tints the default tavern meanwhile), 16 badge icons (`biome_<region>` and gold `master_<region>` for meadow, river, peaks, desert, swamp, snow, coast, tavern; `Engine/Badges.lua`, emoji today) and 16 title portraits (category `titles`, prompts already in `tools/patron_art/prompts.json`: `meadow_walker`, `river_crosser`, `peak_climber`, `dune_crosser`, `marsh_strider`, `snow_trekker`, `cove_sailor`, `tavern_guest` and the `*_master` versions).
- Badge icons for the 15 rule badges in `Engine/Badges.lua` (wins_1, wins_5, wins_25, night_3, night_5, night_8, night_10, minigame_1, minigame_10, collection_25, collection_50, collection_100, streak_3, streak_7, streak_14, season_winter_lanterns): emoji today, shown in `Client/BadgesPanel.lua` medallions.
