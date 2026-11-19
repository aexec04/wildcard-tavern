--[[
	Shared/Engine/PackReveal.lua
	Pure numbers and state (tested) for opening a Patron pack. Client/PackRevealFX plays them. Calm mode and Reduce motion pass
	calm = true: the pack opens at once, every card is face up, no tween runs and no cue is delayed.

	PackReveal.plan(rarities, calm) -> nil | { shake, flash, flips = { { index, at, dur, cue, ring } ... } }
	    rarities = rarity id per card in order ("common" .. "mythical", nil allowed). Cards flip one at a time, 0.3 s each,
	    after the 0.4 s shake and the gold flash. Rare and above add a sparkle ring and the stronger patron_trigger cue.
	PackReveal.new(count, calm) -> state: open(), reveal(i), revealAll(), isOpen(), isRevealed(i), allRevealed(), canKeep(i)
	    A card can be kept (picked) only once it is face up. Skip all reveals everything at once.
	PackReveal.keepWord(category, kept) -> "Seat" / "Seated" for Patrons, "Keep" / "Kept" for everything else
]]

local M = {}

M.SHAKE_SECONDS = 0.4
M.FLASH_SECONDS = 0.3
M.FLIP_SECONDS = 0.3
M.SHAKE_PIXELS = 6
M.FLASH_ALPHA = 0.55 -- peak opacity of the gold flash
M.TAP_WORD = "Tap to open"
M.SKIP_WORD = "Skip all"

local STRONG = { rare = true, epic = true, legendary = true, mythical = true }

function M.isStrong(rarity)
	return STRONG[rarity] == true
end

function M.cueFor(rarity)
	return M.isStrong(rarity) and "patron_trigger" or "card_flip"
end

function M.plan(rarities, calm)
	if calm then return nil end
	local flips = {}
	local t = M.SHAKE_SECONDS + M.FLASH_SECONDS
	for i = 1, #rarities do
		local r = rarities[i]
		flips[i] = { index = i, at = t + (i - 1) * M.FLIP_SECONDS, dur = M.FLIP_SECONDS, cue = M.cueFor(r), ring = M.isStrong(r) }
	end
	return { shake = M.SHAKE_SECONDS, flash = M.FLASH_SECONDS, flips = flips }
end

function M.new(count, calm)
	count = math.max(0, math.floor(tonumber(count) or 0))
	local self = { count = count, opened = false, face = {} }
	function self.open()
		self.opened = true
		if calm then self.revealAll() end
	end
	function self.reveal(i)
		if i >= 1 and i <= count then self.face[i] = true end
	end
	function self.revealAll()
		self.opened = true
		for i = 1, count do self.face[i] = true end
	end
	function self.isOpen() return self.opened end
	function self.isRevealed(i) return self.face[i] == true end
	function self.allRevealed()
		for i = 1, count do if not self.face[i] then return false end end
		return true
	end
	function self.canKeep(i) return self.opened and self.face[i] == true end
	if calm then self.revealAll() end
	return self
end

function M.keepWord(category, kept)
	if category == "patron" then return kept and "Seated" or "Seat" end
	return kept and "Kept" or "Keep"
end

return M
