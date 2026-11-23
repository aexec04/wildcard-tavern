--[[
	ResultButtonHit: pure rules for a result plate's one button (the Night 8 "Enter Endless Nights" plate).
	No Roblox calls.

	ResultButtonHit.inside(rect, x, y)         rect = { x, y, w, h } in screen pixels; true when the point is in it
	ResultButtonHit.pointer(x, y, inset, ignoresInset)
	                                           input positions leave out the top bar; a ScreenGui with IgnoreGuiInset is drawn from the
	                                           very top, so its rects need the inset added back. Returns x, y in GUI space.
	ResultButtonHit.topmostAt(objects, x, y)   objects = { { name, x, y, w, h, z, active, visible } }; the visible active object with
	                                           the highest z whose rect holds the point (ties go to the later one), or nil.
	ResultButtonHit.rewardLine(label)          'Title: "Tavern Keeper", earned by this win': the reward line says why it is shown
	                                           under the "Tavern Champion" heading.
]]
local ResultButtonHit = {}

ResultButtonHit.SUFFIX = ", earned by this win"

function ResultButtonHit.inside(rect, x, y)
	if type(rect) ~= "table" or type(x) ~= "number" or type(y) ~= "number" then return false end
	return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

function ResultButtonHit.pointer(x, y, inset, ignoresInset)
	if ignoresInset then return x, y + (inset or 0) end
	return x, y
end

function ResultButtonHit.topmostAt(objects, x, y)
	local best
	for _, o in ipairs(objects or {}) do
		if o.visible ~= false and o.active and ResultButtonHit.inside(o, x, y) then
			if not best or (o.z or 0) >= (best.z or 0) then best = o end
		end
	end
	return best
end

function ResultButtonHit.rewardLine(label)
	return tostring(label or "") .. ResultButtonHit.SUFFIX
end

return ResultButtonHit
