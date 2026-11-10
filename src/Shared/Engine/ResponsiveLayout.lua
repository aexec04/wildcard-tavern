--[[
	Shared/Engine/ResponsiveLayout.lua
	Pure layout rules for narrow windows and phones (width under 900), tested at 640x360, 800x450,
	1280x720 and 1920x1080. The client (Client/CompactLayout.lua, Collection.lua) applies exactly these
	numbers, so the test harness below checks the real layout: nothing may extend past the screen and no two
	sibling buttons may overlap.

	COMPACT_WIDTH = 900

	gameplay(vpX, vpY) -> {
	    compact, sidebarW (0 when the stats panel collapses into a drawer), left, availW,
	    hand = rect, actions = rect (already scaled), actionScale, deck = rect,
	    buttons = { sortRank, sortSuit, play, discard } = rects (centred in the action row, scaled together)
	}
	collectionPanel(vpX, vpY) -> { w, h }     fractions of the screen
	collectionTitle(panelW) -> { x, w, fullWidth }   the title steps aside of the Card Sets / Badges buttons
	wrapRows(widths, avail, gap) -> rows      chips or tabs wrapped onto extra lines instead of overflowing
	clearOfTopBar(x, y, safeTop) -> y        keeps left-zone panels below Roblox's top bar (about 60px)
	inside(rect, vpX, vpY) -> bool            rect lies fully on screen
	overlaps(a, b) -> bool                    two rects share area
]]

local ResponsiveLayout = {}

ResponsiveLayout.COMPACT_WIDTH = 900
ResponsiveLayout.SIDEBAR_W = 240
ResponsiveLayout.PILE_RESERVE = 150 -- the draw pile (124px) and its margin on the right
ResponsiveLayout.ACTION_NATURAL_W = 230 + 200 + 200 + 2 * 20 -- sort group, Play Hand, Discard, two gaps
ResponsiveLayout.ACTION_H = 54

-- Roblox's own top bar (menu, chat) sits in the top-left corner. Nothing of ours may sit under it: panels in
-- the left zone start at least TOPBAR_H px down (also respect the device safe area on phones).
ResponsiveLayout.TOPBAR_H = 60
ResponsiveLayout.TOPBAR_ZONE_W = 320

-- y (px) for a panel whose left edge is at x: pushed below the top bar when it sits in the left zone.
function ResponsiveLayout.clearOfTopBar(x, y, safeTop)
	local floor = ResponsiveLayout.TOPBAR_H + (safeTop or 0)
	if x < ResponsiveLayout.TOPBAR_ZONE_W and y < floor then
		return floor
	end
	return y
end

function ResponsiveLayout.isCompact(vpX)
	return vpX < ResponsiveLayout.COMPACT_WIDTH
end

local function rect(x, y, w, h)
	return { x = x, y = y, w = w, h = h }
end

function ResponsiveLayout.inside(r, vpX, vpY)
	return r.x >= -0.001 and r.y >= -0.001 and r.x + r.w <= vpX + 0.001 and r.y + r.h <= vpY + 0.001
end

function ResponsiveLayout.overlaps(a, b)
	return a.x < b.x + b.w - 0.001 and b.x < a.x + a.w - 0.001 and a.y < b.y + b.h - 0.001 and b.y < a.y + a.h - 0.001
end

