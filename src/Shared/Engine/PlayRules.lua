--[[
	PlayRules.lua
	Pure. How many cards a hand may use this round, read from the SAME place the server checks
	(state.bossModifier, state.challenge), so the client can dim Play Hand and explain a refusal.
	  PlayRules.exact(state)      -> N when the round needs exactly N cards, else nil
	  PlayRules.minimum(state)    -> N when it needs at least N cards, else nil
	  PlayRules.allows(state, n)  -> ok, message (message names the rule when not ok)
	  PlayRules.hint(state)       -> short text such as "Pick exactly 5 cards", or nil
]]

local BossRules = require(script.Parent.BossRules)
local BossRounds = require(script.Parent.BossRounds)

local PlayRules = {}

-- The client only receives id, name and description for the round's rule; the numbers live in the registry.
local function ruleOf(state)
	local mod = state and state.bossModifier
	if not mod then return nil end
	return (mod.id and BossRounds.getById(mod.id)) or mod
end

function PlayRules.exact(state)
	local rule = ruleOf(state)
	return rule and rule.requiredCardsPerHand or nil
end

function PlayRules.minimum(state)
	if not state then return nil end
	return BossRules.minCards(ruleOf(state)) or BossRules.minCards(state.challenge)
end

local function cards(n)
	return n == 1 and "1 card" or (n .. " cards")
end

function PlayRules.hint(state)
	local exact = PlayRules.exact(state)
	if exact then return "Pick exactly " .. cards(exact) end
	local least = PlayRules.minimum(state)
	if least then return "Pick at least " .. cards(least) end
	return nil
end

function PlayRules.allows(state, count)
	local exact = PlayRules.exact(state)
	if exact then
		if count ~= exact then return false, "This round needs exactly " .. cards(exact) end
		return true
	end
	if count < 1 or count > 5 then return false, "Select 1-5 cards first." end
	local least = PlayRules.minimum(state)
	if least and count < least then return false, "This round needs at least " .. cards(least) end
	return true
end

return PlayRules
