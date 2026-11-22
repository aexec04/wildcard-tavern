# Launch checklist (owner only)

Plain steps for things only you can do. Do them in order. Tick each box as you go.

## Part 1: Before you press Publish

1. [ ] **Make your Game Passes and Products in Creator Hub.**
   - Open Creator Hub, pick your experience, go to Monetization.
   - Already set: Fast Forward and Golden Gala Set.
   - Still at 0 (placeholder): Music Pack, VIP.
   - Developer products still at 0 in `src/Shared/Engine/Store.lua`: Starter Pack, Card Set Bundle, Flair Bundle, Harvest Moon Premium, Winter Welcome Premium and the single flair items. Anything left at 0 shows "Coming soon" in the Store. That is safe, so you can launch with them off.
2. [ ] **Paste each id into the code.**
   - Music Pack: set `GamePasses.MUSIC_PACK` in `src/Shared/Engine/GamePasses.lua` to your new number.
   - VIP: set its `gamePassId` in the same file.
   - Products: set `productId` on each line in `src/Shared/Engine/Store.lua`.
   - Run `lua tools/run_tests_local.lua`. It must say 0 failed.
3. [ ] **Game icon.** Creator Hub > your experience > Icon. Use one of the 2 icon prompts in `claude/LAUNCH-ASSETS.md`, 512x512.
4. [ ] **Thumbnails.** Creator Hub > Thumbnails. Upload 3 to 5 at 1920x1080 from the prompts in `claude/LAUNCH-ASSETS.md`. Make sure none show text you did not mean, and none show drinks.
5. [ ] **Title and description.** Pick a title and paste the description plus keyword line from `claude/LAUNCH-ASSETS.md`.
6. [ ] **Genre and devices.** Settings > Basic Info: pick the genre that fits best (Strategy or Card and Board) and tick Computer, Phone, Tablet. Add Console only if you tested it.
7. [ ] **Age rating questionnaire.** Creator Hub > Settings > Age Guidelines. Answer from section 5 of `claude/LAUNCH-ASSETS.md` (no chat, no real money gambling, virtual currency only). Be honest, because a wrong answer can get the game taken down.
8. [ ] **Test with a friend on a private server.**
   - Publish to Roblox first (see Part 2, step 1) but keep the experience Private.
   - In Creator Hub > Access, add your friend, or make a private server link.
   - Both of you: join, finish the first Night, open the Store, quit to the Tavern, rejoin. Check your run came back.
   - Write down anything confusing they said out loud.
9. [ ] **Test on a real phone.** Join on your own phone. Check: you can read all text, buttons are easy to press, the Menu, Tome, Store and Settings all open and close, and nothing is cut off at the edge.
10. [ ] **Last check.** Run the `/ship-check` skill in Claude Code and fix anything it lists.

## Part 2: Publish

1. [ ] In Studio: File > Publish to Roblox (Ctrl+S only saves, this uploads). Pick your experience.
2. [ ] Join the live version once from the Roblox website, not Studio, and finish a Night. Studio and the real game can behave differently.
3. [ ] Creator Hub > your experience > Settings > Basic Info (or the Access tab): set **Public**. Press Save.
4. [ ] Open the game page as a stranger would (log out or use a private window). Check the icon, thumbnails, title and description look right.
5. [ ] Tell a few people the link. Do not wait for the front page to find you.

## Part 3: The first week

Open Creator Hub > Analytics once a day, about 10 minutes.

- **Day 1 to 2:** Look for crashes or errors first. Then look at how many people joined and how long they stayed.
- **Retention:** Day 1 retention is the share of players who came back the next day. Day 7 is the share who came back a week later. If Day 1 is under 20 percent, the first five minutes lose people. Fix that before anything else.
- **Session length:** Aim for a first session of 10 minutes or more. Under 5 minutes means players leave early.
- **First Night clear rate:** Open the funnel steps `first_hand_played`, `first_round_won`, `first_shop_visit`, `first_run_ended`. The step where the number drops most is the one to fix. If many players play a hand but never win a round, the first Night is too hard or not clear.
- **Run events:** `run_start` and `run_end` show how many runs people start and how far they get (the value on `run_end` is the Night reached).
- **Store:** `store_opened`, `store_prompt`, `store_bought`. Many opens but no prompts means the cards are not clear. Many prompts but no buys means price or trust.
- **Read comments and the Roblox feedback.** Reply kindly. Do not argue.
- More detail on every event is in `claude/LAUNCH.md` section 6.

## Part 4: Shipping an update safely

1. [ ] Make the change on a branch. Run `lua tools/run_tests_local.lua` and check it says 0 failed.
2. [ ] Test in Studio Play. For anything that saves data, also test a fresh account and an old account.
3. [ ] Publish a copy first if you can: make a second, private "test" experience and publish there before the real one.
4. [ ] Publish to the real game at a quiet time (not when most players are online).
5. [ ] Join the live game yourself and check the changed part works.
6. [ ] Watch Analytics and errors for the next hour. If something breaks, open Creator Hub > Experience > Places > Version History and revert to the last good version.
7. [ ] Once real players have saves, never rename a saved data field or an item id. Add new ones and keep the old ones readable.
