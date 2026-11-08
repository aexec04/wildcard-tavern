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
	{ name = "GameBackgroundArt", defaultTint = Color3.fromRGB(215, 205, 195) },
	{ name = "ShopBackgroundArt", defaultTint = Color3.new(1, 1, 1) },
	{ name = "RoundSelect", defaultTint = Color3.new(1, 1, 1) },
	{ name = "TavernMap", defaultTint = Color3.new(1, 1, 1) },
}
local lastSearch = {} -- [host name] = os.clock() of the last PlayerGui search
local controllers = {} -- [host name] = { controller, hostInstance, styledSetId }

local lastBackId = nil
local gui = nil

local function find(name)
	gui = gui or Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	return gui and gui:FindFirstChild(name, true) or nil
end

local M = {}

-- Local-only preview (Card Sets panel "Preview"): overrides what apply() draws, never
-- touches the saved/equipped ids and never fires a remote.
local previewOverride = nil -- { setId, backId }
local lastState = nil

function M.apply(state)
	lastState = state
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
		local image = set.backdropImage
		if image and image ~= "rbxassetid://0" then
			backdrop.Image = image
		else
			backdrop.Image = ArtAssets.gameplayBackground or "rbxassetid://0"
		end
		backdrop:SetAttribute("AppliedSetId", set.id)
	end

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
			local ok = pcall(entry.controller.setStyle, set.backdropStyle)
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
					label.ImageColor3 = Color3.new(1, 1, 1)
				else
					label.Image = ArtAssets.cardBackTemplate or "rbxassetid://0"
					label.ScaleType = Enum.ScaleType.Stretch
					if backId == CardBacks.DefaultId then
						label.ImageColor3 = Color3.new(1, 1, 1)
					else
						local c = back.colors.base
						label.ImageColor3 = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(c[1], c[2], c[3]), 0.6)
					end
				end
			end
			for _, name in ipairs({ "StackBackA", "StackBackB" }) do
				local stack = find(name)
				if stack then
					applyArt(stack)
				end
			end
			if lastBackId == nil then
				applyArt(cardArt)
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
function M.preview(setId, backId)
	previewOverride = { setId = setId, backId = backId }
	if lastState then
		M.apply(lastState)
	end
end

function M.stopPreview()
	if not previewOverride then
		return
	end
	previewOverride = nil
	if lastState then
		M.apply(lastState)
	end
end

function M.isPreviewing()
	return previewOverride ~= nil
end

return M
