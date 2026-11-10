--[[
	Shared/Engine/BadgeWallArt.lua
	Maps badge_wall id -> rbxassetid for the Badges trophy wall (Client/BadgeWall.lua). Empty until the Studio session
	resolves the Decal ids in art-wip/badge_wall to Image ids and records them (generate_patron_art.py -c badge_wall
	record-image). The wall builds a full code-drawn fallback for every key, so it looks right with this table empty.

	Keys: badge_cabinet, badge_velvet_board, badge_map_board, badge_night_sky, badge_curio_shelf, badge_nameplate,
	badge_hook_pin, badge_spotlight, badge_shelf_rail, badge_ribbon_banner, badge_glass_glare
]]

return {
}
