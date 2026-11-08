# The Wildcard Adventure: branching world map (design only)

Goal: the Tavern Map becomes the main reason to play. Today it is a straight 8-Night road with fixed rewards. The new map is a large world graph. The player chooses a path through biomes, takes optional side stops (minigames, shops, shrines) and earns biome rewards. No game code is written by this doc.

What exists now (keep working): `Engine/JourneyMap.lua` (8 Nights, 3 Endless milestones, rewards `title` / `cardBack` / `set`), `profile.clearedNightIds`, `recordNightsCleared`, `equipReward`, `revealState` fog rule, `Client/JourneyMapView/Fog/Hero/Scenery`, `SceneKeys` (scene per Night + round kind), the `EquipJourneyReward` remote. A "run" is 8 Nights of 3 rounds (Small, Big, Boss); one Night = one stop. Everything below builds on those.

## 1. World structure

The world is a directed graph of **stops**. Each stop is one Night (3 rounds) except side stops. The run still ends at the Keeper's Table (Night 8 rule: beat its boss to win), but the road there is chosen.

- **Regions (biomes):** meadow, river, peaks, tavern (existing) plus desert, swamp, snow, coast (new). A run visits 5 regions: **Start (Dusty Road) -> two biome choices -> one more biome choice -> the Tavern region**. The Tavern region is always last (Gate, Hall, Keeper).
- **Main path:** 8 Night stops per run, like today. A run is 8 Nights long whichever branches are taken, so balance (`BalancePlan`) stays valid. Night number = difficulty, as now.
- **Branches:** at 3 forks (after Night 2, 4 and 6) the player picks 1 of 2 or 3 roads. Each road has 2 Night stops, then rejoins at a **crossing**. So the graph is 4 layers: `[N1 N2] -> fork A -> [roadA1 roadA2 | roadB1 roadB2] -> crossing -> ...`.
- **Side stops:** optional spurs off a main node, not Nights. Visiting one costs nothing but time; it is reached by a short dotted detour and returns to the same node. At most 2 per region.
- **Length:** a normal run is 8 Nights (about 25 minutes, as today). With 4 new biomes and 3 forks there are 3 x 3 = 27 distinct main routes, a reason to replay. Endless Nights stay as they are (the doors after the Keeper).
- **Fit to Nights:** one stop = one Night. A biome road of 2 stops = 2 Nights. Scene art keys already exist per Night location, so each new stop needs `_a/_b/_in` scenes (see art list).

## 2. Data format (Lua, `Engine/WorldMap.lua`, pure, tested)

```lua
WorldMap.Regions = {
  meadow = { name = "Wildflower Meadow", tint = {190,200,142}, scenery = "region_meadow", reward = "meadow" },
  -- river, peaks, tavern, desert, swamp, snow, coast, road
}
WorldMap.Stops = {
  dusty_road = { kind = "night", region = "road", art = "dusty_road", name = "The Dusty Road",
                 next = { "wildflower_meadow", "desert_dunes" }, x = 0.05, y = 0.5 },
  wildflower_meadow = { kind = "night", region = "meadow", art = "wildflower_meadow", next = { "garden_terrace" }, ... },
  oasis_stall = { kind = "side", parent = "desert_dunes", side = "shop" },        -- bonus stop
  dice_hollow = { kind = "side", parent = "swamp_boardwalk", side = "minigame", game = "dice" },
}
WorldMap.Start = "dusty_road"
WorldMap.Finish = "keepers_table"
```

- `kind`: `night` (counts as a Night), `side` (optional). `next`: 1 id (road) or 2 to 3 ids (a fork). `art` keeps the SceneKeys / map_nodes key.
- `night` number is NOT stored on the stop. It is the depth along the chosen path (stop 1 = Night 1 ...), so any route gives Nights 1 to 8.
- Pure helpers (all unit-tested under `lua`): `WorldMap.validate()` (every id reachable from Start, every route ends at Finish, every route is exactly 8 Night stops, no cycles, sides have a parent), `choicesAfter(stopId)`, `routeNight(route)`, `regionOf(stopId)`.
- Existing `JourneyMap.Nights` becomes the default straight route; `JourneyMap.nightEntry(n)` keeps working by reading the profile's current route (fallback: the old list), so `recordNightsCleared` and the Night 1 to 8 reward ids do not change.

