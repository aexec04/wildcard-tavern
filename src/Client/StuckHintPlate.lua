--[[
	Client/StuckHintPlate.lua
	The kind "when stuck" line (rules in Engine/StuckHint): a small plate in the stage band, shown once per round for 8 seconds, then gone.
	Display only: it takes no clicks and never changes the run. No tween and no loop, so Calm mode and Reduce motion see the same plate.
	Wears the equipped Card Set ink and plate through HintSkin, like the guided hint.

	update(layer, state, r)   r = Layout rects of the screen (pixels), the same ones the guided hint uses
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Stuck = require(Engine:WaitForChild("StuckHint"))
local Guided = require(Engine:WaitForChild("GuidedHand"))

local M = {}
local plate, line1, line2
local shownKey = nil
local shownAt = 0

local GOLD = Color3.fromRGB(246, 196, 70)

local function build(layer)
	plate = Instance.new("Frame")
	plate.Name = "StuckHint"
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.BackgroundColor3 = Color3.fromRGB(46, 28, 14)
	plate.BackgroundTransparency = 0.05
	plate.BorderSizePixel = 0
	plate.Active = false
	plate.Visible = false
	plate.ZIndex = 30
	plate.Parent = layer
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = plate
	local st = Instance.new("UIStroke"); st.Color = GOLD; st.Thickness = 2; st.Parent = plate
	local function line(name, y, size, color)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBold
		t.TextSize = size
		t.TextColor3 = color
		t.TextTransparency = 0
		t.TextStrokeTransparency = 1
		t.TextWrapped = true
		t.Size = UDim2.new(0.9, 0, 0.5, 0)
		t.Position = UDim2.new(0.05, 0, y, 0)
		t.ZIndex = 31
		t.Parent = plate
		return t
	end
	line1 = line("Line1", 0, 18, Color3.fromRGB(255, 244, 214))
	line2 = line("Line2", 0.5, 16, Color3.fromRGB(235, 218, 180))
	pcall(function()
		require(script.Parent.HintSkin).bind(plate, st, { line1, line2 }, { plate = plate.BackgroundColor3, edge = GOLD, ink = Color3.fromRGB(255, 244, 214) })
	end)
end

function M.update(layer, state, r)
	if not plate or plate.Parent ~= layer then build(layer) end
	if plate.Visible and os.clock() - shownAt >= Stuck.SHOW_SECONDS then plate.Visible = false end
	if state and state.handsRemaining == state.roundStartHands then shownKey = nil end -- a fresh round (or run) may show its own hint
	local hint = Stuck.check(state)
	if not Stuck.shouldShow(shownKey, hint) then return end
	shownKey = hint.key -- once per round, even if the player dismisses nothing
	line1.Text, line2.Text = hint.line1, hint.line2
	local pr = Guided.plateRect(r, layer.AbsoluteSize.Y)
	plate.Size = UDim2.fromOffset(pr.w, math.max(pr.h, 52))
	plate.Position = UDim2.fromOffset(pr.x + pr.w / 2, pr.y)
	plate.Visible = true
	shownAt = os.clock()
	task.delay(Stuck.SHOW_SECONDS, function()
		if plate and plate.Parent and os.clock() - shownAt >= Stuck.SHOW_SECONDS - 0.05 then plate.Visible = false end
	end)
end

return M
