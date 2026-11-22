t = """
## Four new Patrons: code and abilities (Nov 22)
- Commit 99cd248 "Add four Patrons (Lone Wolf, Even Keel, Odd Duck, Good Company) with stand-in portraits, lines, tags and tests". An earlier commit fixed a broken MusicPicker test block that stopped the whole suite loading, and a stale Store Close overlap check (the text Close plate is retired by the round X).
- Tests: 1465 passed, 0 failed (plain lua; lua5.3 is not installed).
- Lone Wolf (+15 Mult on High Card), Even Keel (+3 Mult per scoring 2, 4, 6, 8, 10), Odd Duck (+12 Chips per scoring 3, 5, 7, 9), Good Company (+3 Mult per other Patron). Roster is 85. PATRON-ROSTER.md regenerated.
- Art ids: none.

## Four new Patron portraits (Nov 22)
- Commit 6b348c0 "Four new Patron portraits and cut cards, wired over the stand-ins, with tests". Tests: 1465 passed, 0 failed.
- Cost: estimate about $0.21 for 8 images; actual about $0.45 with retries (cut cards for Odd Duck and Good Company redone, plain portraits redone to drop a sword and mugs). The stand-in field was removed once real art landed.
- The four plain portraits show as stale-prompt in status because the prompt was reworded after generating. The images are approved, do not regenerate.
- Regenerating PatronArt.lua from the state file reverted cobweb_shelf, fair_share and the_regular to older ids; the committed ids were restored by hand. Watch for this on the next art run.
- Not checked in Studio (no Play in this run).
patrons lone_wolf 117785645820969
patrons even_keel 70732053719155
patrons odd_duck 87506159745951
patrons good_company 74868660908783
concept_t_patrons ctp_lone_wolf 127736343560968
concept_t_patrons ctp_even_keel 81325155259964
concept_t_patrons ctp_odd_duck 110264517756271
concept_t_patrons ctp_good_company 107635782240806
"""
open("claude/OUTBOX.md", "a").write(t)
q = open("claude/QUEUE.md").read()
q = q.replace("- [ ] Four new Patron portraits", "- [x] Four new Patron portraits", 1)
open("claude/QUEUE.md", "w").write(q)
