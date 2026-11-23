--[[
	Shared/Engine/VictoryLook.lua
	Pure layout and text rules for the purple and gold Victory screen (Client/VictoryScreen.lua). No Roblox calls.

	layout(w, h, mode) -> rects in screen pixels, mode "run" (Rewards Earned + Run Summary cards) or "pick" (3 reward cards):
	  { scale, banner, title, subtitle, hero, chest, button, rewards?, summary?, cards? = { r1, r2, r3 } }
	fontSize(base, scale) -> integer, never below MIN_TEXT
	rewardColumns(summary) -> { { value, label }... } only what the game really grants (Tips, unlocks)
	summaryRows(summary, best) -> { { label, value }... } only what the code really tracks
	BBOX: opaque content of each generated plate as fractions of its image, so the art can be placed without its empty margin.
]]

local M = {}

M.MIN_TEXT = 16
M.MIN_TAP = 44 -- every button is at least this tall on screen
M.DESIGN_W, M.DESIGN_H = 1280, 720

-- opaque area of each picture (x0, y0, x1, y1 as fractions), measured from the generated PNGs
M.BBOX = {
	victory_banner = { 0.009, 0.236, 0.991, 0.723 },
	victory_button = { 0.007, 0.222, 0.993, 0.770 },
	victory_hero = { 0.0, 0.094, 1.0, 1.0 },
	victory_chest = { 0.127, 0.096, 0.860, 0.938 },
}

-- Pictures drawn mirrored (the chest was generated facing right, so it is flipped to face the cards) and the pixel size of the
-- generated pictures, which the mirroring rect needs (ImageRectOffset x = px, ImageRectSize x = -px).
local function round(n) return math.floor(n + 0.5) end
M.MIRROR = { victory_chest = true }
M.IMAGE_PX = 1024
-- pixel size of each generated picture (width, height); a slot must have the aspect of the picture's opaque box or the art is squashed
M.IMAGE_SIZE = { victory_banner = { 1536, 1024 }, victory_button = { 1536, 1024 }, victory_hero = { 1024, 1536 }, victory_chest = { 1024, 1024 } }
-- width / height of a picture's opaque box in pixels
function M.artAspect(key)
	local bb, sz = M.BBOX[key], M.IMAGE_SIZE[key]
	if not bb or not sz then return nil end
	return ((bb[3] - bb[1]) * sz[1]) / ((bb[4] - bb[2]) * sz[2])
end
function M.bbox(key)
	local bb = M.BBOX[key]
	if bb and M.MIRROR[key] then return { 1 - bb[3], bb[2], 1 - bb[1], bb[4] } end
	return bb
end
-- the warm glow behind a piece of art: centred on that art, about 1.15 times its longer side
M.GLOW_SCALE = 1.15
function M.glow(r)
	return { cx = r.x + r.w / 2, cy = r.y + r.h / 2, size = round(math.max(r.w, r.h) * M.GLOW_SCALE) }
end

function M.fontSize(base, scale)
	return math.max(M.MIN_TEXT, math.floor((base or M.MIN_TEXT) * (scale or 1) + 0.5))
end

-- Design sheet is 1280 x 720; it is scaled to fit and centred, so nothing can leave the screen.
function M.layout(w, h, mode)
	local s = math.min(w / M.DESIGN_W, h / M.DESIGN_H)
	local ox, oy = (w - M.DESIGN_W * s) / 2, (h - M.DESIGN_H * s) / 2
	local function R(x, y, rw, rh)
		return { x = round(ox + x * s), y = round(oy + y * s), w = round(rw * s), h = round(rh * s) }
	end
	local out = {
		scale = s,
		banner = R(320, 14, 640, 211),
		subtitle = R(320, 226, 640, 36),
		hero = R(20, 300, 280, 381), -- 280 x 381 is the aspect of the hero's opaque box (M.artAspect), not squashed
		chest = R(990, 430, 240, 276),
		button = R(510, 540, 260, 96),
		nextStep = R(320, 640, 640, 26), -- under Continue (ends at 636) and above the share line, never over it
	}
	-- the hero bleeds off the bottom of the REAL screen (not the letterboxed design sheet): the generated art ends in a flat cut,
	-- so its bottom edge sits on the screen edge and the cut is never seen. Width and the head's x stay; only y moves down.
	out.hero.y = math.max(out.hero.y, h - out.hero.h)
	out.heroGlow, out.chestGlow = M.glow(out.hero), M.glow(out.chest)
	out.title = { x = out.banner.x + round(out.banner.w * 0.2), y = out.banner.y + round(out.banner.h * 0.18), w = round(out.banner.w * 0.6), h = round(out.banner.h * 0.64) }
	-- a button is never under 44 px, and a short window says it in fewer words so the text fits its plate
	out.compact = s < 0.75
	local minH = M.MIN_TAP
	if out.button.h < minH then out.button.y, out.button.h = out.button.y - math.floor((minH - out.button.h) / 2), minH end
	if mode == "pick" and (230 * s < 205) then -- too short for the portrait cards: art steps aside, three plain cards share the width
		out.compactCards = true
		local gap = 12
		local cw = math.min(220, math.floor((w - 48) / 3))
		local x0 = math.floor((w - (3 * cw + 2 * gap)) / 2)
		local y0 = out.subtitle.y + out.subtitle.h + 6
		local ch = math.max(M.MIN_TAP * 2 + 10, out.button.y - 8 - y0)
		out.cards = {}
		for i = 1, 3 do out.cards[i] = { x = x0 + (i - 1) * (cw + gap), y = y0, w = cw, h = ch } end
	elseif mode == "pick" then
		out.cards = { R(305, 280, 210, 230), R(535, 280, 210, 230), R(765, 280, 210, 230) }
	else
		out.rewards = R(304, 280, 336, 230)
		out.summary = R(660, 280, 320, 230)
		out.invite = R(315, 550, 180, 86) -- Invite a friend, left of Continue
		if out.invite.h < minH then out.invite.y, out.invite.h = out.invite.y - math.floor((minH - out.invite.h) / 2), minH end
		out.share = R(320, 670, 640, 44) -- plain text share line under the next step line (ends at 714 of 720)
	end
	return out
