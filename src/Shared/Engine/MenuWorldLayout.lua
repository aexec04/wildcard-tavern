--[[
	Engine/MenuWorldLayout.lua
	Numbers for the Living Map menu (Client/MenuWorld.lua): the Menu is a painted slice of the Tavern Map. The tavern hub sits in
	the middle, a road runs from its door toward the bottom, and the six counter actions become landmarks standing on the ground
	around it. Pure data and functions (unit tested); every position is a fraction of the screen (anchor centre).

	Motion rule: the WHOLE map is one rigid frame (`drift`: a tiny pan and a 1 percent zoom breath over 40 s), so nothing slides
	against anything. Local life only: chimney smoke, door glow, cloud shadows, fireflies, the hero token on the road.

	apply(MenuLayout) moves the Menu hotspots to their landmark spots and turns on MenuLayout.world. Called once by Client/Menu.lua;
	MenuLayout.Hotspots keeps its counter positions until then, so the older layout tests stay valid.
]]

local MenuWorldLayout = {}

MenuWorldLayout.hub = { x = 0.50, y = 0.50, h = 0.40, asp = 4 / 3 }   -- tavern building, three-quarter view
MenuWorldLayout.road = { x = 0.50, y = 0.80, h = 0.40, asp = 1.5 }    -- dirt road from the door toward the bottom
MenuWorldLayout.door = { x = 0.50, y = 0.66 }                         -- where the door glows and the road starts
MenuWorldLayout.chimney = { x = 0.56, y = 0.31 }                      -- smoke starts here
MenuWorldLayout.hero = { x0 = 0.50, y0 = 0.68, y1 = 0.93, period = 30, size = 28 } -- walks out and back, pixels for size
MenuWorldLayout.drift = { panPx = 6, baseZoom = 1.03, zoomAmp = 0.01, period = 40 }
MenuWorldLayout.fireflies = 4
-- The parchment frame is only a thin edge: at most this share of the width per side and of the height top and bottom.
MenuWorldLayout.frameBand = { side = 0.08, vert = 0.06 }
MenuWorldLayout.clouds = 2
-- drift + smoke + door glow + cloud shadows + hero + fireflies
MenuWorldLayout.animated = 5 + MenuWorldLayout.fireflies

-- Menu layout v2: a strict grid over the quiet painted map. Top centre the Wordmark, centre the Deal Me In block (New Run sits
-- under it inside the same frame), one bottom row of six identical tiles on one baseline with equal gaps, and the slim Notice
-- Board in the left column whose left edge matches the row's left tile edge. Row order is how often the actions are used.
-- Hotspot id -> { x, y, s, asp } (s is the height as a fraction of the screen, width = s * asp of the height).
MenuWorldLayout.grid = { rowY = 0.84, tileS = 0.11, gap = 0.125, order = { "questscroll", "maptable", "tome", "coinjar", "rulebook", "jukebox" } }
MenuWorldLayout.spots = {
	play = { x = 0.50, y = 0.46, s = 0.16, asp = 1.5 }, -- the Deal Me In sign hangs over the door, New Run on its lower edge
}
for i, id in ipairs(MenuWorldLayout.grid.order) do
	local G = MenuWorldLayout.grid
	MenuWorldLayout.spots[id] = { x = 0.5 + (i - 3.5) * G.gap, y = G.rowY, s = G.tileS, asp = 1.0 }
end

