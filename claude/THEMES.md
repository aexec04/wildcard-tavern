# Theme scenes

One equipped Card Set dresses every screen. Source of truth: `src/Shared/Engine/ThemeScenes.lua` (`ThemeScenes.of(setId)`, per key fallback to classic_tavern).
Client: `Client/ThemeWash.lua` draws the interim wash through `Client/BackdropStyles` and follows equip, Preview start and Preview stop live.
Layouts, rects and hit targets never change per set, only art keys and tints.

Slots: menuBackdrop, tableBackground, tableFront (rail), bossTableBackground, mapBackdrop, shopBackdrop (also the Victory backdrop).

Painted = a set specific picture. Wash = tint overlay at 0.78 transparency, a frost vignette for cold sets, and the set's ambient particles (none in Calm mode).

| Set id | Ambient | Table, rail | Boss table | Menu | Map | Shop, Victory |
|---|---|---|---|---|---|---|
| classic_tavern | dust | painted (classic) | painted (classic) | painted (classic) | painted (classic) | painted (classic) |
| winter_evening | snow | painted | painted | painted (ice tavern) | painted id registered, map screen not wired yet | wash (frost) |
| festival_night | lantern | painted | painted | wash | wash | wash |
| closing_time | ember | painted | painted | wash | wash | wash |
| golden_gala | mote | painted | painted | wash | wash | wash |
| meadow_picnic | butterfly | painted | painted | wash | wash | wash |
| riverside_evening | mist | painted | painted | wash | wash | wash |
| summit_camp | cloud | painted | painted | wash (frost) | wash (frost) | wash (frost) |
| dune_market | sand | painted | painted | wash | wash | wash |
| marsh_lanterns | firefly | painted | painted | wash | wash | wash |
| snowy_hearth | snow | painted | painted | wash (frost) | wash (frost) | wash (frost) |
| harbor_lights | shimmer | painted | painted | wash | wash | wash |
| tavern_feast | dust | painted | painted | wash | wash | wash |
| harvest_table | leaf | painted | painted | wash | wash | wash |
| winter_table | snow | painted | painted | wash (frost) | wash (frost) | wash (frost) |

Notes
- The boss table slot resolves to the set's room in ThemeScenes. The boss scene itself is drawn in Gameplay2 (another lane), which still
  uses `table_boss_ref` until that lane reads `ThemeScenes.of(set).art.bossTableBackground`.
- winter_evening pilot art (table_scene theme_ice_menu, theme_ice_boss, theme_ice_map): the menu draws it through ThemeWash; boss and map ids are registered in ThemeScenes and wait for the Gameplay2 and Tavern Map lanes. Shop is still a wash.
