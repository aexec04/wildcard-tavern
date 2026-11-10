--[[
	Shared/Engine/FlairUiArt.lua
	Maps flair_ui id -> rbxassetid for the Flair dressing room (Client/FlairDressingRoom.lua). Empty until the Studio
	session resolves the Decal ids in art-wip/flair_ui to Image ids and records them (generate_patron_art.py -c flair_ui
	record-image). The room builds a full code-drawn fallback for every key and lights up piece by piece. The per-item
	Flair icons live in FlairArt.lua, not here.

	Keys: flair_stage, flair_drawer_front, flair_cabinet, flair_velvet_tray, flair_medallion_ring,
	flair_medallion_ring_locked, flair_on_ribbon, flair_brass_tag, flair_sparkle_burst
]]

return {
}
