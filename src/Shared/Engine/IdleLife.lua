--[[
	Shared/Engine/IdleLife.lua
	Pure numbers (tested) for the quiet idle layer on the Concept T play screen. After IDLE_AFTER seconds without input the
	hand cards breathe 2 px up and down in a slow wave, the Play Hand button glows softly every 4 s while a legal selection
	exists, and after HINT_AFTER seconds a one line hint fades in. The first input ends all of it. Client/IdleLifeFX plays it.
	Calm mode and Reduce motion get nothing (every function returns the still value).

	IdleLife.breath(index, idleFor, calm) -> px   vertical offset of hand card `index` (negative is up), 0 when not idle
	IdleLife.playGlow(idleFor, legal, calm) -> 0..1   brightness of the soft Play Hand glow
	IdleLife.hint(idleFor, calm) -> nil | { text, alpha }   alpha 0..1 (fades in over HINT_FADE)
]]

local M = {}

M.IDLE_AFTER = 8
M.HINT_AFTER = 20
M.HINT_FADE = 0.6
M.BREATH_PERIOD = 3
M.BREATH_STAGGER = 0.2
M.BREATH_PX = 2
M.GLOW_EVERY = 4
M.GLOW_LEN = 1.2
M.HINT_TEXT = "Tip: select up to 5 cards, then Play Hand"

function M.breath(index, idleFor, calm)
	if calm or (tonumber(idleFor) or 0) < M.IDLE_AFTER then return 0 end
	local t = idleFor - M.IDLE_AFTER - ((tonumber(index) or 1) - 1) * M.BREATH_STAGGER
	if t < 0 then return 0 end
	return -M.BREATH_PX * (0.5 - 0.5 * math.cos(2 * math.pi * t / M.BREATH_PERIOD))
end

function M.playGlow(idleFor, legal, calm)
	if calm or not legal or (tonumber(idleFor) or 0) < M.IDLE_AFTER then return 0 end
	local t = (idleFor - M.IDLE_AFTER) % M.GLOW_EVERY
	if t >= M.GLOW_LEN then return 0 end
	return math.sin(math.pi * t / M.GLOW_LEN)
end

function M.hint(idleFor, calm)
	if calm or (tonumber(idleFor) or 0) < M.HINT_AFTER then return nil end
	return { text = M.HINT_TEXT, alpha = math.min(1, (idleFor - M.HINT_AFTER) / M.HINT_FADE) }
end

return M
