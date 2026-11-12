--[[
	Shared/Engine/DebugGotoRules.lua
	Pure parser for the Studio-only DebugGoto jump hook (Client/DebugGoto.lua). parse(value) returns
	{ kind = "menu" | "tome" | "news" | "round1" | "shop" | "spectate", page?, sub? } or nil, reason.
	Unknown values return nil so the client warns and does nothing.
]]

local DebugGotoRules = {}

-- tome page name -> OverlayManager opener id (Engine/PanelGroups page ids)
DebugGotoRules.TOME_PAGES = {
	collection = "collection", cardsets = "cosmeticSets", badges = "badges",
	legend = "legend", flair = "flair", stats = "stats",
}

DebugGotoRules.SEED_CODE = "DEBUG2" -- fixed run seed for round1 (6 chars, A-Z without I and O, digits 2-9)

function DebugGotoRules.parse(value)
	if type(value) ~= "string" or value == "" then
		return nil, "empty value"
	end
	local text = value:lower():gsub("%s+", "")
	if text == "menu" or text == "news" or text == "round1" or text == "shop" or text == "spectate" then
		return { kind = text }
	end
	local parts = {}
	for part in text:gmatch("[^:]+") do
		parts[#parts + 1] = part
	end
	if parts[1] == "tome" and #parts >= 2 and #parts <= 3 then
		local opener = DebugGotoRules.TOME_PAGES[parts[2]]
		if opener then
			return { kind = "tome", page = opener, sub = parts[3] }
		end
		return nil, "unknown tome page " .. parts[2]
	end
	return nil, "unknown value " .. value
end

-- What to answer to a table state while round1 is being reached.
-- Returns "choice", optionId (pick the first option), "select" (start the round) or nil.
function DebugGotoRules.round1Step(state)
	if type(state) ~= "table" then return nil end
	if type(state.choice) == "table" and type(state.choice.options) == "table" and state.choice.options[1] then
		return "choice", state.choice.options[1].id
	end
	if state.phase == "roundSelect" then return "select" end
	return nil
end

-- The round1 jump has a fixed step order: start (StartSeedRun, menu hidden, GameRoot shown, tutorial overlay hidden)
-- -> choice (the first option, as many times as the server asks) -> select (the first Round Select card) -> hand.
-- stepOf(state) names where the table is; handCount(state) is the number of dealt cards once the round is playing, else nil.
DebugGotoRules.ROUND1_ORDER = { "start", "choice", "select", "hand" }

function DebugGotoRules.stepOf(state)
	if type(state) ~= "table" then return "start" end
	if type(state.choice) == "table" and type(state.choice.options) == "table" and state.choice.options[1] then return "choice" end
	if state.phase == "roundSelect" then return "select" end
	if state.phase == "playing" and type(state.hand) == "table" and #state.hand > 0 then return "hand" end
	return "start"
end

function DebugGotoRules.handCount(state)
	if DebugGotoRules.stepOf(state) == "hand" then return #state.hand end
	return nil
end

-- seconds to wait for the whole chain before warning which step it stopped at
DebugGotoRules.ROUND1_TIMEOUT = 12

return DebugGotoRules
