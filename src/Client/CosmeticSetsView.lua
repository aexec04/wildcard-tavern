--[[
	Client/CosmeticSetsView.lua
	Applies the equipped Cosmetic Set backdrop and the equipped card back
	(state.cosmetics.cardBackId) to the live UI.

	state.cosmetics = { equippedSetId, unlockedSetIds } (from the server).
	A set whose backdropImage is nil or "rbxassetid://0" keeps the default
	backdrop (art still to be made, see claude/ART_TODO.md).

	Looks the instances up by name so init.client.lua needs no new locals.
	apply(state) is safe to call on every render; it only works on change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local CosmeticSets = require(Engine:WaitForChild("CosmeticSets"))
local CardBacks = require(Engine:WaitForChild("CardBacks"))
local ArtAssets = require(script.Parent.ArtAssets)

local DEFAULT_BACKDROP_TINT = Color3.fromRGB(215, 205, 195)

local lastSetId = nil
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

	if setId ~= lastSetId then
		local set = CosmeticSets.getById(setId) or CosmeticSets.getById(CosmeticSets.DefaultId)
		local backdrop = find("GameBackgroundArt")
		if backdrop then
			local image = set.backdropImage
			if image and image ~= "rbxassetid://0" then
				backdrop.Image = image
			else
				backdrop.Image = ArtAssets.gameplayBackground or "rbxassetid://0"
			end
			backdrop.ImageColor3 = DEFAULT_BACKDROP_TINT
		end
		lastSetId = setId
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
