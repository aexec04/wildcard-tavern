--[[
	Shared/Engine/OverlayQueueRules.lua
	Pure rules for the post-round overlay queue (tested; drawn by Client/OverlayQueue.lua).

	After a round ends the player sees ONE plate at a time, lowest `priority` number first:
	  1 Round Complete, 2 Unlocks, 3 Rank up, 4 anything else.
	An item is { id, priority, group?, rows?, button?, auto? }:
	  * `id` is shown once per round (a second enqueue of the same id is dropped);
	  * items with the same `group` that are still waiting merge into one plate (rows are appended);
	  * an item with a button never auto-advances; a pure toast advances after AUTO_SECONDS.
	API: new() -> q; q:enqueue(item) -> bool; q:current(); q:advance() -> next item or nil; q:isBusy();
	     q:newRound() forgets the shown ids (call when a new round starts).
]]

local OverlayQueueRules = {}

OverlayQueueRules.AUTO_SECONDS = 4.5
OverlayQueueRules.MAX_WIDTH = 520
OverlayQueueRules.MIN_EDGE = 24
OverlayQueueRules.PRIORITY = { roundComplete = 1, unlock = 2, rank = 3, other = 4 }

local Queue = {}
Queue.__index = Queue

function OverlayQueueRules.new()
	return setmetatable({ waiting = {}, shown = {}, active = nil, counter = 0 }, Queue)
end

function Queue:enqueue(item)
	if type(item) ~= "table" or type(item.id) ~= "string" then return false end
	if self.shown[item.id] then return false end
	if self.active and self.active.id == item.id then return false end
	for _, w in ipairs(self.waiting) do
		if w.id == item.id then return false end
	end
	if item.group then
		for _, w in ipairs(self.waiting) do
			if w.group == item.group then
				w.rows = w.rows or {}
				for _, r in ipairs(item.rows or {}) do w.rows[#w.rows + 1] = r end
				self.shown[item.id] = true
				return true
			end
		end
	end
	self.counter = self.counter + 1
	local copy = {}
	for k, v in pairs(item) do copy[k] = v end
	copy.priority = copy.priority or OverlayQueueRules.PRIORITY.other
	copy.order = self.counter
	if copy.rows then
		local rows = {}
		for i, r in ipairs(copy.rows) do rows[i] = r end
		copy.rows = rows
	end
	self.waiting[#self.waiting + 1] = copy
	return true
end

-- Seconds until a plate closes by itself, or nil when it needs a click.
function OverlayQueueRules.autoSeconds(item)
	if not item or item.button then return nil end
	return OverlayQueueRules.AUTO_SECONDS
end

function Queue:current() return self.active end
function Queue:isBusy() return self.active ~= nil or #self.waiting > 0 end

-- Close the visible plate (if any) and open the next waiting one. Returns it, or nil when the queue is empty.
function Queue:advance()
	if self.active then
		self.shown[self.active.id] = true
		self.active = nil
	end
	if #self.waiting == 0 then return nil end
	local best, bestIndex = nil, nil
	for i, w in ipairs(self.waiting) do
		if not best or w.priority < best.priority or (w.priority == best.priority and w.order < best.order) then
			best, bestIndex = w, i
		end
	end
	table.remove(self.waiting, bestIndex)
	self.active = best
	return best
end

function Queue:newRound()
	self.shown = {}
end

-- Plate size and centred position for a play area: width capped at MAX_WIDTH, at least MIN_EDGE from every edge.
function OverlayQueueRules.plateRect(areaW, areaH, wantH)
	local w = math.min(OverlayQueueRules.MAX_WIDTH, areaW - 2 * OverlayQueueRules.MIN_EDGE)
	local h = math.min(wantH, areaH - 2 * OverlayQueueRules.MIN_EDGE)
	return { x = (areaW - w) / 2, y = (areaH - h) / 2, w = w, h = h }
end

-- Overlay plates never show emoji: a plate icon is a kit piece (Engine/HudKit) chosen by the caller's glyph, or nothing.
OverlayQueueRules.ICON_PIECE = {
	["\u{1F513}"] = "icon_slot", -- unlock
	["\u{1F4B0}"] = "icon_tips", -- tips earned
	["\u{1F3C5}"] = "icon_target", -- rank up
}
function OverlayQueueRules.iconPiece(icon)
	return OverlayQueueRules.ICON_PIECE[icon]
end

-- Painted plate: the kit's `reward` piece; padding keeps text on its parchment, clear of the wood.
OverlayQueueRules.KIT_PLATE = "reward"
OverlayQueueRules.KIT_PAD = { x = 76, top = 44, bottom = 44, minH = 190 }

return OverlayQueueRules
