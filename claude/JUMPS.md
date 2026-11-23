# Admin jump keys (Studio only)

Every key below has a button in the Go panel (Client/AdminJumpPanel, keys in Engine/AdminJumpKeys). A test checks it.
Per-id keys are built from the registries: one `boss3:<id>` button per Boss Round, one `tag:<id>` per Tag, three `recipes:<id>` buttons, one `menu:<id>` per Card Set.

- `round1` start a run
- `night:1` `night:2` `night:3` `night:4` `night:5` `night:6` `night:7` `night:8` `night:9` `night:10` `night:11` `night:12`
- `boon` `reward` `victory` `sellpatron`
- `menu` `store` `map` `boss1`
- `shop:20` `endrun` `endrun:win`
- `patrons:1` `patrons:5`

Menu screens: `news` `collection` `tome:cardsets` `loading` `map:night=1` `map:night=4` `map:night=8` `rarity`

Daily and meta: `season` `tome:badges` `tome:legend` `tome:flair` `tome:stats` `perf` `scale:800x450` `scale:1024x768` `scale:off` `sfx:ladder`

Run screens: `haggle` `haggle:good` `haggle:bad` `road` `runover` `runover:win` `packroom` `wildcard` `legendary` `playhand` `playhand:keep` `beatslow:on` `beatslow:freeze` `beatslow:off` `sfx:roundwin` `shop` `roundwin` `gameover`

Not available (the parser in Engine/DebugGotoRules rejects them, checked by running it, so a button would only print an error):
- daily, daily:done, weekly, seed, freshsave: the DebugGoto header does not list them and no parser branch exists. They would need new Studio-only server jumps that change profile state.
- settings, share: no parser branch. Use the tome pages or the real Menu buttons.
- tavernmap:night=N: the real key is map:night=N (listed above).
- cardset:ID: the real key is menu:ID (any jump may end in a Card Set id), one button per Card Set under "Card Sets".
- tome:store: use store.
