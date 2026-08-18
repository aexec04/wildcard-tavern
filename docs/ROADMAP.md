# 7-Day Roadmap: Wildcard Tavern

**Goal:** a small, original, published Roblox game by end of week.

**Reality check first:** publishing something *polished* in a week with
zero prior coding experience is a stretch goal even for experienced
teams. What makes this realistic is that the hardest part -- the game
logic (scoring, hands, rounds, shop) -- is already written and
unit-tested for you (see `src/Shared/Engine/`, 26 passing tests). Your
week is mostly: get it running, understand it, playtest it, reskin it,
publish it. That's a very different (and much more achievable) task
than writing a card game engine from scratch as beginners.

Assumes both of you can put in roughly 1.5-3 hours on most days. Adjust
pacing to your actual schedules -- what matters is the order, not the
exact day numbers. **Work together (pair up) on days 1-3** since you're
both new to this; split up more on days 4-7 once you're both oriented.

---

### Day 1 -- Get it running
- Both: follow `docs/SETUP_GUIDE.md` end to end (Roblox Studio, VS Code,
  Rojo, GitHub repo, first sync).
- Goal for the day: an empty baseplate in Studio that's synced to the
  shared GitHub repo via Rojo -- both of you can pull each other's
  changes.
- Stretch: get the actual Wildcard Tavern project synced in and press
  Play. You should see 26 lines of `[PASS]` in the Output window and a
  playable (ugly) card game.

### Day 2 -- Understand what you have
- Both: read `docs/DESIGN.md` together. Agree on any theme tweaks now,
  before you're emotionally attached to code.
- Read through `src/Shared/Engine/HandEvaluator.lua` and `Scoring.lua`
  together out loud -- don't worry about understanding every line, just
  get the shape: cards in, hand name + score out.
- Play a few rounds in Studio. Note anything confusing or broken in a
  shared doc/note.

### Day 3 -- Make it yours: names & numbers
- Rename things in `src/Shared/Engine/Patrons.lua` -- swap in your own
  Patron names/flavor, or add 2-3 new ones (copy the pattern of an
  existing entry).
- Tweak `Scoring.HandBase` numbers or `RunState.targetScoreFor` if
  rounds feel too easy/hard once you've played a few runs.
- Run `lua5.3 tools/run_tests_local.lua` after engine changes (or just
  press Play in Studio) to make sure you didn't break anything -- this
  is the payoff of having tests.

### Day 4 -- First pass at visuals
- Split up: one person adjusts colors/fonts/layout in
  `src/Client/init.client.lua` (it's all in code -- change a
  `Color3.fromRGB(...)` value, save, watch Rojo sync it into Studio
  live). The other person starts on a simple background/table image or
  Roblox decal for the tavern setting.
- Keep changes small and commit/push often so you don't lose work or
  create merge conflicts.

### Day 5 -- Playtest & bug bash
- Both: play 5-10 full runs each, on separate computers if possible
  (multiplayer testing catches issues single-player testing misses,
  even though this is a single-player game -- you want two Roblox
  clients hitting the same server).
- Write down every confusing moment, bug, or "that felt bad" as a
  checklist item. Fix the top 3-5 together.

### Day 6 -- Polish & Roblox page
- Fix remaining bugs from Day 5's list.
- Add a game icon/thumbnail, name, and description in the Roblox
  Creator Dashboard.
- Add basic instructions somewhere in-game (a TextLabel explaining
  "click cards, then Play Hand" goes a long way for a first-time
  player).

### Day 7 -- Publish
- Publish the place, set it to Public.
- Playtest the *actual published* version (not just Studio) -- Studio
  and live sometimes behave differently.
- Share the link with a couple of friends outside the project for fresh
  eyes before calling it done.

---

## If you fall behind

Cut scope, don't cut quality. In order of what to cut first if you're
short on time: skip the background art (placeholder colors are fine),
skip adding new Patrons (the 5 provided are enough for a v1), skip
custom card art (text-based cards are a legitimate, testable style
choice, not just a placeholder -- plenty of shipped games look like
this). Do **not** cut playtesting (Day 5) -- an untested game is the
one thing you can't fix after publishing on day 7.
