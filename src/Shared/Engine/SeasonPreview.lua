--[[
	SeasonPreview.lua
	The small popup that opens when a Season tier tile is tapped (Client/SeasonPreview.lua draws it): the reward's art and name, one status
	line, a Claim plate when the tier is ready, and Close. Pure data and functions so tests can check the words and the sizes at four
	screen sizes. Never errors on odd input.

	Season tiers hold free rewards only (Tips, titles, card backs); no line here ever mentions chance, odds or Robux.
]]

local SeasonPreview = {}

SeasonPreview.TITLE_MAX = 40 -- reward names are cut to this many characters
SeasonPreview.LINE_MAX = 60
SeasonPreview.BUTTON_H = 44
SeasonPreview.ART = 96
SeasonPreview.PAD = 20

SeasonPreview.NO_NAME = "A surprise from the tavern"
SeasonPreview.CLAIMED = "Claimed. It is yours to keep."
SeasonPreview.READY = "Ready! Tap Claim to collect it."
SeasonPreview.CLAIM = "Claim"
SeasonPreview.CLOSE = "Close"

local function whole(n)
	n = tonumber(n) or 0
	return math.max(0, math.floor(n))
end

local function commas(n)
	local text = string.format("%d", whole(n))
	while true do
		local nxt, hits = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
		text = nxt
		if hits == 0 then break end
	end
	return text
end

local function clip(text, limit)
	if #text <= limit then return text end
	return text:sub(1, limit - 3) .. "..."
end

-- The words for one tier row (SeasonTrack.view().tiers[i]): { title, status, canClaim, tier }.
function SeasonPreview.of(row, view)
	row = type(row) == "table" and row or {}
	local name = type(row.text) == "string" and row.text:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if name == "" then name = SeasonPreview.NO_NAME end
	local status
	if row.claimed then
		status = SeasonPreview.CLAIMED
	elseif row.reached then
		status = SeasonPreview.READY
	else
		local have = view and tonumber(view.xp) or 0
		local need = whole(row.need)
		local more = math.max(1, need - whole(have))
		status = view and view.xp ~= nil
			and ("Earn " .. commas(more) .. " more season XP to unlock it.")
			or ("Reach " .. commas(need) .. " season XP to unlock it.")
	end
	return {
		tier = whole(row.tier),
		title = clip(name, SeasonPreview.TITLE_MAX),
		heading = "Tier " .. commas(row.tier),
		status = clip(status, SeasonPreview.LINE_MAX),
		canClaim = row.reached == true and row.claimed ~= true,
	}
end

-- Rects (x, y, w, h) inside the popup panel for a viewport. The panel is 360 x 330 and shrinks to fit a small screen; every button is 44 px.
function SeasonPreview.layout(vw, vh)
	local w = math.min(360, math.max(240, vw - 40))
	local h = math.min(330, math.max(260, vh - 40))
	local pad = SeasonPreview.PAD
	local bh = SeasonPreview.BUTTON_H
	local art = math.min(SeasonPreview.ART, h - 250)
	art = math.max(64, art)
	local closeY = h - pad - bh
	local claimY = closeY - 8 - bh
	return {
		panel = { w = w, h = h },
		heading = { x = pad, y = 12, w = w - pad * 2, h = 24 },
		art = { x = math.floor((w - art) / 2), y = 42, w = art, h = art },
		title = { x = pad, y = 42 + art + 8, w = w - pad * 2, h = 24 },
		status = { x = pad, y = 42 + art + 36, w = w - pad * 2, h = 40 },
		claim = { x = pad, y = claimY, w = w - pad * 2, h = bh },
		close = { x = pad, y = closeY, w = w - pad * 2, h = bh },
	}
end

return SeasonPreview
