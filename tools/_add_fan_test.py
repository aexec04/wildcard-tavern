p = 'src/Shared/Tests/EngineTests.lua'
s = open(p).read()
t = '''table.insert(tests, { name = "Hand fan: 7 to 9 cards stay centred on the Play Hand and Discard pair, span at least 45 percent, 24 px clear of the deck", fn = function()
	local L = require(script.Parent.Parent.Engine.Gameplay2Layout)
	local CT = require(script.Parent.Parent.Engine.ConceptTLayout)
	local HS = require(script.Parent.Parent.Engine.HandSizing)
	for _, sz in ipairs({ { 1920, 957 }, { 1920, 1080 }, { 1280, 720 } }) do
		local w, h = sz[1], sz[2]
		local r = L.rects(w, h)
		local pair = (r.play.x + r.discard.x + r.discard.w) / 2
		for n = 7, 9 do
			local f = HS.frameFor(w, CT.handFor(r.hand, w, n), math.max(n, 8))
			local cw = HS.cardSize(w, f.w, f.h, n)
			local span = HS.fanSpan(w, cw, n)
			local c = f.x + f.w / 2
			assert(math.abs(c - pair) <= 12, w .. "x" .. h .. " n=" .. n .. " fan centre " .. c .. " vs pair " .. pair)
			assert(span >= 0.45 * w, w .. "x" .. h .. " n=" .. n .. " span " .. span)
			assert(c + span / 2 <= r.deck.x - 24, w .. "x" .. h .. " n=" .. n .. " clear of the deck")
		end
	end
end })

'''
k = 'table.insert(tests, { name = "TavernLife: fire 0.9'
assert k in s
s = s.replace(k, t + k, 1)
open(p, 'w').write(s)
