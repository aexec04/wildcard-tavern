--[[
	Client/TwistPopup.lua
	"Today's twist": a small popup opened by tapping the Daily twist plate on the table scroll. It shows the twist name and icon, one kind
	line and a "Tomorrow: <name>" hint (words in Engine/TwistPreview, tested). It wears the equipped Card Set paper, plate and ink through
	PopupSkin.dark and TavernKit.setPlateButton, like the Replay popup. Escape, the Got it button and a tap outside close it. No tween, so
	Calm mode and Reduce motion need nothing extra. Display only, it never talks to the server.

	TwistPopup.ask(dateKey)   opens (or refreshes) the popup; builds itself under the ScreenGui on first use
]]

local Layers = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Layers"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Preview = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TwistPreview"))
local OverlayManager = require(script.Parent.OverlayManager)
local Cue = require(script.Parent.Cue)

local TEXT = Color3.fromRGB(250, 240, 220)
local GOLD = Color3.fromRGB(255, 214, 130)

local M = {}
local built = nil

local function build()
	local gui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local screenGui = gui and (gui:FindFirstChild("GameUI"))
	if not screenGui then return nil end

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "TwistPopupBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.35
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = Layers.confirm
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "TwistPanel"
	panel.Size = UDim2.new(0, 420, 0, 240)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.Active = true
	panel.ZIndex = Layers.confirm + 1
	panel.Parent = backdrop
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = Vector2.new(420, 240)
	cap.Parent = panel
	pcall(function()
		local pad = Instance.new("UIScale")
		pad.Parent = panel
		-- fit narrow phones: never wider than 92 percent of the screen
		local w = screenGui.AbsoluteSize.X
		if w > 0 and w * 0.92 < 420 then pad.Scale = math.max(0.6, (w * 0.92) / 420) end
	end)

	local function label(name, size, y, h, color, font)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Size = UDim2.new(1, -40, 0, h)
		l.Position = UDim2.new(0, 20, 0, y)
		l.BackgroundTransparency = 1
		l.Font = font
		l.TextSize = size
		l.TextWrapped = true
		l.TextColor3 = color
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.Text = ""
		l.ZIndex = Layers.confirm + 2
		l.Parent = panel
		return l
	end
	local title = label("Title", 22, 14, 30, GOLD, Enum.Font.GothamBold)
	local nameLabel = label("TwistName", 20, 54, 30, TEXT, Enum.Font.GothamBold)
	local lineLabel = label("TwistLine", 16, 90, 52, TEXT, Enum.Font.Gotham)
	local nextLabel = label("NextHint", 16, 146, 24, GOLD, Enum.Font.Gotham)

	local ok = Instance.new("TextButton")
	ok.Name = "GotIt"
	ok.Size = UDim2.new(0, 180, 0, 48)
	ok.AnchorPoint = Vector2.new(0.5, 0)
	ok.Position = UDim2.new(0.5, 0, 1, -62)
	ok.Font = Enum.Font.GothamBold
	ok.TextSize = 18
	ok.BackgroundColor3 = Color3.fromRGB(70, 110, 60)
	ok.TextColor3 = TEXT
	ok.ZIndex = Layers.confirm + 2
	ok.Parent = panel
	pcall(function() require(script.Parent.TavernKit).setPlateButton(ok, "primary") end)
	local ring = Instance.new("UIStroke")
	ring.Color = GOLD
	ring.Thickness = 3
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = ok

	pcall(function()
		local pStroke = panel:FindFirstChildOfClass("UIStroke")
		require(script.Parent.PopupSkin).dark(panel, pStroke,
			{ { title, GOLD }, { nameLabel, TEXT }, { lineLabel, TEXT }, { nextLabel, GOLD } },
			{ plate = Color3.fromRGB(40, 30, 22), edge = pStroke and pStroke.Color })
	end)

	local function close() backdrop.Visible = false end
	-- one click sound per tap: the tap handlers play it, close() itself is silent (Escape and Overlay closes stay quiet)
	ok.MouseButton1Click:Connect(function() Cue.play("button_click"); close() end)
	backdrop.MouseButton1Click:Connect(function() Cue.play("button_click"); close() end)
	OverlayManager.register("twist-popup", close)
	pcall(function()
		require(script.Parent.PopupDismiss).attach(backdrop, { policy = "cancel", close = close, panel = panel, outside = false, button = true })
	end)

	return { backdrop = backdrop, title = title, name = nameLabel, line = lineLabel, hint = nextLabel, ok = ok }
end

function M.ask(dateKey)
	built = built or build()
	if not built then return end
	local v = Preview.view(dateKey)
	built.title.Text = v.title
	built.name.Text = v.empty and "" or (v.icon .. "  " .. v.name)
	built.line.Text = v.line
	built.hint.Text = v.nextLine
	built.ok.Text = v.close
	if not built.backdrop.Visible then Cue.play("button_click") end -- opening taps once, a repeat tap while open stays quiet
	built.backdrop.Visible = true
end

return M
