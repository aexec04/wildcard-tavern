# Launch art pack

Files for you to upload by hand in Creator Hub. None of these are in the game or uploaded by the tool. No text is baked into any picture, so add the title in an editor if you want one (the left third of each thumbnail is kept calm for it).

Look at every picture once before uploading. Roblox moderates by image, so if one is rejected, tell Claude which file and it can be regenerated with a safer prompt.

## Game icon (512x512)
| File | Creator Hub slot |
|---|---|
| icon_1.png | Game icon (first choice: ivory card with a gold crown) |
| icon_2.png | Alternate icon (golden knave card with a coin) |

## Thumbnails (1920x1080)
| File | Creator Hub slot |
|---|---|
| thumb_1.png | Thumbnail 1 (first image players see: card fan and lantern) |
| thumb_2.png | Thumbnail 2 (tavern keeper with crown and treasure) |
| thumb_3.png | Thumbnail 3 (wizard, knight and cat at the table) |
| thumb_4.png | Thumbnail 4 (friendly ogre boss) |
| thumb_5.png | Thumbnail 5 (ice tavern) |
| thumb_6.png | Thumbnail 6 (Journey Map: branching road, shop and event stops) |
| thumb_7.png | Thumbnail 7 (Shop and builds: merchant, Patrons, Recipes) |
| thumb_8.png | Thumbnail 8 (Scoring: a hand with chips and mult) |

See INVENTORY.md for size, product and status of every file.

## Game pass icons (512x512)
Creator Hub, Monetization, Passes, pick the pass, then Icon.
| File | Pass |
|---|---|
| pass_vip.png | VIP |
| pass_music_pack.png | Music Pack |

## Developer product and bundle icons (512x512)
Creator Hub, Monetization, Developer Products (or the pass page for bundles sold as passes).
| File | Item |
|---|---|
| pass_starter_pack.png | Starter Pack |
| pass_card_set_bundle.png | Card Set Bundle |
| pass_flair_bundle.png | Flair Bundle |
| pass_rainbow_numbers.png | Rainbow Numbers (flair) |
| pass_ribbon_trail.png | Ribbon Trail (flair) |
| pass_crown_flash.png | Crown Flash (flair) |
| pass_star_aura.png | Star Aura (flair) |
| pass_harvest_moon.png | Harvest Moon Premium (season) |
| pass_winter_welcome.png | Winter Welcome Premium (season) |
| pass_one_more_round.png | One More Round |

## Warm tavern set (claude/launch-art/warm/)
Same game look as the in game scenes: warm amber lantern glow, dark oak, gold edges, ivory cards, purple only as a small accent. The first set above is unchanged. Prompts: tools/patron_art/prompts.json (`launch_art_warm_subjects`), command `python3 tools/patron_art/generate_patron_art.py launch_art_warm`.

| File | Creator Hub slot |
| --- | --- |
| warm/icon_a.png | Experience icon, option A (ivory card with a gold crown) |
| warm/icon_b.png | Experience icon, option B (golden knave card, lantern, coins) |
| warm/thumb_w1.png | Thumbnail 1, the Corner Table close up (best first thumbnail) |
| warm/thumb_w2.png | Thumbnail 2, tavern keeper with a gold trophy (left third is a calm wall for a title) |
| warm/thumb_w3.png | Thumbnail 3, the friendly chef ogre boss |
| warm/thumb_w4.png | Thumbnail 4, the ice tavern variant |

Notes: thumb_w1 shows six cards instead of five. thumb_w4 has a purple table runner as its one accent. All six were looked at once for drinks, bottles, barrels, smoke, weapons and text and none appear; still check them in Creator Hub for moderation flags before Publish.

## Notes
- Prompts come from claude/LAUNCH-ASSETS.md (icons 1 and 2, thumbnails 1 to 5) and tools/patron_art/prompts.json (`launch_art_subjects`).
- Rainbow Numbers shows the digits 1 2 3 4 in rainbow colours. A first try showed three sevens, which looks like a slot machine, so it was replaced.
- Thumbnails were generated at 1536x1024 and cropped to 16:9, then resized to exactly 1920x1080. Icons were generated at 1024x1024 and resized to 512x512.
