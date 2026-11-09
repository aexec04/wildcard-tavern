--[[
	Client/BondThreads.lua
	Patron Bonds made visible (Engine/Bonds.lua): a thin glowing thread joins every pair of bonded Patron seats in the
	sidebar. The thread pulses when the round score goes up, and hovering it shows the Bond name. Display only.

	The threads live in their own overlay frame (a child of the sidebar, not of the seat row, so no UIListLayout
	arranges them). Gradient uses Color stops only. Calm mode: no pulse.

	BondThreads.new(sidebar, patronSlots) -> { update = function(state) }
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bonds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Bonds"))
local ClientSettings = require(script.Parent.ClientSettings)
local ContentArt = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt"))

local BondThreads = {}

local TAG_COLORS = {
	pairs = Color3.fromRGB(255, 190, 90), flush = Color3.fromRGB(110, 190, 255), straight = Color3.fromRGB(150, 230, 150),
	economy = Color3.fromRGB(255, 225, 110), scaling = Color3.fromRGB(190, 255, 140), rulebender = Color3.fromRGB(210, 160, 255),
	ranks = Color3.fromRGB(255, 150, 190),
}

function BondThreads.new(sidebar, patronSlots)
	local self = {}
	local layer = Instance.new("Frame")
	layer.Name = "BondThreads"
	layer.BackgroundTransparency = 1
	-- A sibling overlay, never a child of the sidebar: the sidebar has a UIListLayout
	-- that would lay this frame out first and push the real content off the bottom.
	layer.Position = sidebar.Position
	layer.Size = sidebar.Size
	layer.Active = false
	layer.ZIndex = 30
	layer.Parent = sidebar.Parent or sidebar

	local tip = Instance.new("TextLabel")
	tip.Name = "BondTip"
	tip.AnchorPoint = Vector2.new(0.5, 1)
	tip.AutomaticSize = Enum.AutomaticSize.XY
	tip.BackgroundColor3 = Color3.fromRGB(235, 215, 170)
	tip.BorderSizePixel = 0
	tip.Font = Enum.Font.GothamBold
	tip.TextSize = 15
	tip.TextColor3 = Color3.fromRGB(60, 40, 22)
	tip.TextTransparency = 0
	tip.TextStrokeTransparency = 1
	tip.Visible = false
	tip.ZIndex = 32
	tip.Parent = layer
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = tip
		local p = Instance.new("UIPadding")
		p.PaddingLeft, p.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
		p.PaddingTop, p.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
		p.Parent = tip
	end

	-- Painted Bond medallion beside the hover label (ContentArt "bonds"); hidden while no art exists for the bond.
	local tipIcon = Instance.new("ImageLabel")
	tipIcon.Name = "BondIcon"
	tipIcon.AnchorPoint = Vector2.new(1, 0.5)
	tipIcon.Position = UDim2.new(0, -4, 0.5, 0)
	tipIcon.Size = UDim2.fromOffset(24, 24)
	tipIcon.BackgroundTransparency = 1
	tipIcon.Visible = false
	tipIcon.ZIndex = 33
	tipIcon.Parent = tip

	local threads = {}
	local lastScore = nil
	local lastKey = ""

	local function clear()
		for _, t in ipairs(threads) do
			t.frame:Destroy()
		end
		threads = {}
		tip.Visible = false
	end

	local function center(slot)
		local f = slot.frame
		local a = f.AbsolutePosition - layer.AbsolutePosition
		return Vector2.new(a.X + f.AbsoluteSize.X / 2, a.Y + f.AbsoluteSize.Y / 2)
	end

	local function build(bonds)
		clear()
		for _, bond in ipairs(bonds) do
			local sa, sb = patronSlots[bond.a], patronSlots[bond.b]
			if sa and sb and sa.frame.Visible and sb.frame.Visible then
				local pa, pb = center(sa), center(sb)
				local delta = pb - pa
				local len = delta.Magnitude
				if len > 1 then
					local frame = Instance.new("Frame")
					frame.Name = "Thread_" .. bond.tag
					frame.AnchorPoint = Vector2.new(0.5, 0.5)
					frame.Position = UDim2.fromOffset((pa.X + pb.X) / 2, (pa.Y + pb.Y) / 2)
					frame.Size = UDim2.fromOffset(len, 3)
					frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
					local color = TAG_COLORS[bond.tag] or Color3.fromRGB(255, 220, 150)
					frame.BackgroundColor3 = color
					frame.BackgroundTransparency = 0.35
					frame.BorderSizePixel = 0
					frame.Active = true -- hover target
					frame.ZIndex = 31
					frame.Parent = layer
					local g = Instance.new("UIGradient")
					g.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, color),
						ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 250, 225)),
						ColorSequenceKeypoint.new(1, color),
					})
					g.Parent = frame
					frame.MouseEnter:Connect(function()
						tip.Text = bond.name
						local artId = ContentArt.getImageId("bonds", bond.tag)
						tipIcon.Visible = artId ~= nil
						if artId then tipIcon.Image = artId end
						tip.Position = UDim2.fromOffset((pa.X + pb.X) / 2, math.min(pa.Y, pb.Y) - 6)
						tip.Visible = true
					end)
					frame.MouseLeave:Connect(function()
						tip.Visible = false
					end)
					threads[#threads + 1] = { frame = frame }
				end
			end
		end
	end

	local function pulse()
		if ClientSettings.get("reduceShake") then
			return
		end
		for _, t in ipairs(threads) do
			t.frame.BackgroundTransparency = 0
			t.frame.Size = UDim2.fromOffset(t.frame.Size.X.Offset, 5)
			TweenService:Create(t.frame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ BackgroundTransparency = 0.35, Size = UDim2.fromOffset(t.frame.Size.X.Offset, 3) }):Play()
		end
	end

	-- Called from render() with the latest state payload.
	function self.update(state)
		local owned = state.ownedPatrons or {}
		local bonds = Bonds.find(owned)
		local key = {}
		for _, b in ipairs(bonds) do
			key[#key + 1] = b.aId .. ">" .. b.bId .. ">" .. b.tag
		end
		local keyText = table.concat(key, "|") .. "#" .. tostring(state.patronSlotLimit)
		if keyText ~= lastKey then
			lastKey = keyText
			-- Seats settle after the layout runs, so build now and once more shortly after.
			build(bonds)
			task.delay(0.25, function()
				if layer.Parent and keyText == lastKey then
					build(bonds)
				end
			end)
		end
		if lastScore ~= nil and (state.roundScore or 0) > lastScore and #threads > 0 then
			pulse()
		end
		lastScore = state.roundScore or 0
	end

	return self
end

return BondThreads
