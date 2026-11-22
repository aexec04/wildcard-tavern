--[[
	NightBoons.lua
	Small Night boons: when a new Night opens (Nights 2 to 12, normal runs only) the player picks one of three from this
	table. A boon lasts for that Night only (Tips and cheaper prices included), so it is a small lift, never a snowball.
	Server authoritative: the offer lives in session.choice (Engine/RunChoice.lua), the pick is applied by
	NightBoons.apply and stored on the run as state.nightBoon = { id, night, used? }. Never pay to win, no new art.

	Fields per boon: id, name, icon, text (one kid safe line), plus effect keys read by the engine:
		hands, discards, handSize   added to every round of the Night
		roundOneHands/Discards      added to the first round of the Night only
		bossHands, bossDiscards     added to the Boss round of the Night only
		scorePct                    percent added to every hand's Mult
		firstHandPct                percent added to the first hand of each round
		tips                        Tips now
		freeReroll                  the next shop Reroll costs nothing
		patronOff, packOff          Tips off Patron and Pack prices (never below 1)
	Pure Lua, no Roblox APIs.
]]

local NightBoons = {}

NightBoons.FIRST_NIGHT = 2
NightBoons.LAST_NIGHT = 12
NightBoons.OFFERS = 3

NightBoons.Definitions = {
	{ id = "extra_hand", name = "Spare Hand", icon = "✋", text = "+1 Hand this Night", hands = 1 },
	{ id = "extra_discard", name = "Spare Discard", icon = "🔄", text = "+1 Discard this Night", discards = 1 },
	{ id = "wider_grip", name = "Wider Grip", icon = "🤲", text = "+1 card in hand this Night", handSize = 1 },
	{ id = "opening_flourish", name = "Opening Flourish", icon = "🎩", text = "First hand of each round scores x1.5", firstHandPct = 50 },
	{ id = "warm_welcome", name = "Warm Welcome", icon = "🔥", text = "Every hand scores 10% more this Night", scorePct = 10 },
	{ id = "pocket_change", name = "Pocket Change", icon = "🪙", text = "+3 Tips now", tips = 3 },
	{ id = "free_reroll", name = "Free Reroll", icon = "🎲", text = "Your next shop Reroll is free", freeReroll = true },
	{ id = "patron_discount", name = "Friendly Prices", icon = "🏷️", text = "Patrons cost 2 less this Night", patronOff = 2 },
	{ id = "pack_discount", name = "Pack Deal", icon = "🎁", text = "Packs cost 1 less this Night", packOff = 1 },
	{ id = "boss_hand", name = "Boss Ready", icon = "🛡️", text = "+1 Hand on this Night's Boss round", bossHands = 1 },
	{ id = "boss_discard", name = "Boss Prep", icon = "🧰", text = "+1 Discard on this Night's Boss round", bossDiscards = 1 },
	{ id = "steady_pace", name = "Steady Pace", icon = "🐢", text = "+1 Hand and +1 Discard on the first round", roundOneHands = 1, roundOneDiscards = 1 },
}

function NightBoons.getById(id)
	for _, def in ipairs(NightBoons.Definitions) do
		if def.id == id then return def end
	end
	return nil
end

-- True when a Night opening at `night` may offer boons.
function NightBoons.offeredAt(night)
	night = tonumber(night) or 0
	return night >= NightBoons.FIRST_NIGHT and night <= NightBoons.LAST_NIGHT
end

-- The boon active for the run's current Night, or nil. Returns the definition and the stored record.
function NightBoons.active(state)
	local rec = type(state) == "table" and state.nightBoon or nil
	if type(rec) ~= "table" or rec.night ~= state.night then return nil end
	local def = NightBoons.getById(rec.id)
	if not def then return nil end
	return def, rec
end

-- One numeric effect for the current round (boss keys count on the Boss round only, round one keys on round 1 only).
function NightBoons.field(state, key)
	local def = NightBoons.active(state)
	if not def then return 0 end
	local value = tonumber(def[key]) or 0
	if key == "hands" and state.round == 1 then value = value + (def.roundOneHands or 0) end
	if key == "discards" and state.round == 1 then value = value + (def.roundOneDiscards or 0) end
	if (key == "bossHands" or key == "bossDiscards") and not state.isBossRound then return 0 end
	return value
end

-- Percent added to the Mult of a hand (every hand, plus the first hand of the round when `isFirstHand`).
function NightBoons.scorePct(state, isFirstHand)
	return NightBoons.field(state, "scorePct") + (isFirstHand and NightBoons.field(state, "firstHandPct") or 0)
end

function NightBoons.priceOff(state, kind)
	return NightBoons.field(state, kind == "patron" and "patronOff" or "packOff")
end

function NightBoons.freeRerollReady(state)
	local def, rec = NightBoons.active(state)
	return def ~= nil and def.freeReroll == true and not rec.used
end

function NightBoons.useFreeReroll(state)
	if NightBoons.freeRerollReady(state) then
		state.nightBoon.used = true
		return true
	end
	return false
end

-- Three distinct boons for the Night, or nil when boons are not offered (wrong Night, `allowed` false: Daily, Weekly,
-- Seed and tutorial runs). Same shape as every other choice: { kind, title, text, icon, options = { { id, name, icon, line1, line2 } } }.
function NightBoons.draft(state, allowed, rng)
	if allowed == false or type(state) ~= "table" or not NightBoons.offeredAt(state.night) then return nil end
	rng = rng or state.rng or math.random
	local pool = {}
	for _, def in ipairs(NightBoons.Definitions) do pool[#pool + 1] = def end
	local options = {}
	for _ = 1, math.min(NightBoons.OFFERS, #pool) do
		local def = table.remove(pool, rng(#pool))
		options[#options + 1] = { id = def.id, name = def.name, icon = def.icon, line1 = def.text, line2 = "" }
	end
	return { kind = "boon", title = "Pick a Night boon", text = "A small lift for this Night only.", icon = "✨", options = options }
end

-- Applies the pick. Returns ok, message.
function NightBoons.apply(state, id)
	local def = NightBoons.getById(id)
	if not def then return false, "Unknown boon" end
	if not NightBoons.offeredAt(state.night) then return false, "No boons this Night" end
	state.nightBoon = { id = def.id, night = state.night }
	if def.tips then state.tips = (state.tips or 0) + def.tips end
	-- the round that is already dealt (Round Select) gets its hands and discards at once
	local hands, discards = NightBoons.field(state, "hands"), NightBoons.field(state, "discards")
	if hands ~= 0 and state.handsRemaining then
		state.handsRemaining = state.handsRemaining + hands
		state.roundStartHands = (state.roundStartHands or state.handsRemaining) + hands
	end
	if discards ~= 0 and state.discardsRemaining then
		state.discardsRemaining = state.discardsRemaining + discards
		state.roundStartDiscards = (state.roundStartDiscards or state.discardsRemaining) + discards
	end
	return true, def.name .. ": " .. def.text .. "."
end

-- Display data for the HUD tooltip (nil when no boon is active this Night).
function NightBoons.view(state)
	local def = NightBoons.active(state)
	if not def then return nil end
	return { id = def.id, name = def.name, icon = def.icon, text = def.text, line = "Night boon: " .. def.name .. ": " .. def.text }
end

return NightBoons
