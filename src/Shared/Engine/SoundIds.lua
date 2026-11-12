--[[
	SoundIds.lua
	One table of named audio cues and music tracks. Pure data plus tiny helpers, so it runs under plain
	Lua and is unit tested. `Client/Sound.lua` reads it (`playCue`, `setMusicTrack`).

	An empty id ("") means "not picked yet": Sound.lua skips that cue silently. Never invent asset ids;
	pick them from the Roblox audio library and paste them here. `SoundIds.missingCues()` and
	`SoundIds.missingMusic()` list what still needs an id.

	Volumes are per-cue (0 to 1). The player's SFX slider, Mute and the Music slider (Volume panel)
	are applied on top by Sound.lua, so they are not part of this table.
]]

local SoundIds = {}

-- name -> { id = "rbxassetid://<digits>" or "", volume = 0..1, maxLength = seconds? }
SoundIds.Cues = {
	card_deal = { id = "rbxassetid://9114035597", volume = 0.35, maxLength = 0.6 }, -- reuses the deck-flick clip
	card_select = { id = "rbxassetid://9117308777", volume = 3, maxLength = 0.35 },
	card_play = { id = "rbxassetid://9113727134", volume = 0.6 },
	shuffle = { id = "rbxassetid://9114035457", volume = 0.5, maxLength = 1.3, fade = 0.2 }, -- ProSoundEffects "Deck Of Cards 5" (3.9 s with chips at the tail): cut to 1.3 s with a 0.2 s fade
	card_flip = { id = "", volume = 0.35, maxLength = 0.4 }, -- the deal flip (Client/DealFlip.lua)
	discard = { id = "", volume = 0.5 }, -- a Discard was used (Client/FeelHooks.lua)
	chip = { id = "rbxassetid://7381722372", volume = 0.4 },
	chip_big = { id = "rbxassetid://7381723507", volume = 0.5 },
	coin = { id = "rbxassetid://133292918309565", volume = 0.5 },
	buy = { id = "rbxassetid://128537772502751", volume = 0.6 },
	button_click = { id = "rbxassetid://9118728158", volume = 0.35, maxLength = 0.25 },
	hover = { id = "", volume = 0.15 },
	boss_intro = { id = "", volume = 0.6 },
	boss_defeat = { id = "", volume = 0.6 },
	win = { id = "rbxassetid://1170853519", volume = 0.5 },
	lose = { id = "rbxassetid://7381722902", volume = 0.5 },
	map_open = { id = "", volume = 0.4 },
	road_choose = { id = "", volume = 0.5 },
	compass_turn = { id = "", volume = 0.3 },
	shop_enter = { id = "", volume = 0.4 }, -- Peddler greets you (Client/ShopScene.lua)
	shop_buy = { id = "", volume = 0.5 },
	shop_reroll = { id = "", volume = 0.4 },
	shop_cant = { id = "", volume = 0.3 },
	page_turn = { id = "rbxassetid://9118835414", volume = 0.5, maxLength = 1.0, startAt = 0.8, fade = 0.25 }, -- Tavern Ledger page or tab change (ProSoundEffects "Scrapbook Open And Turn Pages 2")
	scroll_open = { id = "rbxassetid://9118835650", volume = 0.45, maxLength = 1.9 }, -- any scroll or panel popup opens (Client/PopupShield.lua; ProSoundEffects "Scrapbook Open And Turn Pages 6")
	scroll_close = { id = "rbxassetid://9118838541", volume = 0.35, maxLength = 0.7 }, -- it closes (ProSoundEffects "Scraping Brisk Plastic Wood 1")
}

-- Optional alternates for the coin cascade (not the default, so nothing regresses): try them in Studio with DebugGoto "sfx:<cue>".
SoundIds.CoinAlternates = { "rbxassetid://9113849583", "rbxassetid://9121189379" } -- "Coin Throws 2" (2.4 s), "BagOfCoins"

-- Display/iteration order (pairs order is not stable).
SoundIds.CueOrder = {
	"card_deal", "card_select", "card_play", "shuffle", "card_flip", "discard", "chip", "chip_big", "coin", "buy", "button_click",
	"hover", "boss_intro", "boss_defeat", "win", "lose", "map_open", "road_choose", "compass_turn",
	"shop_enter", "shop_buy", "shop_reroll", "shop_cant", "page_turn", "scroll_open", "scroll_close",
}

-- Music tracks by key. `region_<id>` plays on the gameplay table while the Night's stop is in that region
-- (empty = fall back to the plain gameplay track).
SoundIds.Music = {
	menu = "rbxassetid://137023744071437",
	gameplay = "rbxassetid://132846105965979",
	shop = "rbxassetid://86731472483471",
	boss = "rbxassetid://133804416597931",
	region_road = "",
	region_meadow = "",
	region_river = "",
	region_peaks = "",
	region_desert = "",
	region_swamp = "",
	region_snow = "",
	region_coast = "",
	region_tavern = "",
}

SoundIds.MusicOrder = {
	"menu", "gameplay", "shop", "boss", "region_road", "region_meadow", "region_river", "region_peaks",
	"region_desert", "region_swamp", "region_snow", "region_coast", "region_tavern",
}

-- Gameplay-table music keys: the plain gameplay track and one per biome. Changing between them crossfades.
function SoundIds.isTableKey(key)
	return key == "gameplay" or (type(key) == "string" and string.sub(key, 1, 7) == "region_")
end

-- Crossfade (fade out, swap, fade in) only between two gameplay-table tracks, never for menu, shop or boss music.
function SoundIds.shouldCrossfade(fromKey, toKey)
	return fromKey ~= nil and fromKey ~= toKey and SoundIds.isTableKey(fromKey) and SoundIds.isTableKey(toKey)
end

function SoundIds.isValidId(id)
	return type(id) == "string" and string.match(id, "^rbxassetid://%d+$") ~= nil and id ~= "rbxassetid://0"
end

-- The id for a cue, or nil when the cue is unknown or has no id yet.
function SoundIds.cueId(name)
	local cue = SoundIds.Cues[name]
	if cue and SoundIds.isValidId(cue.id) then
		return cue.id
	end
	return nil
end

-- Music key for a gameplay table in `regionId`; falls back to "gameplay" when that region has no track.
function SoundIds.regionMusicKey(regionId)
	local key = "region_" .. tostring(regionId)
	if SoundIds.isValidId(SoundIds.Music[key]) then
		return key
	end
	return "gameplay"
end

function SoundIds.missingCues()
	local out = {}
	for _, name in ipairs(SoundIds.CueOrder) do
		if not SoundIds.cueId(name) then
			table.insert(out, name)
		end
	end
	return out
end

-- Cues that still make no sound at all: no id of their own and no composite layers (Engine/SoundFX.Layers). Only boss_intro stays silent.
function SoundIds.silentCues()
	local ok, SoundFX = pcall(function() return require(script.Parent.SoundFX) end)
	local out = {}
	for _, name in ipairs(SoundIds.CueOrder) do
		local layered = ok and SoundFX.layersFor(name) ~= nil
		if not SoundIds.cueId(name) and not layered then
			table.insert(out, name)
		end
	end
	return out
end

function SoundIds.missingMusic()
	local out = {}
	for _, key in ipairs(SoundIds.MusicOrder) do
		if not SoundIds.isValidId(SoundIds.Music[key]) then
			table.insert(out, key)
		end
	end
	return out
end

return SoundIds
