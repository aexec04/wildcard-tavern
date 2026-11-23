--[[
	Engine/WhatsNew.lua
	One short plate on the Menu that lists the latest three additions, once per update. Pure and tested.
	The profile keeps one number, whatsNewSeen: the VERSION the player has dismissed. A brand new profile starts at VERSION (it
	has nothing new to catch up on); an older save without the field starts at 0 and sees the plate once.
	To announce a new update: change the three Entries and raise VERSION by one.

	view(profile)         -> nil, or { title, lines = { three short lines }, button }
	dismiss(profile)      -> true when the profile moved to the current version
	cleanSaved(raw)       -> a safe saved number
	layout(w, h)          -> rects for the plate (tested at four sizes)
]]

local WhatsNew = {}

WhatsNew.VERSION = 1
WhatsNew.TITLE = "What's new"
WhatsNew.BUTTON = "Got it"
WhatsNew.MAX_LINE = 60
WhatsNew.Entries = {
	"Marks: pick one in a Counter pack to power up a card.",
	"Night boons: pick a small lift when a new Night opens.",
	"Endless: keep playing past the last Night for a new best.",
}

function WhatsNew.cleanSaved(raw)
	local n = tonumber(raw)
	if not n or n ~= n or n < 0 or n > WhatsNew.VERSION then return 0 end
	return math.floor(n)
end

function WhatsNew.view(profile)
	if type(profile) ~= "table" then return nil end
	if WhatsNew.cleanSaved(profile.whatsNewSeen) >= WhatsNew.VERSION then return nil end
	return { title = WhatsNew.TITLE, lines = WhatsNew.Entries, button = WhatsNew.BUTTON }
end

function WhatsNew.dismiss(profile)
	if type(profile) ~= "table" then return false end
	if WhatsNew.cleanSaved(profile.whatsNewSeen) >= WhatsNew.VERSION then return false end
	profile.whatsNewSeen = WhatsNew.VERSION
	return true
end

-- Plate: centred, title 24 px, three 16 px lines (two rows each so a long line wraps), a 44 px Got it plate.
WhatsNew.TITLE_H = 36
WhatsNew.LINE_H = 40
WhatsNew.BUTTON_H = 44
WhatsNew.PAD = 16
function WhatsNew.layout(w, h)
	local pw = math.max(280, math.min(520, w - 24))
	local ph = WhatsNew.PAD + WhatsNew.TITLE_H + #WhatsNew.Entries * WhatsNew.LINE_H + 8 + WhatsNew.BUTTON_H + WhatsNew.PAD
	local x = math.floor((w - pw) / 2)
	local y = math.max(12, math.floor((h - ph) / 2))
	local rects = { plate = { x = x, y = y, w = pw, h = ph }, lines = {} }
	rects.title = { x = x + WhatsNew.PAD, y = y + WhatsNew.PAD, w = pw - 2 * WhatsNew.PAD, h = WhatsNew.TITLE_H }
	for i = 1, #WhatsNew.Entries do
		rects.lines[i] = { x = x + WhatsNew.PAD, y = y + WhatsNew.PAD + WhatsNew.TITLE_H + (i - 1) * WhatsNew.LINE_H, w = pw - 2 * WhatsNew.PAD, h = WhatsNew.LINE_H }
	end
	local btnW = math.min(200, pw - 2 * WhatsNew.PAD)
	rects.button = { x = x + math.floor((pw - btnW) / 2), y = y + ph - WhatsNew.PAD - WhatsNew.BUTTON_H, w = btnW, h = WhatsNew.BUTTON_H }
	return rects
end

return WhatsNew
