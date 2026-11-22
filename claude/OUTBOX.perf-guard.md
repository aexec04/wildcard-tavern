## Performance guard: per frame work and memory on the table (Nov 22)
- Commit: "Performance guard: Collection gallery idles when hidden, test pins loop cleanup" (`git log -1 --grep="Performance guard"`).
- Tests: 1386 passed, 0 failed.
- Audit of RunService.Heartbeat / RenderStepped / while true in src/Client (about 40 sites). Already fine: Tooltip placer disconnects in hide; AmbientLife drops its Heartbeat when no scene is left; Collection detail float disconnects in hideDetail; BoardDrawer slide, MinigamePanel needle and RoundRewardBanner disconnect when done; PlayMotion, BossFight cover check (every 0.25 s, gated), CollectionGallery and BadgesPanel return early when hidden; InputWatchdogFX is one 1 s loop; LedgerBook page-turn loop ends at u >= 1.
- Fixed: CollectionGallery Heartbeat called the moth reset every frame while the Collection was hidden. It now resets once on the way out.
- Test added: source checks for the four cleanup sites, plus the FxLoop hub drops finished, cancelled and paused effects.
- Not done: Instance count growth on repeated open and close of Collection, Card Sets, Shop and Map was only checked by reading code (screens are built once and toggled Visible; Collection destroys per-open art). It needs a Studio measure.
- NEEDS YOU: in Studio, open and close those four screens 10 times and compare #game:GetDescendants() before and after.
