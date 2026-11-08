--[[
	Client/TutorialBus.lua
	A tiny shared hand-off between the places that know a tutorial-relevant thing happened or own a button the
	tutorial points at, and the tutorial itself (Client/TutorialWalkthrough). No game state lives here.

	register(name, instanceOrGetter)   a target the tutorial can spotlight ("menuPlay", "selectButton", ...)
	resolve(name) -> Instance | nil
	fire(action, detail?)              something happened ("menu_play", "select_round", ...): the tutorial listens
	listen(fn)                         fn(action, detail); returns a disconnect function
]]

local TutorialBus = {}

local targets = {}
local listeners = {}

function TutorialBus.register(name, instanceOrGetter)
	targets[name] = instanceOrGetter
end

function TutorialBus.resolve(name)
	local t = targets[name]
	if type(t) == "function" then
		local ok, inst = pcall(t)
		return ok and inst or nil
	end
	return t
end

function TutorialBus.fire(action, detail)
	for _, fn in ipairs(listeners) do
		pcall(fn, action, detail)
	end
end

function TutorialBus.listen(fn)
	table.insert(listeners, fn)
	return function()
		for i, f in ipairs(listeners) do
			if f == fn then table.remove(listeners, i) break end
		end
	end
end

return TutorialBus
