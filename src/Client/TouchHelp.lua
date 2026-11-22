--[[
	Client/TouchHelp.lua
	Phones have no hover, so a hover only hint is invisible there. TouchHelp.bind(object, show, hide) makes a tap show the same hint
	for 3 seconds (Engine/TouchHint): the hint goes away on a timeout, on the next tap anywhere else, or when it is tapped again.
	The tap never blocks the object's own action: a button still fires on the tap, the hint is shown beside it. Mouse users are unaffected.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local TouchHint = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TouchHint"))

local TouchHelp = {}

local state = TouchHint.new(TouchHint.DURATION)
local hideCurrent = nil
local installed = false

-- True on a touch device without a mouse (phones, tablets): hover never fires there.
function TouchHelp.isTouchOnly()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function clear()
	state:tapElsewhere()
	if hideCurrent then
		local h = hideCurrent
		hideCurrent = nil
		pcall(h)
	end
end

local function install()
	if installed then return end
	installed = true
	-- a tap on the world (outside every GUI) clears the hint; a tap on another bound object replaces it; otherwise the 3 s timeout ends it
	UserInputService.TouchTapInWorld:Connect(clear)
end

-- show(): put the hint up. hide(): take it down. Returns a function that disconnects the binding.
function TouchHelp.bind(object, show, hide)
	if not TouchHelp.isTouchOnly() then return function() end end
	install()
	local conn = object.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		local now = os.clock()
		local verdict = state:tap(object, now)
		if hideCurrent and verdict == "show" then
			local h = hideCurrent
			hideCurrent = nil
			pcall(h) -- a different object's hint was up
		end
		if verdict == "show" then
			pcall(show)
			hideCurrent = hide
			local stamp = now
			task.delay(TouchHint.DURATION, function()
				if state.shownAt == stamp and state.target == object then clear() end
			end)
		else
			clear() -- second tap: the action runs through the object's own Activated, the hint just goes
		end
	end)
	return function() conn:Disconnect() end
end

return TouchHelp
