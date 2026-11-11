--[[
	Client/ShopCover.lua
	While the Counter (the Shop frame, which also holds the pack stage) is visible, the given frames (hand, Actions row, deck
	widget) are hidden so they cannot poke out between the painted board and the Counter. The Shop frame's Visible is the only
	signal; game state is untouched. A frame the game shows or hides meanwhile is remembered and restored when the Counter
	closes (never left hidden, never forced visible if the game hid it).

	ShopCover.install{ root, frames, onChange(covered) } -> { isCovered() }
]]

local ShopCover = {}

function ShopCover.install(deps)
	local root, frames = deps.root, deps.frames
	local covered, forcing, wanted = false, false, {}

	local function set(f, v)
		forcing = true
		f.Visible = v
		forcing = false
	end

	local function setCovered(on)
		if on == covered then return end
		covered = on
		for _, f in ipairs(frames) do
			if on then
				wanted[f] = f.Visible
				set(f, false)
			else
				if wanted[f] ~= nil then set(f, wanted[f]) end
				wanted[f] = nil
			end
		end
		if deps.onChange then deps.onChange(covered) end
	end

	for _, f in ipairs(frames) do
		f:GetPropertyChangedSignal("Visible"):Connect(function()
			if forcing or not covered then return end
			wanted[f] = f.Visible -- changed by the game while covered: remember it, keep it hidden
			if f.Visible then set(f, false) end
		end)
	end

	local function watch(shop)
		if not shop:IsA("GuiObject") then return end
		setCovered(shop.Visible)
		shop:GetPropertyChangedSignal("Visible"):Connect(function() setCovered(shop.Visible) end)
	end
	local shop = root:FindFirstChild("Shop")
	if shop then
		watch(shop)
	else
		root.ChildAdded:Connect(function(c) if c.Name == "Shop" then watch(c) end end)
	end

	return { isCovered = function() return covered end }
end

return ShopCover