-- Tile centres for a screen width as { id, x, y } fractions: one row of six, or two rows of three on narrow screens.
function MenuWorldLayout.tileSpots(w)
	local out = {}
	for i, id in ipairs(MenuWorldLayout.grid.order) do
		if w < 700 then
			out[#out + 1] = { id = id, x = 0.5 + ((i - 1) % 3 - 1) * 0.3, y = 0.62 + math.floor((i - 1) / 3) * 0.2 }
		else
			out[#out + 1] = { id = id, x = MenuWorldLayout.spots[id].x, y = MenuWorldLayout.grid.rowY }
		end
	end
	return out
end

-- Painted piece (category menu_world) used for each action landmark when its art is recorded.
MenuWorldLayout.art = {
	questscroll = "menu_quest_board",
	maptable = "menu_map_table_tent",
	tome = "menu_tome_library",
	coinjar = "menu_coin_jar_shop",
	rulebook = "menu_rulebook_stand",
	jukebox = "menu_jukebox_stage",
}

-- Every key MenuWorldArt may hold (the generated map only ever contains these).
MenuWorldLayout.artKeys = {
	"menu_tavern_hub", "menu_road_out", "menu_quest_board", "menu_tome_library", "menu_coin_jar_shop", "menu_rulebook_stand",
	"menu_jukebox_stage", "menu_map_table_tent", "menu_notice_post", "menu_cloud_wisp", "menu_fog_edge", "menu_map_frame",
}

-- The four edge strips of the frame art as fractions { name, x, y, w, h }. Each strip shows only that edge of the full-screen art
-- (the art is drawn at screen size inside a clipping frame), so the opaque parchment centre is never drawn.
function MenuWorldLayout.frameStrips()
	local B = MenuWorldLayout.frameBand
	return {
		{ name = "Top", x = 0, y = 0, w = 1, h = B.vert },
		{ name = "Bottom", x = 0, y = 1 - B.vert, w = 1, h = B.vert },
		{ name = "Left", x = 0, y = B.vert, w = B.side, h = 1 - 2 * B.vert },
		{ name = "Right", x = 1 - B.side, y = B.vert, w = B.side, h = 1 - 2 * B.vert },
	}
end

-- Share of the screen left open (not under a frame strip).
function MenuWorldLayout.openShare()
	local B = MenuWorldLayout.frameBand
	return (1 - 2 * B.side) * (1 - 2 * B.vert)
end

-- Pixel rectangle { left, top, right, bottom } of the hub image on a screen.
function MenuWorldLayout.hubRect(w, h)
	local H = MenuWorldLayout.hub
	local ph = H.h * h
	local pw = math.min(ph * H.asp, w)
	return H.x * w - pw / 2, H.y * h - ph / 2, H.x * w + pw / 2, H.y * h + ph / 2
end

-- Hero token position (fractions) at time t: walks from the door down the road and back, period seconds per round trip.
function MenuWorldLayout.heroAt(t)
	local H = MenuWorldLayout.hero
	local phase = (t % H.period) / H.period
	local k = phase < 0.5 and phase * 2 or (1 - phase) * 2
	k = k * k * (3 - 2 * k) -- eased so it slows at both ends
	return H.x0, H.y0 + (H.y1 - H.y0) * k
end

-- Whole-map camera at time t: pan in pixels and zoom scale. Never past panPx and never under 1 + margin.
function MenuWorldLayout.driftAt(t)
	local D = MenuWorldLayout.drift
	local ph = t * math.pi * 2 / D.period
	return math.sin(ph) * D.panPx, math.cos(ph) * D.panPx * 0.6, D.baseZoom + math.sin(ph + 1) * D.zoomAmp
end

-- Move the Menu hotspots to their landmark spots and mark the Menu as the world. Returns the number of hotspots moved.
function MenuWorldLayout.apply(MenuLayout)
	local moved = 0
	for _, hotspot in ipairs(MenuLayout.Hotspots) do
		local spot = MenuWorldLayout.spots[hotspot.id]
		if spot then
			hotspot.x, hotspot.y, hotspot.s, hotspot.asp = spot.x, spot.y, spot.s, spot.asp
			moved = moved + 1
		end
	end
	MenuLayout.world = true
	MenuLayout.WorldArt = MenuWorldLayout.art
	return moved
end

-- Rectangles (pixels) the layout test checks: { id, kind, l, t, r, b } for every hotspot and every name tag.
function MenuWorldLayout.rects(MenuLayout, w, h)
	local out = {}
	for _, hotspot in ipairs(MenuLayout.Hotspots) do
		local spot = MenuWorldLayout.spots[hotspot.id]
		if spot then
			local shifted = { x = spot.x, y = spot.y, s = spot.s, asp = spot.asp, item = hotspot.item }
			local l, t, r, b = MenuLayout.rect(shifted, w, h)
			out[#out + 1] = { id = hotspot.id, kind = "landmark", l, t, r, b }
			if hotspot.item then
				local pl, pt, pr, pb = MenuLayout.plateRect(shifted, w, h)
				out[#out + 1] = { id = hotspot.id, kind = "tag", pl, pt, pr, pb }
			end
		end
	end
	return out
end

return MenuWorldLayout
