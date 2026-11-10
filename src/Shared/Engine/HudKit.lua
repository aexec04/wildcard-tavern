--[[
	Shared/Engine/HudKit.lua
	Per-Card-Set HUD kit: painted left panel frame, section plates, icons and the five top-right round buttons.
	Art map: HudKitArt.lua (generated, keys "<setid>__<piece>", category hud_kit). Pure, no Roblox services.

	Phase 1: only KIT_SETS have art. Every other set is listed in PENDING and keeps the code-drawn look (flat palette,
	tinted medallion buttons); a missing Image id for any piece also falls back to that look.

	  HudKit.piece(setId, piece) -> "rbxassetid://..." or nil
	  HudKit.images(setId)       -> { piece = id } with only the pieces that have an id, or nil when the set has none
	  HudKit.hasKit(setId)       -> true when the set has all 17 pieces
	  HudKit.status(setId)       -> "kit" | "partial" | "pending"
]]

local HudKitArt = require(script.Parent.HudKitArt)

local HudKit = {}

HudKit.PIECES = {
	"panel_frame", "banner", "score_track", "reward", "tile", "patron_tray", "purse_row",
	"icon_target", "icon_tips", "icon_hands", "icon_discards", "icon_slot",
	"btn_volume", "btn_journey", "btn_hand_ref", "btn_settings", "btn_collection",
}

-- Sets whose kit is generated (phase 1). Frosted Garden is the set with id winter_evening.
HudKit.KIT_SETS = { "meadow_picnic", "winter_evening", "classic_tavern" }

-- Sets still waiting for a kit (explicit, so a new set cannot silently lack one). Tests keep this and KIT_SETS in step with CosmeticSets.
HudKit.PENDING = {
	"festival_night", "closing_time", "golden_gala", "riverside_evening", "summit_camp",
	"dune_market", "marsh_lanterns", "snowy_hearth", "harbor_lights", "tavern_feast", "harvest_table", "winter_table",
}

-- Left panel pieces that wear a painted plate: sidebar instance name -> kit piece (Client/SidebarTheme looks them up by name).
HudKit.PLATES = {
	RewardPlate = "reward", TipsRow = "tile", HandsTile = "tile", DiscardsTile = "tile",
	PatronsTray = "patron_tray", BlessingChip = "purse_row",
}
-- Sidebar icon holder name (Sidebar.makeIcon key) -> kit icon piece that replaces the stock icon.
HudKit.ICONS = { target_score = "icon_target", coin_purse = "icon_tips", hands_cards = "icon_hands", discard_bin = "icon_discards" }

function HudKit.key(setId, piece)
	return tostring(setId) .. "__" .. tostring(piece)
end

function HudKit.piece(setId, piece)
	local id = HudKitArt[HudKit.key(setId, piece)]
	if type(id) == "string" and id ~= "" and id ~= "rbxassetid://0" then return id end
	return nil
end

function HudKit.images(setId)
	if not setId then return nil end
	local out, any = {}, false
	for _, piece in ipairs(HudKit.PIECES) do
		local id = HudKit.piece(setId, piece)
		if id then out[piece] = id any = true end
	end
	return any and out or nil
end

function HudKit.hasKit(setId)
	for _, piece in ipairs(HudKit.PIECES) do
		if not HudKit.piece(setId, piece) then return false end
	end
	return true
end

function HudKit.status(setId)
	if HudKit.hasKit(setId) then return "kit" end
	return HudKit.images(setId) and "partial" or "pending"
end

return HudKit
