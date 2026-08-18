# Wildcard Tavern (working title)

A small, original Roblox poker-hand deckbuilder roguelike, built by two
complete beginners in a week. See `docs/` for the full plan:

- **`docs/DESIGN.md`** -- the theme, mechanics, and how/why this is
  original rather than a copy of any specific existing game.
- **`docs/ROADMAP.md`** -- the day-by-day plan to get from "nothing" to
  "published on Roblox" in a week.
- **`docs/SETUP_GUIDE.md`** -- zero-assumed-knowledge steps to install
  Roblox Studio, Git, VS Code, and Rojo, and get this project synced
  into Studio.

## What's already built

The core game logic lives in `src/Shared/Engine/` as plain Lua modules
with **no Roblox-specific code** in them -- that's what makes them
genuinely unit-testable, not just "testable in theory":

- `Card.lua` / `Deck.lua` -- card + standard 52-card deck.
- `HandEvaluator.lua` -- detects poker hands (Pair, Flush, Full House, etc).
- `Scoring.lua` -- turns a hand into a chips x mult score.
- `Patrons.lua` -- the modifier-card system (rename/add to these freely).
- `RunState.lua` -- the round/night progression state machine.

26 unit tests for all of the above live in `src/Shared/Tests/` and run
two ways:

```
lua5.3 tools/run_tests_local.lua      # no Roblox needed at all
```

...or just press **Play** in Roblox Studio -- `src/Server/init.server.lua`
runs the same test suite automatically and prints PASS/FAIL to the
Output window every time.

`src/Server/` and `src/Client/` wire that tested engine up to an actual
playable (if visually plain) game: draw a hand, click cards to select
them, Play or Discard, shop between rounds. It's meant to be reskinned,
not treated as final art.

## Quick start

See `docs/SETUP_GUIDE.md` for the full walkthrough. Short version once
Rojo + the Studio plugin are installed:

```
rojo serve
```

Then connect the Rojo plugin in Studio and press Play.
