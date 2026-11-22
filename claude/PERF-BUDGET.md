# Performance budget audit (2026-11-22)

Method: a source count of tween call sites (`TweenService:Create` and the local `tween(` helper) in the Client files that run when a hand is played and when the Counter opens. The fake GUI cannot run the live table or Counter, so this is a ceiling on code, not a measured runtime count. Pinned by the test "Performance budget" in EngineTests.

| Path | Call sites | Cap |
| --- | --- | --- |
| Hand play (17 files) | 77 | 85 |
| Shop open (6 files) | 43 | 47 |

Top five files by call sites: ShopScene 16, PatronRow 15, ShopCards 13, Gameplay2MomentsFX 10, GameplayScene 9. Per file cap 18.

Result: nothing trimmed. Most sites are one shot (a card flip, a price shake) and each effect file already checks Calm mode and Reduce motion. Repeating effects run on FxLoop (lint test exists). GuiObject limits per screen are covered by the Screen budget tests.

Not measured: live instance counts on a hand play or shop open. That needs Studio Play with the AuditV2 counter.