## 3. Choices: shown and saved

- **Shown:** on the map the next stops after a cleared Night glow. At a fork the road splits into 2 or 3 glowing paths, each with its biome icon, a one-line hint ("Snowy, tougher bosses, rare card backs") and the biome reward preview. Tapping one opens the stop card; "Take this road" confirms. Fog (`revealState`) reveals the chosen road and a teaser of one stop beyond it; unchosen roads dim.
- **Saved:** profile gains `worldRoute` (array of stop ids chosen so far in the CURRENT run, last = current), `worldSeenStopIds` (set, for map memory and fog), `worldBiomeClears` (`[region] = count`), `worldRewardIds` (set, so rewards grant once). Server remote `ChooseRoad(stopId)`; the server validates `stopId` is in `choicesAfter(current)` and only while the phase is `roundSelect` of a new Night (reuse the phase gate style of `phaseAllowsShopActions`). Daily/Weekly/Seed runs get a fixed route from the seed so leaderboards stay fair.
- A run snapshot already exists (`roundStartSnapshot`); `worldRoute` rides in it so "One More Round" restores it.

## 4. Rewards: tied to biomes and branch ends

Rewards do NOT change at every stop. Three triggers only:
1. **Biome milestone:** clearing the 2nd stop of a biome road (branch end) for the first time. Grants that biome's reward.
2. **Region complete (all stops of a biome seen over time):** a bonus title.
3. **Keeper win:** as today (title `tavern_keeper`), plus the route badge.

Per-biome reward table (new content to author in the registries, one per row; ids are examples):

| Biome | Branch-end reward | Theme |
|---|---|---|
| meadow | card back `meadow_checks` (exists) | flowers, bees |
| river | patron `bridge_troll_cook`, title `bridge_crosser` | water, bridges |
| peaks | card set `mountain_festival` (exists), recipe `summit_stew` | snow, gold |
| desert | patron `sand_merchant`, card back `dune_gold` | coins, spice |
| swamp | recipe `bog_brew`, card back `lilypad_green` | misty, mushrooms |
| snow | card set `frosted_garden` (exists), title `frost_walker` | ice, lanterns |
| coast | patron `lighthouse_keeper`, card back `shell_pearl` | tide, ropes |
| tavern | cosmetic set `gala_hall`, title `tavern_keeper` | gold, banners |

Existing Night 1 to 8 reward ids stay valid: the default route still grants them (keep `recordNightsCleared` as the grant path for the default route). New rewards use a second function `recordBiomeCleared(profile, region)` with the same `unlocked*` fields and the same collection discovery. Every new item gets a rarity (the six tiers), a `flavorText`, and a `prompts.json` entry (project rule). Wins in a minigame upgrade the roll inside the biome (section 6), never the fixed reward.

## 5. The compass

The compass becomes the **road wheel**: a clickable ring drawn on the map corner.
- Idle: points to the Finish. Tapping the compass **rotates it to point at the biome** the player wants; the map camera eases to that direction and the roads heading that way highlight. At a fork, spinning the wheel to a direction selects the road whose direction matches (a nice physical way to choose).
- Each biome sits at a compass direction (N snow, E tavern, S desert/swamp, W coast ...). The wheel shows biome icons around the rim.
- A **compass charge** is earned by winning minigames (max 3). Spending one reveals the NEXT biome's reward preview and one hidden side stop on the map (fog lifts for that spur). Free to turn the wheel; charges only reveal.
- Pure helpers: `WorldMap.bearing(fromStop, toStop)` (degrees from x/y) and `WorldMap.pickByBearing(stops, angle)`, unit-tested. UI: `Client/CompassWheel.lua`.

## 6. Side stops and minigames

All are optional, cost nothing to lose, and are played in a small overlay on the map. Winning gives a **bonus token** (up to 3 per run) which the player spends at the branch end to upgrade the biome reward roll (one rarity tier better) and can give a compass charge.

