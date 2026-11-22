## Toasts and popups: stacking, timing and wording audit (2026-11-22)

- Commit: fc79ddd "Toasts: at most 2 visible, 2.5 s minimum on screen, rank toast hold 2.5 s, tests"
- Tests: 1399 passed, 0 failed. `lua5.3` is not installed here, so I ran `lua tools/run_tests_local.lua` (Lua 5.5.1).
- Found: the stack allowed 3 toasts; the rank toast held 1.8 s; shrinking the slot (Round Select) could cut a toast before 2.5 s.
- Fixed in Engine/CornerToastRules.lua: MAX_STACK 2, MIN_SHOW 2.5 s (clamps short holds and stops early demotion). ProgressionFeel.HOLD is now 2.5. Tests updated and a minimum-hold test added.
- Already fine: calm mode has no slide tween (rise is 0), slots sit clear of the Score plate, hand and Play button (existing placement tests), toast text strips emoji.
- Not checked: live Studio look of the two-toast stack, and the wording of every trigger site. Claude wrote this to a new file because OUTBOX.md is too large to append to with the shell here (the write needed approval).
- No [ ] tasks remain. The [h] tasks (Tavern Map, Card Sets layout, Card Set themes, Flair audit, First five minutes) need Studio play or design input, so I left them held. I did not start BACKLOG.md.
