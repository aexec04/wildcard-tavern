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
- A painted parchment map background for the Tavern Map tab (currently a flat panel).
- Victory banner art for the Night 8 moment.
- Backdrops for the winter, festival and closing sets are listed above; they are also Journey rewards.
- Card back art for `kitchen_checks` and `hall_banner` (tinted classic back for now).

