--[[
	Shared/Engine/Gameplay2Touch.lua
	Pure, tested touch audit of the v2 table and the Counter at one window size (Client code stays the drawer).

	Gameplay2Touch.table(w, h) -> list of problems (empty when clean): Mute, Calm, Play Hand, Discard, Rank, Suit and the deck book
	  are at least 44 x 44 (Rank and Suit may be narrower than 44 only if still 44 tall), the Patron label and effect rows are tall
	  enough for 12 px text, Mute and Calm sit clear of the Patron row.
	Gameplay2Touch.shop(w, h, counts) -> list of problems: the tabs, Next Round and the Reroll plate are at least 44 px tall, the
	  Reroll plate is on screen, and no offer card overlaps Next Round, the tabs or the Reroll plate.
	Gameplay2Touch.SIZES = the windows checked: 1280x720, 1024x768, 844x390 (phone landscape). A portrait phone keeps the older
	  screens (Gameplay2Layout.fits is false there), so it is not audited here.
]]

local L = require(script.Parent:WaitForChild("Gameplay2Layout"))
local S = require(script.Parent:WaitForChild("ShopSceneLayout"))

local M = {}

M.SIZES = { { 1280, 720 }, { 1024, 768 }, { 844, 390 } }
M.MIN_TOUCH = 44
M.MIN_ROW_H = 16 -- room for 12 px text and a pixel of air

local function hit(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end
local function inside(r, w, h) return r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h end

function M.table(w, h)
	local bad = {}
	local function no(s) bad[#bad + 1] = s end
	if not L.fits(w, h) then return bad end
	local r = L.rects(w, h)
	for _, k in ipairs({ "mute", "calm", "play", "discard", "sortRank", "sortSuit" }) do
		if r[k].h < M.MIN_TOUCH then no(k .. " is " .. r[k].h .. " px tall") end
	end
	for _, k in ipairs({ "mute", "calm", "sortRank", "sortSuit" }) do
		if r[k].w < M.MIN_TOUCH then no(k .. " is " .. r[k].w .. " px wide") end
	end
	local hitRect = L.deckHit(r)
	if hitRect.h < M.MIN_TOUCH or hitRect.w < M.MIN_TOUCH then no("the deck tap area is " .. hitRect.w .. "x" .. hitRect.h) end
	for i, s in ipairs(r.slots) do
		if s.label.h < M.MIN_ROW_H or s.pill.h < M.MIN_ROW_H then no("Patron seat " .. i .. " rows are too short for text") end
		if hit(s.card, r.mute) or hit(s.card, r.calm) then no("Mute or Calm covers Patron seat " .. i) end
		if not (inside(s.card, w, h) and inside(s.label, w, h) and inside(s.pill, w, h)) then no("Patron seat " .. i .. " off screen") end
	end
	if hit(r.hand, r.play) or hit(r.hand, r.discard) then no("the hand reaches Play Hand or Discard") end
	return bad
end

function M.shop(w, h, counts)
	local bad = {}
	local function no(s) bad[#bad + 1] = s end
	local r = S.rects(w, h, counts)
	if r.tabs.h < M.MIN_TOUCH then no("tabs are " .. r.tabs.h .. " px tall") end
	if r.leave.h < M.MIN_TOUCH then no("Next Round is " .. r.leave.h .. " px tall") end
	if not inside(r.leave, w, h) then no("Next Round is off screen") end
	local plate = S.rerollPlate(r)
	if plate then
		if plate.h < M.MIN_TOUCH then no("Reroll is " .. plate.h .. " px tall") end
		if not inside(plate, w, h) then no("Reroll is off screen") end
		if hit(plate, r.leave) then no("Reroll covers Next Round") end
	end
	for i, o in ipairs(r.offers) do
		if hit(o, r.leave) then no("offer " .. i .. " covers Next Round") end
		if hit(o, r.tabs) then no("offer " .. i .. " covers the tabs") end
		if plate and hit(o, plate) then no("offer " .. i .. " covers Reroll") end
	end
	return bad
end

return M
