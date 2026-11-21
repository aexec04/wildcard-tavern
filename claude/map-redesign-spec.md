# Tavern Map redesign spec (from the user, Nov 21)

Reference image: claude/reference/concept-journey-map-reference.png (the visual target; match composition, hierarchy, palette, spacing, framing).
Goal: turn the current Tavern Map (Client/Journey.lua, JourneyMapView.lua, JourneyMapGraph.lua, JourneyMapHero.lua, JourneyMapScenery.lua, Engine/JourneyMap.lua, WorldMap, WorldMapLayout) into an immersive illustrated roguelike journey map. Reuse the existing progression, keys, Tags, roads, side stops, shops, bosses and encounter launch. Do NOT invent new currencies, key types, progression or a second boss system. Implement, do not just plan.

1. Composition: map fills most of the screen. Warm dark wood frame, antique gold trim, purple crown banners at the top corners, candles at the lower corners. Aged illustrated parchment map inside. Clean, readable, no clutter.
2. Header (one compact dark carved wood bar with gold trim): title "The Tavern Map" (left plate), then a plate with Night N / 8, Journey N / total, Keys N (small icons: crown, compass, key), and a round X close button top right.
3. Map: hand-illustrated countryside parchment: dirt roads, trees, small buildings (the tavern at the start), bridges, a river, a windmill, fields, lanterns, fences. Scenery supports navigation and never covers nodes or labels. Branching route, understandable without scrolling or zooming.
4. Reusable node visual: round illustration, name label plate, type tag under the name (SHOP gold, EVENT purple, BOSS red, Encounter green), small badge top right (coin for shop, ? for event, green check for completed). States: locked (subdued), available, current (strong gold glow ring plus the player figure standing on it), completed (check). Hover and selected states. Key-locked nodes show their key requirement clearly.
5. Routes: curved, dashed cream paths (organic, not rigid straight lines), branches clear, selected route subtly highlighted, no overlapping nodes, labels or routes.
6. Boss node: larger, crimson accents, crowned skull emblem and red banners, a "BOSS" tag; the clear destination of the Night. Use the existing boss data.
7. Selected location panel, lower left (about 40 percent width, dark wood and gold): location illustration left, name, type with icon, one line description, Target score when it applies, green Continue (or Select) button. It must not permanently cover the map and must update on selection.
8. Interaction: click selects and highlights; inaccessible nodes cannot be selected; Continue enters the location through the existing launch path; completed nodes stay marked; map updates as the run progresses; skip/Tag system untouched.
9. Keys in header and on the map follow existing rules only.
10. Performance and scale: reuse assets, modular code, no extra client/server traffic, UIScale or constraints, works at 1920x957, 1280x720, 1024x768 and 800x450. Server stays authoritative.
