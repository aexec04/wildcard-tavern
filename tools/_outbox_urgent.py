import subprocess
h = subprocess.check_output(["git", "log", "--format=%h %s", "-1"]).decode().strip()
t = """
## URGENT: Patron pick broken after the portrait fix (Nov 22)
- Commit: %s
- Tests: 1465 passed, 0 failed.
- Cause: the plain Patron portraits are full tavern scenes (about 1024 square), so a scaled, top anchored copy overflowed the ring. Fix: new Engine/DraftPortrait gives the cut card's portrait window (PatronCardCrop, scaled into the stored texture), drawn Crop inside a clipping, rounded ring, with the plain portrait fitted whole as a fallback. A test walks all 85 Patrons (none blank, all inside the texture, window above the baked name). Studio prints [PortraitCrop] warn if a picture leaves its ring.
- Counter shop, My Patrons and the table seats never used the plain portrait, so they were not changed. Not checked live (no Studio Play in this run): look at Choose your first Patron at 1920x957.
""" % h
open("claude/OUTBOX.md", "a").write(t)
q = open("claude/QUEUE.md").read()
q = q.replace("- [ ] URGENT: Patron pick is broken live after the portrait fix", "- [x] URGENT: Patron pick is broken live after the portrait fix", 1)
open("claude/QUEUE.md", "w").write(q)
