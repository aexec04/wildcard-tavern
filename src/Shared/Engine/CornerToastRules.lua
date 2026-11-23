--[[
	Shared/Engine/CornerToastRules.lua
	Small notices (an unlock, a finished quest, a rank, a chosen blessing) are a corner toast, not the big plate: one line or
	two, no button, never in the way. Pure rules (tested); drawn by Client/CornerToast.lua. The big OverlayQueue plate is only for
	items that say `plate = true` (the daily reward and Round Complete).

	  CornerToastRules.styleOf(item)            "plate" when item.plate == true, else "toast"
	  CornerToastRules.textFor(item)            -> text, names   the toast's words ("Unlocked: A, B and 2 more", no emoji)
	  CornerToastRules.plan(screen)             -> { maxVisible, lines, height }   screen = "table" | "roundSelect" | "choice" | "shop"
	  CornerToastRules.slot(w, h, plan, index)  -> { x, y, w, h }   index 1 is the top (the newest)
	  CornerToastRules.below(plan, w, keepOut)  -> plan             starts the column under a panel that stands in its way
	  CornerToastRules.new()                    -> stack: push(item, now), tick(now, max), dismiss(order), newRound()

	Where it sits: the right edge, 8 px under the top-right corner buttons (they end at y 66), 12 px from the edge, at most 300
	wide. On Round Select the cards start at y 104, so the slot there is ONE compact line between the buttons and the cards; every
	other screen has room for two two-line toasts clear of the left HUD, the hand, Play Hand, Discard, the deck widget, the Counter
	offers and the Choose buttons.
]]

local M = {}

M.WIDTH_MAX = 300
M.EDGE = 12 -- from the right edge of the screen
M.TOP = 74 -- the corner buttons end at y 66; 8 px under them
M.GAP = 6
M.AUTO_SECONDS = 4
M.FADE = 0.2
M.MAX_STACK = 2 -- never more than two toasts on screen
M.MAX_QUEUE = 6 -- and a short queue behind them: a flood (a first run unlock burst) drops the oldest waiting notice, so nothing shows minutes late
M.MIN_SHOW = 2.5 -- every toast stays readable at least this long, even when a smaller slot or a tap-free queue wants the room
M.CARDS_TOP = 104 -- Round Select's cards start here (RoundSelect.lua panelRow)
M.LINE_HEIGHT = 17

function M.styleOf(item)
	return (type(item) == "table" and item.plate == true) and "plate" or "toast"
end

