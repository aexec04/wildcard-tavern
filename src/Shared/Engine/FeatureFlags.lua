--[[
	Engine/FeatureFlags.lua
	One switch per old (Gilded Knave v1) feature that the focused remake hides. A flag that is false means the icon or button is not
	created, its opener does nothing and nothing registers for it. Nothing is deleted: set LEGACY_V1 = true to turn every flag on, or
	set one flag true to bring one feature back. claude/GILDED-KNAVE-V1.md lists where each flag is read.

	enabled(name) -> bool    LEGACY_V1 wins over the single flag
	cornerIcon(name) -> bool the five round corner icons: "volume", "journey", "handRef", "settings", "collection"
	setOverride(name, v)     tests only: force one flag, nil clears it
]]

local M = {}

M.LEGACY_V1 = false

-- Every opener found, default off (the remake shows HUD pills, Round bar, Patron row, hand, deck, Play Hand and Discard).
M.FLAGS = {
	JOURNEY_MAP = false,    -- corner Journey icon (Client/Journey.lua opener)
	TOME_COLLECTION = false, -- corner Collection icon (Client/Collection.lua opener)
	SETTINGS = false,        -- corner gear (Client/Settings.lua opener, ConceptTPlay gear move)
	VOLUME_PANEL = false,    -- corner speaker (Client/VolumePanel.lua opener)
	RECIPES = false,         -- corner Poker Hands reference icon (Client/PokerHandsReference.lua opener)
	DAILY_BOARD = false,
	NOTICE_BOARD = false,
	HAGGLE_COUNTER = false,
	PACK_ROOM = false,
	SEASON = false,
	STOREFRONT = false,
}

-- corner icon name -> the flag that owns it
M.CORNER = {
	volume = "VOLUME_PANEL",
	journey = "JOURNEY_MAP",
	handRef = "RECIPES",
	settings = "SETTINGS",
	collection = "TOME_COLLECTION",
}

local overrides = {}

function M.enabled(name)
	if overrides[name] ~= nil then return overrides[name] end
	if M.LEGACY_V1 then return true end
	return M.FLAGS[name] == true
end

function M.cornerIcon(name)
	local flag = M.CORNER[name]
	return flag ~= nil and M.enabled(flag)
end

function M.setOverride(name, v) overrides[name] = v end

return M
