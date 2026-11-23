--[[
	Client/SidebarSlide.lua
	The left stats panel (parchment board, content, edge shadow) can be moved off screen for two reasons,
	and slides back in (0.3s) when neither applies:
	  "roundSelect"  Round Select covers the full width and the panel only matters during a round;
	  "compact"      the window is narrower than 900px (Engine/ResponsiveLayout): the panel becomes a drawer
	                 that Client/CompactLayout's "Stats" tab opens over the table.

	  setReason(root, width, reason, hidden)   set or clear one reason
	  set(root, width, hidden)                 the "roundSelect" reason (kept for the hub's render hook)
]]

local TweenService = game:GetService("TweenService")

local SidebarSlide = {}

local NAMES = { "SidebarBoard", "Sidebar", "EdgeShadow" }
local reasons = {} -- [reason] = true while it applies
local shown = nil -- nil until the first call, then true (hidden) / false (visible)

local function anyReason()
	for _, on in pairs(reasons) do
		if on then return true end
	end
	return false
end

-- How far left a hidden piece sits: its own left edge goes past the screen edge by the piece's real width (the painted
-- board is wider than the base sidebar width, so the old width + 40 left its foot and top corner on screen).
function SidebarSlide.hiddenX(x, width, pieceWidth)
	return x - math.max(width or 0, pieceWidth or 0) - 40
end

function SidebarSlide.setReason(root, width, reason, hidden)
	reasons[reason] = hidden == true
	local hide = anyReason()
	if shown == hide then return end
	local first = shown == nil
	shown = hide
	if first and not hide then return end -- already in its resting place at startup
	for _, name in ipairs(NAMES) do
		local inst = root:FindFirstChild(name)
		if inst then
			local x = (name == "EdgeShadow") and width or 0
			local pieceW = 0
			pcall(function() pieceW = inst.AbsoluteSize.X end)
			local target = UDim2.new(0, hide and SidebarSlide.hiddenX(x, width, pieceW) or x, 0, 0)
			if hide or not require(script.Parent.ClientSettings).motionAllowed() then
				inst.Position = target
			else
				TweenService:Create(inst, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Position = target }):Play()
			end
		end
	end
end

function SidebarSlide.set(root, width, hidden)
	SidebarSlide.setReason(root, width, "roundSelect", hidden)
end

return SidebarSlide
