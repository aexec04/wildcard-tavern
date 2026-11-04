--[[
	Client/HandHighlight.lua
	Tiny dependency-free bridge: the gameplay screen reports which hand type
	the currently selected cards make (from its existing HandEvaluator-based
	preview), and the Poker Hands reference listens to highlight that row.
	Standalone so init.client.lua spends no top-level local on it.
]]

local current = nil
local listeners = {}

return {
	set = function(handName)
		if handName == current then
			return
		end
		current = handName
		for _, fn in ipairs(listeners) do
			fn(current)
		end
	end,
	get = function()
		return current
	end,
	onChange = function(fn)
		table.insert(listeners, fn)
	end,
}
