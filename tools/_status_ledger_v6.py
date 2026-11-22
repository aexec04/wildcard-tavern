p = "claude/STATUS.md"
L = open(p).read().split("\n")
for i, l in enumerate(L):
    if l.startswith("- **Ledger v5:**"):
        L[i] = l.replace(
            "Page turns flip a sheet cut from the same page art in 0.22 s in and 0.22 s out with the `page_turn` cue; calm mode crossfades in 0.12 s.",
            "Page turns move ONE sheet cut from the page art, hinged at the spine (width follows cos, 6 px lift, spine shade, cast shadow; the sheet is never rotated because Roblox ignores clipping on rotated frames, which had made the whole book flip). Turning is drag based: grab the outer edge or bottom corner of a page, let go past 0.4 or with a flick to complete (0.25 s), otherwise it springs back; a click or tap on the corner, the Left and Right keys and the section tabs (one quick sheet to the chosen section) also turn; at the first and last page the sheet only lifts a little, silently. `page_turn` plays as the sheet leaves the page, a soft tick on settle, one sound per 0.15 s; calm mode crossfades in 0.12 s with no sheet.",
        )
    if l.startswith("- **Studio check, ledger book:**"):
        L[i] = l + "\n- **Studio check, Ledger v6:** drag the page corner, only one sheet moves (book, table and the other page stay still), sound at lift, tabs jump with one quick sheet, arrow keys turn, the ends only lift, pages show their text on every section, no grey bar on the right page."
open(p, "w").write("\n".join(L))
print("ok")
