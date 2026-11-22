## Launch safety: data and remote hardening audit (2026-11-22)
(New OUTBOX file: OUTBOX.md is over 10,000 lines and the shell blocked appending to it.)

- Commit: 7124955 Launch safety: block saves after a load throw, retry the final save, clear leaving-player leaderboard state, audit test for rate limits, Studio-only debug remotes and receipt order
- Tests: 1380 passed, 0 failed (`lua tools/run_tests_local.lua`; lua5.3 is not installed, plain lua is).
- Already fine:
  - All 59 RemoteEvent handlers call RateLimit.allow first. The leaderboard functions and MakeChallengeSeed have their own cooldowns, and GetMenuTicker uses RateLimit.
  - The four Debug* remotes return outside Studio.
  - loadProfile retries with backoff and sets saveBlocked on failure. Every ProfileStore call is in pcall.
  - Autosave runs every 120 s and BindToClose flushes.
  - Store receipts save before acknowledging and are idempotent by PurchaseId.
  - Game passes are checked with UserOwnsGamePassAsync. The Studio bypass is IsStudio only.
- Fixed:
  1. If loadProfile itself threw, onPlayerAdded gave a blank profile that could later overwrite the real save. It is now saveBlocked and shows the "can't be saved" notice.
  2. The final save on leave or shutdown now retries a DataStore error twice (1 s, 2 s, not in Studio).
  3. lastEndlessRequest and endlessDirty are cleared on leave, and lastSeedRequest is weak keyed.
- Test added: a source audit pinning the rate limit on every handler, the Studio guard on Debug remotes, the load fallback blocking saves, the final save retry, and receipts saving before acknowledging.
- Left, needs you:
  - The "continue" Developer Product dedupe (grantedReceipts) is per-server memory only. A rare cross-server receipt replay could double grant a revive. Fixing it needs stored purchase ids in the profile (a design call).
  - Argument type and range checks per handler were spot checked, not exhaustively proven.
  - Real DataStore failure behavior needs a Studio check with API access off. Expect the notice and no save.
- Queue state: no [ ] tasks remain. The [h] tasks (map road, Studio test failures, Card Set screens, Flair audit, first five minutes) still need Studio screenshots or a design decision. BACKLOG.md items are all DONE.
