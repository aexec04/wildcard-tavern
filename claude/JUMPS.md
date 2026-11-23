# Admin jump keys (Studio only)

Every key below has a button in the Go panel (Client/AdminJumpPanel, keys in Engine/AdminJumpKeys). A test checks it.
Per-id keys are built from the registries: one `boss3:<id>` button per Boss Round, one `tag:<id>` per Tag, three `recipes:<id>` buttons.

- `round1` start a run
- `night:1` `night:2` `night:3` `night:4` `night:5` `night:6` `night:7` `night:8` `night:9` `night:10` `night:11` `night:12`
- `boon` `reward` `victory` `sellpatron`
- `menu` `store` `map` `boss1`
- `shop:20` `endrun` `endrun:win`
- `patrons:1` `patrons:5`

Not available yet (no DebugGoto or DebugJump key exists, so no button): daily, daily:done, weekly, seed, freshsave.
Add the server jump first, then one line here and in AdminJumpKeys.
