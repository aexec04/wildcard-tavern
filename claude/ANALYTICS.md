# Launch analytics events

Code: `src/Shared/Engine/AnalyticsEvents.lua` (pure names, payload rules and the logger), hooked in `src/Server/init.server.lua` through `LaunchLog`. Server values only, never client input. No names or free text are ever sent. Studio sends nothing unless the Workspace attribute `AnalyticsDebug` is true; Studio still prints `[Analytics] <name>` once per event name. Older events (`FirstFiveMinutes` funnel, run_start, run_end, store and tuning events) are in `Engine/Analytics.lua` and `LAUNCH.md` section 6.

## Funnel `LaunchFunnel` (once per player session, fresh funnel session id per visit)
| # | Step | Fires when | Question it answers |
|---|---|---|---|
| 1 | menu_opened | player reaches the menu | How many joins become sessions |
| 2 | run_started | first real run of the session starts (tutorial excluded) | Do players press play at all |
| 3 | first_hand_played | first hand scored | Do they understand the table |
| 4 | first_round_cleared | first round won | How fast the first win comes |
| 5 | first_night_cleared | first Boss Round beaten | Where players quit before Night 1 ends |
| 6 | first_patron_bought | first Patron bought at the Counter | Is the shop understood |
| 7 | second_run_started | second run in the same session | Do they come straight back |

## Economy (Tips, via LogEconomyEvent, max 30 per player per minute)
- Sources: `round_clear` (Tips gained when a round is won), `events` (Tips from a between Nights event), `selling` (Patron or Recipe sold).
- Sinks: `shop_patron`, `shop_pack`, `reroll`.
- Questions: is Tips balance growing too fast (earn far above spend), which sink is used least, is selling a main income.

## Custom events
- `run_ended` (value = round score, fields night, cause: boss, hands or won): where runs end and how hard the score is.
- `boss_lost` (field boss = boss id): which Boss Round kills the most runs.

Reading: Creator Hub > Analytics > Funnels (LaunchFunnel), Economy (Tips), Custom events.
