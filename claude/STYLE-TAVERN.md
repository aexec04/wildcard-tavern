# Tavern style sheet

The look to match: the main menu (painted tavern, gold serif title, dark brown plates with thin gold trim, green Deal Me In) and the Night screen (`Client/RoundSelect.lua`: three painted room cards, brown plates, green Select, gold Target boxes). All numbers below are read from code and live in `Engine/TavernStyle.lua`; `Client/TavernKit.lua` draws them. Do not change the look of those two screens.

## Colors (RGB)
| Use | Value | Source |
|---|---|---|
| Plate fill | 40, 30, 22 | RoundSelect frame, `Palette.panelBg` |
| Card panel fill | 55, 42, 30 | Night card |
| Dark box fill (Target, room label) | 30, 22, 16 | RoundSelect |
| Wood chip fill (Tips) | 92, 62, 34 | RoundSelect |
| Gold trim (plates, buttons) | 200, 165, 90, stroke transparency 0.15 | `VisualHelpers.addGoldChrome` |
| Wood plate edge (chips, labels) | 150, 118, 66 | RoundSelect |
| Bright gold | 222, 182, 104 | `VisualHelpers` GOLD |
| Title cream | 250, 240, 220 | RoundSelect title, button text |
| Subtitle cream | 220, 205, 185 | RoundSelect |
| Chip text | 245, 232, 200 | RoundSelect |
| Primary green (Night Select) | 70, 130, 70 | RoundSelect |
| Primary green in the kit | 48, 102, 52 | deeper, so cream text is 4.5:1 even at the gradient top (Night's green gives 4.0:1) |
| Secondary brown (Skip) | 90, 60, 30 | RoundSelect |
| Target number | 120, 170, 255 | RoundSelect |
| Gold box number / medal | 230, 184, 70 | RoundSelect |
| Wordmark gold | 236, 205, 134 top, 184, 146, 80 bottom, outline 46, 30, 14 | `Client/Wordmark` |

## Type
- Title: Fondamento (the Wordmark serif), cream, dark outline (stroke transparency 0), 34 px on screens, 56 px for the game name.
- UI text: GothamBold, 16 px buttons, 17 px chips, 18 px Target box, never under 14.
- Body: Gotham 18 px, soft cream.

## Shape
- Plates and buttons: corner radius 6 (`PANEL_RADIUS`, `BUTTON_RADIUS`), cards 14, chips and boxes 8, pills fully round.
- Strokes: plates 2 px, buttons 1.5 px, Night cards 3 px (Boss 4 px), Border mode, gold trim.
- Gradients: Color only, a light 6 percent top and a dark 15 percent bottom. Never `UIGradient.Transparency`.
- Shadows: a soft offset dark frame behind a plate (`VisualHelpers.addSoftShadow`); no full screen vignettes on plates.

## Buttons
- Primary (green): 44 px tall, cream GothamBold 16, dark green text stroke 0.3, gold stroke 1.5.
- Secondary (brown): 40 px tall, same text, dark brown text stroke.
- Target box: dark fill, gold stroke, gold number, 36 px tall.
- Feel: hover lifts 2 px, press squeezes to 0.97, 0.08 s; nothing moves in Calm mode, Reduce motion or Fast speed.

## Rules
- Everything is drawn with Frame, UICorner, UIStroke, UIGradient and text. No stretched images.
- One drawn rect is also the click rect (a button is one GuiButton).
- Rarity colors belong to Patron cards only.
