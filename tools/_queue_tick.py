import os, sys
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
q = os.path.join(root, "claude/QUEUE.md")
t = open(q, encoding="utf-8").read()
for title in sys.argv[1:]:
    t = t.replace("- [ ] " + title, "- [x] " + title, 1)
open(q, "w", encoding="utf-8").write(t)
