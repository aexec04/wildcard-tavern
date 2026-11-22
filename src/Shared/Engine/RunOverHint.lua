--[[
	Shared/Engine/RunOverHint.lua
	The one kind line on the Run Over screen about the next Starting Deck to open ("Next deck: the Lucky Deck opens at Night 3."), read from
	the deck rows the server already sends (state.startingDecks, Engine/StartingDecks.view). nil when every deck is open, so the
	line never shows stale or empty. 60 characters or less, kid safe, no dash characters. Night boons are all offered from the start and
	Card Sets are listed by the existing Next unlock line, so decks are the only unlock this line adds.
	  RunOverHint.line(rows) -> string or nil
]]

local RunOverHint = {}

RunOverHint.MAX_LEN = 60

function RunOverHint.line(rows)
	if type(rows) ~= "table" then return nil end
	local best
	for _, row in ipairs(rows) do
		if type(row) == "table" and row.open == false and type(row.name) == "string" then
			local night = tonumber(row.unlockNight) or tonumber(tostring(row.hint or ""):match("Night (%d+)"))
			if night and (not best or night < best.night) then best = { night = night, name = row.name } end
		end
	end
	if not best then return nil end
	local line = "Next deck: " .. best.name .. " opens at Night " .. math.floor(best.night) .. "."
	if #line > RunOverHint.MAX_LEN then line = best.name .. " opens at Night " .. math.floor(best.night) .. "." end
	return line
end

return RunOverHint
