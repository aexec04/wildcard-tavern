--[[
	Client/BossPresenceFX.lua
	Boss Round presentation on the Concept T play screen (numbers in Engine/BossPresence, tested): a dark red plate with the boss
	name and one line rule slides in under the Round banner (clear of the Patron row), a slow red pulse breathes on the room
	edges, and a boss clear fires the big confetti. The plate and the edge pulse never take input. Calm mode (Reduce Motion /
	Reduce Shake) shows the plate in place with no slide and no pulse; Fast speed skips the slide.

	show(root, boss)   hide()   fanfare(root)
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local BossPresence = require(Engine:WaitForChild("BossPresence"))
local Layout = require(Engine:WaitForChild("ConceptTLayout"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}
local plate, edges, conn

local function calm() return ClientSettings.get("reduceShake") == true end
local function fast() return ClientSettings.get("animSpeed") == "fast" end

function M.hide()
	if conn then conn:Disconnect(); conn = nil end
	if plate then plate:Destroy(); plate = nil end
	if edges then edges:Destroy(); edges = nil end
end

function M.show(root, boss)
	M.hide()
	if not root or type(boss) ~= "table" then return end
	local size = root.AbsoluteSize
	if not Layout.fits(size.X, size.Y) then return end
	local rects = Layout.rects(size.X, size.Y)
	local p = BossPresence.plate(size.X, size.Y, rects, rects.patrons)
	if p.h < 20 then return end

	plate = Instance.new("TextLabel")
	plate.Name = "BossRulePlate"
	plate.Size = UDim2.fromOffset(p.w, p.h)
	plate.Position = UDim2.fromOffset(p.x, p.y)
	plate.BackgroundColor3 = Color3.fromRGB(92, 22, 24)
	plate.BackgroundTransparency = 0.05
	plate.BorderSizePixel = 0
	plate.Active = false
	plate.ZIndex = 34
	plate.Font = Enum.Font.Merriweather
	plate.TextSize = p.textSize
	plate.TextColor3 = Color3.fromRGB(250, 235, 200)
	plate.TextStrokeColor3 = Color3.fromRGB(30, 8, 8)
	plate.TextStrokeTransparency = 0.4
	plate.TextTransparency = 0
	plate.TextTruncate = Enum.TextTruncate.AtEnd
	plate.Text = BossPresence.line(boss)
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = plate
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(214, 168, 70); stroke.Thickness = 2; stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; stroke.Parent = plate
	plate.Parent = root

	local slide = not fast() and BossPresence.slide(calm())
	if slide then
		plate.Position = UDim2.fromOffset(p.x, p.y - slide.rise)
		plate.TextTransparency, plate.BackgroundTransparency = 1, 1
		pcall(function()
			TweenService:Create(plate, TweenInfo.new(slide.dur, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(p.x, p.y), TextTransparency = 0, BackgroundTransparency = 0.05 }):Play()
		end)
	end

	if BossPresence.pulse(0, calm()) then
		-- one smooth gradient frame per edge (SmoothVignette), tinted red; its strength follows the sine
		local v = require(script.Parent.SmoothVignette).build(root, {
			name = "BossEdgePulse", zIndex = 3, color = Color3.fromRGB(150, 20, 24),
			left = { strength = 0.16, extent = 0.16 }, right = { strength = 0.16, extent = 0.16 },
			top = { strength = 0.16, extent = 0.14 }, bottom = { strength = 0.16, extent = 0.14 },
		})
		edges = v.holder
		local t0 = os.clock()
		conn = RunService.Heartbeat:Connect(function()
			local a = BossPresence.pulse(os.clock() - t0, calm())
			if not a or not edges or not edges.Parent then return end
			for edge in pairs(v.frames) do v.setStrength(edge, a) end
		end)
	end
end

-- the stronger clear when the boss falls: the big confetti burst (none in Calm mode)
function M.fanfare(root)
	M.hide()
	local f = BossPresence.fanfare(calm(), fast())
	if f and root then pcall(function() require(script.Parent.ConfettiFX).burst(root, f.big) end) end
end

return M
