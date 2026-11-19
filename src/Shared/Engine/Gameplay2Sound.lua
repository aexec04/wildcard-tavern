--[[
	Engine/Gameplay2Sound.lua
	Gameplay v2: which existing cue (Engine/SoundIds) each moment of the table plays, and where, as data a test can check against the
	source files. No new cue is invented and no asset id is made up; a cue with an empty id stays silent (Cue.play never throws).

	MOMENTS = { { moment, cue, file, marker } ... }   `marker` is a string that must appear in `file` (a call site check)
	effective(cueVolume, scale, sfxVolume, muted) -> 0..1   the volume a cue plays at: the cue's own volume x the call's scale x the
	                                                         SFX slider, 0 when muted, never above 1
	SLIDER_STEPS                                            the slider settings the tests walk
]]

local M = {}

M.MOMENTS = {
	{ moment = "card deal", cue = "card_deal", file = "src/Client/DealFlip.lua", marker = '"card_deal"' },
	{ moment = "card select", cue = "card_select", file = "src/Client/init.client.lua", marker = '"card_select"' },
	{ moment = "card play", cue = "card_play", file = "src/Client/init.client.lua", marker = '"card_play"' },
	{ moment = "discard", cue = "discard", file = "src/Client/init.client.lua", marker = "SOUND_IDS.discard" },
	{ moment = "score tick", cue = "score_tick", file = "src/Client/Gameplay2ScoreFX.lua", marker = '"score_tick"' },
	{ moment = "score total", cue = "score_total", file = "src/Client/Gameplay2ScoreFX.lua", marker = '"score_total"' },
	{ moment = "Patron trigger", cue = "patron_trigger", file = "src/Client/PatronRow.lua", marker = '"patron_trigger"' },
	{ moment = "coin", cue = "coin", file = "src/Client/RoundRewardBanner.lua", marker = '"coin"' },
	{ moment = "round clear", cue = "round_clear", file = "src/Client/RoundRewardBanner.lua", marker = '"round_clear"' },
	{ moment = "defeat", cue = "defeat", file = "src/Client/GameOver.lua", marker = '"defeat"' },
	{ moment = "Patron tooltip", cue = "hover", file = "src/Client/PatronTipFX.lua", marker = '"hover"' },
	{ moment = "shop buy", cue = "shop_buy", file = "src/Client/ShopScene.lua", marker = '"shop_buy"' },
	{ moment = "nothing selected", cue = "shop_cant", file = "src/Client/Gameplay2FeelFX.lua", marker = '"shop_cant"' },
}

-- cues that may stay silent until an id is pasted in (SoundFX.EMPTY_OK); the call site must still exist
M.SILENT_OK = {
	{ moment = "boss entrance", cue = "boss_intro", file = "src/Client/Gameplay2MomentsFX.lua", marker = '"boss_intro"' },
}

M.SLIDER_STEPS = { 0, 0.1, 0.25, 0.5, 0.75, 1 }

function M.effective(cueVolume, scale, sfxVolume, muted)
	if muted then return 0 end
	local v = (tonumber(cueVolume) or 0) * (tonumber(scale) or 1) * math.max(0, math.min(1, tonumber(sfxVolume) or 1))
	return math.max(0, math.min(1, v))
end

return M
