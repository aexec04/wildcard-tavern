--[[
	Shared/Engine/CollectionCards.lua
	Pure helpers (tested) for the Collection book's Concept T look. Client/Collection draws them.

	  CollectionCards.countPill(found, total)     -> "12 / 81" (floored, never above total, never negative)
	  CollectionCards.tabText(name, found, total) -> "Patrons  12 / 81" for a tab plate
	  CollectionCards.lockedGlyph(tab, found)     -> "?" for a locked Patron, Recipe or Boss entry, nil otherwise
	  CollectionCards.pageCue(fromTab, toTab, fromMode, toMode) -> "page_turn" when the page really changes, else nil
	  CollectionCards.useCutCard(tab, found, hasCard) -> true when the detail popup shows the large Concept T cut card
]]

local M = {}

M.CUE = "page_turn" -- a SoundIds cue

local function whole(n)
	return math.floor(tonumber(n) or 0)
end

function M.countPill(found, total)
	local t = math.max(0, whole(total))
	local f = math.max(0, math.min(whole(found), t))
	return string.format("%d / %d", f, t)
end

-- "23 of 81 found": the plain count line of a library page
function M.foundText(found, total)
	local t = math.max(0, whole(total))
	local f = math.max(0, math.min(whole(found), t))
	return string.format("%d of %d found", f, t)
end

-- "Works with: Pairs, Flush" for a Patron's detail card (at most two tags, words from Engine/Synergy); "" when it has none
function M.synergyLine(id)
	local ok, tags = pcall(function() return require(script.Parent:WaitForChild("PatronTips")).tagsOf(id) end)
	if not ok or not tags or #tags == 0 then return "" end
	local words = {}
	for _, t in ipairs(tags) do words[#words + 1] = t.word end
	return "Works with: " .. table.concat(words, ", ")
end

M.CHIP_H = 44 -- rarity filter plates are touch targets

function M.tabText(name, found, total)
	return tostring(name) .. "  " .. M.countPill(found, total)
end

local GLYPH_TABS = { patrons = true, recipes = true, bosses = true, housePasses = true }

function M.lockedGlyph(tab, found)
	if found then return nil end
	return GLYPH_TABS[tab] and "?" or nil
end

function M.pageCue(fromTab, toTab, fromMode, toMode)
	if fromMode ~= toMode or fromTab ~= toTab then return M.CUE end
	return nil
end

function M.useCutCard(tab, found, hasCard)
	return tab == "patrons" and found == true and hasCard == true
end

return M
