--[[
	BlessingChipLayout.lua
	Pure layout maths for the blessing chip at the foot of the gameplay sidebar (Client/BlessingChip.lua).
	The sidebar stack (round banner, score, tips, hands, Patron seats, status line) fills the column from the
	top; the chip takes what is left below it and never overlaps a neighbour. Pure Lua.
]]

local BlessingChipLayout = {}

BlessingChipLayout.STACK_HEIGHT = 648 -- top padding plus every sidebar section, with margin (8 px clear of the status plate)
-- icon, name, blessing line and curse line: sized from the content (name 3..23, blessing 26..46, curse 48..68), 2 px under the last line
BlessingChipLayout.FULL_HEIGHT = 70
BlessingChipLayout.COMPACT_HEIGHT = 44 -- icon and name; the tooltip carries both lines
BlessingChipLayout.MARGIN = 10

-- sidebarHeight: pixels of the sidebar column. reservedBottom: pixels at the bottom already used (Crowd Rule chips).
-- Returns { mode = "full" | "compact" | "hidden", height, bottom } where bottom is the offset from the column foot.
function BlessingChipLayout.plan(sidebarHeight, reservedBottom)
	reservedBottom = reservedBottom or 0
	local free = sidebarHeight - BlessingChipLayout.STACK_HEIGHT - reservedBottom - BlessingChipLayout.MARGIN * 2
	local bottom = reservedBottom + BlessingChipLayout.MARGIN
	if free >= BlessingChipLayout.FULL_HEIGHT then
		return { mode = "full", height = BlessingChipLayout.FULL_HEIGHT, bottom = bottom }
	elseif free >= BlessingChipLayout.COMPACT_HEIGHT then
		return { mode = "compact", height = BlessingChipLayout.COMPACT_HEIGHT, bottom = bottom }
	end
	return { mode = "hidden", height = 0, bottom = bottom }
end

-- Where the chip's top edge sits, measured from the column top.
function BlessingChipLayout.top(sidebarHeight, plan)
	return sidebarHeight - plan.bottom - plan.height
end

return BlessingChipLayout
