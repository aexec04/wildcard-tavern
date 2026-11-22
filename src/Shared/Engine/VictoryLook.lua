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
M.DESIGN_W, M.DESIGN_H = 1280, 720

-- opaque area of each picture (x0, y0, x1, y1 as fractions), measured from the generated PNGs
M.BBOX = {
	victory_banner = { 0.009, 0.236, 0.991, 0.723 },
	victory_button = { 0.007, 0.222, 0.993, 0.770 },
	victory_hero = { 0.0, 0.094, 1.0, 1.0 },
	victory_chest = { 0.127, 0.096, 0.860, 0.938 },
}

local function round(n) return math.floor(n + 0.5) end

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
		hero = R(20, 300, 280, 407),
		chest = R(990, 430, 240, 276),
		button = R(510, 540, 260, 96),
		nextStep = R(320, 648, 640, 30),
	}
	out.title = { x = out.banner.x + round(out.banner.w * 0.2), y = out.banner.y + round(out.banner.h * 0.18), w = round(out.banner.w * 0.6), h = round(out.banner.h * 0.64) }
	if mode == "pick" then
		out.cards = { R(305, 280, 210, 230), R(535, 280, 210, 230), R(765, 280, 210, 230) }
	else
		out.rewards = R(304, 280, 336, 230)
		out.summary = R(660, 280, 320, 230)
		out.invite = R(315, 550, 180, 86) -- Invite a friend, left of Continue
		out.share = R(320, 650, 640, 44) -- plain text share line under Continue
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

M.NEXT_SIZE = 16
M.NEXT_RUN = "Next: Endless Mode starts at the next Night."
M.CONTINUE_TEXT = "Continue to Endless"
M.CONTINUE_SIZE = 22
M.SUBTITLE_RUN = "The Tavern celebrates your triumph!"
M.SUBTITLE_PICK = "A thank you from the tavern."

return M
