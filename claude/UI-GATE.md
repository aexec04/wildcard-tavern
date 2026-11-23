# UI gate (why UI bugs kept coming back, and the rule that stops it)

Root cause: our tests check layout MATH (rect numbers from Engine modules). The bugs were in the REAL GuiObjects
(a plate left visible, a ScrollingFrame clipping a price chip, text wider than its plate, a painted plate drawn over a prop).
The math tests passed while the screen was wrong.

Rule: a UI change is NOT done until tools/live_ui_audit.luau prints "0 findings" (or only known full-bleed OFFSCREEN
backgrounds) on the screen it touched, at 1920x957 and 1506x751, in a REAL run (not only DebugGoto), and the screen was
looked at in a screenshot. Tests are a second check, not the proof.

How: Studio Play, execute_luau on the Client with the contents of tools/live_ui_audit.luau. It reports OVERFLOW, CLIPPED,
OFFSCREEN, OVERLAP on the real GuiObjects. Click buttons in real runs with user_mouse_input instance_path (coordinate clicks
often miss).

Real-run path: Deal Me In, Patron Choose, blessing Choose, RoundPanel1..3 SelectButton, DebugSetTarget:FireServer(1) to
lower the target, pick a card, Play Hand, Shop.NextRound.
