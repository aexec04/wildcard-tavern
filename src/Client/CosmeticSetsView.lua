--[[
	Client/CosmeticSetsView.lua
	Applies the equipped Cosmetic Set backdrop and the equipped card back
	(state.cosmetics.cardBackId) to the live UI.

	state.cosmetics = { equippedSetId, unlockedSetIds } (from the server).
	A set whose backdropImage is nil or "rbxassetid://0" keeps the default
	backdrop (art still to be made, see claude/ART_TODO.md). The set's
	backdropStyle (code-drawn tint, vignette, particles) is applied over every
	backdrop in HOSTS by Client/BackdropStyles.lua.

	Looks the instances up by name so init.client.lua needs no new locals.
	apply(state) is safe to call on every render; it only works on change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local CosmeticSets = require(Engine:WaitForChild("CosmeticSets"))
local CardBacks = require(Engine:WaitForChild("CardBacks"))
local ArtAssets = require(script.Parent.ArtAssets)
local BackdropStyles = require(script.Parent.BackdropStyles)
local CardBackView = require(script.Parent.CardBackView)
local TweenService = game:GetService("TweenService")

-- Backdrops that show the equipped set's style: gameplay, Shop, Round
-- Select and the Journey map. defaultTint is restored when a set has no style.
local HOSTS = {
	{ name = "GameBackgroundArt", defaultTint = Color3.fromRGB(215, 205, 195), noAmbient = true }, -- TableLook carries the gameplay ambient motion
	{ name = "TableLook", defaultTint = Color3.new(1, 1, 1) }, -- the style host above the gameplay scene painting (Client/TableLook.lua)
	{ name = "ShopBackgroundArt", defaultTint = Color3.new(1, 1, 1) },
	{ name = "RoundSelect", defaultTint = Color3.new(1, 1, 1), noAmbient = true }, -- ambient motion only on the table and the Counter
	{ name = "TavernMap", defaultTint = Color3.new(1, 1, 1), noAmbient = true },
}
local lastSearch = {} -- [host name] = os.clock() of the last PlayerGui search
local controllers = {} -- [host name] = { controller, hostInstance, styledSetId }

local lastBackId = nil
local lastSceneSet = nil
local gui = nil

local function find(name)
	gui = gui or Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not gui then return nil end
	-- A backdrop host is a scene Frame or ImageLabel, never a button or anything inside a popup: the Settings "Tavern Map" button once matched
	-- the map host by name and the Golden Gala bunting drew inside it. Scan every descendant with the name, skip GuiButtons.
	for _, d in ipairs(gui:GetDescendants()) do
		if d.Name == name and d:IsA("GuiObject") and not d:IsA("GuiButton") then return d end
	end
	return nil
end

local M = {}

-- Local-only preview (Card Sets panel "Preview"): overrides what apply() draws, never
-- touches the saved/equipped ids and never fires a remote.
local previewOverride = nil -- { setId, backId }
local lastState = nil

-- The set the table should show right now: the Card Sets "Preview" if one is running, else the equipped set.
function M.currentSet(state)
	local cosmetics = type(state) == "table" and state.cosmetics or nil
	local setId = cosmetics and cosmetics.equippedSetId or CosmeticSets.DefaultId
	if previewOverride then setId = previewOverride.setId end
	return CosmeticSets.getById(setId) or CosmeticSets.getById(CosmeticSets.DefaultId)
end

-- Whole-table theme from the set's accent: a faint wash on the side panel, the hand tray felt and a thin
-- accent frame around the table, plus the card faces (CardFace.setStyle). The default set restores today's look.
local themedFaceSetId = nil
local themeTargets = {} -- [name] = instance, so render() does not search PlayerGui every call
local function themeTarget(name)
	local inst = themeTargets[name]
	if inst and inst.Parent then return inst end
	inst = find(name)
	themeTargets[name] = inst
	return inst
end

local function applyTheme(set)
	local theme = CosmeticSets.themeOf(set)
	local SetSkin = require(script.Parent.SetSkin)
	if themedFaceSetId ~= set.id then
		themedFaceSetId = set.id
		SetSkin.set(theme.skin) -- before the faces rebuild, so they read the new skin
		local face = theme.face
		if not face.neutral then -- thin-edge ivory card: edge and pips in the set accent, frost or warm motif
			local look = CosmeticSets.cardLook(set)
			face = {}
			for k, v in pairs(theme.face) do face[k] = v end
			face.border, face.motif = look.edge, look.motif
			warn(("[SetSkin] cardLook set=%s edge=%s paper=%s motif=%s"):format(tostring(set.id), table.concat(look.edge, ","), table.concat(look.paper, ","), tostring(look.motif)))
		end
		pcall(function() require(script.Parent.CardFace).setStyle(face, set) end)
		pcall(function() require(script.Parent.GamepadMenuNav).setRingColor(CosmeticSets.focusRingOf(set.id)) end)
	end
	local accent = theme.accent and Color3.fromRGB(theme.accent[1], theme.accent[2], theme.accent[3]) or nil
	for _, name in ipairs(SetSkin.HUD_PANELS) do -- side panel, hand tray and draw pile wear the panel skin too
		local target = themeTarget(name)
		if target then SetSkin.register(target, "panel") end
	end

	-- Each target is themed once per set; targets built later (the tray is created with the first hand)
	-- are picked up on a later call.
	local board = themeTarget("SidebarBoard")
	if board and board:GetAttribute("ThemedSet") ~= set.id then
		board:SetAttribute("ThemedSet", set.id)
		local wash = board:FindFirstChild("SetAccent")
		if not wash then
			wash = Instance.new("Frame")
			wash.Name = "SetAccent"
			wash.Size = UDim2.fromScale(1, 1)
			wash.BorderSizePixel = 0
			wash.Active = false
			wash.ZIndex = 1 -- above the board art, below the content (ZIndex 3)
			wash.BackgroundTransparency = 1
			wash.Parent = board
		end
		if accent then wash.BackgroundColor3 = accent end
		wash.BackgroundTransparency = accent and 0.86 or 1
		if board:GetAttribute("PlayBoardPainted") then wash.Visible = false end -- the painted board has no accent wash (it read as a dark band)
	end

	local layers = themeTarget("TableLookLayers")
	if layers and layers:GetAttribute("ThemedSet") ~= set.id then
		layers:SetAttribute("ThemedSet", set.id)
		local edge = layers:FindFirstChild("AccentEdge")
		if not edge then
			edge = Instance.new("Frame")
			edge.Name = "AccentEdge"
			edge.Size = UDim2.fromScale(1, 1)
			edge.BackgroundTransparency = 1
			edge.BorderSizePixel = 0
			edge.Active = false
			edge.ZIndex = 0
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 7
			stroke.Transparency = 1
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = edge
			edge.Parent = layers
		end
		local stroke = edge:FindFirstChildOfClass("UIStroke")
		if stroke then
			if accent then stroke.Color = accent end
			stroke.Transparency = accent and 0.5 or 1
		end
	end

	local tray = themeTarget("HandTray")
	if tray and tray:GetAttribute("ThemedSet") ~= set.id then
		tray:SetAttribute("ThemedSet", set.id)
		local original = tray:GetAttribute("OriginalFelt")
		if not original then
			original = tray.BackgroundColor3
			tray:SetAttribute("OriginalFelt", original)
		end
		tray.BackgroundColor3 = accent and original:Lerp(accent, 0.28) or original
	end
end

-- The draw pile's frame and plate follow the equipped back and set (CosmeticSets.pileStyleOf).
local function applyPile(set, back, backId)
	local widget = themeTarget("DeckWidget")
	if not widget then return end
	local sig = tostring(backId) .. "|" .. tostring(set.id)
	if widget:GetAttribute("ThemedPile") == sig then return end
	widget:SetAttribute("ThemedPile", sig)
	local pile = CosmeticSets.pileStyleOf(set, back)
	local function c3(t) return Color3.fromRGB(t[1], t[2], t[3]) end
	widget.BackgroundColor3 = c3(pile.plate)
	local rim = widget:FindFirstChildOfClass("UIStroke")
	if rim then rim.Color = c3(pile.rim) end
	local glow = widget:FindFirstChild("PileGlow")
	if glow then
		local gs = glow:FindFirstChildOfClass("UIStroke")
		if gs then gs.Color = c3(pile.glow) end
	end
	-- the carved holder art and the board behind the card take a faint tint of the rim colour
	for _, child in ipairs({ widget:FindFirstChild("SkinArt"), widget:FindFirstChild("DeckBoard") }) do
		if child and child:IsA("ImageLabel") then
			local original = child:GetAttribute("OriginalTint")
			if not original then
				original = child.ImageColor3
				child:SetAttribute("OriginalTint", original)
			end
			child.ImageColor3 = original:Lerp(c3(pile.rim), 0.3)
		end
	end
end

-- The table scene (corner banners, set picture) and the draw pile read HudTheme.skin(), which SetSkin only updates after the set's HUD kit
-- has preloaded. Refresh the scene once that skin lands, so a Preview never leaves the previous set's banners and pile on screen.
local skinHooked = false
local function hookSkinRefresh()
	if skinHooked then return end
	skinHooked = true
	pcall(function()
		require(script.Parent.HudTheme).onSkin(function()
			local ok, scene = pcall(function() return require(script.Parent.GameplayScene).get() end)
			if ok and scene and lastState then pcall(scene.update, lastState) end
		end)
	end)
end

function M.apply(state)
	lastState = state
	hookSkinRefresh()
	local sceneSet = M.currentSet(state).id
	if sceneSet ~= lastSceneSet then
		lastSceneSet = sceneSet
		-- The scene painting (GameplayScene) follows the set; Preview only calls apply(), so refresh it here.
		local ok, scene = pcall(function() return require(script.Parent.GameplayScene).get() end)
		if ok and scene then pcall(scene.update, state) end
	end
	local cosmetics = state.cosmetics
	local setId = cosmetics and cosmetics.equippedSetId or CosmeticSets.DefaultId
	local backId = cosmetics and cosmetics.cardBackId or CardBacks.DefaultId
	if previewOverride then
		setId, backId = previewOverride.setId, previewOverride.backId
	end

	local set = CosmeticSets.getById(setId) or CosmeticSets.getById(CosmeticSets.DefaultId)

	-- Base image (gameplay only: the other backdrops have no set art yet).
	local backdrop = find("GameBackgroundArt")
	if backdrop and backdrop:GetAttribute("AppliedSetId") ~= set.id then
		local image = set.scenery
		if not image or image == "rbxassetid://0" then image = set.backdropImage end
		if image and image ~= "rbxassetid://0" then
			backdrop.Image = image
		else
			backdrop.Image = ArtAssets.gameplayBackground or "rbxassetid://0"
		end
		backdrop:SetAttribute("AppliedSetId", set.id)
	end

	applyTheme(set)

	-- Style stack over each backdrop. A host that did not exist yet (Shop,
	-- Round Select and the map are built on demand) is picked up on a later call.
	for _, host in ipairs(HOSTS) do
		local entry = controllers[host.name]
		local instance = entry and entry.instance.Parent and entry.instance or nil
		if not instance and os.clock() - (lastSearch[host.name] or -10) > 1 then
			lastSearch[host.name] = os.clock()
			instance = find(host.name)
		end
		if instance and (not entry or entry.instance ~= instance) then
			entry = { controller = BackdropStyles.attach(instance, { defaultTint = host.defaultTint }), instance = instance }
			controllers[host.name] = entry
		end
		if entry and entry.styledSetId ~= set.id then
			local ok = pcall(entry.controller.setStyle, CosmeticSets.hostStyleOf(set, host.name)) -- Round Select and the Counter get no tint, overlay or vignette
			if not host.noAmbient then pcall(entry.controller.setAmbient, set.id) end -- living backdrop: butterflies, clouds, snow ...
			entry.styledSetId = set.id -- even on failure: don't retry every render
			if not ok then
				warn("Backdrop style failed for " .. host.name)
			end
		end
	end

	-- The card back is separate from the set: the player can pick any
	-- unlocked back, or follow the set's.
	local back = CardBacks.getById(backId)
	if backId ~= lastBackId then
		local cardArt = find("CardBackArt")
		if cardArt and back then
			local painted = CardBackView.imageFor(backId)
			local function applyArt(label)
				if painted then
					label.Image = painted
					label.ScaleType = Enum.ScaleType.Crop
					-- the default back is warmed to copper and bronze so it sits with the wood and parchment of the room; other backs keep their own colours
					label.ImageColor3 = backId == CardBacks.DefaultId and Color3.fromRGB(236, 150, 120) or Color3.new(1, 1, 1)
				else
					label.Image = ArtAssets.cardBackTemplate or "rbxassetid://0"
					label.ScaleType = Enum.ScaleType.Stretch
					if backId == CardBacks.DefaultId then
						label.ImageColor3 = Color3.fromRGB(236, 150, 120) -- the default back is warmed to copper and bronze: pure blue sat apart from the wood and parchment of the room
					else
						local c = back.colors.base
						label.ImageColor3 = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(c[1], c[2], c[3]), 0.6)
					end
				end
			end
			for _, name in ipairs({ "StackBackA", "StackBackB", "StackBackC", "StackBackD", "StackBackE" }) do
				local stack = find(name)
				if stack then
					applyArt(stack)
				end
			end
			if lastBackId == nil or not require(script.Parent.ClientSettings).motionAllowed() then
				applyArt(cardArt) -- first paint, or Calm and Reduce motion: no flip
			else
				-- Equip moment: flip the pile (scale X 1 -> 0 -> 1 over 0.35s), swapping the art at the midpoint.
				local flipId = backId
				local half = TweenInfo.new(0.175, Enum.EasingStyle.Sine)
				local close = TweenService:Create(cardArt, half, { Size = UDim2.fromScale(0, 1) })
				close.Completed:Once(function()
					if lastBackId == flipId then
						applyArt(cardArt)
					end
					TweenService:Create(cardArt, half, { Size = UDim2.fromScale(1, 1) }):Play()
				end)
				close:Play()
			end
			lastBackId = backId
		end
	end

	applyPile(set, back, backId)

	-- Theme: the equipped back's trim color tints the hand tray rim at low strength.
	-- The default back keeps today's gold.
	local tray = find("HandTray")
	if tray and tray:GetAttribute("TintedBack") ~= backId then
		tray:SetAttribute("TintedBack", backId)
		local trim = back and back.colors.trim
		for _, stroke in ipairs({ tray:FindFirstChildOfClass("UIStroke"), tray:FindFirstChild("InnerRim") and tray.InnerRim:FindFirstChildOfClass("UIStroke") }) do
			if stroke then
				local original = stroke:GetAttribute("OriginalColor")
				if not original then
					original = stroke.Color
					stroke:SetAttribute("OriginalColor", original)
				end
				if trim and backId ~= CardBacks.DefaultId then
					stroke.Color = original:Lerp(Color3.fromRGB(trim[1], trim[2], trim[3]), 0.45)
				else
					stroke.Color = original
				end
			end
		end
	end
end

-- Show a set (backdrop, style and its back) on the live table, locally only.
local previewListeners = {}
local function notifyPreview()
	for _, fn in ipairs(previewListeners) do pcall(fn) end
end

-- Backdrops (menu, shop, map) listen here so a preview dresses them too. Returns nothing; listeners live for the session.
function M.onPreview(fn) previewListeners[#previewListeners + 1] = fn end
function M.previewSetId() return previewOverride and previewOverride.setId or nil end

function M.preview(setId, backId)
	previewOverride = { setId = setId, backId = backId }
	if lastState then
		M.apply(lastState)
	end
	notifyPreview()
end

function M.stopPreview()
	if not previewOverride then
		return
	end
	previewOverride = nil
	if lastState then
		M.apply(lastState)
	end
	notifyPreview()
end

function M.isPreviewing()
	return previewOverride ~= nil
end

return M
