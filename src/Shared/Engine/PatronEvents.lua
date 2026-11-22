--[[
	Shared/Engine/PatronEvents.lua
	Pure helpers (tested) that turn Scoring.calculate's ordered `breakdown` into the Patron scoring beats the
	Patron Row plays, one per Patron effect, in the exact order the engine applied them. Nothing here changes a
	score: it only reads the breakdown.

	  PatronEvents.fromBreakdown(breakdown) -> { {patronId, kind, amount, label, index} ... }
	      kind is "chips" | "mult" | "xmult" | "money" (the engine's "tips"); "retrigger" is reserved for effects
	      that repeat a card, the engine records none today. Entries caused by cards or the base hand are skipped.
	  PatronEvents.replay(breakdown) -> chips, mult, score   re-applies every entry; equals Scoring.calculate
	  PatronEvents.text(event) -> string, colorKey ("chips" blue, "mult" red, "xmult" red bold, "money" gold)
	  PatronEvents.tavernNotes(bossRules, isFirstHand, bargainPct) -> { {kind, factor, label} ... }
	      score changes the table makes AFTER the breakdown (Boss Round chip or mult factors, Sleepy Cook, a Dealer's
	      Bargain); shown as grey or red pills on the tavern plate, never on a Patron.
	  PatronEvents.gap(fast, repeats) -> seconds between beats (0.24, quicker on repeats, never under 0.2)
]]

local PatronEvents = {}

local ScorePacing = require(script.Parent.ScorePacing)
PatronEvents.GAP, PatronEvents.GAP_FAST = ScorePacing.GAP, ScorePacing.FAST_CAP -- 240 ms between beats

local KIND = { chips = "chips", mult = "mult", xmult = "xmult", tips = "money" }

-- Studio-only screenshot aid (DebugGoto beatslow:on|freeze|off): "slow" spaces beats GAP_SLOW apart and holds each
-- one HOLD_SLOW; "freeze" is slow, and the second beat stays on screen until the mode is switched off.
PatronEvents.GAP_SLOW, PatronEvents.HOLD_SLOW, PatronEvents.FREEZE_AT = 2.0, 1.6, 2
local slowMode = nil

function PatronEvents.setSlow(mode)
	if mode == "on" or mode == "slow" then slowMode = "slow"
	elseif mode == "freeze" then slowMode = "freeze"
	else slowMode = nil end
	return slowMode
end

function PatronEvents.slowMode() return slowMode end

-- repeats = how many times in a row this hand was played (Engine/ScorePacing: each repeat is 30 ms quicker, never under 60 ms)
function PatronEvents.gap(fast, repeats)
	if slowMode then return PatronEvents.GAP_SLOW end
	return ScorePacing.gap(repeats, fast, false)
end

-- seconds the ring, pill and dimming stay up for one beat (nil = the normal short animation)
function PatronEvents.hold()
	return slowMode and PatronEvents.HOLD_SLOW or nil
end

function PatronEvents.fromBreakdown(breakdown)
	local out = {}
	for i, e in ipairs(breakdown or {}) do
		local src = e.source
		if src and src.type == "patron" and KIND[e.kind] then
			out[#out + 1] = { patronId = src.patronId, kind = KIND[e.kind], amount = e.amount, label = e.label, index = i }
		end
	end
	return out
end

function PatronEvents.replay(breakdown)
	local chips, mult, xmult = 0, 0, 1
	for _, e in ipairs(breakdown or {}) do
		if e.kind == "chips" then chips = chips + e.amount
		elseif e.kind == "mult" then mult = mult + e.amount
		elseif e.kind == "xmult" then xmult = xmult * e.amount end
	end
	mult = mult * xmult
	return chips, mult, chips * mult
end

local function num(n)
	n = math.floor(n * 100 + 0.5) / 100
	if n == math.floor(n) then return string.format("%d", math.floor(n)) end
	return tostring(n)
end

PatronEvents.fmt = num -- one rounding (two decimals at most) for every place that prints an amount

function PatronEvents.text(event)
	if event.kind == "chips" then return "+" .. num(event.amount) .. " Chips", "chips" end
	if event.kind == "mult" then return "+" .. num(event.amount) .. " Mult", "mult" end
	if event.kind == "xmult" then return "x" .. num(event.amount) .. " Mult", "xmult" end
	if event.kind == "money" then return "+$" .. num(event.amount), "money" end
	return "", "chips"
end

-- rim colour of the floating value pill, one per rarity tier (the text keeps the kind colour, so rarity never
-- depends on colour alone: the card's label pill already says the tier in words)
PatronEvents.RARITY_RIM = {
	common = { 205, 145, 85 }, uncommon = { 110, 215, 120 }, rare = { 90, 170, 255 },
	epic = { 190, 120, 255 }, legendary = { 255, 205, 70 },
}
function PatronEvents.rarityRim(rarity)
	return PatronEvents.RARITY_RIM[tostring(rarity or ""):lower()] or PatronEvents.RARITY_RIM.common
end

function PatronEvents.tavernNotes(bossRules, isFirstHand, bargainPct)
	local notes = {}
	if bossRules and bossRules.chipsMultiplier and bossRules.chipsMultiplier ~= 1 then
		notes[#notes + 1] = { kind = "chips", factor = bossRules.chipsMultiplier, label = "Boss rule" }
	end
	if bossRules and bossRules.multMultiplier and bossRules.multMultiplier ~= 1 then
		notes[#notes + 1] = { kind = "mult", factor = bossRules.multMultiplier, label = "Boss rule" }
	end
	if bossRules and bossRules.firstHandMultiplier and isFirstHand and bossRules.firstHandMultiplier ~= 1 then
		notes[#notes + 1] = { kind = "mult", factor = bossRules.firstHandMultiplier, label = "First hand" }
	end
	if bargainPct and bargainPct ~= 0 then
		notes[#notes + 1] = { kind = "mult", factor = math.max(0.1, 1 + bargainPct / 100), label = "Bargain" }
	end
	return notes
end

-- pill text for a tavern note; the second value is true when it hurts (factor under 1)
function PatronEvents.noteText(note)
	return string.format("%s x%s %s", note.label, num(note.factor), note.kind == "chips" and "Chips" or "Mult"), note.factor < 1
end

return PatronEvents
