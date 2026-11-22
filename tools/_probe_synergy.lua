-- Patron synergy probe: each Patron alone and every pair on sample hands. Run: lua tools/_probe_synergy.lua
local toolsDir = arg[0]:match("(.*)/_probe_synergy%.lua$") or "."
package.path = toolsDir .. "/sim/?.lua;" .. package.path
local E = require("EngineLoader").load(toolsDir .. "/../src/Shared")
local Card, HE, Scoring, Patrons = E.Card, E.HandEvaluator, E.Scoring, E.Patrons
local function C(r, s) return Card.new(r, s) end
local HANDS = {
	{ "High Card", { C(2,"Hearts"), C(5,"Spades"), C(7,"Diamonds"), C(9,"Clubs"), C(13,"Hearts") } },
	{ "Pair", { C(8,"Hearts"), C(8,"Spades"), C(3,"Diamonds"), C(9,"Clubs"), C(12,"Hearts") } },
	{ "Two Pair", { C(8,"Hearts"), C(8,"Spades"), C(3,"Diamonds"), C(3,"Clubs"), C(12,"Hearts") } },
	{ "Three of a Kind", { C(8,"Hearts"), C(8,"Spades"), C(8,"Diamonds"), C(9,"Clubs"), C(12,"Hearts") } },
	{ "Straight", { C(5,"Hearts"), C(6,"Spades"), C(7,"Diamonds"), C(8,"Clubs"), C(9,"Hearts") } },
	{ "Flush", { C(2,"Hearts"), C(5,"Hearts"), C(7,"Hearts"), C(9,"Hearts"), C(13,"Hearts") } },
	{ "Full House", { C(8,"Hearts"), C(8,"Spades"), C(8,"Diamonds"), C(3,"Clubs"), C(3,"Hearts") } },
	{ "Four of a Kind", { C(8,"Hearts"), C(8,"Spades"), C(8,"Diamonds"), C(8,"Clubs"), C(3,"Hearts") } },
}
local VARIANTS = {
	{ isLastHand = false, held = { C(4,"Clubs"), C(11,"Spades"), C(14,"Diamonds") }, again = false, few = false },
	{ isLastHand = true, held = { C(13,"Clubs"), C(13,"Spades"), C(12,"Diamonds") }, again = true, few = true },
}
local function scoreV(owned, h, v)
	local cards = h[2]
	if v.few then cards = { cards[1], cards[2], cards[3] } end
	local r = HE.evaluate(h[2])
	local ctx = { allPlayedCards = cards, heldCards = v.held, handsRemaining = v.isLastHand and 0 or 2, discardsRemaining = 2, isLastHand = v.isLastHand, night = 3, round = 2,
		tips = 10, roundsCleared = 4, bossesCleared = 1, handsPlayedTotal = 10, discardsUsedTotal = 6, patronsSold = 1, handStatsBefore = {},
		alreadyPlayedThisHandTypeThisRound = v.again, rng = Scoring.noLuck, handLevels = {} }
	local ok, s = pcall(Scoring.calculate, r, owned, ctx)
	if not ok then return nil, s end
	return s
end
local function score(owned, h)
	local best, err = nil, nil
	for _, v in ipairs(VARIANTS) do
		local s, e = scoreV(owned, h, v)
		if not s then err = e else best = math.max(best or 0, s) end
	end
	return best, err
end
local function scoreBase(h) return scoreV({}, h, VARIANTS[1]) end
local defs = Patrons.Definitions
local base = {}
for _, h in ipairs(HANDS) do base[h[1]] = scoreBase(h) end
local dead, errs = {}, {}
for _, p in ipairs(defs) do
	local any = false
	for _, h in ipairs(HANDS) do
		local s, e = score({ p }, h)
		if not s then errs[#errs+1] = p.id .. ": " .. tostring(e) break end
		if s > base[h[1]] then any = true end
	end
	if not any then dead[#dead+1] = p.id end
end
print("patrons", #defs, "errors", #errs, "dead alone", #dead)
for _, e in ipairs(errs) do print("ERR", e) end
for _, d in ipairs(dead) do print("DEAD", d) end
local pairsOut, runaway = {}, {}
for i = 1, #defs do for j = i + 1, #defs do
	local best, bh = 0, nil
	for _, h in ipairs(HANDS) do
		local s = score({ defs[i], defs[j] }, h)
		if s then
			local ratio = s / base[h[1]]
			if ratio > best then best, bh = ratio, h[1] end
		end
	end
	pairsOut[#pairsOut+1] = { defs[i].id, defs[j].id, best, bh }
	if best > 20 then runaway[#runaway+1] = pairsOut[#pairsOut] end
end end
table.sort(pairsOut, function(a, b) return a[3] > b[3] end)
for k = 1, 10 do local p = pairsOut[k]; print(string.format("TOP %d %s + %s  x%.1f on %s", k, p[1], p[2], p[3], p[4])) end
print("runaway pairs (>20x)", #runaway)
for _, p in ipairs(runaway) do print(string.format("RUN %s + %s x%.1f on %s", p[1], p[2], p[3], p[4])) end
local singles = {}
for _, p in ipairs(defs) do
	local best, bh = 0, nil
	for _, h in ipairs(HANDS) do local s = score({p}, h); if s and s / base[h[1]] > best then best, bh = s / base[h[1]], h[1] end end
	singles[#singles+1] = { p.id, best, bh }
end
table.sort(singles, function(a,b) return a[2] > b[2] end)
for k = 1, 5 do print(string.format("SINGLE %s x%.1f on %s", singles[k][1], singles[k][2], singles[k][3])) end