-- Notices never show emoji (kit icons or none): drop any glyph outside plain text, and tidy the spaces.
function M.stripEmoji(s)
	s = tostring(s or "")
	local out = {}
	for ch in s:gmatch(utf8.charpattern) do
		local ok, cp = pcall(utf8.codepoint, ch)
		if ok and (cp < 0x2000 or (cp >= 0x2010 and cp <= 0x206F)) then -- Latin text and general punctuation stay; symbols and pictographs go
			out[#out + 1] = ch
		end
	end
	return (table.concat(out):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "Unlocked: Nest Egg", "Unlocked: A and B", "Unlocked: A, B and 3 more"
function M.mergeNames(names, prefix)
	prefix = prefix or "Unlocked: "
	if #names == 0 then return "" end
	if #names == 1 then return prefix .. names[1] end
	if #names == 2 then return prefix .. names[1] .. " and " .. names[2] end
	return string.format("%s%s, %s and %d more", prefix, names[1], names[2], #names - 2)
end

-- The words of one item. Returns text, names (names only for an unlock, so later unlocks can merge into it).
function M.textFor(item)
	if type(item) ~= "table" then return "", nil end
	if item.group == "unlock" then
		local names = {}
		for _, row in ipairs(item.rows or {}) do
			local n = M.stripEmoji(row)
			if n ~= "" then names[#names + 1] = n end
		end
		return M.mergeNames(names), names
	end
	local text = M.stripEmoji(item.text or "")
	if item.title and item.title ~= "" and text == "" then text = M.stripEmoji(item.title) end
	return text, nil
end

-- What fits: Round Select has one compact line between the buttons and the cards, every other screen three two-line toasts.
function M.plan(screen)
	if screen == "roundSelect" then
		-- its Tips chip ends at y 52 and its cards start at y 104: one compact line fits between them (y 68 to 100)
		return { maxVisible = 1, lines = 1, height = 32, top = 68 }
	end
	-- two 48 px toasts and a gap end at y 178 (three would end at y 230: the Counter's offer cards start at y 241 at 1280x720, and bob 5 px higher)
	return { maxVisible = M.MAX_STACK, lines = 2, height = 48, top = M.TOP }
end

function M.slot(w, h, plan, index)
	local width = math.min(M.WIDTH_MAX, math.floor(w * 0.3))
	return {
		x = w - M.EDGE - width,
		y = (plan.top or M.TOP) + (index - 1) * (plan.height + M.GAP),
		w = width,
		h = plan.height,
	}
end

-- A panel standing where the toast column would start (the Mult panel beside the Patron display on the table): the
-- column begins under it instead of on top of it. keepOut = { x, y, w, h } in the slot's own pixels, or nil.
-- Changes and returns the plan. A panel left of the column, or wholly above its top, changes nothing.
M.KEEP_OUT_GAP = 8
function M.below(plan, w, keepOut)
	if type(keepOut) ~= "table" then return plan end
	local slotX = M.slot(w, 0, plan, 1).x
	local top = plan.top or M.TOP
	if keepOut.x + keepOut.w > slotX - M.GAP and keepOut.y + keepOut.h > top - M.GAP then
		plan.top = math.max(top, math.floor(keepOut.y + keepOut.h + M.KEEP_OUT_GAP))
	end
	return plan
end

-- The table's Tips pill in the toast's own pixels (TableCheck's reference rect scaled to the screen), so the column can start under it.
function M.tipsPillKeepOut(w, h)
	local TC = require(script.Parent.TableCheck)
	local t
	for _, e in ipairs(TC.TARGETS) do if e.key == "TipsPill" then t = e end end
	local kx, ky = w / TC.REF_W, h / TC.REF_H
	return { x = t.x0 * kx, y = t.y0 * ky, w = (t.x1 - t.x0) * kx, h = (t.y1 - t.y0) * ky }
end

-- ===== the stack =====
local Stack = {}
Stack.__index = Stack

function M.new()
	return setmetatable({ visible = {}, pending = {}, seen = {}, counter = 0 }, Stack)
end

local function findUnlock(list)
	for _, e in ipairs(list) do
		if e.group == "unlock" then return e end
	end
end

-- Queue one notice. A second unlock merges into the one already waiting or showing ("Unlocked: A, B and 2 more") and restarts
-- its timer; an id seen this round is dropped. Returns true when it was taken.
function Stack:push(item, now)
	if type(item) ~= "table" then return false end
	if type(item.id) == "string" then
		if self.seen[item.id] then return false end
		self.seen[item.id] = true
	end
	local text, names = M.textFor(item)
	if text == "" then return false end
	if names then
		local into = findUnlock(self.visible) or findUnlock(self.pending)
		if into then
			for _, n in ipairs(names) do into.names[#into.names + 1] = n end
			into.text = M.mergeNames(into.names)
			if into.expiresAt then into.expiresAt = now + M.AUTO_SECONDS end -- (a merge restarts the clock)
			into.changed = true
			return true
		end
	end
	self.counter = self.counter + 1
	self.pending[#self.pending + 1] = {
		order = self.counter, id = item.id, text = text, names = names, group = item.group, icon = item.icon, artId = item.artId, hold = item.hold, rise = item.rise,
	}
	while #self.pending > M.MAX_QUEUE do table.remove(self.pending, 1) end
	return true
end

-- Expire what has been up long enough, fit the stack to `max`, bring in waiting notices (the newest on top).
-- Returns true when something changed (the view must redraw).
function Stack:tick(now, max)
	max = max or M.MAX_STACK
	local changed = false
	for i = #self.visible, 1, -1 do
		local e = self.visible[i]
		if e.expiresAt and now >= e.expiresAt then
			table.remove(self.visible, i)
			changed = true
		end
		if e.changed then e.changed = nil changed = true end
	end
	-- a smaller slot (Round Select): the oldest go back to waiting, in order, and come again when there is room
	while #self.visible > max do
		-- one still inside its minimum reading time stays; the extra toast waits instead
		local idx
		for i = #self.visible, 1, -1 do
			local v = self.visible[i]
			if v.shownAt and now - v.shownAt >= M.MIN_SHOW then idx = i break end
		end
		if not idx then break end
		local e = table.remove(self.visible, idx)
		e.expiresAt = nil
		table.insert(self.pending, 1, e)
		changed = true
	end
	while #self.visible < max and #self.pending > 0 do
		local e = table.remove(self.pending, 1)
		e.shownAt = now
		e.expiresAt = now + math.max(e.hold or M.AUTO_SECONDS, M.MIN_SHOW)
		table.insert(self.visible, 1, e) -- newest on top
		changed = true
	end
	return changed
end

function Stack:dismiss(order)
	for i, e in ipairs(self.visible) do
		if e.order == order then
			table.remove(self.visible, i)
			return true
		end
	end
	return false
end

function Stack:isEmpty() return #self.visible == 0 and #self.pending == 0 end

-- A new round: the same id may be shown again.
function Stack:newRound() self.seen = {} end

return M
