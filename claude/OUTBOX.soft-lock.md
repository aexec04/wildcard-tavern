## Event and shop flow soft lock check (Nov 22)
(OUTBOX.md is 1.4 MB, too large to append to, so this entry is in its own file.)

- Commit: 1187bc5 Soft lock check: scripted runs through Nights 1 to 3 keep a legal next action, Tips, hand and card count
- Tests: 0 failed (plain run and Studio-style no-io pass).
- New test in EngineTests walks 8 seeded runs through Nights 1 to 3 with the real RunState, Shop and RunChoice: discard, play, Counter buy, reroll, sell, advance, skip Tag (even seeds), event card between Nights. After every action: Tips whole and not negative, hands and discards not negative, a round in progress has a non-empty hand, a hand left and a legal play, and the card total never changes. Every event card can be answered and leaving the Counter is always legal.
- No engine bug found, so no engine change. tools/run_fuzz.lua already covers the wider random case.
- Needs you: the five [h] tasks (map road, Card Sets screen layout, Card Set themes on cards, Flair audit, First five minutes) need Studio screenshots or a design call.
