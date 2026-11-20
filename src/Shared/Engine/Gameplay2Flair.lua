--[[
	Engine/Gameplay2Flair.lua
	Gameplay v2: the hand name flair at the centre of the table. When a hand is played its name ("Flush", "Full House") slams in
	above the score in 40 px gold serif with a short light sweep; better hands get more. Pure numbers, tested;
	Client/Gameplay2FlairFX draws it on one FxLoop job. Presentation only: it never changes a score and never takes a click
	(a tap skips it). Calm mode and Reduce motion show the text only.

	  plain      High Card, Pair, Two Pair, Three of a Kind: slam and sweep
	  wipe       Straight, Flush: plus a gold underline wipe
	  burst      Full House, Four of a Kind: plus a gold burst
	  vignette   Straight Flush, Royal Flush, Five of a Kind and better: plus a brief gold vignette on the screen edge

	tierOf(handName)                  -> "plain" | "wipe" | "burst" | "vignette"
	overkill(score, target)           -> true when this one hand reaches the round Target on its own
	spec(handName, calm, fast, over)  -> { tier, slam, sweep, underline, burst, vignette, overkill, total, hold, static }
	fontSize(stage, avoidBottom)      -> pixels (at most 40) or nil when there is no room
	nameRect(stage, avoidBottom, size) -> { x, y, w, h } above the numeral digits, below the Patron row (avoidBottom), inside the stage width
	bannerRect(name, stage, handName, size) -> { x, y, w, h } the dark banner behind the name
	sidePlates(banner, stage)         -> { chips, mult } rects left and right of the banner, nil when they do not fit
	sideText(chips, mult)             -> "126 Chips", "x 4 Mult"
	overkillRect(name, stage, handName, size) -> { x, y, w, h } or nil: a small plate right of the banner, nil when it does not fit
]]

local M = {}

M.FONT = 40
M.MIN_FONT = 22
M.CAPTION = 26 -- the caption row at the top of the stage (Gameplay2 capH): the name may reach down into it, never past it
M.GAP = 2 -- clear of the Patron row's last row
M.OVERLAP = 12 -- the numeral's box has about this much empty ascent above its digits, so the name may reach into it
M.TOTAL = 1.2
M.PLATE_W, M.PLATE_H = 104, 24

local TIER = {
	["High Card"] = "plain", ["Pair"] = "plain", ["Two Pair"] = "plain", ["Three of a Kind"] = "plain",
	["Straight"] = "wipe", ["Flush"] = "wipe",
	["Full House"] = "burst", ["Four of a Kind"] = "burst",
	["Straight Flush"] = "vignette", ["Royal Flush"] = "vignette", ["Five of a Kind"] = "vignette",
}
local RANK = { plain = 1, wipe = 2, burst = 3, vignette = 4 }

function M.tierOf(name)
	local t = TIER[tostring(name or "")]
	if t then return t end
	local n = tostring(name or ""):lower()
	if n:find("royal", 1, true) or n:find("five", 1, true) or n:find("straight flush", 1, true) then return "vignette" end
	if n:find("four", 1, true) or n:find("house", 1, true) then return "burst" end
	if n:find("flush", 1, true) or n:find("straight", 1, true) then return "wipe" end
	return "plain"
end

function M.overkill(score, target)
	score, target = tonumber(score), tonumber(target)
	if not score or not target or target <= 0 then return false end
	return score >= target
end

function M.spec(handName, calm, fast, over)
	local tier = M.tierOf(handName)
	local r = RANK[tier]
	if calm then
		return { tier = tier, static = true, slam = nil, sweep = 0, underline = 0, burst = 0, vignette = 0, overkill = over == true, total = 1.0, hold = 1.0 }
	end
	local k = fast and 0.5 or 1
	return {
		tier = tier, static = false,
		slam = { from = 1.4, down = 0.13 * k, settle = 0.17 * k }, -- 0.3 s in all, like the hand name slam elsewhere
		sweep = 0.3 * k,
		underline = r >= 2 and 0.3 * k or 0,
		burst = r >= 3 and (r >= 4 and 14 or 8) or 0,
		vignette = r >= 4 and 0.5 * k or 0,
		overkill = over == true,
		total = M.TOTAL * k,
		hold = M.TOTAL * k,
	}
end

-- the name's bottom edge: into the numeral's empty ascent, but never below the stage (a short stage ends just above the hand)
local function bottomOf(stage)
	return math.min(stage.y + M.CAPTION + M.OVERLAP, stage.y + stage.h)
end

function M.fontSize(stage, avoidBottom)
	local bottom = bottomOf(stage)
	local top = math.max(avoidBottom or 0, stage.y - 60) + M.GAP
	local room = bottom - top
	local size = math.min(M.FONT, math.floor(room - 4))
	if size < M.MIN_FONT then return nil end
	return size
end

function M.nameRect(stage, avoidBottom, size)
	size = size or M.fontSize(stage, avoidBottom)
	if not size then return nil end
	local h = size + 4
	return { x = stage.x, y = bottomOf(stage) - h, w = stage.w, h = h }
end

local function textWidth(name, size)
	return math.floor(#tostring(name) * size * 0.58)
end

M.BANNER_PAD = 22 -- dark banner: clear air each side of the name
M.SIDE_W, M.SIDE_H, M.SIDE_GAP = 104, 28, 8 -- the Chips and Mult plates beside the banner

-- the dark ornate banner behind the name: as wide as the name plus BANNER_PAD each side (never wider than the stage), as tall as the row
function M.bannerRect(name, stage, handName, size)
	if not name or not size then return nil end
	local w = math.min(stage.w, textWidth(handName, size) + 2 * M.BANNER_PAD)
	return { x = math.floor(stage.x + (stage.w - w) / 2), y = name.y, w = w, h = name.h }
end

-- the Chips plate left of the banner and the Mult plate right of it, on the banner's row; nil when both do not fit inside the stage
function M.sidePlates(banner, stage)
	if not banner then return nil end
	local h = math.min(M.SIDE_H, banner.h)
	local y = banner.y + math.floor((banner.h - h) / 2)
	local lx = banner.x - M.SIDE_GAP - M.SIDE_W
	local rx = banner.x + banner.w + M.SIDE_GAP
	if lx < stage.x or rx + M.SIDE_W > stage.x + stage.w then return nil end
	return { chips = { x = lx, y = y, w = M.SIDE_W, h = h }, mult = { x = rx, y = y, w = M.SIDE_W, h = h } }
end

-- the words on the two plates ("126 Chips", "x 4 Mult"), whole numbers
function M.sideText(chips, mult)
	return string.format("%d Chips", math.floor((tonumber(chips) or 0) + 0.5)), string.format("x %d Mult", math.floor((tonumber(mult) or 0) + 0.5))
end

function M.overkillRect(name, stage, handName, size)
	if not name or not size then return nil end
	local tw = textWidth(handName, size) + 2 * M.BANNER_PAD
	local free = (stage.w - tw) / 2 - 8
	if free < M.PLATE_W then return nil end
	return { x = stage.x + stage.w / 2 + tw / 2 + 8 + (free - M.PLATE_W) / 2, y = name.y + math.floor((name.h - M.PLATE_H) / 2), w = M.PLATE_W, h = M.PLATE_H }
end

return M
