--[[
	Engine/ScorePopupRules.lua
	Timing and placement rules for the scoring popup (the trigger lines and the played cards), pure and tested.

	HOLD        seconds each scoring line stays up before the next one (the hub's ENTRY_STAGGER follows it)
	zones(r, rows) -> { avoid = { rects the popup must never cover: Patron seats, Target plate }, allowed = { name row, played band } }
	clear(a, b)    true when two {x,y,w,h} rects do not overlap
]]
local M = {}

M.HOLD = 0.9

function M.clear(a, b)
	return not (a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h)
end

-- r = Gameplay2Layout.rects(w, h), rows = Gameplay2Layout.scoringRows(r, capH)
function M.zones(r, rows)
	local avoid = { r.target }
	for _, s in ipairs(r.slots or {}) do avoid[#avoid + 1] = s.card end
	local allowed = {}
	if rows.name then allowed[#allowed + 1] = rows.name end
	allowed[#allowed + 1] = { x = r.stage.x, y = rows.band.top, w = r.stage.w, h = math.max(1, rows.band.bottom - rows.band.top) }
	return { avoid = avoid, allowed = allowed }
end

return M
