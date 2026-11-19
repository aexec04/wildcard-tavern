--[[
	Shared/Engine/PatronTips.lua
	Pure helpers (tested) for the Patron hover or long press tooltip plate on the play screen. Client/PatronTipFX draws it.

	  PatronTips.tagsOf(id)               -> up to MAX_TAGS { tag, icon, word } (the "flat" tag is never shown)
	  PatronTips.sentence(description)    -> the first sentence of the effect text
	  PatronTips.content(id, name, description, rarity) -> { name, rarity (word), effect, tags }
	  PatronTips.sharing(ownedIds, index) -> { [seatIndex] = true } for the OTHER seats that share a shown tag with seat `index`
	  PatronTips.place(card, tip, avoid, screen, gap, margin) -> x, y   above, below, right or left of the card; clear of every
	      `avoid` rect ({ x, y, w, h }) when any side allows it, else the least bad one, always inside the screen
	  PatronTips.motion(calm) -> { fade, animate }   no tween in Calm mode or Reduce motion
]]

local Patrons = require(script.Parent.Patrons)
local Synergy = require(script.Parent.Synergy)
local AbilityText = require(script.Parent.AbilityText)

local M = {}

M.MAX_TAGS = 2
M.HIGHLIGHT_ALPHA = 0.4 -- gold outline opacity on the other Patrons that share a tag
M.RARITY_WORDS = { common = "Common", uncommon = "Uncommon", rare = "Rare", epic = "Epic", legendary = "Legendary", mythical = "Mythical" }

function M.tagsOf(id)
	local def = Patrons.getById(id)
	local out = {}
	for _, tag in ipairs((def and def.tags) or {}) do
		local info = Synergy.Tags[tag]
		if info and tag ~= "flat" and #out < M.MAX_TAGS then
			out[#out + 1] = { tag = tag, icon = info.icon, word = info.word }
		end
	end
	return out
end

function M.sentence(description)
	local text = tostring(description or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	local stop = text:find("[%.!?]%s")
	if stop then return text:sub(1, stop) end
	return text
end

function M.content(id, name, description, rarity)
	local r = tostring(rarity or "common"):lower()
	return {
		name = tostring(name or ""),
		rarity = M.RARITY_WORDS[r] or "Common",
		effect = M.sentence(description),
		-- the tooltip body: effect line, then the condition on its own line; `bodyRich` has the numbers in gold
		body = AbilityText.plain(AbilityText.tooltip(M.sentence(description))),
		bodyRich = AbilityText.tooltip(M.sentence(description)),
		tags = M.tagsOf(id),
	}
end

-- The set bonus lines this seat is part of ("Rare Court: x1.2 Mult"), joined with a plain separator; "" when none
function M.setLine(ownedIds, index)
	local SetBonuses = require(script.Parent.SetBonuses)
	local lines = {}
	for _, set in ipairs(SetBonuses.members(SetBonuses.formed(ownedIds), index)) do
		lines[#lines + 1] = SetBonuses.lineOf(set)
	end
	if #lines == 0 then
		local p = SetBonuses.progress(ownedIds, index)
		if p ~= "" then return p end
	end
	return table.concat(lines, "   ")
end

function M.sharing(ownedIds, index)
	local out = {}
	local mine = {}
	for _, t in ipairs(M.tagsOf(ownedIds[index])) do mine[t.tag] = true end
	for i, id in ipairs(ownedIds) do
		if i ~= index and id then
			for _, t in ipairs(M.tagsOf(id)) do
				if mine[t.tag] then out[i] = true break end
			end
		end
	end
	return out
end

local function hits(x, y, w, h, r)
	return x < r.x + r.w and x + w > r.x and y < r.y + r.h and y + h > r.y
end

local function clamp(x, y, tip, screen, margin)
	return math.max(margin, math.min(x, screen.X - tip.X - margin)), math.max(margin, math.min(y, screen.Y - tip.Y - margin))
end

function M.place(card, tip, avoid, screen, gap, margin)
	gap, margin = gap or 8, margin or 6
	local cy = card.y + card.h / 2 - tip.Y / 2
	local candidates = {
		{ card.x + card.w / 2 - tip.X / 2, card.y - gap - tip.Y },
		{ card.x + card.w / 2 - tip.X / 2, card.y + card.h + gap },
		{ card.x + card.w + gap, cy },
		{ card.x - gap - tip.X, cy },
	}
	local best, bestScore
	for _, c in ipairs(candidates) do
		local x, y = clamp(c[1], c[2], tip, screen, margin)
		local score = 0
		for _, r in ipairs(avoid or {}) do
			if hits(x, y, tip.X, tip.Y, r) then score = score + 1 end
		end
		if hits(x, y, tip.X, tip.Y, card) then score = score + 0.5 end -- never on its own card unless nothing else fits
		if not bestScore or score < bestScore then best, bestScore = { x, y }, score end
		if score == 0 then break end
	end
	return best[1], best[2]
end

function M.motion(calm)
	if calm then return { fade = 0, animate = false } end
	return { fade = 0.1, animate = true }
end

return M
