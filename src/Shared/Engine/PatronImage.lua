--[[
	Engine/PatronImage.lua
	The one picture a Patron has everywhere (table seat, Collection gallery and detail, My Patrons, Patron pick, Counter offers,
	Run Over, Legend): its Concept T cut card (ConceptTPatronArt, "ctp_<id>") when it has one, else the older portrait
	(PatronArt). Every screen reads it through here, ContentArt.getImageId("patrons", id) and PatronPlaque.apply included, so two
	screens can never show two different pictures of one Patron.

	get(id)            -> "rbxassetid://..." or nil
	get(id, true)      -> the plain portrait only (the few places that draw the portrait window of a cut card, Engine/DraftPortrait)
	missingCard()      -> sorted Patron ids that still have no cut card (they fall back to the portrait; an art task covers them)
	ids()              -> sorted ids of every Patron with any picture
]]
local Engine = script.Parent
local Portraits = require(Engine:WaitForChild("PatronArt"))
local Cards = require(Engine:WaitForChild("ConceptTPatronArt"))

local M = {}

local function good(v)
	return type(v) == "string" and v ~= "" and v ~= "rbxassetid://0"
end

function M.get(id, portraitOnly)
	if type(id) ~= "string" or id == "" then return nil end
	if not portraitOnly then
		local card = Cards["ctp_" .. id]
		if good(card) then return card end
	end
	local p = Portraits[id]
	if good(p) then return p end
	return nil
end

function M.ids()
	local seen, out = {}, {}
	for id in pairs(Portraits) do seen[id] = true end
	for key in pairs(Cards) do
		local id = key:match("^ctp_(.+)$")
		if id then seen[id] = true end
	end
	for id in pairs(seen) do out[#out + 1] = id end
	table.sort(out)
	return out
end

function M.missingCard()
	local out = {}
	for _, id in ipairs(M.ids()) do
		if not good(Cards["ctp_" .. id]) then out[#out + 1] = id end
	end
	return out
end

return M
