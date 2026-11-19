--[[
	Client/ConfettiFX.lua
	A short gold and purple confetti burst for a cleared round (spec in Engine/Confetti, tested). One Heartbeat loop moves every
	piece, nothing takes input, all pieces are gone after about 1.8 s. Calm mode (Reduce Motion / Reduce Shake) draws nothing.

	burst(screenGui, big) -> number of pieces drawn
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Confetti = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Confetti"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}
local LIFE = 1.8

function M.burst(screenGui, big)
	local calm = ClientSettings.get("reduceShake") == true
	local n = Confetti.count(calm, ClientSettings.get("animSpeed") == "fast", big == true)
	if n == 0 or not screenGui then return 0 end
	local holder = Instance.new("Frame")
	holder.Name = "ConfettiBurst"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Active = false
	holder.ZIndex = 54 -- under the reward plate (55)
	holder.Parent = screenGui
	local spec = Confetti.pieces(n, math.floor(os.clock() * 1000))
	local parts = {}
	for i, p in ipairs(spec) do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.Active = false
		f.BackgroundColor3 = Color3.fromRGB(p.color[1], p.color[2], p.color[3])
		f.Size = UDim2.fromOffset(p.size, math.max(4, math.floor(p.size * 0.6)))
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.ZIndex = 54
		f.Visible = false
		f.Parent = holder
		parts[i] = f
	end
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if t > LIFE + 0.3 or not holder.Parent then
			conn:Disconnect()
			holder:Destroy()
			return
		end
		local h = holder.AbsoluteSize.Y
		for i, p in ipairs(spec) do
			local f = parts[i]
			local lt = t - p.delay
			if lt >= 0 and lt <= LIFE then
				f.Visible = true
				f.Position = UDim2.new(p.x, p.vx * lt, 0, h * 0.18 + p.vy * lt + 0.5 * Confetti.GRAVITY * lt * lt)
				f.Rotation = p.spin * lt
				f.BackgroundTransparency = math.max(0, (lt / LIFE - 0.6) / 0.4)
			else
				f.Visible = false
			end
		end
	end)
	return n
end

return M
