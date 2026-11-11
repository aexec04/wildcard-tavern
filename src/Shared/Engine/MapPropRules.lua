--[[
	Shared/Engine/MapPropRules.lua
	Which Tavern Map props may be drawn, and how wide a label plate may be.
	OPAQUE lists map_decor ids whose PNG has a baked dark background (a hard square on the map).
	While an id is listed it is not drawn; remove it once a transparent version is recorded.
]]
local M = {}

-- Every map_decor id is opaque until re-exported with a transparent background.
M.OPAQUE = {
	pine_tree = true, cottage = true, windmill = true, signpost = true, compass_rose = true, bridge = true,
	mushroom_ring = true, lantern_post = true, cactus = true, palm_tree = true, reed_cluster = true,
	igloo = true, sailboat = true, lighthouse = true, tent = true, seashell = true,
}

function M.isDrawable(key)
	return not M.OPAQUE[key]
end

M.PLATE_PAD = 12

-- Plate width for a label: text plus PLATE_PAD each side, never above maxW.
function M.plateWidth(textW, maxW)
	local w = math.ceil(textW) + M.PLATE_PAD * 2
	return maxW and math.min(w, maxW) or w
end

return M
