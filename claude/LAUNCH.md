# Wildcard Tavern: playtest and launch notes

Plain language, for you, the solo developer. Do the sections in order. Tick a line only when you saw it with your own eyes.
Tip: do the playtest on a phone-sized window too (Studio device emulator, 360x640) and once at 1920x1080.

## 1. Thirty minute self playtest

Use a fresh test account if you can (no saves), then a second pass on your main account.
Screenshot anything that looks wrong and write the screen name on it.

**Minutes 0 to 3: the first five minutes**
- [ ] Menu opens, title shows, music plays, nothing overlaps the frame art. Screenshot: menu.
- [ ] Tutorial tile: the whole walkthrough finishes in about two minutes and ends with a card back and the Newcomer title.
- [ ] A brand new profile starts a normal run, the first hands are the scripted ones, the hint text names the real combo.
- [ ] Play Hand, Discard and the sort buttons work and nothing blocks input after a score.

**Minutes 3 to 10: one full Night**
- [ ] Round Select shows three cards that fit the screen, Select works, Skip gives a Tag and goes to the next Round Select (no Shop after a skip).
- [ ] Travel cover plays, then the scene matches the road stop. The Boss round has the walk-in, the boss portrait, taunt bubble, damage numbers.
- [ ] Clear a round: the Counter (Shop) opens. Buy a Patron, a Recipe and a Pack. Reroll once. Next Round closes it.
- [ ] Hover a Patron seat, the deck pile, a corner icon: one tooltip, above the target, gone when you move away.
- [ ] Open Your Deck: card faces, states (in hand, played, discarded) look right.
- [ ] Open Poker Hands: your last hand row is highlighted.

**Minutes 10 to 15: lose and win paths**
- [ ] Lose a run on purpose: Game Over shows the summary, Share, Challenge, Invite buttons, and One More Round (free once a day).
- [ ] Run Summary: Save as my badge works once.
- [ ] Start a Quick Run from Run Setup: four Nights, stake 1, gentle first Night.
- [ ] Run Setup: sections in order (Deck Variant, Difficulty, Stakes, Challenge, Special Modes). Begin Run, Cancel.

**Minutes 15 to 22: every menu tile and panel**
- [ ] Daily, Weekly and Seed tiles: each opens, the board loads or shows a calm message.
- [ ] Road Ahead (Tavern Map): fog, hero walk, Take this road chips, compass wheel, side stops. Screenshot: map.
- [ ] Quests: three quests, claim shows XP. Tavern Rank bar moves after a run.
- [ ] Store: Starter Pack, Card Set Bundle, VIP, Continue show prices; in Studio the free grant works.
- [ ] News: the three live events show dates.
- [ ] Collection: six rarity tiers, filter chips, detail card art first, Card Sets (Preview, Equip), Badges, Stats.
- [ ] Stats: last runs, lifetime tiles, Quick Run best after you finished one.
- [ ] Settings: every toggle changes something (Reduce Shake, Reduce Flashing, Reduce Motion, Larger Text, Colorblind, Hold to Confirm). Restart Run hold uses your chosen time.
- [ ] How to Play: both pages, no clipped text.
- [ ] Boss Rush (after a first win), Challenge runs (twists), Endless after Night 8 with Crowd Rule chips.

**Minutes 22 to 30: edge cases**
- [ ] Rejoin: your Tips, collection and settings are still there.
- [ ] Leave in the middle of a run, rejoin: you land on the menu, no stuck screen.
- [ ] Spam click Select, Buy, Play Hand: no double charge, no error in Output.
- [ ] Output window: no red errors, no "failed due to" asset warnings, no [Startup] warnings.
- [ ] Phone size: Menu, Round Select, Counter, Settings all reachable, buttons big enough to tap.

## 2. Creator Hub list

**Game page**
- Name: Wildcard Tavern. Short description (first two lines show everywhere): "Build a poker deck, hire quirky Patrons, beat the Boss each Night. A cozy card roguelike with a new Daily every day."
- Long description: how a run works (hands, Patrons, Recipes, Bosses), Daily and Weekly boards, Endless mode, no pay to win.
- Genre: Strategy or Adventure card game. Allowed devices: Computer, Phone, Tablet. Maturity questionnaire: no violence, no gambling with Robux, no real money random rewards (packs use in-game Tips only).
- Thumbnails: six candidates are in `art-wip/store_page/`. Best first pick `thumb_hero.png`, then `thumb_boss.png`, then `thumb_patrons.png`, `thumb_map.png`, `thumb_treasure.png`, `thumb_cozy.png`. Add the title in an editor. Check each for stray text first.
- Icon (512x512): `icon_cards.png` first, then `icon_lantern.png`, `icon_hero.png`.
- Trailer idea (30 seconds, no voice): hand scores climb with a rising sound, a Patron joins the table, the Boss walk-in, a gold "Night cleared", the Tavern Map unrolling, then the title and "New Daily every day". Record it in Studio with the built-in recorder.

**Store items and where to paste ids**
- Starter Pack (Developer Product): create it, paste the number into `Engine/Store.lua`, item `starter_pack`, field `productId` (now 0).
- Card Set Bundle (Developer Product): `Engine/Store.lua`, item `card_set_bundle`, `productId` (now 0).
- VIP (Game Pass): create it, paste the number into `Engine/GamePasses.lua`, entry `vip`, `gamePassId` (now 0).
- Already set: Fast Forward pass, Golden Gala Set pass, One More Round product (`DeveloperProducts` in `Engine/GamePasses.lua`). Check the prices in Creator Hub match what you want.
- After pasting, test a purchase in a published place with a second account. The server only acknowledges a receipt after the profile saved.

