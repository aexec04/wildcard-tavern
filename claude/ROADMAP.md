# Wildcard Tavern: Roadmap to the front page

Solo project now (one developer). Goal: reach the Roblox Home "Recommended for You" front page and give players a reason to return every day. Target: at least 3 hours of content on average per player. No deadline of one week; ship in phases and keep every build playable.

## What the Roblox algorithm rewards
Long-term retention, engagement and monetization of players who find the game organically on Home. Ad traffic does not count toward ranking. So: win the first 5 minutes, then bring players back daily, then monetize without hurting either. Check Creator Analytics > Acquisition > Home Recommendations after launch and fix the weakest signal first.

## Rules for every feature
- It must serve one of: first-5-minutes, daily return, run-after-run variety, social spread, fair monetization.
- Art and feel are the selling point: less text, more painted Roblox-style art, hover for detail.
- Never pay to win. Cosmetics and convenience only. Daily and weekly leaderboards stay fair.
- Code-only tasks and art-spend tasks are always separate queue tasks.

## Phase 1: First 5 minutes
- [ ] Thumbnail, icon, title and a short gameplay video for the game page (user-only: Creator Hub)
- [ ] Fast load, mobile layout and controls pass on a real phone (user-only test)
- [x] Tutorial under 2 minutes ending in a first win and a reward
- [x] First-run reward and "next goal" banner on the menu

## Phase 2: Daily return and long-term goals
- [x] Difficulty ladder: win to unlock the next tier, each tier adds one rule; stamps on the map
- [x] Unlock drip: start small, unlock Patrons, recipes, Card Sets and titles through play; Collection shows locked silhouettes
- [x] Daily login streak and 3 daily quests (small Tips and cosmetic rewards)
- [x] Always-visible next goal on the menu
- [x] Follow prompt so players get Roblox reminders
- [x] Tavern Season: a 30 day, 30 tier reward ladder on top of Tavern Rank (`Engine/SeasonTrack.lua`, Season tile on the menu)
- [x] Collection completion rewards (rings and 25, 50, 75, 100 percent milestones per group) and a menu ticker with today's best run (`Engine/CollectionRewards.lua`, `Engine/MenuTicker.lua`)

## Phase 3: Variety and exploration
- [x] Map discoveries: hidden chests, merchants and secret Patrons per region; regions discovered counter
- [x] Start-of-run choices: starting deck, starting Patron, one curse or blessing
- [x] Random events between Nights
- [x] Challenge runs with a twist (Pairs Only, No Discards)
- [x] Legend prestige after stake 8: ten cosmetic Legend levels (`Engine/Legend.lua`)
- [x] More bosses with distinct rules; Boss Rush after the first win

## Phase 4: Social
- [x] Friends and global leaderboards for Daily, Weekly and Endless
- [x] Share a seed or run result, "beat my score" challenge
- [ ] Later: co-op or versus

## Phase 5: Game feel and monetization
- [x] Score pops, screen shake, combo chains, card sounds, one music track per biome (user-only: pick audio ids)
- [x] Cosmetic sales: Card Sets, backdrops, titles; Starter Pack; VIP pass; paid continue with separate boards
- [x] Flair: equippable Score Numbers, Play Trail, Finisher and Name Aura (`Engine/Flair.lua`, Flair panel in the Collection); store pieces come with the premium track task
- [ ] Real Game Passes, Developer Products and Badges created in Creator Hub (user-only)

## Phase 6: Live ops after launch
- [x] Live ops tables (`Engine/LiveEvents.lua`) and a News banner and panel on the menu
- [ ] An update every 1 to 2 weeks (new road, Patrons or a seasonal event)
- [ ] Weekly look at Home Recommendations analytics

## Creator Hub items you must create (placeholders are id 0 in code until you paste the real ids)
Everything below is cosmetic or a tiny convenience, never pay to win. In Studio each placeholder is granted free so it can be tested; in the live game it shows "Coming soon" until its id is set.
- [ ] Developer Product "Starter Pack" (one time per player, the game grants it once even if bought twice). Paste its id into `Store.Items` `starter_pack.productId` in `src/Shared/Engine/Store.lua`. Contents: Gilded Ledger card back, Winter Evening Card Set, Founding Guest title.
- [ ] Developer Product "Card Set Bundle". Paste its id into `card_set_bundle.productId`. Contents: Festival Night and Closing Time Card Sets.
- [ ] Game Pass "VIP". Paste its id into the `vip` entry of `GamePasses.Definitions` in `src/Shared/Engine/GamePasses.lua`. Perks: gold star beside the name on boards, +3 Tips banked each day, a second badge slot.
- [x] Developer Product "One More Round" is already set (`GamePasses.DeveloperProducts`). Game Passes Fast Forward and Golden Gala Set are already set.
- [ ] Developer Products for Flair and the Season premium track (one time each, ids go into `Store.Items` `productId` in `src/Shared/Engine/Store.lua`): `flair_rainbow_numbers`, `flair_ribbon_trail`, `flair_crown_finisher`, `flair_star_aura`, `flair_bundle`, `premium_harvest_moon`, `premium_winter_welcome`. Prices are read from MarketplaceService; until an id is set the live game says "Coming soon" and Studio grants it free.
- [ ] Store icons: generate `store_subjects` images (4 bundle cards) and the `menu_icons` `store` icon with the art task, then wire them (emoji until then).
- [ ] Roblox Badges: create them in Creator Hub and paste the ids into `src/Shared/Engine/BadgeIds.lua` (list in that file).

## Adding a live event in 5 lines
Open `src/Shared/Engine/LiveEvents.lua` and append one entry to `LiveEvents.Definitions`:
1. `id = "my_event", name = "My Event", icon = "🎉", bannerKey = "news_my_event", blurb = "One short line for the banner."`
2. `startDate = "2026-12-05", endDate = "2026-12-07"` (UTC, both days count)
3. `modifier = { kind = "xpMultiplier", value = 2 }` or `{ kind = "dailyLabel", text = "Theme Name" }` or `{ kind = "none" }`
4. `rewards = { { kind = "title", id = "..." }, { kind = "cardBack", id = "..." }, { kind = "tips", amount = 5 } }` (optional; claimed once while it runs)
5. Run `lua tools/run_tests_local.lua`: a test checks dates, ids and reward ids. Add a `news_subjects` prompt in `tools/patron_art/prompts.json` for the banner art (an emoji shows until it exists).
Events never change the Daily, Weekly or Seed boards: the modifier only affects account XP or adds text beside the Daily date.

