--[[
	Client/CardFlights.lua
	Discard flight: a ghost copy of each discarded hand card arcs to the deck pile and shrinks (numbers in
	Engine/PlayMotion.flight, tested). The ghosts live under the screen root, so the hand rebuild that follows the server
	reply cannot cut them off. Calm mode (Reduce Motion / Reduce Shake) and Fast speed make no ghosts and no tweens.

	discard(root, buttons, deckFrame, point) -> number of flights started
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PM = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PlayMotion"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

function M.discard(root, buttons, deckFrame, point)
	local calm = ClientSettings.get("reduceShake") == true
	local fast = ClientSettings.get("animSpeed") == "fast"
	if calm or fast or not root or not deckFrame or not deckFrame.Parent then return 0 end
	local origin = root.AbsolutePosition
	local ex = deckFrame.AbsolutePosition.X + deckFrame.AbsoluteSize.X / 2 - origin.X
	local ey = deckFrame.AbsolutePosition.Y + deckFrame.AbsoluteSize.Y / 2 - origin.Y
	if point then ex, ey = point.x, point.y end -- Gameplay v2: a discard pile point at the bottom right (root pixels)
	local started, count = 0, #buttons
	for order, button in ipairs(buttons) do
		local p = PM.flight(order, count, calm, fast)
		if p and button and button.Parent then
			local ghost = button:Clone()
			ghost.Name = "DiscardGhost"
			ghost.Active = false
			ghost.AutoButtonColor = false
			ghost.AnchorPoint = Vector2.new(0.5, 0.5)
			local sx = button.AbsolutePosition.X + button.AbsoluteSize.X / 2 - origin.X
			local sy = button.AbsolutePosition.Y + button.AbsoluteSize.Y / 2 - origin.Y
			ghost.Size = UDim2.fromOffset(button.AbsoluteSize.X, button.AbsoluteSize.Y)
			ghost.Position = UDim2.fromOffset(sx, sy)
			ghost.Rotation = button.AbsoluteRotation
			ghost.ZIndex = 90
			for _, d in ipairs(ghost:GetDescendants()) do
				if d:IsA("GuiObject") then d.Active = false; d.ZIndex = math.max(d.ZIndex, 90) end
			end
			local fades = {} -- slide-and-fade: every visible part fades out over the second half of the flight
			for _, d in ipairs(ghost:GetDescendants()) do
				if d:IsA("GuiObject") then
					local f = { obj = d, bg = d.BackgroundTransparency }
					if d:IsA("ImageLabel") or d:IsA("ImageButton") then f.img = d.ImageTransparency end
					if d:IsA("TextLabel") or d:IsA("TextButton") then f.txt = d.TextTransparency; f.stroke = d.TextStrokeTransparency end
					fades[#fades + 1] = f
				end
			end
			local ghostBg = ghost.BackgroundTransparency
			local ghostEdge = nil -- the set's card back trim colour around the ghost (classic: none)
			pcall(function()
				local skin = require(script.Parent.HudTheme).skin()
				local tint = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CosmeticSets")).deckTint(skin and skin.id)
				if tint then
					ghostEdge = Instance.new("UIStroke")
					ghostEdge.Name = "SetGhostEdge"
					ghostEdge.Thickness = 2
					ghostEdge.Color = Color3.fromRGB(tint.trim[1], tint.trim[2], tint.trim[3])
					ghostEdge.Parent = ghost
				end
			end)
			local sc = Instance.new("UIScale")
			sc.Parent = ghost
			ghost.Parent = root
			started += 1
			task.delay(p.delay, function()
				local t0 = os.clock()
				require(script.Parent.FxLoop).add(function()
					local t = (os.clock() - t0) / p.dur
					if t >= 1 or not ghost.Parent then
						ghost:Destroy()
						return true
					end
					local e = t * t -- accelerate toward the pile
					local x, y = PM.arc(sx, sy, ex, ey, e, p.arc)
					ghost.Position = UDim2.fromOffset(x, y)
					sc.Scale = 1 - (1 - p.endScale) * e
					local a = math.clamp((t - 0.5) * 2, 0, 1) -- 0 until halfway, then to 1
					if a > 0 then
						ghost.BackgroundTransparency = ghostBg + (1 - ghostBg) * a
						if ghostEdge then ghostEdge.Transparency = a end
						for _, f in ipairs(fades) do
							local o = f.obj
							if o.Parent then
								o.BackgroundTransparency = f.bg + (1 - f.bg) * a
								if f.img then o.ImageTransparency = f.img + (1 - f.img) * a end
								if f.txt then
									o.TextTransparency = f.txt + (1 - f.txt) * a
									o.TextStrokeTransparency = f.stroke + (1 - f.stroke) * a
								end
							end
						end
					end
				end)
			end)
		end
	end
	return started
end

return M
