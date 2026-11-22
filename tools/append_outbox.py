"""Appends art-wip/outbox_entry_tmp.md to claude/OUTBOX.md, then deletes the entry file. Usage: python3 -I tools/append_outbox.py"""
import os

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
entry = os.path.join(root, "art-wip", "outbox_entry_tmp.md")
with open(entry) as f:
    text = f.read()
with open(os.path.join(root, "claude", "OUTBOX.md"), "a") as f:
    f.write(text)
os.remove(entry)
print("appended", len(text), "characters")
