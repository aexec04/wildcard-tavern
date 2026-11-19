--[[
	Client/CardFlights.lua
	Discard flight: a ghost copy of each discarded hand card arcs to the deck pile and shrinks (numbers in
	Engine/PlayMotion.flight, tested). The ghosts live under the screen root, so the hand rebuild that follows the server
	reply cannot cut them off. Calm mode (Reduce Motion / Reduce Shake) and Fast speed make no ghosts and no tweens.

	discard(root, buttons, deckFrame) -> number of flights started
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PM = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PlayMotion"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

function M.discard(root, buttons, deckFrame)
	local calm = ClientSettings.get("reduceShake") == true
	local fast = ClientSettings.get("animSpeed") == "fast"
	if calm or fast or not root or not deckFrame or not deckFrame.Parent then return 0 end
	local origin = root.AbsolutePosition
	local ex = deckFrame.AbsolutePosition.X + deckFrame.AbsoluteSize.X / 2 - origin.X
	local ey = deckFrame.AbsolutePosition.Y + deckFrame.AbsoluteSize.Y / 2 - origin.Y
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
			local sc = Instance.new("UIScale")
			sc.Parent = ghost
			ghost.Parent = root
			started += 1
			task.delay(p.delay, function()
				local t0 = os.clock()
				local conn
				conn = RunService.RenderStepped:Connect(function()
					local t = (os.clock() - t0) / p.dur
					if t >= 1 or not ghost.Parent then
						conn:Disconnect()
						ghost:Destroy()
						return
					end
					local e = t * t -- accelerate toward the pile
					local x, y = PM.arc(sx, sy, ex, ey, e, p.arc)
					ghost.Position = UDim2.fromOffset(x, y)
					sc.Scale = 1 - (1 - p.endScale) * e
				end)
			end)
		end
	end
	return started
end

return M
