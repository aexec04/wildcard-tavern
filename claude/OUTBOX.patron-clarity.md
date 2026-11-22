# Patron clarity: every Patron says what it does in one kid friendly line (Nov 22)

- Commit: "Patron clarity: shorten six long Patron lines, test length, jargon and duplicates"
- Tests: 1383 passed, 0 failed.
- Audit: every Patron `description` in Engine/Patrons.lua is the single source for the seat tooltip, Counter card and Collection tile (all read `.description`), so one edit fixes all three.
- Six lines were 70 characters or longer and were shortened keeping the real numbers: vip_table (88), big_spender (75), spare_change (78), efficient_service (76), rainy_day_fund (75), tasting_menu (71).
- No duplicate lines and no empty lines were found.
- New test "Patron descriptions: non empty, under 70 chars, no jargon, no duplicates" bans: multiplicative, additive, stack, trigger, proc, scalar, modifier, synergy, retrigger, per-hand.
- Not checked: that each line's numbers match the ability code beyond the existing Balance test rows. Nothing needs the user.
