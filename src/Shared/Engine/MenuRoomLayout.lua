--[[
	Engine/MenuRoomLayout.lua
	Numbers for the Tavern Room Menu (Client/MenuRoom.lua): the Menu is the inside of the tavern and the props ARE the buttons.
	The card table in the middle is Deal Me In (New Run or Continue), the scroll and the road map hang on the back wall, the Tome
	stands on its lectern at the left, the Rulebook and the Coin Jar sit on the bar, the Jukebox stands left of the fireplace.
	Pure data and functions (unit tested); every position is a fraction of the screen (anchor centre), s is the height as a
	fraction of the screen and the width is s * asp of that height.

	apply(MenuLayout) moves the Menu hotspots to their prop spots and points MenuLayout.WorldArt at the menu_room art keys.
	Called once by Client/Menu.lua. Presentation only: every action keeps its handler, route and scroll.
]]

local MenuRoomLayout = {}

-- Hotspot id -> { x, y, s, asp }. Props on the wall and the bar sit above the table's top edge (y 0.655).
MenuRoomLayout.spots = {
	play        = { x = 0.50,  y = 0.79, s = 0.27, asp = 1.5 },    -- the card table, the deck is the primary button
	questscroll = { x = 0.43,  y = 0.30, s = 0.13, asp = 1.0 },    -- the scroll on its wall hook
	maptable    = { x = 0.57,  y = 0.30, s = 0.13, asp = 1.0 },    -- the rolled road map on its bracket
	tome        = { x = 0.20,  y = 0.66, s = 0.26, asp = 1.0 },    -- the open book on the lectern
	rulebook    = { x = 0.36,  y = 0.53, s = 0.12, asp = 1.0 },    -- the small book on the bar
	coinjar     = { x = 0.50,  y = 0.52, s = 0.14, asp = 1.0 },    -- the coin jar on the bar
	jukebox     = { x = 0.735, y = 0.60, s = 0.30, asp = 2 / 3 },  -- the jukebox left of the fireplace
}

-- menu_room art key per prop (the painted piece that stands in for the old landmark art).
MenuRoomLayout.art = {
	play = "menu_room_cardtable",
	questscroll = "menu_room_scroll",
	maptable = "menu_room_map",
	tome = "menu_room_tome",
	rulebook = "menu_room_rulebook",
	coinjar = "menu_room_coinjar",
	jukebox = "menu_room_jukebox",
}

-- Every key MenuRoomArt may hold (the generated map only ever contains these).
MenuRoomLayout.artKeys = {
	"menu_room_wall", "menu_room_jukebox", "menu_room_coinjar", "menu_room_tome", "menu_room_scroll", "menu_room_noticeboard",
	"menu_room_map", "menu_room_rulebook", "menu_room_cardtable", "menu_room_lantern", "menu_room_sign",
}

-- Decor that is not a button: the hanging lantern at the left edge and the glows. Fractions as above (glows: w and h are fractions).
MenuRoomLayout.lantern = { x = 0.06, y = 0.14, s = 0.26, asp = 0.5 }
MenuRoomLayout.fire = { x = 0.905, y = 0.56, w = 0.10, h = 0.20 }        -- the fireplace opening in menu_room_wall
MenuRoomLayout.motes = 3                                                 -- a few motes drifting in the firelight
MenuRoomLayout.glint = { every = 7, length = 0.5 }                       -- one glint on the coin jar every `every` s, `length` s long
MenuRoomLayout.flicker = 0.03                                            -- fire and lantern glow flicker amplitude (transparency)
MenuRoomLayout.minTouch = 44                                             -- smallest button side in pixels

-- Animated objects: fire glow, lantern glow, 3 motes, coin glint, tome page ripple, 2 jukebox note puffs. The NEW badge swing is
-- the hotspots' own. At most 10 in all; the lantern from MenuScene is counted on top (cap in MenuLayout.MAX_ANIMATED).
MenuRoomLayout.animated = 2 + MenuRoomLayout.motes + 1 + 1 + 2
MenuRoomLayout.MAX_ROOM_ANIMATED = 10

