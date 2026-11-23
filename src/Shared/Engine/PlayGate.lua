--[[
	Engine/PlayGate.lua
	One send per table state. A two finger tap, a tap plus a key press or a gamepad press that lands before the
	server answers must never send Play Hand or Discard twice (the second send would act on the replacement cards that
	now sit at the same positions). The gate opens again as soon as the table changes (the server dealt new cards,
	a hand or a discard was used) or after TIMEOUT seconds, so a play the server refused is never stuck.

	local gate = PlayGate.new()
	if gate:try(os.clock(), PlayGate.key(state)) then  -- send  end
]]

local PlayGate = {}
PlayGate.__index = PlayGate

PlayGate.TIMEOUT = 0.6 -- longest a send holds the gate when the table does not change

function PlayGate.new()
	return setmetatable({ sentAt = nil, key = nil }, PlayGate)
end

-- What the table looks like to the gate: hands and discards left and the cards in the hand, in order.
function PlayGate.key(state)
	if type(state) ~= "table" then return "none" end
	local parts = { tostring(state.handsRemaining), tostring(state.discardsRemaining), tostring(state.round), tostring(state.night) }
	for _, c in ipairs(type(state.hand) == "table" and state.hand or {}) do
		parts[#parts + 1] = tostring(c.rank) .. tostring(c.suit)
	end
	return table.concat(parts, ",")
end

-- true: send now (and the gate closes). false: the same table was already sent a moment ago, ignore this press.
function PlayGate:try(now, key)
	if self.sentAt ~= nil and self.key == key and now - self.sentAt < PlayGate.TIMEOUT and now >= self.sentAt then
		return false
	end
	self.sentAt, self.key = now, key
	return true
end

-- The one gate the table's Play Hand and Discard share (the hub keeps no local for it).
local shared = nil
function PlayGate.shared()
	shared = shared or PlayGate.new()
	return shared
end

return PlayGate
