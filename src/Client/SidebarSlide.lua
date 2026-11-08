--[[
	Client/SidebarSlide.lua
	The left stats panel (parchment board, content, edge shadow) only matters during a round. While
	Round Select is up it is moved off screen (Round Select now covers the full width); when the phase
	leaves Round Select it slides back in (0.3s) under the travel transition, so nothing pops.

	  set(root, width, hidden)   hidden = true snaps it away, false slides it back (no-op if unchanged)
]]

local TweenService = game:GetService("TweenService")

local SidebarSlide = {}

local NAMES = { "SidebarBoard", "Sidebar", "EdgeShadow" }
local state = nil -- nil until the first call, then true (hidden) / false (shown)

function SidebarSlide.set(root, width, hidden)
	hidden = hidden == true
	if state == hidden then return end
	local first = state == nil
	state = hidden
	if first and not hidden then return end -- already in its resting place at startup
	for _, name in ipairs(NAMES) do
		local inst = root:FindFirstChild(name)
		if inst then
			local x = (name == "EdgeShadow") and width or 0
			local target = UDim2.new(0, hidden and (x - width - 40) or x, 0, 0)
			if hidden then
				inst.Position = target
			else
				TweenService:Create(inst, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Position = target }):Play()
			end
		end
	end
end

return SidebarSlide
