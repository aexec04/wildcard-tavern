# Fresh Start Brief: Roblox Tavern Card Game (working title TBD)

Status: draft for you and your friend to react to. Nothing here touches the old Wildcard Tavern repo, which stays as it is. Target look: `claude/reference/concepts/concept_R_*.png`.

## 1. The pitch (one paragraph)
A cheerful, hand-painted Roblox card game set in a cozy tavern full of blocky regulars. You play poker hands to beat each round's target score. Collectible Patron characters sit above the table and boost your hands with effects. Five clear rarity tiers make every new Patron exciting to find. One screen, few buttons, instantly readable.

## 2. Keep it its own game
Poker-hand scoring is a mechanic, and mechanics are fair game. Identity, names, art and layout are what make a game its own.
- Never use these words in the game, the art or the Roblox page: Balatro, Joker, Ante, Blind, Tarot. Our word for the collectible characters is **Patron**.
- No left sidebar, no blue Chips box beside a red Mult box, no "Run Info" or "Options" buttons. Our HUD is the minimal one in section 5.
- Pick at least one twist that only we have (decide together, these are suggestions):
  1. **Seats:** Patrons sit in a row and neighbors boost each other, so arranging them is a puzzle.
  2. **Cheers meter:** every scored hand fills a Cheers meter, and a full meter makes the whole tavern cheer for a bonus.
  3. **Friends at the table:** a friend can sit in and lend one Patron for a round.

## 3. Art direction (from concept R)
- Stylized Roblox 3D, hand-painted textures, limited warm palette, soft stylized lighting.
- Bright, cozy, friendly. Not dark, not gritty, no skulls, no hooded figures.
- Blocky Roblox avatars are the style, and they are crafted: every regular has a different face, hair, skin tone, age and outfit.
- Lived-in details: a sleeping orange cat on a barrel, purple banners with a crown, a chandelier, a fireplace.
- No bloom, no glossy over-rendering, no stock-ad look. If it looks like a mobile ad, redo it.
- Layout: the table is the stage. Background crowd stays soft and low contrast.

## 4. Rarity tiers (the whole system on one table)
| Tier | Frame | Gem | Feel |
|---|---|---|---|
| Common | carved wood and brass, no glow | gray | simple, reliable |
| Uncommon | emerald green, leaf filigree | green | small twist |
| Rare | sapphire blue, soft shimmer | blue | strong effect |
| Epic | amethyst purple, swirling sparkles | purple | build-defining |
| Legendary | shining gold, light rays, tiny crown | gold | run-changing, animated |

Rules: tier is always shown by frame color, gem and a text label (never color alone). Higher tiers get more particles and a bigger reveal animation. Effect pills float above a Patron when it scores: blue for Chips, red for Mult, gold for coins.

## 5. Minimal HUD (nothing else on screen)
- Top center: wooden banner with the round number and a gold progress bar to the target.
- Top left: coin counter and hands-left counter, two small round icons.
- Top right: settings gear.
- Top row: up to five Patron cards.
- Middle of the felt: scoring stage (hand name and big score), visible only while cards are selected or scoring.
- Bottom center: hand of 7 cards. Play Hand (large, green) and Discard (smaller, red).
- Bottom right: deck pile with a count plate.
Everything else (shop, collection, rules) lives in separate screens, not on the table.

## 6. Core loop (small enough to finish)
1. Round starts with a target score. You draw 7 cards.
2. Select up to 5 cards and press Play Hand. Score = Chips x Mult from the hand type, then Patrons add effects.
3. Limited hands and discards per round. Reach the target to win the round.
4. Between rounds: pick or buy a Patron, spend coins.
5. Run ends after a set number of rounds, with a win screen.
First playable scope: 8 hand types, 5 Patrons (one per tier), 3 rounds, placeholder art allowed.

## 7. Week plan for two beginners in Roblox Studio
Use **Team Create** (Home tab, then Team Create) so you both edit the same place. Keep logic in ModuleScripts so it is easy to test.
- Day 1: set up Team Create, folders (ReplicatedStorage/Shared, ServerScriptService, StarterGui), a Cards module (52 cards), and print a shuffled deck.
- Day 2: hand UI. Show 7 cards, click to select up to 5, Play and Discard buttons, using a placeholder card image.
- Day 3: hand evaluation. Detect pair through straight flush, give each a base Chips and Mult. Test with printed hands.
- Day 4: scoring and rounds. Target score, hands and discards left, win and lose. Server decides the score, client only shows it.
- Day 5: Patrons. Data table with tier and effect, 5 working Patrons, effect pills when they score.
- Day 6: art pass. Upload the generated sheets as Images, swap placeholders for painted cards, buttons, banner and Patron frames.
- Day 7: between-round shop, polish, friends playtest, fix the top three problems.
Rules of thumb: finish a playable ugly version first, art last; one change at a time; commit to Team Create versions often.

## 8. Asset list to generate (in this style)
1. Patron card sheet: five finished cards plus five empty frames (one per tier).
2. UI kit: Play Hand, Discard, round banner (empty and filled bar), coin and hand pills, gear, deck pile, effect pills, scoring glow ring, five rarity gems.
3. Card faces: A, K, Q, J, pip cards and the card back.
4. Background scene: the tavern with the crowd soft and low contrast (generated separately so it never competes with the cards).
Generate with `python3 tools/concept_image.py --assets`, then cut out and upload as Image assets.

## 9. Decisions for you and your friend
- The game name.
- Which twist from section 2.
- How many Patrons in the first build beyond the first five.
- Whether the table is a real 3D scene or a 2D painted screen. Recommendation for week one: 2D painted screen, upgrade to 3D later.
