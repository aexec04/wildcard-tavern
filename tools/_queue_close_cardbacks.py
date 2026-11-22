import os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
p = os.path.join(root, "claude/STATUS.md")
L = open(p, encoding="utf-8").read().split("\n")
for i, l in enumerate(L):
    if l.startswith("- A test steps through all 14 sets"):
        L.insert(i + 1, "- Every non classic Card Set has its own painted card back (`back_<setId>`, set only, in CardBackArt) used by the deck pile and the Card Sets view; classic keeps its back. Test checks unique ids and recorded art.")
        break
open(p, "w", encoding="utf-8").write("\n".join(L))
q = os.path.join(root, "claude/QUEUE.md")
t = open(q, encoding="utf-8").read().replace("- [ ] Card back art per Card Set", "- [x] Card back art per Card Set", 1)
open(q, "w", encoding="utf-8").write(t)
