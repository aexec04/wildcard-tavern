--[[
	Client/BoonsPage.lua
	The Collection's Boons page: a popup over the Collection listing the 12 Night boons (Engine/BoonsPage), each row a set plated tile with
	the painted icon (emoji fallback), the name and one line, or "Not seen yet" in a dimmer row. Wears the equipped Card Set through
	PopupSkin.dark and SetInk. Escape, the Close plate and a tap outside close it. No tween, so Calm mode and Reduce motion need nothing
	extra. Display only, it never talks to the server.

	BoonsPage.open(seenIds)   opens the page for the ids of state.collection.boonsSeen
	BoonsPage.openView(view)  opens any view with the same row shape (the Marks and Legends page uses it)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Page = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("BoonsPage"))
local OverlayManager = require(script.Parent.OverlayManager)
local Cue = require(script.Parent.Cue)

local CREAM = Color3.fromRGB(250, 240, 220)
local SOFT = Color3.fromRGB(226, 212, 186)
local GOLD = Color3.fromRGB(255, 214, 130)
local PLATE = Color3.fromRGB(40, 30, 22)
local ROW = Color3.fromRGB(62, 44, 28)

local M = {}
local built

local function label(parent, name, size, color, font, z)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = color
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Active = false
	l.ZIndex = z or 6002
	l.Parent = parent
	return l
end
local function build()
	local gui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local screenGui = gui and gui:FindFirstChild("GameUI")
	if not screenGui then return nil end

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "BoonsPageBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.35
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 6000
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "BoonsPanel"
	panel.BackgroundColor3 = PLATE
	panel.Active = true
	panel.ZIndex = 6001
	panel.Parent = backdrop
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(200, 160, 84)
	edge.Thickness = 3
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = panel
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = panel

	local title = label(panel, "Title", 24, GOLD)
	local count = label(panel, "Count", Page.TEXT_SIZE, CREAM, Enum.Font.Gotham)

	local list = Instance.new("ScrollingFrame")
	list.Name = "BoonList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.ZIndex = 6002
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = "Close"
	close.Font = Enum.Font.GothamBold
	close.TextSize = 18
	close.TextColor3 = CREAM
	close.BackgroundColor3 = Color3.fromRGB(70, 110, 60)
	close.ZIndex = 6002
	close.Parent = panel
	pcall(function() require(script.Parent.TavernKit).setPlateButton(close, "primary") end)

	local function shut() backdrop.Visible = false end
	close.MouseButton1Click:Connect(function() Cue.play("button_click"); shut() end)
	backdrop.MouseButton1Click:Connect(function() Cue.play("button_click"); shut() end)
	OverlayManager.register("boons-page", shut)
	pcall(function()
		require(script.Parent.PopupDismiss).attach(backdrop, { policy = "cancel", close = shut, panel = panel, outside = false, button = true })
	end)
	return { backdrop = backdrop, panel = panel, title = title, count = count, list = list, close = close, edge = edge, screenGui = screenGui }
end

local function place(obj, r)
	obj.Position = UDim2.fromOffset(r.x, r.y)
	obj.Size = UDim2.fromOffset(r.w, r.h)
end

-- Draws any view shaped like Engine/BoonsPage.view (rows with id, name, icon, line, seen and an optional art category).
function M.openView(view)
	built = built or build()
	if not built then return end
	local size = built.screenGui.AbsoluteSize
	local L = Page.layout(size.X, size.Y)
	-- the panel and its parts sit at window pixels; the backdrop covers the window, so panel coordinates are relative to it
	place(built.panel, L.panel)
	local function rel(r) return { x = r.x - L.panel.x, y = r.y - L.panel.y, w = r.w, h = r.h } end
	place(built.title, rel({ x = L.header.x, y = L.header.y, w = L.header.w, h = 34 }))
	place(built.count, rel({ x = L.header.x, y = L.header.y + 34, w = L.header.w, h = 26 }))
	place(built.list, rel(L.list))
	place(built.close, rel(L.close))
	built.title.Text = view.title
	built.count.Text = view.count
	for _, child in ipairs(built.list:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	local ink = nil
	pcall(function() ink = require(script.Parent.SetInk).get() end)
	for i, row in ipairs(view.rows) do
		local tile = Instance.new("Frame")
		tile.Name = "Boon_" .. row.id
		tile.LayoutOrder = i
		tile.Size = UDim2.new(1, -10, 0, L.rowH)
		tile.BackgroundColor3 = ink and ink.plate or ROW
		tile.BackgroundTransparency = 0
		tile.ZIndex = 6003
		tile.Parent = built.list
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = tile
		local s = Instance.new("UIStroke"); s.Color = ink and ink.accent or Color3.fromRGB(200, 160, 84); s.Thickness = row.seen and 2 or 1
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = tile
		local icon = label(tile, "Icon", 30, CREAM, Enum.Font.GothamBold, 6004)
		icon.Position = UDim2.fromOffset(6, 6)
		icon.Size = UDim2.fromOffset(52, 52)
		icon.TextXAlignment = Enum.TextXAlignment.Center
		icon.Text = row.icon
		local host = Instance.new("Frame")
		host.Name = "IconArtHost"
		host.BackgroundTransparency = 1
		host.Active = false
		host.Position = icon.Position
		host.Size = icon.Size
		host.ZIndex = 6004
		host.Parent = tile
		pcall(function()
			local img = require(script.Parent.ArtIcon).apply(host, row.art or "boon_icons", row.artKey or row.id, icon, { cornerRadius = 8 })
			if img and not row.seen then img.ImageColor3 = Color3.fromRGB(130, 130, 130) end -- dimmed, never black
		end)
		local name = label(tile, "Name", Page.TEXT_SIZE, row.seen and CREAM or SOFT, Enum.Font.GothamBold, 6004)
		name.Position = UDim2.fromOffset(68, 6)
		name.Size = UDim2.new(1, -78, 0, 24)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = row.name
		local line = label(tile, "Line", Page.TEXT_SIZE, row.seen and GOLD or SOFT, Enum.Font.Gotham, 6004)
		line.Position = UDim2.fromOffset(68, 32)
		line.Size = UDim2.new(1, -78, 0, 24)
		line.TextTruncate = Enum.TextTruncate.AtEnd
		line.Text = row.line
	end
	built.list.CanvasPosition = Vector2.new(0, 0)
	pcall(function()
		require(script.Parent.PopupSkin).dark(built.panel, built.edge, { { built.title, GOLD }, { built.count, CREAM } }, { plate = PLATE, edge = built.edge.Color })
	end)
	if not built.backdrop.Visible then Cue.play("button_click") end
	built.backdrop.Visible = true
end

function M.open(seenIds)
	M.openView(Page.view(seenIds))
end

return M
