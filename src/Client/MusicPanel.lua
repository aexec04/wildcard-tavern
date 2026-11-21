--[[
	Client/MusicPanel.lua
	The Music panel: the soundtrack choices (rules in Engine/MusicPicker, tested), a tick on the chosen one, a "Music pack" lock on the
	extra tracks until the pass is owned, and a Get Music pack button (MarketplaceService:PromptGamePassPurchase for GamePasses.MUSIC_PACK;
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

local function rgb(name) local c = Style.rgb(name); return Color3.fromRGB(c[1], c[2], c[3]) end

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

local function refresh()
	if not rowsHost then return end
	local selected = Picker.effective(ClientSettings.get("musicTrack"), ownsPack)
	for _, row in ipairs(rowsHost:GetChildren()) do
		if row:IsA("GuiButton") then
			local t = row:GetAttribute("TrackId")
			row.Tick.Visible = (t == selected)
			row.Lock.Visible = row:GetAttribute("Pack") == true and not ownsPack
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

	local panel = Instance.new("Frame")
	panel.Name = "MusicPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(360, 56 + #Picker.TRACKS * 52 + 76)
	panel.BackgroundColor3 = rgb("plateDark")
	panel.BorderSizePixel = 0
	panel.ZIndex = Z + 1
	panel.Parent = backdrop
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 12); pc.Parent = panel
	local ps = Instance.new("UIStroke"); ps.Color = rgb("goldTrim"); ps.Thickness = 2; ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ps.Parent = panel
	local fit = Instance.new("UISizeConstraint"); fit.MaxSize = Vector2.new(360, 9999); fit.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -64, 0, 40)
	title.Position = UDim2.fromOffset(16, 8)
	title.Font = Enum.Font[Style.FONTS.title]
	title.Text = "Music"
	title.TextSize = 24
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 214, 130)
	title.ZIndex = Z + 2
	title.Parent = panel

	rowsHost = Instance.new("Frame")
	rowsHost.Name = "Tracks"
	rowsHost.BackgroundTransparency = 1
	rowsHost.Position = UDim2.fromOffset(12, 56)
	rowsHost.Size = UDim2.new(1, -24, 0, #Picker.TRACKS * 52)
	rowsHost.ZIndex = Z + 2
	rowsHost.Parent = panel
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = rowsHost

	local function text(parent, str, size, color, align, w)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(w or 1, 0, 1, 0)
		l.Font = Enum.Font[Style.FONTS.ui]
		l.Text = str
		l.TextSize = size
		l.TextColor3 = color
		l.TextXAlignment = align or Enum.TextXAlignment.Left
		l.TextTransparency, l.TextStrokeTransparency = 0, 1
		l.ZIndex = Z + 4
		l.Parent = parent
		return l
	end

	for i, t in ipairs(Picker.list(false)) do
		local row = Instance.new("TextButton")
		row.Name = "Track_" .. t.id
		row.LayoutOrder = i
		row.Text = ""
		row.AutoButtonColor = false
		row.BackgroundColor3 = rgb("brown")
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 44)
		row.ZIndex = Z + 3
		row:SetAttribute("TrackId", t.id)
		row:SetAttribute("Pack", t.pack)
		row.Parent = rowsHost
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 8); rc.Parent = row
		local name = text(row, t.name, 18, Color3.fromRGB(250, 238, 212), Enum.TextXAlignment.Left, 0.6)
		name.Position = UDim2.fromOffset(14, 0)
		local lock = text(row, "Music pack", 14, Color3.fromRGB(246, 196, 70), Enum.TextXAlignment.Right, 0.4)
		lock.Name = "Lock"
		lock.AnchorPoint = Vector2.new(1, 0)
		lock.Position = UDim2.new(1, -12, 0, 0)
		lock.Visible = t.pack
		local tick = text(row, "Playing", 14, Color3.fromRGB(150, 220, 150), Enum.TextXAlignment.Right, 0.4)
		tick.Name = "Tick"
		tick.AnchorPoint = Vector2.new(1, 0)
		tick.Position = UDim2.new(1, -12, 0, 0)
		tick.Visible = false
		row.MouseButton1Click:Connect(function()
			pcall(function() require(script.Parent.Cue).play("button_click") end)
			if Picker.effective(t.id, ownsPack) ~= t.id then return end -- a locked track does nothing but show its lock
			ClientSettings.set("musicTrack", t.id)
			apply(); refresh()
		end)
	end

	buyButton = Instance.new("TextButton")
	buyButton.Name = "GetMusicPack"
	buyButton.Text = ""
	buyButton.BackgroundColor3 = Color3.fromRGB(46, 112, 56)
	buyButton.BorderSizePixel = 0
	buyButton.AnchorPoint = Vector2.new(0.5, 1)
	buyButton.Position = UDim2.new(0.5, 0, 1, -14)
	buyButton.Size = UDim2.new(1, -32, 0, 48)
	buyButton.ZIndex = Z + 3
	buyButton.Parent = panel
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = buyButton
	buyLabel = text(buyButton, "Get Music pack", 18, Color3.fromRGB(250, 238, 212), Enum.TextXAlignment.Center)
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
	OverlayManager.registerOpener("music", function() refresh(); backdrop.Visible = true end)
	pcall(function() require(script.Parent.PopupDismiss).attach(backdrop, { id = "music", panel = panel, close = close, button = true }) end)
	ClientSettings.onChanged(function(key) if key == "musicTrack" then pcall(apply); pcall(refresh) end end)
	refresh()
	return backdrop
end

return M
