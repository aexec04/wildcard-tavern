--[[
	Client/SellUndoPlate.lua
	After a Patron is sold: a plate at the bottom centre names the Tips gained and offers Undo for 5 seconds (Engine/SellUndo).
	No tween anywhere, so Calm mode needs nothing; the countdown is plain text. The server decides whether the Undo is honoured.

	SellUndoPlate.show(screenGui, refund, onUndo)   replaces any plate already showing
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local SellUndo = require(Engine:WaitForChild("SellUndo"))

local SellUndoPlate = {}

local serial = 0

function SellUndoPlate.show(screenGui, refund, onUndo)
	if not screenGui then return end
	serial += 1
	local mine = serial
	local old = screenGui:FindFirstChild("SellUndoPlate")
	if old then old:Destroy() end

	local cam = workspace.CurrentCamera
	local size = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
	local r = SellUndo.layout(size.X, size.Y)

	local plate = Instance.new("Frame")
	plate.Name = "SellUndoPlate"
	plate.AnchorPoint = Vector2.new(0, 0)
	plate.Position = UDim2.fromOffset(r.x, r.y)
	plate.Size = UDim2.fromOffset(r.w, r.h)
	plate.BackgroundColor3 = Color3.fromRGB(43, 28, 18)
	plate.BorderSizePixel = 0
	plate.ZIndex = 300
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 10); corner.Parent = plate
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(242, 207, 114); stroke.Thickness = 2; stroke.Parent = plate

	local label = Instance.new("TextLabel")
	label.Name = "SoldLine"; label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, 0); label.Size = UDim2.new(1, -140, 1, 0)
	label.Font = Enum.Font.GothamBold; label.TextSize = 16; label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(250, 240, 214); label.TextTransparency = 0; label.TextStrokeTransparency = 1
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = SellUndo.line(refund); label.ZIndex = 301; label.Parent = plate

	local undo = Instance.new("TextButton")
	undo.Name = "UndoButton"; undo.AutoButtonColor = true
	undo.AnchorPoint = Vector2.new(1, 0.5); undo.Position = UDim2.new(1, -6, 0.5, 0); undo.Size = UDim2.fromOffset(120, 44)
	undo.BackgroundColor3 = Color3.fromRGB(242, 207, 114); undo.BorderSizePixel = 0
	undo.Font = Enum.Font.GothamBold; undo.TextSize = 16; undo.TextColor3 = Color3.fromRGB(43, 28, 18)
	undo.TextTransparency = 0; undo.TextStrokeTransparency = 1
	undo.Text = SellUndo.button(SellUndo.WINDOW); undo.ZIndex = 302; undo.Parent = plate
	local ucorner = Instance.new("UICorner"); ucorner.CornerRadius = UDim.new(0, 8); ucorner.Parent = undo

	plate.Parent = screenGui

	local started = os.clock()
	local done = false
	local function close()
		done = true
		if plate.Parent then plate:Destroy() end
	end
	undo.Activated:Connect(function()
		if done then return end
		close()
		if onUndo then pcall(onUndo) end
	end)
	task.spawn(function()
		while not done and plate.Parent and mine == serial do
			local left = SellUndo.WINDOW - (os.clock() - started)
			if left <= 0 then break end
			undo.Text = SellUndo.button(left)
			task.wait(0.25)
		end
		if mine == serial or not done then close() end
	end)
end

return SellUndoPlate
