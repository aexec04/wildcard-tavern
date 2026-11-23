--[[
	Engine/SetPreview.lua
	What the Card Sets room shows when a set tile is picked, owned or not. Every pick previews the set at once (hero table, name plate
	"Previewing <name>") with one line about how to get it, and one 44 px button that matches the state: Equip, Buy (price), Get it (a pass set
	whose Game Pass id is configured) or no button at all with a kind line (nothing a player can do yet). Never a dead button.
	Pure functions, no Roblox calls.
]]
local M = {}

M.BUTTON_H = 44

-- set: a CosmeticSets definition. state = { owned, equipped, passConfigured } (passConfigured: the Game Pass for a gamepass set has a real id).
-- Returns { title, line, kind = "equipped" | "equip" | "buy" | "pass" | "info", action = button text or nil, showButton, buttonH }.
function M.plan(set, state, unlockText)
	local out = { title = state.owned and set.name or ("Previewing " .. set.name), line = unlockText or "", buttonH = M.BUTTON_H }
	local unlock = set.unlock or {}
	if state.equipped then
		out.kind, out.action = "equipped", "Equipped"
	elseif state.owned then
		out.kind, out.action = "equip", "Equip"
	elseif unlock.kind == "tips" then
		out.kind, out.action = "buy", string.format("Buy (%d)", math.floor(unlock.price or 0))
	elseif unlock.kind == "gamepass" and state.passConfigured then
		out.kind, out.action = "pass", "Get it"
	else
		out.kind = "info"
		if unlock.kind == "gamepass" then out.line = "Coming soon to the Shop." end
	end
	out.showButton = out.action ~= nil
	return out
end

-- The Studio only "unlock all sets" switch: on only inside Studio, never on a live server, never written to a profile.
function M.studioUnlockOn(isStudio, attribute)
	return isStudio == true and attribute == true
end

return M
