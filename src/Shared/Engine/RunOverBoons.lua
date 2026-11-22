--[[
	Shared/Engine/RunOverBoons.lua
	The Night boons strip on the Run Over screen: one row of small chips, one per boon taken this run (state.boonsTaken, from
	NightBoons.history), under the Patrons. Tapping a chip names it in the line under the strip. Nothing shows when no boon was taken.
	  RunOverBoons.view(taken) -> nil | { label, chips = { { id, name, icon, night, line } }, idle }
	Chips are 44 px (RunOverLayout.CHIP); the strip wraps to more rows only when the width cannot hold them in one.
	Every line is 90 characters or less and shown at 16 px in a two line box.
]]

local NightBoons = require(script.Parent.NightBoons)

local RunOverBoons = {}

RunOverBoons.LABEL = "Night boons taken"
RunOverBoons.IDLE = "Tap a boon to read it."
RunOverBoons.MAX = 12 -- one per Night (Nights 2 to 12 offer boons); anything beyond is junk

function RunOverBoons.lineFor(chip)
	return "Night " .. chip.night .. ", " .. chip.name .. ": " .. chip.text
end

function RunOverBoons.view(taken)
	if type(taken) ~= "table" then return nil end
	local chips = {}
	for _, rec in ipairs(taken) do
		if #chips >= RunOverBoons.MAX then break end
		local def = type(rec) == "table" and NightBoons.getById(rec.id) or nil
		if def then
			local chip = { id = def.id, name = def.name, icon = def.icon, night = math.floor(tonumber(rec.night) or 0), text = def.text }
			chip.line = RunOverBoons.lineFor(chip)
			chips[#chips + 1] = chip
		end
	end
	if #chips == 0 then return nil end
	return { label = RunOverBoons.LABEL .. " (" .. #chips .. ")", chips = chips, idle = RunOverBoons.IDLE }
end

return RunOverBoons
