import subprocess
h = subprocess.check_output(["git", "log", "--format=%h", "-1"]).decode().strip()
t = """
## Hand: lifted picked cards rise into the Score plate (Nov 20)
- Commit: a0876ae Hand: picked cards stay 10 px clear of the Score plate (frame 22 px lower, plate leaves lift room), gold pick edge 3 px, test
- Tests: 1243 passed, 0 failed
- Hand frame stands 22 px lower (HandSizing.PICK_ROOM), idle plate ends 28 + 10 px above the card tops; gap at the tallest picked card is 10 px at 1506x751, 14 at 1280x720 and 1920x957. Gold pick edge is 3 px. Not checked live: look at five picks at 1920x957.

## Score plate: numeral shows 0 while TARGET CLEARED (Nov 20)
- Commit: %s Score plate: numeral is written in the cleared phase (was stuck at 0), gold from the Target on, test
- Tests: 1244 passed, 0 failed
- Cause: the numeral only counted while phase was playing and never wrote a total that arrived in another phase. Engine/ScoreNumeral.action now writes it at once; Studio prints [ScoreNumeral] per change. Not checked live.
- Queue: no [ ] or [h] tasks left, BACKLOG all DONE. Stopping.
""" % h
open("claude/OUTBOX.md", "a").write(t)
