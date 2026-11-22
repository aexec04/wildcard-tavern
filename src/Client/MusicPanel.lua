--[[
	Client/MusicPanel.lua
	The Music panel: dark carved wood with gold trim. The soundtrack choices (rules in Engine/MusicPicker, tested) as wood plates with a
	note icon, a green "Playing" tag on the playing one and a gold edge on the chosen one. Under them a Music shop plate ("Music pack",
	three locked placeholder rows, and a Get Music pack button: MarketplaceService:PromptGamePassPurchase for GamePasses.MUSIC_PACK;
	disabled and reading "Coming soon" while the id is 0). The choice is the saved setting musicTrack and is applied at once through the
	Sound module's setCustomTrack / clearCustomTrack. Opened from the gear menu's "Music tracks" row (OverlayManager opener "music").
	Pass ownership arrives with the game state: init.client.lua hands every state to MusicPanel.setState(state, SoundModule).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Picker = require(Engine:WaitForChild("MusicPicker"))
local GamePasses = require(Engine:WaitForChild("GamePasses"))
local Style = require(Engine:WaitForChild("TavernStyle"))
local ClientSettings = require(script.Parent.ClientSettings)
local OverlayManager = require(script.Parent.OverlayManager)

local M = {}

local Z = 5200
local ownsPack, soundModule = false, nil
local weSetTrack = false -- true while the track playing is the one we picked (so "auto" only clears our own override)
local rowsHost, buyButton, buyLabel, backdrop
local shopRowRefs = {}

local function rgb(name) local c = Style.rgb(name); return Color3.fromRGB(c[1], c[2], c[3]) end
local GOLD, CREAM = Color3.fromRGB(246, 196, 70), Color3.fromRGB(250, 238, 212)

-- play what the selection and ownership say; never touches a Jukebox track the player set themselves
local function apply()
	if not soundModule then return end
	local want = Picker.effective(ClientSettings.get("musicTrack"), ownsPack)
	local asset = Picker.assetFor(want)
	if asset then
		if soundModule.hasCustomTrack() and not weSetTrack then return end
		weSetTrack = true
		soundModule.setCustomTrack(asset)
	elseif weSetTrack then
		weSetTrack = false
		soundModule.clearCustomTrack()
	end
end

local nowLabel
local function refresh()
	if not rowsHost then return end
	local selected = Picker.effective(ClientSettings.get("musicTrack"), ownsPack)
	if nowLabel then nowLabel.Text = Picker.nowPlaying(selected, ownsPack) end
	for _, row in ipairs(rowsHost:GetChildren()) do
		if row:IsA("GuiButton") then
			local t = row:GetAttribute("TrackId")
			local chosen = (t == selected)
			row.Tick.Visible = chosen
			row.Lock.Visible = row:GetAttribute("Pack") == true and not ownsPack
			row:SetAttribute("Chosen", chosen)
			local st = row:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = chosen and rgb("goldTrim") or rgb("goldTrimPlate")
				st.Thickness = chosen and 2 or 1
			end
			row.BackgroundColor3 = chosen and Color3.fromRGB(62, 46, 26) or rgb("plateDark")
		end
	end
	for i, r in ipairs(Picker.shopRows(ownsPack)) do
		local ref = shopRowRefs[i]
		if ref then
			ref.tag.Text = r.tag
			ref.tag.Visible = r.tag ~= ""
			ref.lock.Visible = r.locked
		end
	end
	local b = Picker.buyButton(GamePasses.MUSIC_PACK, ownsPack)
	buyButton.Visible = b.show
	buyButton.Active = b.enabled
	buyButton.AutoButtonColor = false
	buyButton.BackgroundColor3 = b.enabled and Color3.fromRGB(46, 112, 56) or Color3.fromRGB(70, 60, 52)
	buyLabel.Text = b.text
end

function M.setState(state, sound)
	if sound then soundModule = sound end
	local now = type(state) == "table" and Picker.ownsPack(state.ownedGamePassIds) or false
	if now ~= ownsPack then ownsPack = now; pcall(refresh) end
	pcall(apply)
end

local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o end

local function addText(parent, str, size, color, align, w)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(w or 1, 0, 1, 0)
	l.Font = Enum.Font.Merriweather
	l.Text = str
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextTransparency, l.TextStrokeTransparency = 0, 1
	l.ZIndex = Z + 4
	l.Parent = parent
	return l
end

-- a dark wood plate with a thin gold edge (track rows and shop rows)
local function woodPlate(parent, className, h, z)
	local p = Instance.new(className)
	if className == "TextButton" then p.Text = ""; p.AutoButtonColor = false end
	p.BackgroundColor3 = rgb("plateDark")
	p.BorderSizePixel = 0
	p.Size = UDim2.new(1, 0, 0, h)
	p.ZIndex = z
	p.Parent = parent
	corner(p, 8)
	local st = Instance.new("UIStroke"); st.Color = rgb("goldTrimPlate"); st.Thickness = 1; st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = p
	return p
end

local function bar(parent, color, x, y, w, h, r)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(w, h)
	f.Position = UDim2.fromOffset(x, y)
	f.ZIndex = Z + 4
	f.Parent = parent
	if r then corner(f, r) end
	return f
end

-- a small note (round head, stem, flag), drawn so it needs no font glyph
local function noteIcon(row, color)
	local box = Instance.new("Frame")
	box.Name = "Note"
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(16, 20)
	box.AnchorPoint = Vector2.new(0, 0.5)
	box.Position = UDim2.new(0, 12, 0.5, 0)
	box.ZIndex = Z + 4
	box.Parent = row
	bar(box, color, 0, 14, 8, 6, 3)
	bar(box, color, 6, 1, 2, 15)
	bar(box, color, 8, 1, 7, 3)
	return box
end

-- a small padlock (shackle and body) at the right of a row
local function padlockIcon(row, color)
	local box = Instance.new("Frame")
	box.Name = "Padlock"
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(16, 20)
	box.AnchorPoint = Vector2.new(1, 0.5)
	box.Position = UDim2.new(1, -14, 0.5, 0)
	box.ZIndex = Z + 4
	box.Parent = row
	local sh = bar(box, color, 3, 0, 10, 10, 5)
	sh.BackgroundTransparency = 1
	local ss = Instance.new("UIStroke"); ss.Color = color; ss.Thickness = 2; ss.Parent = sh
	bar(box, color, 0, 8, 16, 11, 3)
	return box
end

function M.install(root)
	if backdrop and backdrop.Parent then return backdrop end
	backdrop = Instance.new("TextButton")
	backdrop.Name = "MusicBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = Z
	backdrop.Visible = false
	backdrop.Parent = root

	local L = Picker.layout(1920, 957)
	local panel = Instance.new("Frame")
	panel.Name = "MusicPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(L.panel.w, L.panel.h)
	panel.BackgroundColor3 = rgb("plateDark")
	panel.BorderSizePixel = 0
	panel.ZIndex = Z + 1
	panel.Parent = backdrop
	pcall(function() require(script.Parent.TitleBand).attach(panel, { z = Z + 1 }) end)
	corner(panel, 12)
	local ps = Instance.new("UIStroke"); ps.Color = rgb("goldTrim"); ps.Thickness = 2; ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ps.Parent = panel
	-- the panel never outgrows the screen (16 px margin, see MusicPicker.layout); the body below the title scrolls
	local function resize()
		local v = backdrop.AbsoluteSize
		if v.X < 1 or v.Y < 1 then return end
		local l = Picker.layout(v.X, v.Y)
		panel.Size = UDim2.fromOffset(l.panel.w, l.panel.h)
	end
	backdrop:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	resize()

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -64, 0, 40)
	title.Position = UDim2.fromOffset(16, 8)
	title.Font = Enum.Font[Style.FONTS.title]
	title.Text = "Music"
	title.TextSize = 26
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = rgb("cream")
	title.TextTransparency, title.TextStrokeTransparency = 0, 1
	title.ZIndex = Z + 2
	title.Parent = panel

	nowLabel = Instance.new("TextLabel")
	nowLabel.Name = "NowPlaying"
	nowLabel.BackgroundTransparency = 1
	nowLabel.Size = UDim2.new(1, -32, 0, 26)
	nowLabel.Position = UDim2.fromOffset(16, 48)
	nowLabel.Font = Enum.Font[Style.FONTS.title]
	nowLabel.Text = Picker.nowPlaying(ClientSettings.get("musicTrack"), ownsPack)
	nowLabel.TextSize = 16
	nowLabel.TextXAlignment = Enum.TextXAlignment.Left
	nowLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nowLabel.TextColor3 = GOLD
	nowLabel.TextTransparency, nowLabel.TextStrokeTransparency = 0, 1
	nowLabel.ZIndex = Z + 2
	nowLabel.Parent = panel

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(12, Picker.TITLE_H)
	body.Size = UDim2.new(1, -24, 1, -Picker.TITLE_H - 8)
	body.CanvasSize = UDim2.fromOffset(0, Picker.contentHeight())
	body.ScrollBarThickness = 4
	body.ZIndex = Z + 2
	body.Parent = panel
	local bodyList = Instance.new("UIListLayout")
	bodyList.SortOrder = Enum.SortOrder.LayoutOrder
	bodyList.Padding = UDim.new(0, Picker.ROW_GAP)
	bodyList.Parent = body

	local tracksH = #Picker.TRACKS * (Picker.ROW_H + Picker.ROW_GAP) - Picker.ROW_GAP
	rowsHost = Instance.new("Frame")
	rowsHost.Name = "Tracks"
	rowsHost.BackgroundTransparency = 1
	rowsHost.LayoutOrder = 1
	rowsHost.Size = UDim2.new(1, -8, 0, tracksH)
	rowsHost.ZIndex = Z + 2
	rowsHost.Parent = body
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, Picker.ROW_GAP)
	list.Parent = rowsHost

	for i, t in ipairs(Picker.list(false)) do
		local row = woodPlate(rowsHost, "TextButton", Picker.ROW_H, Z + 3)
		row.Name = "Track_" .. t.id
		row.LayoutOrder = i
		row:SetAttribute("TrackId", t.id)
		row:SetAttribute("Pack", t.pack)
		row:SetAttribute("Chosen", false)
		noteIcon(row, GOLD)
		local name = addText(row, t.name, 18, CREAM, Enum.TextXAlignment.Left, 0.55)
		name.Position = UDim2.fromOffset(38, 0)
		local lock = addText(row, "Music pack", 16, GOLD, Enum.TextXAlignment.Right, 0.4)
		lock.Name = "Lock"
		lock.AnchorPoint = Vector2.new(1, 0)
		lock.Position = UDim2.new(1, -12, 0, 0)
		lock.Visible = t.pack
		-- the playing track: a green "Playing" tag
		local tick = addText(row, "Playing", 16, Color3.fromRGB(160, 235, 160), Enum.TextXAlignment.Center)
		tick.Name = "Tick"
		tick.AnchorPoint = Vector2.new(1, 0.5)
		tick.Size = UDim2.fromOffset(84, 24)
		tick.Position = UDim2.new(1, -10, 0.5, 0)
		tick.BackgroundTransparency = 0
		tick.BackgroundColor3 = Color3.fromRGB(32, 78, 40)
		corner(tick, 12)
		tick.Visible = false
		row.MouseButton1Click:Connect(function()
			pcall(function() require(script.Parent.Cue).play("button_click") end)
			if Picker.effective(t.id, ownsPack) ~= t.id then return end -- a locked track does nothing but show its lock
			ClientSettings.set("musicTrack", t.id)
			apply(); refresh()
		end)
	end

	-- the Music shop: always shown so the pass has a home. Rows are placeholders until real ids exist (MusicPicker.SHOP_TRACKS).
	local shopRowH = Picker.ROW_H - 4
	local shopPlate = Instance.new("Frame")
	shopPlate.Name = "MusicShop"
	shopPlate.LayoutOrder = 2
	shopPlate.BackgroundColor3 = rgb("woodChip")
	shopPlate.BorderSizePixel = 0
	shopPlate.Size = UDim2.new(1, -8, 0, Picker.shopHeight())
	shopPlate.ZIndex = Z + 3
	shopPlate.Parent = body
	corner(shopPlate, 10)
	local sst = Instance.new("UIStroke"); sst.Color = rgb("goldTrim"); sst.Thickness = 1.5; sst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; sst.Parent = shopPlate
	local sTitle = addText(shopPlate, Picker.SHOP_TITLE, 20, rgb("cream"), Enum.TextXAlignment.Left)
	sTitle.Font = Enum.Font[Style.FONTS.title]
	sTitle.Size = UDim2.new(1, -24, 0, 28)
	sTitle.Position = UDim2.fromOffset(12, 12)
	local sLine = addText(shopPlate, Picker.SHOP_LINE, 16, rgb("creamSoft"), Enum.TextXAlignment.Left)
	sLine.Size = UDim2.new(1, -24, 0, 22)
	sLine.Position = UDim2.fromOffset(12, 40)
	local shopRowsHost = Instance.new("Frame")
	shopRowsHost.Name = "ShopRows"
	shopRowsHost.BackgroundTransparency = 1
	shopRowsHost.Position = UDim2.fromOffset(8, 70)
	shopRowsHost.Size = UDim2.new(1, -16, 0, #Picker.SHOP_TRACKS * (shopRowH + Picker.ROW_GAP))
	shopRowsHost.ZIndex = Z + 3
	shopRowsHost.Parent = shopPlate
	local sl = Instance.new("UIListLayout")
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Padding = UDim.new(0, Picker.ROW_GAP)
	sl.Parent = shopRowsHost
	for i, r in ipairs(Picker.shopRows(false)) do
		local row = woodPlate(shopRowsHost, "Frame", shopRowH, Z + 4)
		row.Name = "Shop_" .. r.id
		row.LayoutOrder = i
		row:SetAttribute("Placeholder", r.placeholder)
		noteIcon(row, Color3.fromRGB(150, 130, 90))
		local nm = addText(row, r.name, 17, Color3.fromRGB(215, 200, 170), Enum.TextXAlignment.Left, 0.55)
		nm.Position = UDim2.fromOffset(38, 0)
		local tag = addText(row, r.tag, 16, Color3.fromRGB(190, 170, 130), Enum.TextXAlignment.Right, 0.35)
		tag.Name = "Tag"
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Position = UDim2.new(1, -38, 0, 0)
		local lockIcon = padlockIcon(row, Color3.fromRGB(200, 165, 90))
		shopRowRefs[i] = { tag = tag, lock = lockIcon, id = r.id }
	end

	buyButton = Instance.new("TextButton")
	buyButton.Name = "GetMusicPack"
	buyButton.Text = ""
	buyButton.BackgroundColor3 = Color3.fromRGB(46, 112, 56)
	buyButton.BorderSizePixel = 0
	buyButton.AnchorPoint = Vector2.new(0.5, 1)
	buyButton.Position = UDim2.new(0.5, 0, 1, -12)
	buyButton.Size = UDim2.new(1, -24, 0, 44)
	buyButton.ZIndex = Z + 4
	buyButton.Parent = shopPlate
	corner(buyButton, 8)
	local bst = Instance.new("UIStroke"); bst.Color = rgb("goldTrim"); bst.Thickness = 1; bst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; bst.Parent = buyButton
	buyLabel = addText(buyButton, "Get Music pack", 18, CREAM, Enum.TextXAlignment.Center)
	buyButton.MouseButton1Click:Connect(function()
		local b = Picker.buyButton(GamePasses.MUSIC_PACK, ownsPack)
		if not b.enabled then return end
		pcall(function() require(script.Parent.Cue).play("button_click") end)
		pcall(function() MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, GamePasses.MUSIC_PACK) end)
	end)
	if RunService:IsStudio() and (tonumber(GamePasses.MUSIC_PACK) or 0) <= 0 then
		warn("MUSIC_PACK game pass id not set (src/Shared/Engine/GamePasses.lua)")
	end

	local function close() backdrop.Visible = false end
	pcall(function() require(script.Parent.CloseX).attach(panel, close, { inset = 8, top = 8, z = Z + 6 }) end)
	backdrop.MouseButton1Click:Connect(close)
	OverlayManager.register("music", close)
	OverlayManager.registerOpener("music", function() refresh(); resize(); backdrop.Visible = true end)
	pcall(function() require(script.Parent.PopupDismiss).attach(backdrop, { id = "music", panel = panel, close = close, button = true }) end)
	ClientSettings.onChanged(function(key) if key == "musicTrack" then pcall(apply); pcall(refresh) end end)
	refresh()
	return backdrop
end

return M