function ResponsiveLayout.gameplay(vpX, vpY)
	local compact = ResponsiveLayout.isCompact(vpX)
	local sidebarW = compact and 0 or ResponsiveLayout.SIDEBAR_W
	local left = compact and 12 or (ResponsiveLayout.SIDEBAR_W + 20)
	local rightMargin = (compact and 12 or 20) + ResponsiveLayout.PILE_RESERVE
	local availW = math.max(120, vpX - left - rightMargin)
	local scale = math.min(1, availW / ResponsiveLayout.ACTION_NATURAL_W)
	local actionH = ResponsiveLayout.ACTION_H * scale
	local naturalX = left + (availW - ResponsiveLayout.ACTION_NATURAL_W * scale) / 2
	local y = vpY - 80
	local function btn(offset, w)
		return rect(naturalX + offset * scale, y, w * scale, actionH)
	end
	-- sort group (230 wide: caption 46 + Rank 80 + Suit 80 + gaps), then Play Hand, then Discard
	local sortRank = btn(46 + 8, 80)
	local sortSuit = btn(46 + 8 + 80 + 8, 80)
	local play = btn(230 + 20, 200)
	local discard = btn(230 + 20 + 200 + 20, 200)
	return {
		compact = compact, sidebarW = sidebarW, left = left, availW = availW,
		hand = rect(left, vpY - 272, availW, 176),
		actions = rect(left, y, availW, actionH),
		actionScale = scale,
		deck = rect(vpX - 20 - 124, vpY - 84 - 195, 124, 195),
		buttons = { sortRank = sortRank, sortSuit = sortSuit, play = play, discard = discard },
	}
end

-- The layout before the compact mode existed (used to report what failed): the stats panel always
-- reserves 240px, the action row never scales.
function ResponsiveLayout.gameplayLegacy(vpX, vpY)
	local left = ResponsiveLayout.SIDEBAR_W + 20
	local availW = vpX - (ResponsiveLayout.SIDEBAR_W + 40 + ResponsiveLayout.PILE_RESERVE)
	local naturalX = left + (availW - ResponsiveLayout.ACTION_NATURAL_W) / 2
	local y = vpY - 80
	local function btn(offset, w) return rect(naturalX + offset, y, w, ResponsiveLayout.ACTION_H) end
	return {
		availW = availW,
		hand = rect(left, vpY - 272, availW, 176),
		actions = rect(left, y, availW, ResponsiveLayout.ACTION_H),
		buttons = { sortRank = btn(54, 80), sortSuit = btn(142, 80), play = btn(250, 200), discard = btn(470, 200) },
	}
end

function ResponsiveLayout.collectionPanel(vpX, vpY)
	local w = math.max(0.66, math.min(0.96, 900 / math.max(vpX, 1)))
	local h = (vpY < 500) and 0.94 or 0.78
	return { w = w, h = h }
end

-- Badges panel: the Collection panel's size and (centred) left edge, pushed right so it never covers the left HUD column
-- (sidebarW wide, default 240) and shrunk so it stays on screen. Returns { x, w, h } in pixels, x = left edge.
function ResponsiveLayout.badgesPanel(vpX, vpY, sidebarW)
	sidebarW = sidebarW or 240
	local fit = ResponsiveLayout.collectionPanel(vpX, vpY)
	local w = math.floor(fit.w * vpX)
	local x = math.floor((vpX - w) / 2)
	local minX = sidebarW + 12
	if x < minX then x = minX end
	if x + w > vpX - 12 then w = math.max(120, vpX - 12 - x) end
	return { x = x, w = w, h = math.floor(fit.h * vpY) }
end

-- The Card Sets and Badges buttons sit at x 15..217 on the title row. On a panel narrower than 600 the title
-- moves to the right of them (x 224) instead of centring behind them.
function ResponsiveLayout.collectionTitle(panelW)
	if panelW >= 600 then
		return { x = 0, w = panelW, fullWidth = true }
	end
	return { x = 224, w = math.max(60, panelW - 224 - 60), fullWidth = false }
end

-- widths = { w1, w2, ... } of items in order; returns { {indices...}, ... } so that each row's total width
-- (items plus `gap` between them) fits `avail`. An item wider than avail gets its own row.
function ResponsiveLayout.wrapRows(widths, avail, gap)
	local rows, row, used = {}, {}, 0
	for i, w in ipairs(widths) do
		local need = (#row > 0) and (used + gap + w) or w
		if #row > 0 and need > avail then
			rows[#rows + 1] = row
			row, used = { i }, w
		else
			row[#row + 1] = i
			used = need
		end
	end
	if #row > 0 then rows[#rows + 1] = row end
	return rows
end

return ResponsiveLayout
