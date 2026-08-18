# Wildcard Tavern -- Design Doc (v0.1)

*Working title -- rename freely, nothing here is precious.*

## 1. The pitch

A single-player, roguelike deckbuilder where you play poker hands from a
standard 52-card deck to hit a score target each round, earning currency
between rounds to recruit helpers and grow your deck's power. Survive as
many rounds as you can.

If that sounds like it's in the same genre as a certain popular indie
card game -- it is, on purpose. That genre (poker-hand-scoring roguelike
deckbuilder) has multiple independent implementations; the goal here is
to build *our own* game in that genre, not to reproduce any specific
game's art, characters, names, or code. Section 4 covers how we keep
clear water between the two.

## 2. Core loop

1. **Draw** a hand of 8 cards from a shuffled 52-card deck.
2. **Select** 1-5 cards and **Play** them. The game detects the best
   poker hand among the selected cards (Pair, Flush, Full House, etc.)
   and scores it: `(base chips + card chip values + bonuses) x (base mult + bonuses)`.
3. Repeat until you either **hit the round's target score** (you win the
   round) or **run out of hands** without hitting it (your run ends).
4. On a round win, visit **The Bar** (the shop): spend **Tips** (currency)
   to recruit **Patrons** -- passive helpers that boost future hands.
5. Advance to the next round. Target scores climb each round, across
   **Nights** (a Night = 3 rounds). Difficulty ramps steadily.

You also get a limited number of **Discards** per round (swap unwanted
cards for new ones without spending a hand).

## 3. Terminology (ours vs. the genre convention)

We picked fantasy-tavern flavor instead of the more common
carnival/tarot flavor, and renamed every system-level term. This isn't
just cosmetic -- it's what makes this *our* game rather than a reskin.

| Generic deckbuilder-roguelike concept | Our term |
|---|---|
| Passive modifier card / companion | **Patron** |
| Shop between rounds | **The Bar** |
| Currency | **Tips** |
| Boss/round-ending checkpoint | **Round**, escalating by **Night** |
| Run-progression tier (3 rounds) | **Night** |
| Consumable modifier cards (stretch goal) | **Recipes** |

Patron names and effects (see `src/Shared/Engine/Patrons.lua`) are 100%
original: The Regular, Lucky Dice, Suit Yourself, Last Call, The Bard.
Add your own -- that's most of the game's personality and it's the
cheapest thing to iterate on.

## 4. Staying clear of a copyright strike

Quick, non-lawyer summary (see the caveat at the end): copyright
protects specific *expression* -- art, character designs, written text,
music, code -- not general game *mechanics* or *rules*. "Score poker
hands against a target, spend currency on modifier cards between
rounds, survive escalating rounds" is a mechanical structure, and
mechanics generally aren't what copyright strikes are made of. Standard
playing cards and poker hand rankings are public domain.

What *would* create real risk is copying another game's specific
expression: its exact character names/art/designs, its specific written
flavor text, its exact visual style, its logo, or its code. So the
concrete rules for this project:

- **Never** use the name "Balatro" anywhere in the game, its assets, or
  its Roblox page.
- **Never** copy specific character designs, portraits, or art style
  1:1. Commission/build your own art direction (see Section 6).
- **Never** copy specific joke text, card flavor text, or UI copy
  verbatim.
- Reuse only genre-generic terms (poker hand names, "deck", "hand",
  "shop") -- avoid any invented proper nouns from other specific games
  (we're already doing this via the terminology table above).
- Our numeric balance (chip/mult values, price points, target-score
  curve) is our own pass, not copied from anywhere.

*Caveat: this is general guidance, not legal advice -- I'm not a
lawyer. If you want real certainty (e.g. before a big public launch),
it's worth a short consult with someone who actually practices IP law.*

## 5. MVP scope (this week) vs. later

**In scope for the week-1 published version:**
- Single-player only (no multiplayer/PvP -- that's a big scope add).
- Core loop above: draw, play, discard, score, shop, advance.
- 5 original Patrons.
- Procedurally-built functional UI (not hand-designed in Studio yet).
- A simple escalating target-score curve across Nights/Rounds.

**Explicitly out of scope for week 1 (write these down so nobody feels
like the game is "incomplete" -- they're deliberate cuts):**
- Consumable cards ("Recipes"), Patron rarity/leveling, run seeds,
  daily challenges, cosmetics, monetization, multiplayer/leaderboards,
  save/persistence across sessions (DataStores), sound/music, custom
  art (placeholder text-card UI ships first, art comes after the loop
  is fun).

## 6. Suggested next steps after week 1

Once the core loop is confirmed fun via playtesting: replace the
placeholder card buttons with real card art, add sound, add
DataStore-based run stats/leaderboard, add 5-10 more Patrons, add a
"Recipes" consumable system, consider a simple prestige/meta-progression
layer.
