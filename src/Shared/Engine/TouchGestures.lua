--[[
	Shared/Engine/TouchGestures.lua
	Pure numbers and maths (tested) for phone and tablet play: a tap selects a hand card (the hub lifts it 24 px, a second
	tap deselects), a sideways drag reorders the hand and the neighbours slide aside over 0.12 s, a press held 0.35 s shows
	the tooltip of a hand card or a Patron card. Reordering is cosmetic: it only changes the on-screen order, never the
	server's hand. Client/HandTouchFX plays it; Calm mode and Reduce motion get the end state with no tween.

	TouchGestures.classify(dist, held, released) -> "pending" | "tap" | "drag" | "long"
	TouchGestures.reorder(order, from, to) -> new array (the item at `from` moves to `to`, others keep their order)
	TouchGestures.slotAt(x, centers) -> index of the nearest centre
	TouchGestures.hitSize(w, h) -> w, h grown to at least 44 px
	TouchGestures.withinTap(dx, dy, w, h) -> true when a release is inside the card plus 8 px of slack
	TouchGestures.motion(calm) -> nil | { slide, drop, lift }
]]

local M = {}

M.LONG_PRESS = 0.35 -- seconds held with no movement before the tooltip shows
M.DRAG_START = 12 -- pixels of sideways movement before a press becomes a drag
M.TAP_MOVE = 10 -- a press that moves less than this and is released before LONG_PRESS is a tap
M.LIFT = 24 -- a selected card rises this many pixels (the hub's SELECTED_LIFT)
M.SLIDE = 0.15-- neighbours slide aside over this many seconds
M.MIN_TARGET = 44 -- smallest touch target
M.SLACK = 8 -- extra pixels around a card that still count as a tap
M.CUE = "card_flip" -- soft cue on drop
M.SWALLOW = 0.15 -- seconds after a drag or long press during which the click that follows is ignored

function M.classify(dist, held, released)
	dist = math.abs(tonumber(dist) or 0)
	held = tonumber(held) or 0
	if dist >= M.DRAG_START then return "drag" end
	if released then
		if dist < M.TAP_MOVE and held < M.LONG_PRESS then return "tap" end
		if dist < M.TAP_MOVE then return "long" end
		return "pending"
	end
	if dist < M.TAP_MOVE and held >= M.LONG_PRESS then return "long" end
	return "pending"
end

-- moves the item at `from` to position `to`; out of range positions are clamped; the input is not changed
local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

function M.reorder(order, from, to)
	local n = #order
	local out = {}
	for i = 1, n do out[i] = order[i] end
	if n == 0 or type(from) ~= "number" then return out end
	from = clamp(math.floor(from), 1, n)
	to = clamp(math.floor(tonumber(to) or from), 1, n)
	if from == to then return out end
	local item = table.remove(out, from)
	table.insert(out, to, item)
	return out
end

-- the slot whose centre is nearest to x
function M.slotAt(x, centers)
	local best, bestD = nil, math.huge
	for i, c in ipairs(centers) do
		local d = math.abs(x - c)
		if d < bestD then best, bestD = i, d end
	end
	return best
end

function M.hitSize(w, h)
	return math.max(w or 0, M.MIN_TARGET), math.max(h or 0, M.MIN_TARGET)
end

-- is a release dx, dy from the card centre still a tap on a w x h card (never smaller than the 44 px target)
function M.withinTap(dx, dy, w, h)
	local hw, hh = M.hitSize(w, h)
	return math.abs(dx) <= hw / 2 + M.SLACK and math.abs(dy) <= hh / 2 + M.SLACK
end

-- tooltip text of a hand card: "Queen of Hearts" and one line per garnish, special or stamp (CardData = Engine/Card)
M.MYSTERY_TIP = "Mystery card\nThe True Wildcard. Play it and it becomes the card that scores the most."

-- the hidden True Wildcard: still face down, so its tip must not give away the rank and suit it was dealt as
function M.isMystery(card)
	return type(card) == "table" and card.isTrueWildcard == true and card.wildcardLocked ~= true
end

function M.cardTip(card, CardData)
	if type(card) ~= "table" then return "" end
	if M.isMystery(card) then return M.MYSTERY_TIP end
	local names = (CardData and CardData.RankNames) or {}
	local lines = {}
	if card.rank and card.suit then
		lines[1] = tostring(names[card.rank] or card.rank) .. " of " .. tostring(card.suit)
	else
		lines[1] = "Wild token"
	end
	for _, pair in ipairs({ { "garnish", "Garnishes" }, { "special", "Specials" }, { "stamp", "Stamps" } }) do
		local id = card[pair[1]]
		local def = id and CardData and CardData[pair[2]] and CardData[pair[2]][id]
		if def and def.name then
			lines[#lines + 1] = def.name .. (def.description and (": " .. def.description) or "")
		end
	end
	return table.concat(lines, "\n")
end

function M.motion(calm)
	if calm then return nil end
	return { slide = M.SLIDE, drop = M.SLIDE, lift = M.LIFT }
end

return M