**Badges**
- Real Roblox Badges are optional. Each one you create goes into `Engine/BadgeIds.lua` as `BadgeIds.<game badge id> = <number>`. Until an id is there the award is skipped quietly.
- Names to create (one per game badge id): `biome_<region>` and `master_<region>` for meadow, river, peaks, desert, swamp, snow, coast, tavern; `wins_1`, `wins_5`, `wins_25`; `night_3`, `night_5`, `night_8`, `night_10`; `minigame_1`, `minigame_10`; `collection_25`, `collection_50`, `collection_100`; `streak_3`, `streak_7`, `streak_14`; `season_winter_lanterns`.
- Start with `wins_1`, `night_3`, `night_8`, `streak_3`, they are the easiest to earn and drive the "I got a badge" feeling.

**Sound and music slots still empty** (the game stays silent for these and nothing breaks; pick ids from the Roblox audio library, never guess)
- File `Engine/SoundIds.lua`, table `Cues`, empty `id`: `shuffle`, `card_flip`, `discard`, `hover`, `boss_intro`, `boss_defeat`, `map_open`, `road_choose`, `compass_turn`.
- Same file, table `Music`, empty: `region_road`, `region_meadow`, `region_river`, `region_peaks`, `region_desert`, `region_swamp`, `region_snow`, `region_coast`, `region_tavern` (an empty one falls back to the plain gameplay track).
- Filled today: menu, gameplay, shop, boss music and the card, chip, coin, buy, click, win and lose cues.
- Check every id plays in a published place: some library audio is private and fails silently.

**Notifications, age and safety**
- Experience notifications: the game offers them once after the first win. Turn them on in Creator Hub (Communication) and write one friendly default message.
- Age guidelines questionnaire: answer honestly, no chat features are added by the game, no user content.
- Private servers: leave off for launch.
- To test saving inside Studio, turn on "Enable Studio Access to API Services" in Game Settings > Security (your test place). The live place does not need it.

## 3. Two server join test (the save lease)

The profile saver uses a lease so two servers cannot overwrite each other. This only runs in a published place.
1. Publish. Join with account A on server 1 (check Output for no [Startup] warnings).
2. Join the same place with account A from a second device so it lands on another server (use "Join Another Server" from the server list, or have a friend teleport you). Expect: the second session shows the quiet notice "progress can't be saved right now" and plays a fresh profile, saving blocked.
3. Leave server 2. Play a hand on server 1, rejoin elsewhere later: your real profile is back and your Tips are the ones from server 1.
4. Close server 1 from the dashboard, join again: the profile loads without a delay longer than a few seconds.
5. If the notice shows when you did NOT have two servers, wait a minute and rejoin, then report it. Never ship if progress is lost.

## 4. One week after launch: daily routine

Open Creator Hub > Analytics each morning (10 minutes). Look at Home Recommendations first.
- **Day 1 to 2:** Home Recommendations: impressions, click-through rate (CTR), and "play rate". If CTR is under about 5 percent, change the thumbnail first (try `thumb_hero` against `thumb_boss`). If play rate is low, the title or the first line of the description is the problem.
- **Day 3 to 4:** Retention: day 1 and day 7 retention. Day 1 under 20 percent means the first five minutes lose people; read the funnel steps in the custom events (first_hand_played, first_round_won, first_shop_visit, first_run_ended) to see which one drops.
- **Day 5 to 7:** Average session time against the 3 hour goal for the week, and the daily active users trend. Compare weekdays with the weekend.
- Numbers to compare every day: CTR, day 1 retention, average session minutes, Daily board entries, crash and error count (Performance tab).
- What to change first, in this order: thumbnail and title, then the first five minutes (tutorial length, first win hint), then balance (stake 1 win rate), then new content. Change one thing per day so you can tell what worked.
- Read player comments and the favourite count. Reply to bug reports with a fix date.

## 5. Six week update calendar (uses the live event table)

Events live in `Engine/LiveEvents.lua` (UTC dates, both days count). Edit the table, test with a date override, publish. Already there: Lantern Weekend (2026-11-13 to 15, double Rank XP), Harvest Week (2026-11-16 to 22, Daily dressing), The Founders' Feast (2026-11-25 to 2026-12-02, limited title and card back).
- **Week 1:** launch week. Hotfix only. Post the Daily result screenshot in the game's community feed.
- **Week 2:** Harvest Week plus a Collection milestone push. Ship a small balance patch from the pick-rate numbers.
- **Week 3:** The Founders' Feast. Announce the limited title, one new Patron, one new Recipe.
- **Week 4:** Winter set drops (Winter Evening card set, snow backdrop). Double XP weekend.
- **Week 5:** New road (biome) reward and a new challenge twist. Invite week: remind players about the invite reward.
- **Week 6:** Season track (monthly ladder) and the first Legend prestige reward. Review all retention numbers and plan the next six weeks.
- Rule of thumb: one thing players can see on the first screen, every week.

## 6. Last checks before you press Publish

- [ ] Tests pass: `lua tools/run_tests_local.lua`, and `lua tools/test_sim.lua`.
- [ ] No red text in Output during a full run in Studio Play.
- [ ] The word list check: no banned words in game text (run the ship-check skill).
- [ ] Game page, thumbnail, icon, passes and products set (section 2).
- [ ] Two server test done (section 3).
- [ ] Pushed from your own terminal, then Roblox Studio Publish to Roblox.