-- Tile centres for a screen width as { id, x, y } fractions: the props in place, or two rows of three on narrow screens
-- (phones show the list and no props at all, see MenuLayout.isPhone).
function MenuRoomLayout.tileSpots(w)
	local order = { "questscroll", "maptable", "tome", "coinjar", "rulebook", "jukebox" }
	local out = {}
	for i, id in ipairs(order) do
		if w < 700 then
			out[#out + 1] = { id = id, x = 0.5 + ((i - 1) % 3 - 1) * 0.3, y = 0.62 + math.floor((i - 1) / 3) * 0.2 }
		else
			out[#out + 1] = { id = id, x = MenuRoomLayout.spots[id].x, y = MenuRoomLayout.spots[id].y }
		end
	end
	return out
end

-- Pixel rectangle { l, t, r, b } of a prop on a screen (the whole prop is the click surface).
function MenuRoomLayout.propRect(MenuLayout, id, w, h)
	local spot = MenuRoomLayout.spots[id]
	return MenuLayout.rect(spot, w, h)
end

-- Rectangles (pixels) the layout test checks: { id, kind, l, t, r, b } for every prop and every name tag.
function MenuRoomLayout.rects(MenuLayout, w, h)
	local out = {}
	for _, hotspot in ipairs(MenuLayout.Hotspots) do
		local spot = MenuRoomLayout.spots[hotspot.id]
		if spot then
			local shifted = { x = spot.x, y = spot.y, s = spot.s, asp = spot.asp, item = hotspot.item }
			local l, t, r, b = MenuLayout.rect(shifted, w, h)
			out[#out + 1] = { id = hotspot.id, kind = "prop", l, t, r, b }
			if hotspot.item then
				local pl, pt, pr, pb = MenuLayout.plateRect(shifted, w, h)
				out[#out + 1] = { id = hotspot.id, kind = "tag", pl, pt, pr, pb }
			end
		end
	end
	return out
end

-- Move the Menu hotspots to their prop spots, mark the Menu as a painted scene and point the art at menu_room. Returns the count moved.
function MenuRoomLayout.apply(MenuLayout)
	local moved = 0
	for _, hotspot in ipairs(MenuLayout.Hotspots) do
		local spot = MenuRoomLayout.spots[hotspot.id]
		if spot then
			hotspot.x, hotspot.y, hotspot.s, hotspot.asp = spot.x, spot.y, spot.s, spot.asp
			moved = moved + 1
		end
	end
	MenuLayout.world = true
	MenuLayout.WorldArt = MenuRoomLayout.art
	MenuLayout.WorldArtCategory = "menu_room"
	MenuLayout.room = true
	return moved
end

-- Coin glint phase: 0 when idle, then 0 to 1 over the glint length once every `every` seconds.
function MenuRoomLayout.glintAt(t)
	local G = MenuRoomLayout.glint
	local local_t = t % G.every
	if local_t > G.length then return 0 end
	return local_t / G.length
end

-- Flicker value (-flicker .. +flicker) at time t from two slow sines, never past the amplitude.
function MenuRoomLayout.flickerAt(t)
	local A = MenuRoomLayout.flicker
	return (math.sin(t * 1.7) * 0.65 + math.sin(t * 4.3) * 0.35) * A
end

-- Mote position (fractions) around the fire at time t for mote i (1 to motes): a slow rise that loops.
function MenuRoomLayout.moteAt(i, t)
	local F = MenuRoomLayout.fire
	local k = (t / (9 + i) + (i - 1) / MenuRoomLayout.motes) % 1
	return F.x + math.sin(t * 0.6 + i * 2.1) * 0.025 - 0.03 * k, F.y - 0.02 - k * 0.2, 1 - math.abs(k * 2 - 1)
end

return MenuRoomLayout
