--[[
	Engine/ScreenFade.lua
	Tested numbers for the soft screen transitions: a 0.25 s fade through warm dark when the Menu, the Counter,
	Round Select or Run Over opens, and a small painted "Dealing..." plate when a load runs longer than 0.4 s.
	Calm mode and Reduce motion get no fade at all (the screen simply appears, never a blank frame).
	Pure math, no Roblox calls. Client/ScreenFadeFX plays it.
]]
local ScreenFade = {}

ScreenFade.DURATION = 0.25
ScreenFade.DEALING_AFTER = 0.4
ScreenFade.HOLD_MAX = 8 -- a load never holds the cover longer than this
ScreenFade.COVER = { 24, 15, 9 } -- warm dark
ScreenFade.PLATE = { 52, 36, 22 }
ScreenFade.TEXT = { 250, 238, 212 }
ScreenFade.TEXT_SIZE = 20
ScreenFade.DEALING_TEXT = "Dealing..."
-- Frames whose opening plays the fade (names under GameRoot).
ScreenFade.WATCHED = { "MenuRoot", "ShopBackdrop", "RoundSelect", "GameOver" }

function ScreenFade.watches(name)
	for _, n in ipairs(ScreenFade.WATCHED) do
		if n == name then return true end
	end
	return false
end

-- Plan for one opening: fade seconds (0 means none), and whether input is locked while it runs.
function ScreenFade.plan(calm, reduceMotion)
	if calm or reduceMotion then return { fade = 0, lockInput = false } end
	return { fade = ScreenFade.DURATION, lockInput = true }
end

-- Cover transparency at time t of a fade of `dur` seconds: 0 (solid warm dark) to 1 (gone).
function ScreenFade.transparencyAt(t, dur)
	if not dur or dur <= 0 then return 1 end
	return math.max(0, math.min(1, t / dur))
end

-- The Dealing plate shows once a load has run past DEALING_AFTER and is not ready yet.
function ScreenFade.dealingVisible(elapsed, ready)
	return ready ~= true and elapsed >= ScreenFade.DEALING_AFTER and elapsed < ScreenFade.HOLD_MAX
end

-- The cover is released when the load is ready or the cap passed.
function ScreenFade.released(elapsed, ready)
	return ready == true or elapsed >= ScreenFade.HOLD_MAX
end

return ScreenFade
