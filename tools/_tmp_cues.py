p = 'src/Shared/Engine/SoundIds.lua'
s = open(p).read()
old = '\tscroll_close = { id = "rbxassetid://9118838541", volume = 0.35, maxLength = 0.7 }, -- it closes (ProSoundEffects "Scraping Brisk Plastic Wood 1")\n}'
new = '''\tscroll_close = { id = "rbxassetid://9118838541", volume = 0.35, maxLength = 0.7 }, -- it closes (ProSoundEffects "Scraping Brisk Plastic Wood 1")
	-- Backlog 6 named cues with no id yet (chat Claude fills them from the Roblox audio library; an empty id plays nothing)
	score_tick = { id = "", volume = 0.35, maxLength = 0.3 }, -- each card or chip beat while a hand scores
	score_total = { id = "", volume = 0.6 }, -- the final total lands
	patron_trigger = { id = "", volume = 0.45, maxLength = 0.6 }, -- a Patron's effect fires (Client/PatronRow.trigger)
	round_clear = { id = "", volume = 0.6 }, -- Round Complete plate (Client/RoundRewardBanner)
	defeat = { id = "", volume = 0.5 }, -- the run is lost (Run Over screen)
}'''
assert old in s
s = s.replace(old, new, 1)
old = '"shop_enter", "shop_buy", "shop_reroll", "shop_cant", "page_turn", "scroll_open", "scroll_close",\n}'
new = '''"shop_enter", "shop_buy", "shop_reroll", "shop_cant", "page_turn", "scroll_open", "scroll_close",
	"score_tick", "score_total", "patron_trigger", "round_clear", "defeat",
}

-- the eleven cue names the backlog asked for; every one must exist in Cues (an empty id is a safe no-op)
SoundIds.Named = { "card_deal", "card_select", "card_play", "score_tick", "score_total", "patron_trigger", "coin", "round_clear", "defeat", "button_click", "shop_buy" }'''
assert old in s
s = s.replace(old, new, 1)
open(p, 'w').write(s)

p = 'src/Shared/Tests/EngineTests.lua'
s = open(p).read()
old = '''		"shop_enter", "shop_buy", "shop_reroll", "shop_cant", "page_turn", "scroll_open", "scroll_close" }
	expectEqual(#S.CueOrder, #required)'''
new = '''		"shop_enter", "shop_buy", "shop_reroll", "shop_cant", "page_turn", "scroll_open", "scroll_close",
		"score_tick", "score_total", "patron_trigger", "round_clear", "defeat" }
	expectEqual(#S.CueOrder, #required)
	for _, name in ipairs(S.Named) do expectEqual(S.Cues[name] ~= nil, true, "named cue " .. name) end
	for _, name in ipairs({ "score_tick", "score_total", "patron_trigger", "round_clear", "defeat" }) do
		expectEqual(S.cueId(name), nil, name .. " has no id yet, so it plays nothing")
	end'''
assert old in s
s = s.replace(old, new, 1)
open(p, 'w').write(s)

p = 'src/Client/RoundRewardBanner.lua'
s = open(p).read()
old = '\tpcall(function() require(script.Parent.Cue).play("coin", 2) end)\n'
new = old + '\tpcall(function() require(script.Parent.Cue).play("round_clear", 3) end) -- no id yet: silent\n'
assert old in s
s = s.replace(old, new, 1)
open(p, 'w').write(s)
print("ok")
