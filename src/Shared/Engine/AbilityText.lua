--[[
	Shared/Engine/AbilityText.lua
	Pure helpers (tested) that turn a registry description (Patrons, Recipes, House Passes, Packs) into the three forms
	the UI needs, so cards, shop offers and tooltips read the same way:

	  AbilityText.split(description)   -> { trigger = "When you play a Pair" | nil, effect = "+15 Chips" }
	      The condition goes on its own line; an effect with no condition has trigger nil.
	  AbilityText.card(description)    -> up to two short lines { trigger?, effect } for a card or shop offer (never cut with "...")
	  AbilityText.gold(text, hex)      -> RichText with every number token (+4, x1.5, 50%, 3) in gold
	  AbilityText.plain(richText)      -> the text with the markup removed (for tests and screen readers)
	  AbilityText.check(description)   -> list of problems (empty when fine): too long, ellipsis, tiny words, not a sentence

	Limits live here so the registry test and the tooltip agree: TOOLTIP_MAX characters for the whole text, CARD_LINE for each
	card line (a 238 px card at 14 px holds about 34), at most CARD_LINES lines. An entry may carry `short` for the card.
]]

local M = {}

M.TOOLTIP_MAX = 120
M.CARD_LINE = 34
M.CARD_LINES = 2
M.GOLD = "F6C446"

-- the first of these (earliest in the sentence) splits a condition from the effect
local TRIGGERS = {
	{ " if ", "If " },
	{ " when ", "When " },
	{ " for every ", "For every " },
	{ " for each ", "For each " },
	{ " every time ", "Every time " },
	{ " at the end of ", "At the end of " },
}

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function stripDot(s)
	return (s:gsub("[%.]+$", ""))
end

local function upper(s)
	return (s:gsub("^%l", string.upper))
end

function M.split(description)
	local text = stripDot(trim(tostring(description or "")))
	if text == "" then
		return { effect = "" }
	end
	local lower = text:lower()
	local bestAt, bestTrigger
	for _, t in ipairs(TRIGGERS) do
		local at = lower:find(t[1], 2, true)
		if at and (not bestAt or at < bestAt) then
			bestAt, bestTrigger = at, t
		end
	end
	-- a comma leading into the condition ("Adds X, if held at round end") is dropped from the effect side
	if bestAt and bestAt > 3 then
		local effect = trim(text:sub(1, bestAt - 1)):gsub(",$", "")
		local rest = trim(text:sub(bestAt + #bestTrigger[1]))
		if effect ~= "" and rest ~= "" then
			return { trigger = bestTrigger[2] .. rest, effect = upper(trim(effect)) }
		end
	end
	return { effect = upper(text) }
end

-- side notes in brackets that carry no number ("(not played)", "(caps at Ace)") stay in the tooltip only; a bracket with a
-- number ("(+30 Chips)") is the point of the line and is kept
local function compact(text)
	local out = text:gsub("%s*%(([^%)]*)%)", function(inner)
		if inner:find("%d") then
			return nil
		end
		return ""
	end)
	return trim(out)
end

-- greedy word wrap at `width` characters; never cuts a word and never adds an ellipsis
function M.wrap(text, width)
	local lines, line = {}, ""
	for word in tostring(text):gmatch("%S+") do
		if line == "" then
			line = word
		elseif #line + 1 + #word <= width then
			line = line .. " " .. word
		else
			lines[#lines + 1] = line
			line = word
		end
	end
	if line ~= "" then
		lines[#lines + 1] = line
	end
	return lines
end

-- the text a card or shop offer shows: the registry's `short` when it has one, else the full text without number-less
-- brackets, wrapped to the card width. At most CARD_LINES lines (check() fails the registry otherwise).
function M.card(description, short)
	local text = compact(stripDot(trim(tostring(short or description or ""))))
	return M.wrap(text, M.CARD_LINE)
end

-- tooltip body: condition on its own line, effect above it, numbers in gold
function M.tooltip(description, hex)
	local parts = M.split(description)
	local lines = { M.gold(parts.effect, hex) }
	if parts.trigger then
		lines[#lines + 1] = M.gold(parts.trigger, hex)
	end
	return table.concat(lines, "\n")
end

-- every number token: an optional + - x prefix, digits, an optional decimal and percent
function M.gold(text, hex)
	hex = hex or M.GOLD
	local out = tostring(text or ""):gsub("([%+%-x]?)(%d+%.?%d*%%?)", function(prefix, digits)
		return string.format('<font color="#%s">%s%s</font>', hex, prefix, digits)
	end)
	return out
end

function M.plain(rich)
	return (tostring(rich or ""):gsub("<[^>]->", ""))
end

function M.check(description, short)
	local problems = {}
	local text = tostring(description or "")
	if trim(text) == "" then
		problems[#problems + 1] = "empty"
		return problems
	end
	if #text > M.TOOLTIP_MAX then
		problems[#problems + 1] = "tooltip text over " .. M.TOOLTIP_MAX .. " characters (" .. #text .. ")"
	end
	if text:find("...", 1, true) or text:find("\226\128\166", 1, true) then
		problems[#problems + 1] = "ellipsis"
	end
	if text:find("\226\128\148", 1, true) or text:find("--", 1, true) then
		problems[#problems + 1] = "dash"
	end
	if not text:find("[%.%)]$") then
		problems[#problems + 1] = "does not end like a sentence"
	end
	local lines = M.card(text, short)
	if #lines > M.CARD_LINES then
		problems[#problems + 1] = "card text needs " .. #lines .. " lines, the limit is " .. M.CARD_LINES .. " (add a short form)"
	end
	return problems
end

return M
