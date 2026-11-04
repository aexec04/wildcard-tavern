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

function M.apply(state)
	local cosmetics = state.cosmetics
	local setId = cosmetics and cosmetics.equippedSetId or CosmeticSets.DefaultId
	local backId = cosmetics and cosmetics.cardBackId or CardBacks.DefaultId

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
	if backId ~= lastBackId then
		local cardArt = find("CardBackArt")
		local back = CardBacks.getById(backId)
		if cardArt and back then
			if backId == CardBacks.DefaultId then
				cardArt.ImageColor3 = Color3.new(1, 1, 1)
			else
				local c = back.colors.base
				local base = Color3.fromRGB(c[1], c[2], c[3])
				cardArt.ImageColor3 = Color3.new(1, 1, 1):Lerp(base, 0.6)
			end
			lastBackId = backId
		end
	end
end

return M
