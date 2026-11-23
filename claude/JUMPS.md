# Admin jumps (Studio only)

Set a StringValue named `DebugGoto` under your Player (or the attribute `DebugGoto`) to one of the keys below. Nothing happens outside Studio. The output prints `[DebugGoto] <key> ok` or the reason it was ignored.

Jumping the same key twice: the value only fires when it changes, so set it to an empty string first, then the key again (the empty value is ignored). `DebugGotoRules.assignSteps(current, value)` gives that order.

Any key may end in `:<cardSetId>` (for example `haggle:winter_evening`, `menu:meadow_picnic`) to preview that Card Set over the equipped one.

## Screens

| Key | Lands on |
| --- | --- |
| `menu` | The main menu |
| `news` | The news panel |
| `tome:<collection\|cardsets\|badges\|legend\|flair\|stats>[:subtab]` | That Tome page |
| `collection`, `collection:<tab>` | The Tome Collection page |
| `store`, `store:<tab>`, `season` | The Store and Season panels (they open on their first tab) |
| `daily` | Daily Rewards |
| `daily:done`, `weekly` | The Daily leaderboard |
| `settings` | Settings |
| `share` | The win Run Over screen with the Invite and Share lines |
| `map`, `map:night=N`, `tavernmap:night=N` | The Tavern Map (N is 1 to 8) |
| `loading`, `loading:<0..100>` | The loading screen frozen at 60 percent, or that percent |
| `spectate` | Needs a second player, only warns |

## Table and run screens

| Key | Lands on |
| --- | --- |
| `round1`, `seed` | Round 1 of the fixed seed run |
| `round1:<cardSetId>` or `cardset:<id>` | Round 1 with that Card Set previewed |
| `round1:mod=<blessingId>[,tag=<tagId>]` | Round 1 with that blessing and skip Tag on offer |
| `freshsave` | A brand new profile (guided first run), then the menu |
| `shop` | The Counter with two Patrons and two packs |
| `roundwin`, `gameover` | The round win and game over screens |
| `roundselect`, `road` | Round select, and Choose your road with three sample stops |
| `haggle`, `haggle:good`, `haggle:bad` | The Counter with a Wandering Stranger offer |
| `runover`, `runover:win` | The Run Over screen, loss or win sample |
| `boss1`, `boss1:<bossId>` | The play screen in a Boss Round (first one, or that id) |
| `packroom` | An open Patron pack at 5 of 5 Patrons: the Make room step |
| `rarity`, `rarity:<page>` | The first Patron draft with one Patron per rarity |
| `boon` | The Night boon picker with three sample boons |
| `wildcard`, `legendary` | Plays the True Wildcard or Legendary banner and effect once |
| `drawer:open`, `drawer:closed` | The Patron drawer |
| `patrons:<0..8>` | Seats that many Patrons on the live run |
| `playhand`, `playhand:keep` | Plays the first 5 cards (keep: raises the target so the round stays open) |
| `beatslow:on\|freeze\|off` | Slows the Patron scoring beats, or freezes beat 2 |
| `equip:<setId>` | Really equips that Card Set (Studio server remote) |

## Tools

| Key | What it does |
| --- | --- |
| `sfx:<cue>`, `sfx:ladder`, `sfx:roundwin` | Plays a sound cue, an 8 step pitch ladder, or the whole round win set |
| `scale:<w>x<h>`, `scale:off` | Shrinks the GameUI to that viewport, or restores it |
| `sweep`, `sweep:stop` | Visits every capture screen in turn |
| `perf` | Prints the GameUI instance counts |
| `audit:v2`, `selfcheck`, `tablecheck`, `decorcheck`, `screencheck` | Print layout and text checks for the open screen |

## Server remotes

`DebugGrantPatrons`, `DebugSetTag`, `DebugSetMod`, `DebugSetTarget`, `DebugEquipSet` and `DebugFreshSave` all return at once unless `RunService:IsStudio()`. A test checks that this is the first line of every Debug handler.

There is no `bossN:<id>` key. Use `boss1:<bossId>` for any Boss Round, whatever its Night.

## Admin jump keys (Studio only)

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

Admin keys (Studio only, they parse now; the panel lists them under Daily and meta): freshsave, daily, daily:done, weekly, seed, settings, share, store:<tab>, collection:<tab>, cardset:<id>, tavernmap:night=<n>.
- tome:store: use store.
