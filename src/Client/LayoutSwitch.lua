--[[
	Client/LayoutSwitch.lua
	UIListLayout, UIGridLayout and UIPageLayout have NO Enabled property (only UIStroke, UIGradient and the like do), so a layout is
	switched off by taking it out of the tree and on again by putting it back under the same parent. Frames keep the Position and
	Size that were set while it was away.

	LayoutSwitch.off(host)   stash every list/grid/page layout that is a child of host
	LayoutSwitch.on(host)    put them back; returns the first one (or the one still attached)
	LayoutSwitch.isOff(host)
]]

local LayoutSwitch = {}

local LAYOUTS = { UIListLayout = true, UIGridLayout = true, UIPageLayout = true }
local stash = setmetatable({}, { __mode = "k" }) -- host -> { layouts }

function LayoutSwitch.off(host)
	local held = stash[host]
	for _, c in ipairs(host:GetChildren()) do
		if LAYOUTS[c.ClassName] then
			held = held or {}
			table.insert(held, c)
			c.Parent = nil
		end
	end
	stash[host] = held
end

function LayoutSwitch.on(host)
	local held = stash[host]
	stash[host] = nil
	if held then
		for _, c in ipairs(held) do c.Parent = host end
		return held[1]
	end
	for _, c in ipairs(host:GetChildren()) do
		if LAYOUTS[c.ClassName] then return c end
	end
	return nil
end

function LayoutSwitch.isOff(host)
	return stash[host] ~= nil
end

return LayoutSwitch
