# Studio check commands

Run in Play, from the command bar or the DebugGoto box.

- `audit:v2` prints the Gameplay v2 rects and layout warnings for five window sizes, every KitLabel with its TextTransparency, and the live GuiObject count.
- `selfcheck` walks every shown TextButton, TextLabel and KitLabel of the open screen and warns `[SelfCheck]` on: text transparency above 0.5, contrast under 3:1 against its plate, label ZIndex not above its plate children, label rect outside its parent, two labels overlapping by more than 20 percent. It ends with `[SelfCheck] N text objects checked, M warning(s)`; M must be 0.
- `scale:<w>x<h>` shrinks GameUI to that viewport (`scale:off` restores it).

Pass order for one screen: open it (table, Counter, Run Over, pause, My Patrons), run `selfcheck`, then repeat after `scale:1280x720`, `scale:1024x768` and `scale:844x390`.
The rules are in `Engine/SelfCheck.lua` (tested); `Client/SelfCheck.lua` only describes the live objects.
