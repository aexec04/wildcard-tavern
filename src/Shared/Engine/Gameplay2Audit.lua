--[[
	Engine/Gameplay2Audit.lua
	Gameplay v2: one audit of the table at a window size, pure and tested; Client/AuditV2 prints it in Studio.

	audit(w, h) -> { fits, warnings = { "text" }, rects = { name = { x, y, w, h } }, handCard = { w, h } }
	Checks (every window the v2 table is up on, landscape and at least 720 x 360):
	  - no two rects overlap except the intended pairs, nothing is off screen
	  - hand cards are at least 56 px wide, Play Hand, Discard, Rank, Suit and the deck are at least 44 px tall (touch targets)
	  - Rank and Suit are both on screen and clear of the hand and Play Hand
	  - the Patron row does not reach the stage (the score) and the hand does not reach the buttons
	  - every text size in TavernStyle is 12 px or more
	A window the table does not fit (a portrait phone, under 640 x 360) is not audited: the older play screen runs there, and
	the result says so with fits = false.
	SIZES lists the five windows the audit runs for.
]]

local Layout = require(script.Parent:WaitForChild("Gameplay2Layout"))
local CTLayout = require(script.Parent:WaitForChild("ConceptTLayout"))
local HandSizing = require(script.Parent:WaitForChild("HandSizing"))
local Style = require(script.Parent:WaitForChild("TavernStyle"))

local M = {}

M.SIZES = { { 1920, 1080 }, { 1280, 720 }, { 1024, 600 }, { 800, 400 }, { 390, 844 } }
M.MIN_CARD_W = 56
M.MIN_TOUCH = 44
M.MIN_TEXT = 12

local function hit(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end

function M.audit(w, h)
	local out = { fits = Layout.fits(w, h) and w >= h, warnings = {}, rects = {} }
	if not out.fits then return out end
	local function warn(s) out.warnings[#out.warnings + 1] = s end
	local r = Layout.rects(w, h)
	out.rects = Layout.flat(r)
	for _, pair in ipairs(Layout.overlaps(r)) do warn("overlap " .. pair) end
	local ok, name = Layout.onScreen(r, w, h)
	if not ok then warn("off screen " .. tostring(name)) end
	-- the hand the table really gets with a full eight cards (the widest case)
	local hf = CTLayout.handFor(r.hand, w, 8)
	local cw, ch = HandSizing.cardSize(w, hf.w, hf.h, 8)
	out.handCard = { w = cw, h = ch }
	if cw < M.MIN_CARD_W then warn(string.format("hand cards %d px wide, under %d", cw, M.MIN_CARD_W)) end
	for _, k in ipairs({ "play", "discard", "sortRank", "sortSuit", "deck" }) do
		if r[k].h < M.MIN_TOUCH then warn(string.format("%s is %d px tall, under %d", k, r[k].h, M.MIN_TOUCH)) end
	end
	for _, k in ipairs({ "sortRank", "sortSuit" }) do
		if hit(r[k], hf) then warn(k .. " sits on the hand") end
		if hit(r[k], r.play) then warn(k .. " sits on Play Hand") end
	end
	if hit(hf, r.play) or hit(hf, r.discard) then warn("the hand reaches the buttons") end
	if hit(r.stage, r.hand) then warn("the score stage reaches the hand") end
	for i = 1, 5 do
		local s = r.slots[i]
		if hit(s.card, r.stage) or hit(s.pill, r.stage) then warn("Patron seat " .. i .. " reaches the score stage") end
	end
	for key, size in pairs(Style.TEXT) do
		if type(size) == "number" and size < M.MIN_TEXT then warn("text size " .. key .. " is " .. size .. ", under " .. M.MIN_TEXT) end
	end
	return out
end

-- printable lines for Client/AuditV2 and for tests: "WxH ok" or one line per warning, then every rect
function M.report(w, h)
	local a = M.audit(w, h)
	local lines = {}
	if not a.fits then
		lines[1] = string.format("%dx%d: the v2 table is off here (portrait or under 720 x 360), the older play screen runs", w, h)
		return lines, a
	end
	lines[1] = string.format("%dx%d: %s, hand card %dx%d", w, h, #a.warnings == 0 and "ok" or (#a.warnings .. " warning(s)"), a.handCard.w, a.handCard.h)
	for _, s in ipairs(a.warnings) do lines[#lines + 1] = "  WARN " .. s end
	local names = {}
	for k in pairs(a.rects) do names[#names + 1] = k end
	table.sort(names)
	for _, k in ipairs(names) do
		local v = a.rects[k]
		lines[#lines + 1] = string.format("  %-10s %4d,%4d  %4dx%4d", k, v.x, v.y, v.w, v.h)
	end
	return lines, a
end

return M