end

local ScoreText = require(script.Parent.ScoreText)

local function n(v) return ScoreText.clean(v) end

-- commas up to 999,999,999, then short forms (1.2B), so a huge Endless total still fits the Victory plate
local function commas(v)
	return ScoreText.plate(v)
end
M.commas = commas

-- summary = { tipsEarned, unlockCount, score, night, cap, hands, tipsTotal }
function M.rewardColumns(summary)
	summary = summary or {}
	local cols = { { value = "+" .. commas(summary.tipsEarned), label = "Tips" } }
	if n(summary.unlockCount) > 0 then
		cols[#cols + 1] = { value = tostring(n(summary.unlockCount)), label = n(summary.unlockCount) == 1 and "Unlock" or "Unlocks" }
	end
	return cols
end

function M.summaryRows(summary, best)
	summary = summary or {}
	local rows = {
		{ label = "Final Round Score", value = commas(summary.score) },
		{ label = "Best Hand", value = best and best.name or "-" },
		{ label = "Night Reached", value = n(summary.cap) > 0 and string.format("%d of %d", n(summary.night), n(summary.cap)) or tostring(n(summary.night)) },
		{ label = "Hands Played", value = commas(summary.hands) },
		{ label = "Tips Earned", value = commas(summary.tipsTotal) },
	}
	-- the celebration rows (only what the run really tracks, each shown when it has something to say)
	if n(summary.bestNight) > 0 then
		rows[#rows + 1] = { label = "Best Night", value = tostring(math.max(n(summary.bestNight), n(summary.night))) }
	end
	if summary.boons ~= nil then
		rows[#rows + 1] = { label = "Boons Picked", value = tostring(n(summary.boons)) }
	end
	if n(summary.deckSize) > 0 then
		local deck = tostring(n(summary.deckSize)) .. " cards"
		if n(summary.marked) > 0 then deck = deck .. ", " .. n(summary.marked) .. " marked" end
		rows[#rows + 1] = { label = "Your Deck", value = deck }
	end
	return rows
end

-- One Run Summary row fitted to its card: the label at the left, the value at the right, 8 px apart and 12 px (TextFit.SIDE) clear of the
-- card edges, so the pair is never wider than the card minus 24 px. A long label takes its short form, then a very long value is cut.
M.SHORT_LABELS = {
	["Final Round Score"] = { "Final Score", "Score" }, ["Night Reached"] = { "Night" }, ["Hands Played"] = { "Hands" },
	["Tips Earned"] = { "Tips" }, ["Boons Picked"] = { "Boons" }, ["Your Deck"] = { "Deck" }, ["Best Night"] = { "Best" },
}
M.ROW_GAP = 8
function M.fitRow(row, size, cardW)
	local TextFit = require(script.Parent.TextFit)
	local avail = cardW - 2 * TextFit.SIDE - M.ROW_GAP
	local value = tostring(row.value)
	local label = tostring(row.label)
	local choices = { label }
	for _, short in ipairs(M.SHORT_LABELS[label] or {}) do choices[#choices + 1] = short end
	for _, l in ipairs(choices) do
		if TextFit.width(l, size) + TextFit.width(value, size) <= avail then return { label = l, value = value } end
	end
	local l = choices[#choices]
	return { label = l, value = TextFit.clip(value, math.max(0, avail - TextFit.width(l, size)), size) }
end

-- How many rows fit the Run Summary card at this screen size at the 16 px minimum (the rows start 48 design px down, each needs
-- 1.15 x the text size). The five plain rows always stay; the celebration rows (Best Night, Boons Picked, Your Deck) are dropped
-- from the end when the card is too short, so small screens never overlap text.
function M.fitRows(rows, w, h)
	local L = M.layout(w, h, "run")
	local room = L.summary.h - round(48 * L.scale)
	local fit = math.max(5, math.floor(room / (M.MIN_TEXT * 1.15)))
	local out = {}
	for i = 1, math.min(#rows, fit) do out[i] = rows[i] end
	return out
end

-- The text size of the Run Summary rows: 22 for the five plain rows, 16 (the minimum) once the celebration rows join.
function M.rowSize(count)
	return (count or 0) > 5 and M.MIN_TEXT or 22
end

-- The plain text share line for the Victory screen (no links; ShareResult keeps the Roblox chat limit).
function M.shareLine(summary, best)
	local ShareResult = require(script.Parent.ShareResult)
	local hand = best and { name = best.name, score = best.score } or nil
	return ShareResult.line({ night = n(summary and summary.night), won = true, bestHand = hand }, nil)
end

M.INVITE_TEXT = "Invite a friend"
M.INVITE_SHORT = "Invite"

M.NEXT_SIZE = 16
M.NEXT_RUN = "Next: Endless Mode starts at the next Night."
M.CONTINUE_TEXT = "Continue to Endless"
M.CONTINUE_SHORT = "Endless"
M.CONTINUE_SIZE = 22
M.SUBTITLE_RUN = "The Tavern celebrates your triumph!"
M.SUBTITLE_PICK = "A thank you from the tavern."

return M