| Stop | One line | UI needed |
|---|---|---|
| Dice (minigame) | Roll two dice against the house, closest to 7 without going over, up to 3 rolls. | dice icons, roll button, tally. |
| Card flip (minigame) | Memory match: 6 face-down cards, find 3 pairs in 8 flips. | 6 card buttons, flip tween (reuse `DealFlip`), flip counter. |
| Lockpick (minigame) | Stop a sweeping needle inside the green arc 3 times. | circular track, moving needle, tap. |
| Trivia (minigame) | 3 tavern-lore questions about the cards and hands (from registries, kid-safe). | question card, 3 answer buttons, timer ring. |
| Shop stop | A small Counter with 2 offers, no reroll; uses the existing Shop cards. | reuse `ShopCards`, new smaller frame. |
| Shrine | Pay Tips for a random free House Pass for the next Night. | altar art, one button. |
| Rest stop | Restore the One More Round or add 1 hand to the next Night (pick one). | two-choice dialog. |

Rules: a side stop is visited between Nights while the phase is `roundSelect`; the server runs minigame results (seeded RNG, never trust the client for the win flag; the client sends moves, the server scores). Rewards are tokens and run bonuses only, so a minigame can never break balance by itself.

## 7. Build order (each fits one queue task)

1. **WorldMap data + validator + tests** (`Engine/WorldMap.lua`, default route equals today's 8 Nights, `validate()` tests, no UI change).
2. **Profile + remote**: `worldRoute`, `worldBiomeClears`, `ChooseRoad`, route in the run snapshot, Daily/Seed fixed routes, engine tests for rejection outside `roundSelect`.
3. **Map rendering of forks**: `JourneyMapView` draws the graph (roads, glow, choice card), fog on the graph, hero walks the chosen road. Uses the existing art for 2 branches only.
4. **Biome rewards**: `recordBiomeCleared`, 8 reward rows authored into Patrons/Recipes/CardBacks/Titles with rarity, collection discovery, tests for "grant once".
5. **Compass wheel**: `CompassWheel.lua`, bearing helpers, charges, reveal of a side stop.
6. **Side stops (shop, shrine, rest)**: server handlers, phase gate, UI reuse.
7. **Minigames, two at a time**: (a) dice + card flip, (b) lockpick + trivia, with server scoring, tokens and the reward upgrade.
8. **New biomes art + scenes + balance pass**: desert, swamp, snow, coast stops; per-biome boss pool flavor; simulation tests of every route.

## 8. Art needed (counts, generated with `house_style` like the existing)

- `scenes`: 4 new biomes x 2 stops x 3 (`_a/_b/_in`) = **24**; plus side stop interiors (shop, shrine, rest) x 3 = **9** (optional, can reuse tavern scenes first).
- `map_nodes`: 8 new stops + 7 side-stop icons + 4 minigame icons = **19**.
- `map_regions`: desert, swamp, snow, coast (wide painted tiles, same recipe) = **4**.
- `map_decor`: about 8 new doodles (cactus, palm, reed, igloo, boat, lighthouse, tent, shell) = **8**.
- `card_backs`: 5 (dune_gold, lilypad_green, shell_pearl, frost_walker, gala) = **5**.
- `patrons` 3, `recipes` 2, `titles` 4 for the biome rewards = **9**.
- `fx` / `hud`: compass wheel ring, fork glow, token icon, dice faces, lockpick dial = about **8**.
- `minigame_icons`: 4. Total roughly **90 images**, in 3 batches (regions and nodes first, scenes next, rewards last). Image ids are recorded the usual way.

## 9. Risks

- **Balance:** more routes means more difficulty variance. Mitigation: Night number = depth, so every route has the same 8 difficulty steps; biomes only change flavor (boss pool, shop weights), not targets. Simulation test per route in step 8.
- **Save compatibility:** the game is unpublished (no live saves), but keep `clearedNightIds` and the 8 reward ids stable so the default route behaves like today.
- **Scope/art cost:** 90 images and 4 minigames is large. Ship in order: forks + biomes with existing art first (steps 1 to 4), minigames last. Each step leaves the game playable.
- **Leaderboard fairness:** Daily/Weekly/Seed must fix the route from the seed, and minigame bonuses must not apply to ranked boards (or use a separate board like Revived).
- **Server authority:** minigame results and route choices must be validated server-side (rejection tests, like the shop phase gate).
- **UI complexity:** a large graph on one canvas has clipping and label risks (we already tuned a single trail). Use the Nudge tool and keep forks to 3 roads at most.
- **Content rules:** kid-safe names only, no alcohol (swamp/coast/desert names and the shop stop must avoid drink references), no copied art from other games.
